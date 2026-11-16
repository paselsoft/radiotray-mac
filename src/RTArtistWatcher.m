#import "RTArtistWatcher.h"
#import "RTIcyMetadataReader.h"
#import "RTStreamResolver.h"
#import "RTOnAir.h"

static const NSTimeInterval RTListenTimeout = 15;   // secondi massimi per stazione
static const NSTimeInterval RTPause = 3;            // tra una stazione e l'altra
static const NSTimeInterval RTRenotifyAfter = 30 * 60;

@interface RTArtistWatcher () <RTIcyMetadataReaderDelegate>
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, strong) NSMutableArray<NSArray<NSString *> *> *queue;
@property (nonatomic, strong, nullable) NSArray<NSString *> *current;
@property (nonatomic, strong) RTIcyMetadataReader *reader;
@property (nonatomic, strong) RTStreamResolver *resolver;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSTimer *timeout;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *notified;
@property (nonatomic) NSUInteger generation;
@end

@implementation RTArtistWatcher

- (instancetype)init
{
    if ((self = [super init])) {
        _artists = @[];
        _queue = [NSMutableArray array];
        _notified = [NSMutableDictionary dictionary];
        _reader = [RTIcyMetadataReader new];
        _reader.delegate = self;
        _resolver = [RTStreamResolver new];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

static NSString *RTFold(NSString *s)
{
    return [[s stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)artistIn:(NSString *)title matching:(NSArray<NSString *> *)artists
{
    NSString *t = RTFold(title);
    for (NSString *artist in artists) {
        NSString *a = RTFold(artist);
        if (a.length < 2) continue;
        NSString *pattern = [NSString stringWithFormat:@"(^|[^\\p{L}\\p{N}])%@($|[^\\p{L}\\p{N}])",
                             [NSRegularExpression escapedPatternForString:a]];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
        if ([re firstMatchInString:t options:0 range:NSMakeRange(0, t.length)]) return artist;
    }
    return nil;
}

- (void)start
{
    if (self.running) return;
    self.running = YES;
    [self next];
}

- (void)stop
{
    self.running = NO;
    self.generation++;
    [self.timeout invalidate];
    self.timeout = nil;
    [self.reader stop];
    [self.resolver cancel];
    self.current = nil;
    [self.queue removeAllObjects];
}

- (void)finishStation
{
    [self.timeout invalidate];
    self.timeout = nil;
    [self.reader stop];
    self.current = nil;
    if (!self.running) return;
    NSUInteger generation = self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RTPause * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.generation == generation) [self next];
    });
}

- (void)next
{
    if (!self.running) return;
    if (self.artists.count == 0) {
        [self stop];
        return;
    }
    if (self.queue.count == 0) {
        [self.queue addObjectsFromArray:[self.delegate stationsToWatch:self] ?: @[]];
        if (self.queue.count == 0) {
            // nessuna stazione da controllare: si riprova fra un minuto
            NSUInteger generation = self.generation;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.generation == generation) [self next];
            });
            return;
        }
    }
    NSArray<NSString *> *station = self.queue.firstObject;
    [self.queue removeObjectAtIndex:0];
    self.current = station;
    NSUInteger generation = self.generation;
    self.timeout = [NSTimer scheduledTimerWithTimeInterval:RTListenTimeout target:self selector:@selector(timedOut:)
                                                  userInfo:nil repeats:NO];
    __weak typeof(self) weakSelf = self;
    [self.resolver resolve:station[2] direct:NO completion:^(NSArray<NSString *> *streams, NSString *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.generation != generation || strongSelf.current != station) return;
        if (!streams.count) {
            [strongSelf finishStation];
            return;
        }
        NSString *source = [RTOnAir sourceForURLs:[@[station[2]] arrayByAddingObjectsFromArray:streams]];
        if ([source hasPrefix:@"gedi:"]) {
            [strongSelf readGedi:[source substringFromIndex:5] station:station generation:generation];
        } else if ([streams[0].lowercaseString containsString:@".m3u8"]) {
            [strongSelf finishStation];   // HLS senza titoli leggibili da qui
        } else {
            [strongSelf.reader startWithURL:streams[0]];
        }
    }];
}

- (void)readGedi:(NSString *)site station:(NSArray<NSString *> *)station generation:(NSUInteger)generation
{
    NSURL *url = [NSURL URLWithString:[site stringByAppendingString:@"/api/pub/v2/all/gdwc-audio-player/onair?format=json"]];
    [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation != generation || self.current != station) return;
            NSDictionary *song = [RTOnAir songFromGediJSON:data];
            if ([song[@"artist"] length]) [self check:[NSString stringWithFormat:@"%@ - %@", song[@"artist"], song[@"title"]]];
            [self finishStation];
        });
    }] resume];
}

- (void)timedOut:(NSTimer *)timer
{
    if (timer != self.timeout) return;
    [self finishStation];
}

- (void)check:(NSString *)title
{
    NSArray<NSString *> *station = self.current;
    if (!station || !title.length) return;
    NSString *artist = [RTArtistWatcher artistIn:title matching:self.artists];
    if (!artist) return;
    NSString *key = [NSString stringWithFormat:@"%@\n%@\n%@", station[0], station[1], RTFold(title)];
    NSDate *last = self.notified[key];
    if (last && -last.timeIntervalSinceNow < RTRenotifyAfter) return;
    self.notified[key] = [NSDate date];
    [self.delegate artistWatcher:self found:artist title:title station:station];
}

- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStreamTitle:(NSString *)title
{
    if (!self.current) return;
    [self check:title];
    [self finishStation];
}

@end
