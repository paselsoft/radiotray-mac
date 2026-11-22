#import "RTFFmpegEngine.h"
#import "RTFFmpegOutput.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#include <stdatomic.h>
#include <signal.h>

static const double RTSampleRate = 44100;
static const AVAudioFrameCount RTChunkFrames = 4410;            // 0,1 s per buffer
static const long RTStartFrames = (long)(RTSampleRate * 1.5);  // si parte con 1,5 s pronti
static const long RTResumeFrames = (long)(RTSampleRate * 1.0); // dopo un vuoto si riparte con 1 s
static const long RTMaxQueuedFrames = (long)(RTSampleRate * 8); // oltre, si smette di leggere (ffmpeg aspetta)

@interface RTFFmpegEngine ()
@property (nonatomic, strong) AVAudioEngine *audio;
@property (nonatomic, strong) AVAudioPlayerNode *node;
@property (nonatomic, strong) AVAudioFormat *format;
@property (nonatomic, strong, nullable) NSTask *task;
@property (nonatomic, strong, nullable) NSPipe *outPipe;
@property (nonatomic, strong, nullable) NSPipe *errPipe;
@property (nonatomic, strong) RTFFmpegOutput *output;
@property (nonatomic, strong) NSMutableString *errBuffer;
@property (nonatomic, strong, nullable) NSTimer *flushTimer;
@property (nonatomic) BOOL started;     // il nodo suona
@property (nonatomic) BOOL waiting;     // buffer vuoto, in attesa di dati
@property (nonatomic) BOOL reconfiguring;
@end

@implementation RTFFmpegEngine
{
    atomic_long _queuedFrames;   // audio in coda nel nodo (frame)
    atomic_uint _session;        // cambia a ogni avvio e arresto: i dati di una sessione vecchia si scartano
}

@synthesize delegate = _delegate;
@synthesize volume = _volume;
@synthesize outputDeviceUID = _outputDeviceUID;

+ (BOOL)isAvailable
{
    return [RTFFmpegOutput ffmpegPath] != nil;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _volume = 1;
        _errBuffer = [NSMutableString string];
        _output = [RTFFmpegOutput new];
        atomic_init(&_queuedFrames, 0);
        atomic_init(&_session, 0);
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stop];
}

- (NSString *)engineName { return @"ffmpeg"; }

#pragma mark - AVAudioEngine

- (void)setupAudio
{
    if (self.audio) return;
    self.audio = [AVAudioEngine new];
    self.node = [AVAudioPlayerNode new];
    self.format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:RTSampleRate channels:2];
    [self.audio attachNode:self.node];
    [self.audio connect:self.node to:self.audio.mainMixerNode format:self.format];
    // uscita cambiata dal sistema (cuffie staccate, cassa scollegata, frequenza diversa): il motore si ferma da solo
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(configurationChanged:)
                                                 name:AVAudioEngineConfigurationChangeNotification object:self.audio];
}

/// Imposta il dispositivo di uscita sull'unità audio di AVAudioEngine (a motore fermo).
- (void)applyOutputDevice
{
    AudioDeviceID device = 0;
    UInt32 size = sizeof(device);
    if (self.outputDeviceUID.length) {
        CFStringRef uid = (__bridge CFStringRef)self.outputDeviceUID;
        AudioValueTranslation translation = { &uid, sizeof(uid), &device, sizeof(device) };
        AudioObjectPropertyAddress addr = { kAudioHardwarePropertyDeviceForUID, kAudioObjectPropertyScopeGlobal, 0 };
        UInt32 tsize = sizeof(translation);
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &tsize, &translation) != noErr) device = 0;
    }
    if (!device) {
        AudioObjectPropertyAddress addr = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, 0 };
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &device) != noErr) return;
    }
    AudioUnit unit = self.audio.outputNode.audioUnit;
    if (!unit || !device) return;
    OSStatus err = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, sizeof(device));
    if (err != noErr) NSLog(@"RadioTray: ffmpeg, uscita audio non impostata (%d)", (int)err);
}

- (BOOL)startAudio
{
    [self setupAudio];
    [self applyOutputDevice];
    self.audio.mainMixerNode.outputVolume = self.volume;
    [self.audio prepare];
    NSError *error = nil;
    if (![self.audio startAndReturnError:&error]) {
        NSLog(@"RadioTray: AVAudioEngine non parte: %@", error.localizedDescription);
        return NO;
    }
    return YES;
}

/// Ferma e riavvia l'audio (cambio di uscita): l'audio in coda si scarta e si riparte dopo 1 s di buffer.
- (void)restartAudio
{
    if (!self.task || !self.audio) return;
    self.reconfiguring = YES;
    [self.node stop];                 // chiama i completamenti dei buffer in coda: il conteggio torna a zero
    atomic_store(&_queuedFrames, 0);
    [self.audio stop];
    self.reconfiguring = NO;
    if (![self startAudio]) {
        [self failWith:@"L'uscita audio non risponde" formatProblem:NO];
        return;
    }
    // si riparte come dopo un vuoto del buffer
    self.started = YES;
    if (!self.waiting) {
        self.waiting = YES;
        [self.delegate audioEngineIsWaiting:self];
    }
}

- (void)configurationChanged:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.task) return;
        NSLog(@"RadioTray: ffmpeg, l'uscita audio è cambiata: riavvio dell'audio");
        [self restartAudio];
    });
}

- (void)setVolume:(float)volume
{
    _volume = volume;
    if (self.audio) self.audio.mainMixerNode.outputVolume = volume;
}

- (void)setOutputDeviceUID:(NSString *)outputDeviceUID
{
    if ((outputDeviceUID == _outputDeviceUID) || [outputDeviceUID isEqualToString:_outputDeviceUID ?: @""]) return;
    _outputDeviceUID = [outputDeviceUID copy];
    // su 10.13 il dispositivo si cambia a motore fermo: stop, nuova uscita, ripartenza
    if (self.task && self.audio.isRunning) [self restartAudio];
}

#pragma mark - Avvio e arresto

- (void)playURL:(NSString *)url
{
    [self stop];
    NSString *path = [RTFFmpegOutput ffmpegPath];
    if (!path) {
        [self failWith:@"Formato Ogg/Opus/FLAC: serve ffmpeg in /usr/local/bin" formatProblem:NO];
        return;
    }
    if (![self startAudio]) {
        [self failWith:@"L'audio del Mac non risponde" formatProblem:NO];
        return;
    }
    unsigned session = atomic_fetch_add(&_session, 1) + 1;
    atomic_store(&_queuedFrames, 0);
    self.started = NO;
    self.waiting = NO;
    self.output = [RTFFmpegOutput new];
    [self.errBuffer setString:@""];

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = [RTFFmpegOutput argumentsForURL:url];
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSPipe *outPipe = [NSPipe pipe], *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = errPipe;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *t) {
        int status = t.terminationStatus;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || atomic_load(&strongSelf->_session) != session) return;   // fermato da noi
            NSString *why = strongSelf.output.lastError;
            NSLog(@"RadioTray: ffmpeg è terminato (codice %d%@)", status, why ? [@", " stringByAppendingString:why] : @"");
            [strongSelf failWith:why ?: @"Lo stream si è interrotto" formatProblem:!strongSelf.started && status != 0 && why == nil];
        });
    };
    errPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *fh) {
        NSData *data = fh.availableData;
        if (!data.length) {
            fh.readabilityHandler = nil;
            return;
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                      ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf && atomic_load(&strongSelf->_session) == session) [strongSelf consumeStderr:text];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        errPipe.fileHandleForReading.readabilityHandler = nil;
        [self failWith:[NSString stringWithFormat:@"ffmpeg non parte: %@", error.localizedDescription] formatProblem:NO];
        return;
    }
    self.task = task;
    self.outPipe = outPipe;
    self.errPipe = errPipe;
    NSLog(@"RadioTray: ffmpeg avviato (pid %d) per %@", task.processIdentifier, url);
    [self.delegate audioEngineIsWaiting:self];

    // lettura del PCM su un thread a parte
    NSFileHandle *reader = outPipe.fileHandleForReading;
    AVAudioPlayerNode *node = self.node;
    AVAudioFormat *format = self.format;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [weakSelf readPCMFrom:reader node:node format:format session:session];
    });
}

- (void)stop
{
    atomic_fetch_add(&_session, 1);   // da qui ogni dato o evento della sessione vecchia viene ignorato
    [self.flushTimer invalidate];
    self.flushTimer = nil;
    NSTask *task = self.task;
    self.task = nil;
    if (task) {
        task.terminationHandler = nil;
        if (task.isRunning) {
            [task terminate];   // SIGTERM: ffmpeg chiude la connessione ed esce
            // se non esce entro 2 secondi, si termina d'autorità: mai processi ffmpeg orfani
            int pid = task.processIdentifier;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                if (task.isRunning) {
                    NSLog(@"RadioTray: ffmpeg (pid %d) non si è chiuso, lo termino", pid);
                    kill(pid, SIGKILL);
                }
            });
        }
        NSLog(@"RadioTray: ffmpeg fermato (pid %d)", task.processIdentifier);
    }
    self.errPipe.fileHandleForReading.readabilityHandler = nil;
    [self.errPipe.fileHandleForReading closeFile];
    [self.outPipe.fileHandleForReading closeFile];   // il thread di lettura riceve la fine del file ed esce
    self.errPipe = nil;
    self.outPipe = nil;
    if (self.audio) {
        self.reconfiguring = YES;
        [self.node stop];
        self.reconfiguring = NO;
        [self.audio stop];
    }
    atomic_store(&_queuedFrames, 0);
    self.started = NO;
    self.waiting = NO;
}

- (void)failWith:(NSString *)error formatProblem:(BOOL)formatProblem
{
    [self stop];
    [self.delegate audioEngine:self didFail:error formatProblem:formatProblem];
}

#pragma mark - PCM

/// Legge da stdout di ffmpeg: float32 little-endian, stereo interlacciato. Gira su un thread a parte.
- (void)readPCMFrom:(NSFileHandle *)reader node:(AVAudioPlayerNode *)node format:(AVAudioFormat *)format session:(unsigned)session
{
    NSMutableData *pending = [NSMutableData data];
    const NSUInteger bytesPerFrame = 2 * sizeof(float);
    const NSUInteger chunkBytes = RTChunkFrames * bytesPerFrame;
    while (atomic_load(&_session) == session) {
        // troppo audio in coda (ffmpeg legge più in fretta all'inizio): si aspetta, ffmpeg si ferma sulla pipe piena
        if (atomic_load(&_queuedFrames) > RTMaxQueuedFrames) {
            usleep(100000);
            continue;
        }
        NSData *data = nil;
        @try {
            data = [reader availableData];
        } @catch (NSException *e) {
            data = nil;   // pipe chiusa da stop
        }
        if (!data.length) break;   // fine dello stream (o ffmpeg terminato)
        [pending appendData:data];
        while (pending.length >= chunkBytes && atomic_load(&_session) == session) {
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:RTChunkFrames];
            buffer.frameLength = RTChunkFrames;
            const float *src = pending.bytes;
            float *left = buffer.floatChannelData[0], *right = buffer.floatChannelData[1];
            for (AVAudioFrameCount i = 0; i < RTChunkFrames; i++) {
                left[i] = src[2 * i];
                right[i] = src[2 * i + 1];
            }
            [pending replaceBytesInRange:NSMakeRange(0, chunkBytes) withBytes:NULL length:0];
            atomic_fetch_add(&_queuedFrames, (long)RTChunkFrames);
            __weak typeof(self) weakSelf = self;
            [node scheduleBuffer:buffer completionHandler:^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                long remaining = atomic_fetch_sub(&strongSelf->_queuedFrames, (long)RTChunkFrames) - (long)RTChunkFrames;
                if (remaining <= 0 && atomic_load(&strongSelf->_session) == session) {
                    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf bufferEmptied:session]; });
                }
            }];
            long queued = atomic_load(&_queuedFrames);
            if (queued >= RTResumeFrames) {
                dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf bufferFilled:session queued:queued]; });
            }
        }
    }
}

- (void)bufferFilled:(unsigned)session queued:(long)queued
{
    if (atomic_load(&_session) != session || !self.task) return;
    if (!self.started) {
        if (queued < RTStartFrames) return;
        self.started = YES;
        [self.node play];
        [self.delegate audioEngineDidStartPlaying:self];
    } else if (self.waiting) {
        self.waiting = NO;
        if (!self.node.isPlaying) [self.node play];
        [self.delegate audioEngineDidStartPlaying:self];
    }
}

- (void)bufferEmptied:(unsigned)session
{
    if (atomic_load(&_session) != session || !self.task || self.reconfiguring || !self.started || self.waiting) return;
    if (atomic_load(&_queuedFrames) > 0) return;
    // il buffer si è svuotato (rete lenta): si aspetta di riaverne 1 s invece di suonare a singhiozzo
    self.waiting = YES;
    [self.node pause];
    [self.delegate audioEngineIsWaiting:self];
}

#pragma mark - stderr

- (void)consumeStderr:(NSString *)text
{
    [self.errBuffer appendString:text];
    NSRange nl;
    BOOL formatChanged = NO;
    while ((nl = [self.errBuffer rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]]).location != NSNotFound) {
        NSString *line = [self.errBuffer substringToIndex:nl.location];
        [self.errBuffer deleteCharactersInRange:NSMakeRange(0, nl.location + 1)];
        if ([self.output consumeLine:line]) formatChanged = YES;
        [self deliverMetadata];
    }
    if (formatChanged && [self.delegate respondsToSelector:@selector(audioEngine:didReadFormat:bitrate:)]) {
        [self.delegate audioEngine:self didReadFormat:self.output.codec bitrate:self.output.bitrate];
    }
    // un blocco di metadati si chiude quando ffmpeg tace per un attimo
    [self.flushTimer invalidate];
    self.flushTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(flushMetadata) userInfo:nil repeats:NO];
}

- (void)flushMetadata
{
    self.flushTimer = nil;
    [self.output flushMetadata];
    [self deliverMetadata];
}

- (void)deliverMetadata
{
    NSString *station = [self.output takeStationName];
    if (station && [self.delegate respondsToSelector:@selector(audioEngine:didReadStationName:)]) {
        [self.delegate audioEngine:self didReadStationName:station];
    }
    NSString *title = [self.output takeTitle];
    if (title && [self.delegate respondsToSelector:@selector(audioEngine:didReadTitle:)]) {
        [self.delegate audioEngine:self didReadTitle:title];
    }
}

@end
