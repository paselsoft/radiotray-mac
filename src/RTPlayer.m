#import "RTPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "RTIcyMetadataReader.h"

static void *RTItemStatusContext = &RTItemStatusContext;
static void *RTItemMetadataContext = &RTItemMetadataContext;
static void *RTPlayerTimeControlContext = &RTPlayerTimeControlContext;

static const NSTimeInterval RTConnectTimeout = 20.0;
static const NSTimeInterval RTStallTimeout = 20.0;
/// attese prima di ogni tentativo di riconnessione (secondi)
static const NSTimeInterval RTReconnectDelays[] = { 2, 5, 10, 15, 20, 30, 30, 30, 60, 60 };
static const NSUInteger RTMaxReconnects = sizeof(RTReconnectDelays) / sizeof(RTReconnectDelays[0]);

@interface RTPlayer () <RTIcyMetadataReaderDelegate>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong, nullable) AVPlayerItem *item;
@property (nonatomic, copy) NSArray<NSString *> *urls;
@property (nonatomic) NSUInteger urlIndex;
@property (nonatomic, readwrite) RTPlayerState state;
@property (nonatomic, copy, readwrite, nullable) NSString *currentURL;
@property (nonatomic, copy, nullable) NSString *lastError;
@property (nonatomic, strong, nullable) NSTimer *connectTimer;
@property (nonatomic) BOOL hasPlayed;          // l'URL corrente ha suonato
@property (nonatomic) BOOL everPlayed;         // la stazione ha suonato almeno una volta: se cade si riconnette
@property (nonatomic) NSUInteger reconnectAttempt;
@property (nonatomic, strong, nullable) NSTimer *reconnectTimer;
@property (nonatomic, strong, nullable) NSTimer *stallTimer;
@property (nonatomic) BOOL avMetadataSeen;   // AVPlayer consegna i metadati: il lettore ICY non serve
@property (nonatomic, strong) RTIcyMetadataReader *icyReader;
@end

@implementation RTPlayer

- (instancetype)init
{
    if ((self = [super init])) {
        _player = [AVPlayer new];
        _player.automaticallyWaitsToMinimizeStalling = YES;
        _urls = @[];
        _volume = 100;
        _icyReader = [RTIcyMetadataReader new];
        _icyReader.delegate = self;
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

- (void)setVolume:(NSInteger)volume
{
    _volume = MAX(0, MIN(100, volume));
    self.player.volume = (float)_volume / 100.0f;
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
    [self detachItem];
    [self.player pause];
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
    [self detachItem];
    [self.player pause];
    self.urls = @[];
    self.currentURL = nil;
    self.state = RTPlayerStateStopped;
}

- (void)startCurrent
{
    [self detachItem];
    if (self.urlIndex >= self.urls.count) {
        NSString *error = self.lastError ?: @"Impossibile riprodurre la stazione";
        [self stop];
        [self.delegate player:self didFailWithError:error];
        return;
    }

    NSString *urlString = self.urls[self.urlIndex];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        self.lastError = @"URL dello stream non valido";
        self.urlIndex++;
        [self startCurrent];
        return;
    }
    NSLog(@"RadioTray: riproduco %@ (%lu/%lu)", urlString, (unsigned long)self.urlIndex + 1, (unsigned long)self.urls.count);

    self.currentURL = urlString;
    self.hasPlayed = NO;
    self.state = RTPlayerStateConnecting;

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
    self.player.volume = (float)self.volume / 100.0f;
    [self.player play];

    self.connectTimer = [NSTimer scheduledTimerWithTimeInterval:RTConnectTimeout target:self
                                                       selector:@selector(connectTimedOut:) userInfo:nil repeats:NO];
}

- (void)detachItem
{
    [self.connectTimer invalidate];
    self.connectTimer = nil;
    [self.stallTimer invalidate];
    self.stallTimer = nil;
    [self.icyReader stop];
    self.avMetadataSeen = NO;
    AVPlayerItem *item = self.item;
    if (!item) return;
    self.item = nil;
    [item removeObserver:self forKeyPath:@"status" context:RTItemStatusContext];
    [item removeObserver:self forKeyPath:@"timedMetadata" context:RTItemMetadataContext];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:item];
    [self.player replaceCurrentItemWithPlayerItem:nil];
}

- (void)tryNextWithError:(NSString *)error
{
    NSLog(@"RadioTray: %@ (%@)", error, self.currentURL ?: @"?");
    if (self.everPlayed) {
        // la stazione funzionava: è caduta la connessione, si riprova invece di arrendersi
        [self scheduleReconnectAfterError:error];
        return;
    }
    self.lastError = error;
    self.urlIndex++;
    [self startCurrent];
}

- (void)scheduleReconnectAfterError:(NSString *)error
{
    [self detachItem];
    [self.player pause];
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
    self.urlIndex = 0;
    self.lastError = nil;
    [self startCurrent];
}

- (void)reconnectNow
{
    if (self.state == RTPlayerStateStopped || self.urls.count == 0) return;
    NSLog(@"RadioTray: riavvio dello stream");
    [self cancelReconnect];
    self.reconnectAttempt = 0;
    self.urlIndex = 0;
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

- (void)itemFailedToPlay:(NSNotification *)note
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self itemFailedToPlay:note]; });
        return;
    }
    if (note.object != self.item) return;
    NSError *error = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    [self tryNextWithError:error.localizedDescription ?: @"Lo stream si è interrotto"];
}

- (void)itemEnded:(NSNotification *)note
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self itemEnded:note]; });
        return;
    }
    if (note.object != self.item) return;
    [self tryNextWithError:@"Lo stream si è interrotto"];
}

- (void)handleMetadata:(NSArray<AVMetadataItem *> *)items
{
    NSString *title = nil;
    NSString *artist = nil;
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

- (void)startIcyReaderIfNeeded
{
    // su 10.13 AVPlayer non consegna i titoli ICY: li si legge con una seconda connessione
    if (self.avMetadataSeen || !self.currentURL) return;
    if ([[NSURL URLWithString:self.currentURL].path.pathExtension.lowercaseString isEqualToString:@"m3u8"]) return;
    [self.icyReader startWithURL:self.currentURL];
}

- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStationName:(NSString *)name
{
    if (!self.item) return;
    [self.delegate player:self didReceiveStationName:name];
}

- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStreamTitle:(NSString *)title
{
    if (self.avMetadataSeen || !self.item) return;
    [self.delegate player:self didReceiveStreamTitle:title];
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
            [self tryNextWithError:self.item.error.localizedDescription ?: @"Formato dello stream non supportato"];
        }
    } else if (context == RTItemMetadataContext) {
        if (object != self.item) return;
        [self handleMetadata:self.item.timedMetadata];
    } else if (context == RTPlayerTimeControlContext) {
        if (!self.item) return;
        switch (self.player.timeControlStatus) {
            case AVPlayerTimeControlStatusPlaying:
                if (!self.hasPlayed) [self startIcyReaderIfNeeded];
                self.hasPlayed = YES;
                self.everPlayed = YES;
                self.reconnectAttempt = 0;
                [self.connectTimer invalidate];
                self.connectTimer = nil;
                [self.stallTimer invalidate];
                self.stallTimer = nil;
                self.state = RTPlayerStatePlaying;
                break;
            case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                self.state = self.hasPlayed ? RTPlayerStateBuffering : RTPlayerStateConnecting;
                if (self.hasPlayed && !self.stallTimer) {
                    self.stallTimer = [NSTimer scheduledTimerWithTimeInterval:RTStallTimeout target:self
                                                                     selector:@selector(stallTimedOut:) userInfo:nil repeats:NO];
                }
                break;
            case AVPlayerTimeControlStatusPaused:
                break;
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
