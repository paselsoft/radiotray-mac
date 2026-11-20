#import "RTHttpsUpgrade.h"
#import "RTStationChecker.h"

static NSString *const kStoreKey = @"https-upgrades-2";   // -2: ora si controllano anche i titoli (ICY)
static const NSTimeInterval RTRecheckAfter = 30 * 24 * 3600;

typedef void (^RTHeadCompletion)(BOOL audio, BOOL icy, NSString *detail);

@interface RTHttpsUpgrade () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, RTHeadCompletion> *pending;
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
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 12;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"RadioTray-Mac", @"Icy-MetaData": @"1" };
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
        _pending = [NSMutableDictionary dictionary];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"https-upgrades"];   // risultati della 1.10–1.14
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

+ (BOOL)acceptHTTPSAudio:(BOOL)httpsAudio httpsTitles:(BOOL)httpsTitles httpTitles:(BOOL)httpTitles
{
    // l'https deve suonare e, se l'http manda i titoli, mandarli anche lui (Radio Monte Carlo no)
    return httpsAudio && (httpsTitles || !httpTitles);
}

/// Si legge solo l'intestazione della risposta (audio? titoli ICY?), poi si chiude.
- (void)head:(NSString *)address completion:(RTHeadCompletion)completion
{
    NSURL *url = [NSURL URLWithString:address];
    if (!url) {
        completion(NO, NO, @"indirizzo non valido");
        return;
    }
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:url];
    self.pending[@(task.taskIdentifier)] = completion;
    [task resume];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    completionHandler(NSURLSessionResponseCancel);
    RTHeadCompletion completion = self.pending[@(dataTask.taskIdentifier)];
    [self.pending removeObjectForKey:@(dataTask.taskIdentifier)];
    if (!completion) return;
    NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
    BOOL icy = NO;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSDictionary *h = [(NSHTTPURLResponse *)response allHeaderFields];
        for (NSString *k in h) if ([k caseInsensitiveCompare:@"icy-metaint"] == NSOrderedSame && [h[k] integerValue] > 0) icy = YES;
    }
    BOOL audio = [RTStationChecker isAudioResponseStatus:code contentType:response.MIMEType];
    completion(audio, icy, [NSString stringWithFormat:@"HTTP %ld %@%@", (long)code, response.MIMEType ?: @"", icy ? @", titoli" : @""]);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    RTHeadCompletion completion = self.pending[@(task.taskIdentifier)];
    [self.pending removeObjectForKey:@(task.taskIdentifier)];
    if (completion) completion(NO, NO, error.localizedDescription ?: @"nessuna risposta");
}

- (void)next
{
    if (self.busy || self.queue.count == 0) return;
    NSString *url = self.queue.firstObject;
    [self.queue removeObjectAtIndex:0];
    NSString *https = [RTHttpsUpgrade httpsCandidateForURL:url];
    self.busy = YES;
    __weak typeof(self) weakSelf = self;
    [self head:url completion:^(BOOL httpAudio, BOOL httpTitles, NSString *httpDetail) {
        [weakSelf head:https completion:^(BOOL httpsAudio, BOOL httpsTitles, NSString *httpsDetail) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            BOOL ok = [RTHttpsUpgrade acceptHTTPSAudio:httpsAudio httpsTitles:httpsTitles httpTitles:httpTitles];
            NSLog(@"RadioTray: https per %@: %@ (http: %@; https: %@)", url, ok ? @"sì" : @"no", httpDetail, httpsDetail);
            [strongSelf remember:ok forURL:url];
            strongSelf.busy = NO;
            [strongSelf next];
        }];
    }];
}

@end
