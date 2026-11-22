#import "RTAVPlayerEngine.h"
#import <AVFoundation/AVFoundation.h>

static void *RTItemStatusContext = &RTItemStatusContext;
static void *RTItemMetadataContext = &RTItemMetadataContext;
static void *RTPlayerTimeControlContext = &RTPlayerTimeControlContext;

@interface RTAVPlayerEngine ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong, nullable) AVPlayerItem *item;
@property (nonatomic, strong, nullable) NSTimer *infoTimer;
@property (nonatomic) BOOL played;
@end

@implementation RTAVPlayerEngine

@synthesize delegate = _delegate;
@synthesize volume = _volume;
@synthesize outputDeviceUID = _outputDeviceUID;

- (instancetype)init
{
    if ((self = [super init])) {
        _player = [AVPlayer new];
        _player.automaticallyWaitsToMinimizeStalling = YES;
        _volume = 1;
        [_player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew
                     context:RTPlayerTimeControlContext];
    }
    return self;
}

- (void)dealloc
{
    [self detachItem];
    [_player removeObserver:self forKeyPath:@"timeControlStatus" context:RTPlayerTimeControlContext];
}

- (NSString *)engineName { return @"AVPlayer"; }

- (void)setVolume:(float)volume
{
    _volume = volume;
    self.player.volume = volume;
}

- (void)setOutputDeviceUID:(NSString *)outputDeviceUID
{
    _outputDeviceUID = [outputDeviceUID copy];
    self.player.audioOutputDeviceUniqueID = _outputDeviceUID;
}

- (void)playURL:(NSString *)urlString
{
    [self detachItem];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self.delegate audioEngine:self didFail:@"URL dello stream non valido" formatProblem:NO];
        return;
    }
    self.played = NO;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.preferredForwardBufferDuration = 4.0;
    self.item = item;
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:RTItemStatusContext];
    [item addObserver:self forKeyPath:@"timedMetadata" options:NSKeyValueObservingOptionNew context:RTItemMetadataContext];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(itemFailedToPlay:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    [nc addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];

    [self.player replaceCurrentItemWithPlayerItem:item];
    self.player.volume = self.volume;
    [self.player play];
}

- (void)stop
{
    [self detachItem];
    [self.player pause];
}

- (void)detachItem
{
    [self.infoTimer invalidate];
    self.infoTimer = nil;
    AVPlayerItem *item = self.item;
    if (!item) return;
    self.item = nil;
    [item removeObserver:self forKeyPath:@"status" context:RTItemStatusContext];
    [item removeObserver:self forKeyPath:@"timedMetadata" context:RTItemMetadataContext];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:item];
    [self.player replaceCurrentItemWithPlayerItem:nil];
}

- (void)itemFailedToPlay:(NSNotification *)note
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self itemFailedToPlay:note]; });
        return;
    }
    if (note.object != self.item) return;
    NSError *error = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    [self.delegate audioEngine:self didFail:error.localizedDescription ?: @"Lo stream si è interrotto" formatProblem:NO];
}

- (void)itemEnded:(NSNotification *)note
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self itemEnded:note]; });
        return;
    }
    if (note.object != self.item) return;
    [self.delegate audioEngine:self didFail:@"Lo stream si è interrotto" formatProblem:NO];
}

/// Formato dalla traccia audio, bitrate dalla stima della traccia o dal registro HLS.
- (void)updateStreamInfo
{
    AVPlayerItem *item = self.item;
    if (!item) return;
    NSString *format = nil;
    double bitrate = 0;
    for (AVPlayerItemTrack *t in item.tracks) {
        AVAssetTrack *track = t.assetTrack;
        if (![track.mediaType isEqualToString:AVMediaTypeAudio]) continue;
        for (id desc in track.formatDescriptions) {
            switch (CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)desc)) {
                case kAudioFormatMPEGLayer3: format = @"MP3"; break;
                case kAudioFormatMPEG4AAC: format = @"AAC"; break;
                case kAudioFormatMPEG4AAC_HE:
                case kAudioFormatMPEG4AAC_HE_V2: format = @"HE-AAC"; break;
                default: break;
            }
        }
        if (bitrate <= 0 && track.estimatedDataRate > 0) bitrate = track.estimatedDataRate;
    }
    if (bitrate <= 0) {
        AVPlayerItemAccessLogEvent *event = item.accessLog.events.lastObject;
        if (event.indicatedBitrate > 0) bitrate = event.indicatedBitrate;
        else if (event.observedBitrate > 0) bitrate = event.observedBitrate;
    }
    if ([self.delegate respondsToSelector:@selector(audioEngine:didReadFormat:bitrate:)]) {
        [self.delegate audioEngine:self didReadFormat:format bitrate:(NSInteger)lround(bitrate / 1000.0)];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    BOOL ours = context == RTItemStatusContext || context == RTItemMetadataContext || context == RTPlayerTimeControlContext;
    if (ours && ![NSThread isMainThread]) {
        // tutta la logica gira sul thread principale
        dispatch_async(dispatch_get_main_queue(), ^{
            [self observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        });
        return;
    }
    if (context == RTItemStatusContext) {
        if (object != self.item) return;
        if (self.item.status == AVPlayerItemStatusFailed) {
            // AVPlayer non riesce ad aprire lo stream: di solito un formato che non conosce (Ogg, FLAC…)
            [self.delegate audioEngine:self didFail:self.item.error.localizedDescription ?: @"Formato dello stream non supportato"
                         formatProblem:!self.played];
        }
    } else if (context == RTItemMetadataContext) {
        if (object != self.item) return;
        if ([self.delegate respondsToSelector:@selector(audioEngine:didReceiveMetadataItems:)]) {
            [self.delegate audioEngine:self didReceiveMetadataItems:self.item.timedMetadata ?: @[]];
        }
    } else if (context == RTPlayerTimeControlContext) {
        if (!self.item) return;
        switch (self.player.timeControlStatus) {
            case AVPlayerTimeControlStatusPlaying:
                if (!self.played) {
                    self.played = YES;
                    [self updateStreamInfo];
                    // il registro di accesso (bitrate HLS) si riempie dopo qualche secondo
                    [self.infoTimer invalidate];
                    self.infoTimer = [NSTimer scheduledTimerWithTimeInterval:6 target:self selector:@selector(updateStreamInfo)
                                                                    userInfo:nil repeats:NO];
                }
                [self.delegate audioEngineDidStartPlaying:self];
                break;
            case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                [self.delegate audioEngineIsWaiting:self];
                break;
            case AVPlayerTimeControlStatusPaused:
                break;
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
