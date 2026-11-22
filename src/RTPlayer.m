#import "RTPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "RTIcyMetadataReader.h"
#import "RTTrackInfo.h"
#import "RTAVPlayerEngine.h"
#import "RTFFmpegEngine.h"
#import "RTFFmpegOutput.h"

static const NSTimeInterval RTConnectTimeout = 20.0;
static const NSTimeInterval RTStallTimeout = 20.0;
/// attese prima di ogni tentativo di riconnessione (secondi)
static const NSTimeInterval RTReconnectDelays[] = { 2, 5, 10, 15, 20, 30, 30, 30, 60, 60 };
static const NSUInteger RTMaxReconnects = sizeof(RTReconnectDelays) / sizeof(RTReconnectDelays[0]);

@interface RTPlayer () <RTIcyMetadataReaderDelegate, RTAudioEngineDelegate>
@property (nonatomic, strong) RTAVPlayerEngine *avEngine;
@property (nonatomic, strong, nullable) RTFFmpegEngine *ffEngine;
@property (nonatomic, strong, nullable) id<RTAudioEngine> engine;   // il motore che sta suonando (nil se fermo)
@property (nonatomic, strong) NSMutableSet<NSString *> *ffmpegURLs; // indirizzi che AVPlayer non sa leggere
@property (nonatomic, copy) NSArray<NSString *> *urls;
@property (nonatomic) NSUInteger urlIndex;
@property (nonatomic, readwrite) RTPlayerState state;
@property (nonatomic, copy, readwrite, nullable) NSString *currentURL;
@property (nonatomic, copy, nullable) NSString *lastError;
@property (nonatomic, strong, nullable) NSTimer *connectTimer;
@property (nonatomic) BOOL hasPlayed;          // l'URL corrente ha suonato
@property (nonatomic) BOOL everPlayed;         // la stazione ha suonato almeno una volta: se cade si riconnette
@property (nonatomic) NSUInteger reconnectAttempt;
@property (nonatomic) NSUInteger goodIndex;     // ultimo server che ha suonato: le riconnessioni partono da lì
@property (nonatomic) NSUInteger failovers;     // server di riserva provati dopo una caduta
@property (nonatomic, strong, nullable) NSTimer *reconnectTimer;
@property (nonatomic, strong, nullable) NSTimer *stallTimer;
@property (nonatomic) BOOL avMetadataSeen;   // il motore consegna i titoli: il lettore ICY non serve
@property (nonatomic, strong) RTIcyMetadataReader *icyReader;
@property (nonatomic, copy, readwrite, nullable) NSString *streamFormat;
@property (nonatomic, readwrite) NSInteger streamBitrate;
@property (nonatomic) NSInteger declaredBitrate;              // icy-br
@property (nonatomic, copy, nullable) NSString *declaredFormat; // dal Content-Type
@property (nonatomic, copy, nullable) NSString *engineFormat;   // riconosciuto dal motore
@property (nonatomic) NSInteger engineBitrate;
@end

@implementation RTPlayer

- (instancetype)init
{
    if ((self = [super init])) {
        _avEngine = [RTAVPlayerEngine new];
        _avEngine.delegate = self;
        _ffmpegURLs = [NSMutableSet set];
        _urls = @[];
        _volume = 100;
        _readsTitles = YES;
        _icyReader = [RTIcyMetadataReader new];
        _icyReader.delegate = self;
    }
    return self;
}

- (void)dealloc
{
    [_avEngine stop];
    [_ffEngine stop];
}

- (void)setVolume:(NSInteger)volume
{
    _volume = MAX(0, MIN(100, volume));
    self.avEngine.volume = (float)_volume / 100.0f;
    self.ffEngine.volume = (float)_volume / 100.0f;
}

- (void)setState:(RTPlayerState)state
{
    if (_state == state) return;
    _state = state;
    [self.delegate player:self didChangeState:state];
}

- (void)markConnecting
{
    [self cancelReconnect];
    self.everPlayed = NO;
    [self detachEngine];
    self.hasPlayed = NO;
    self.state = RTPlayerStateConnecting;
}

- (void)playStreams:(NSArray<NSString *> *)urls
{
    [self cancelReconnect];
    self.urls = urls;
    self.urlIndex = 0;
    self.lastError = nil;
    self.everPlayed = NO;
    self.reconnectAttempt = 0;
    self.goodIndex = 0;
    self.failovers = 0;
    [self startCurrent];
}

- (void)cancelReconnect
{
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;
}

- (void)stop
{
    [self cancelReconnect];
    self.everPlayed = NO;
    [self detachEngine];
    self.urls = @[];
    self.currentURL = nil;
    self.state = RTPlayerStateStopped;
}

/// Il motore giusto per l'indirizzo: ffmpeg per Ogg/Opus/FLAC (o se AVPlayer non l'ha saputo leggere).
- (id<RTAudioEngine>)engineForURL:(NSString *)url needsFFmpeg:(BOOL *)needs
{
    BOOL ffmpeg = [self.ffmpegURLs containsObject:url] ||
                  [RTFFmpegOutput needsFFmpegForURL:url contentType:self.streamContentTypes[url]];
    if (needs) *needs = ffmpeg;
    if (!ffmpeg) return self.avEngine;
    if (![RTFFmpegEngine isAvailable]) return nil;
    if (!self.ffEngine) {
        self.ffEngine = [RTFFmpegEngine new];
        self.ffEngine.delegate = self;
    }
    return self.ffEngine;
}

- (void)startCurrent
{
    [self detachEngine];
    if (self.urlIndex >= self.urls.count) {
        NSString *error = self.lastError ?: @"Impossibile riprodurre la stazione";
        [self stop];
        [self.delegate player:self didFailWithError:error];
        return;
    }

    NSString *urlString = self.urls[self.urlIndex];
    if (![NSURL URLWithString:urlString]) {
        self.lastError = @"URL dello stream non valido";
        self.urlIndex++;
        [self startCurrent];
        return;
    }
    BOOL needsFFmpeg = NO;
    id<RTAudioEngine> engine = [self engineForURL:urlString needsFFmpeg:&needsFFmpeg];
    if (!engine) {
        self.lastError = @"Formato Ogg/Opus/FLAC: per ascoltarlo serve ffmpeg in /usr/local/bin";
        self.urlIndex++;
        [self startCurrent];
        return;
    }
    NSLog(@"RadioTray: riproduco %@ (%lu/%lu) con %@", urlString, (unsigned long)self.urlIndex + 1,
          (unsigned long)self.urls.count, engine.engineName);

    self.currentURL = urlString;
    self.hasPlayed = NO;
    self.state = RTPlayerStateConnecting;
    self.engine = engine;
    engine.volume = (float)self.volume / 100.0f;
    engine.outputDeviceUID = self.outputDeviceUID;
    [engine playURL:urlString];

    if (self.engine == engine) {   // il motore potrebbe aver già rinunciato (per esempio ffmpeg che non parte)
        self.connectTimer = [NSTimer scheduledTimerWithTimeInterval:RTConnectTimeout target:self
                                                           selector:@selector(connectTimedOut:) userInfo:nil repeats:NO];
    }
}

- (void)detachEngine
{
    [self.connectTimer invalidate];
    self.connectTimer = nil;
    [self.stallTimer invalidate];
    self.stallTimer = nil;
    [self.icyReader stop];
    self.avMetadataSeen = NO;
    self.declaredBitrate = 0;
    self.declaredFormat = nil;
    self.engineFormat = nil;
    self.engineBitrate = 0;
    if (self.streamFormat || self.streamBitrate) {
        self.streamFormat = nil;
        self.streamBitrate = 0;
        [self.delegate player:self didUpdateStreamFormat:nil bitrate:0];
    }
    id<RTAudioEngine> engine = self.engine;
    self.engine = nil;
    [engine stop];
}

- (void)tryNextWithError:(NSString *)error
{
    NSLog(@"RadioTray: %@ (%@)", error, self.currentURL ?: @"?");
    if (self.everPlayed) {
        // la stazione funzionava ed è caduta: prima si provano subito gli altri server della stessa radio,
        // poi si riprova a intervalli crescenti invece di arrendersi
        if (self.urls.count > 1 && self.failovers + 1 < self.urls.count) {
            self.failovers++;
            self.urlIndex = (self.urlIndex + 1) % self.urls.count;
            NSLog(@"RadioTray: passo al server di riserva %lu/%lu", (unsigned long)self.urlIndex + 1, (unsigned long)self.urls.count);
            [self startCurrent];
            return;
        }
        self.failovers = 0;
        [self scheduleReconnectAfterError:error];
        return;
    }
    self.lastError = error;
    self.urlIndex++;
    [self startCurrent];
}

- (void)scheduleReconnectAfterError:(NSString *)error
{
    [self detachEngine];
    [self cancelReconnect];
    if (self.reconnectAttempt >= RTMaxReconnects) {
        NSString *message = [NSString stringWithFormat:@"%@ (riconnessione non riuscita)", error];
        [self stop];
        [self.delegate player:self didFailWithError:message];
        return;
    }
    NSTimeInterval delay = RTReconnectDelays[self.reconnectAttempt];
    self.reconnectAttempt++;
    self.hasPlayed = NO;
    self.state = RTPlayerStateConnecting;
    NSLog(@"RadioTray: riconnessione n. %lu tra %.0f s", (unsigned long)self.reconnectAttempt, delay);
    [self.delegate player:self willReconnect:self.reconnectAttempt error:error];
    self.reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:delay target:self
                                                         selector:@selector(reconnectTimerFired:) userInfo:nil repeats:NO];
}

- (void)reconnectTimerFired:(NSTimer *)timer
{
    if (timer != self.reconnectTimer) return;
    self.reconnectTimer = nil;
    self.urlIndex = self.goodIndex < self.urls.count ? self.goodIndex : 0;
    self.lastError = nil;
    [self startCurrent];
}

- (void)reconnectNow
{
    if (self.state == RTPlayerStateStopped || self.urls.count == 0) return;
    NSLog(@"RadioTray: riavvio dello stream");
    [self cancelReconnect];
    self.reconnectAttempt = 0;
    self.failovers = 0;
    self.urlIndex = self.goodIndex < self.urls.count ? self.goodIndex : 0;
    self.lastError = nil;
    [self startCurrent];
}

- (void)stallTimedOut:(NSTimer *)timer
{
    if (timer != self.stallTimer) return;
    self.stallTimer = nil;
    if (self.state == RTPlayerStateBuffering) {
        [self tryNextWithError:@"Lo stream si è bloccato"];
    }
}

- (void)connectTimedOut:(NSTimer *)timer
{
    if (self.connectTimer != timer) return;
    self.connectTimer = nil;
    if (!self.hasPlayed) {
        [self tryNextWithError:@"La stazione non risponde (tempo scaduto)"];
    }
}

#pragma mark - Eventi del motore

- (void)audioEngineDidStartPlaying:(id<RTAudioEngine>)engine
{
    if (engine != self.engine) return;
    if (!self.hasPlayed) {
        [self startIcyReaderIfNeeded];
        [self updateStreamInfo];
    }
    self.hasPlayed = YES;
    self.everPlayed = YES;
    self.reconnectAttempt = 0;
    self.failovers = 0;
    self.goodIndex = self.urlIndex;
    [self.connectTimer invalidate];
    self.connectTimer = nil;
    [self.stallTimer invalidate];
    self.stallTimer = nil;
    self.state = RTPlayerStatePlaying;
}

- (void)audioEngineIsWaiting:(id<RTAudioEngine>)engine
{
    if (engine != self.engine) return;
    self.state = self.hasPlayed ? RTPlayerStateBuffering : RTPlayerStateConnecting;
    if (self.hasPlayed && !self.stallTimer) {
        self.stallTimer = [NSTimer scheduledTimerWithTimeInterval:RTStallTimeout target:self
                                                         selector:@selector(stallTimedOut:) userInfo:nil repeats:NO];
    }
}

- (void)audioEngine:(id<RTAudioEngine>)engine didFail:(NSString *)error formatProblem:(BOOL)formatProblem
{
    if (engine != self.engine) return;
    NSString *url = self.currentURL;
    if (formatProblem && engine == self.avEngine && url && !self.hasPlayed && [RTFFmpegEngine isAvailable] &&
        ![self.ffmpegURLs containsObject:url]) {
        // AVPlayer non sa leggere questo stream: si riprova lo stesso indirizzo con ffmpeg
        NSLog(@"RadioTray: AVPlayer non apre %@ (%@), riprovo con ffmpeg", url, error);
        [self.ffmpegURLs addObject:url];
        [self startCurrent];
        return;
    }
    [self tryNextWithError:error];
}

- (void)audioEngine:(id<RTAudioEngine>)engine didReceiveMetadataItems:(NSArray<AVMetadataItem *> *)items
{
    if (engine != self.engine) return;
    [self handleMetadata:items];
}

- (void)audioEngine:(id<RTAudioEngine>)engine didReadTitle:(NSString *)title
{
    if (engine != self.engine || !self.readsTitles) return;
    if (!self.avMetadataSeen) {
        self.avMetadataSeen = YES;   // i titoli arrivano dal motore: la seconda connessione non serve
        [self.icyReader stop];
    }
    [self.delegate player:self didReceiveStreamTitle:title];
}

- (void)audioEngine:(id<RTAudioEngine>)engine didReadStationName:(NSString *)name
{
    if (engine != self.engine) return;
    [self.delegate player:self didReceiveStationName:name];
}

- (void)audioEngine:(id<RTAudioEngine>)engine didReadFormat:(NSString *)format bitrate:(NSInteger)kbps
{
    if (engine != self.engine) return;
    self.engineFormat = format;
    self.engineBitrate = kbps;
    [self updateStreamInfo];
}

#pragma mark - Titoli

- (void)handleMetadata:(NSArray<AVMetadataItem *> *)items
{
    NSString *title = nil;
    NSString *artist = nil;
    // RDS: un JSON con titolo, artista e copertina ufficiale nei metadati ID3 (TXXX / PRIV)
    for (AVMetadataItem *m in items) {
        NSData *raw = m.dataValue ?: [m.stringValue dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *song = [RTTrackInfo stationSongFromData:raw];
        if (!song) continue;
        NSString *t = [song[@"artist"] length] ? [NSString stringWithFormat:@"%@ - %@", song[@"artist"], song[@"title"]] : song[@"title"];
        if (!self.avMetadataSeen) {
            self.avMetadataSeen = YES;
            [self.icyReader stop];
        }
        if (song[@"cover"]) [self.delegate player:self didReceiveCoverURL:song[@"cover"] forStreamTitle:t];
        [self.delegate player:self didReceiveStreamTitle:t];
        return;
    }
    for (AVMetadataItem *m in items) {
        NSString *key = [m.key isKindOfClass:[NSString class]] ? [(NSString *)m.key lowercaseString] : @"";
        NSString *value = m.stringValue;
        if (!value) continue;
        if ([key isEqualToString:@"streamtitle"]) {
            title = value;
        } else if (!title && [m.commonKey isEqualToString:AVMetadataCommonKeyTitle]) {
            title = value;
        } else if ([m.commonKey isEqualToString:AVMetadataCommonKeyArtist]) {
            artist = value;
        }
    }
    if (title && artist && [title rangeOfString:@" - "].location == NSNotFound) {
        // metadati ID3 separati (HLS): si ricompone "Artista - Titolo"
        title = [NSString stringWithFormat:@"%@ - %@", artist, title];
    }
    if (title) {
        if (!self.avMetadataSeen) {
            self.avMetadataSeen = YES;
            [self.icyReader stop];
        }
        [self.delegate player:self didReceiveStreamTitle:title];
    }
}

- (void)setOutputDeviceUID:(NSString *)outputDeviceUID
{
    _outputDeviceUID = [outputDeviceUID copy];
    self.avEngine.outputDeviceUID = _outputDeviceUID;
    self.ffEngine.outputDeviceUID = _outputDeviceUID;   // ffmpeg: si ferma e riparte l'audio sulla nuova uscita
}

- (void)setReadsTitles:(BOOL)readsTitles
{
    if (_readsTitles == readsTitles) return;
    _readsTitles = readsTitles;
    if (!readsTitles) {
        [self.icyReader stop];
    } else if (self.state == RTPlayerStatePlaying) {
        [self startIcyReaderIfNeeded];
    }
}

- (void)startIcyReaderIfNeeded
{
    // su 10.13 AVPlayer non consegna i titoli ICY: li si legge con una seconda connessione
    // (negli stream Ogg/FLAC non ci sono metadati ICY: lì i titoli li legge ffmpeg)
    if (!self.readsTitles || self.avMetadataSeen || !self.currentURL) return;
    if ([[NSURL URLWithString:self.currentURL].path.pathExtension.lowercaseString isEqualToString:@"m3u8"]) return;
    if (self.engine == self.ffEngine &&
        [RTFFmpegOutput needsFFmpegForURL:self.currentURL contentType:self.streamContentTypes[self.currentURL]]) return;
    [self.icyReader startWithURL:self.currentURL];
}

+ (NSString *)formatForContentType:(NSString *)contentType
{
    NSString *ct = contentType.lowercaseString ?: @"";
    if ([ct containsString:@"mpeg"] && ![ct containsString:@"mpegurl"]) return @"MP3";
    if ([ct containsString:@"aacp"]) return @"HE-AAC";
    if ([ct containsString:@"aac"] || [ct containsString:@"mp4"]) return @"AAC";
    if ([ct containsString:@"flac"]) return @"FLAC";
    if ([ct containsString:@"opus"]) return @"Opus";
    if ([ct containsString:@"ogg"]) return @"Ogg";
    if ([ct containsString:@"mpegurl"]) return @"HLS";
    return nil;
}

/// Formato e bitrate da mostrare: quelli del motore, completati dalle intestazioni (icy-br, Content-Type).
- (void)updateStreamInfo
{
    if (!self.engine) return;
    NSString *format = self.engineFormat ?: self.declaredFormat;
    NSInteger kbps = self.declaredBitrate > 0 ? self.declaredBitrate : self.engineBitrate;
    if ((format == self.streamFormat || [format isEqualToString:self.streamFormat ?: @""]) && kbps == self.streamBitrate) return;
    self.streamFormat = format;
    self.streamBitrate = kbps;
    [self.delegate player:self didUpdateStreamFormat:format bitrate:kbps];
}

- (void)metadataReader:(RTIcyMetadataReader *)reader didReadBitrate:(NSInteger)kbps contentType:(NSString *)contentType
{
    if (!self.engine) return;
    self.declaredBitrate = kbps;
    self.declaredFormat = [RTPlayer formatForContentType:contentType];
    [self updateStreamInfo];
}

- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStationName:(NSString *)name
{
    if (!self.engine) return;
    [self.delegate player:self didReceiveStationName:name];
}

- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStreamTitle:(NSString *)title
{
    if (self.avMetadataSeen || !self.engine) return;
    [self.delegate player:self didReceiveStreamTitle:title];
}

@end
