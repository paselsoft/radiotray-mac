#import "RTHttpsUpgrade.h"
#import "RTStationChecker.h"

static NSString *const kStoreKey = @"https-upgrades";
static const NSTimeInterval RTRecheckAfter = 30 * 24 * 3600;

@interface RTHttpsUpgrade ()
@property (nonatomic, strong) RTStationChecker *checker;
@property (nonatomic, strong) NSMutableArray<NSString *> *queue;
@property (nonatomic) BOOL busy;
@end

@implementation RTHttpsUpgrade

+ (instancetype)shared
{
    static RTHttpsUpgrade *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [RTHttpsUpgrade new]; });
    return shared;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _checker = [RTStationChecker new];
        _queue = [NSMutableArray array];
    }
    return self;
}

+ (NSString *)httpsCandidateForURL:(NSString *)url
{
    NSURLComponents *c = [NSURLComponents componentsWithString:url];
    if (![c.scheme.lowercaseString isEqualToString:@"http"] || !c.host.length) return nil;
    if (c.port && c.port.integerValue != 80) return nil;   // su una porta particolare l'https quasi mai c'è
    NSCharacterSet *notIP = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789.:[]"] invertedSet];
    if ([c.host rangeOfCharacterFromSet:notIP].location == NSNotFound) return nil;   // indirizzo IP: niente certificato
    c.scheme = @"https";
    c.port = nil;
    return c.string;
}

- (NSDictionary *)store
{
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kStoreKey];
    return d ?: @{};
}

/// @YES / @NO se il risultato è noto e recente, nil se va (ri)provato.
- (NSNumber *)knownResultFor:(NSString *)url
{
    NSDictionary *e = [self store][url];
    if (![e isKindOfClass:[NSDictionary class]]) return nil;
    NSDate *date = e[@"date"];
    if (![date isKindOfClass:[NSDate class]] || -date.timeIntervalSinceNow > RTRecheckAfter) return nil;
    return [e[@"ok"] isKindOfClass:[NSNumber class]] ? e[@"ok"] : nil;
}

- (void)remember:(BOOL)ok forURL:(NSString *)url
{
    NSMutableDictionary *d = [[self store] mutableCopy];
    d[url] = @{ @"ok": @(ok), @"date": [NSDate date] };
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kStoreKey];
}

- (NSArray<NSString *> *)upgradedURLs:(NSArray<NSString *> *)urls
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *u in urls) {
        NSString *https = [RTHttpsUpgrade httpsCandidateForURL:u];
        if (https && [[self knownResultFor:u] boolValue] && ![out containsObject:https]) [out addObject:https];
        if (![out containsObject:u]) [out addObject:u];
    }
    return out;
}

- (void)probeURLs:(NSArray<NSString *> *)urls
{
    NSUInteger added = 0;
    for (NSString *u in urls) {
        if (added >= 3) break;
        if (![RTHttpsUpgrade httpsCandidateForURL:u] || [self knownResultFor:u] || [self.queue containsObject:u]) continue;
        [self.queue addObject:u];
        added++;
    }
    [self next];
}

- (void)next
{
    if (self.busy || self.queue.count == 0) return;
    NSString *url = self.queue.firstObject;
    [self.queue removeObjectAtIndex:0];
    NSString *https = [RTHttpsUpgrade httpsCandidateForURL:url];
    self.busy = YES;
    __weak typeof(self) weakSelf = self;
    [self.checker checkURL:https direct:YES completion:^(BOOL ok, NSString *detail) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSLog(@"RadioTray: https per %@: %@ (%@)", url, ok ? @"sì" : @"no", detail);
        [strongSelf remember:ok forURL:url];
        strongSelf.busy = NO;
        [strongSelf next];
    }];
}

@end
