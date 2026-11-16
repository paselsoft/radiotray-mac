#import "RTStationChecker.h"
#import "RTStreamResolver.h"

@interface RTStationChecker () <NSURLSessionDataDelegate>
@property (nonatomic, strong) RTStreamResolver *resolver;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy, nullable) RTCheckCompletion completion;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@end

@implementation RTStationChecker

- (instancetype)init
{
    if ((self = [super init])) {
        _resolver = [RTStreamResolver new];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 12;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"RadioTray-Mac" };
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (void)dealloc
{
    [_session invalidateAndCancel];
}

+ (BOOL)isAudioResponseStatus:(NSInteger)status contentType:(NSString *)contentType
{
    if (status < 200 || status >= 300) return NO;
    NSString *ct = contentType.lowercaseString ?: @"";
    if ([ct hasPrefix:@"text/html"] || [ct hasPrefix:@"application/json"]) return NO;   // pagina d'errore
    return YES;
}

- (void)finish:(BOOL)ok detail:(NSString *)detail
{
    RTCheckCompletion c = self.completion;
    self.completion = nil;
    [self.task cancel];
    self.task = nil;
    if (c) c(ok, detail);
}

- (void)cancel
{
    self.completion = nil;
    [self.resolver cancel];
    [self.task cancel];
    self.task = nil;
}

- (void)checkURL:(NSString *)url direct:(BOOL)direct completion:(RTCheckCompletion)completion
{
    [self cancel];
    self.completion = completion;
    __weak typeof(self) weakSelf = self;
    [self.resolver resolve:url direct:direct completion:^(NSArray<NSString *> *streams, NSString *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.completion) return;
        if (!streams.count) {
            [strongSelf finish:NO detail:error ?: @"playlist vuota"];
            return;
        }
        NSURL *u = [NSURL URLWithString:streams[0]];
        if (!u) {
            [strongSelf finish:NO detail:@"indirizzo dello stream non valido"];
            return;
        }
        strongSelf.task = [strongSelf.session dataTaskWithURL:u];
        [strongSelf.task resume];
    }];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    completionHandler(NSURLSessionResponseCancel);   // basta l'intestazione: lo stream non finisce mai
    if (dataTask != self.task) return;
    NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
    NSString *ct = response.MIMEType;
    if ([RTStationChecker isAudioResponseStatus:code contentType:ct]) {
        NSString *br = nil;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSDictionary *h = [(NSHTTPURLResponse *)response allHeaderFields];
            for (NSString *k in h) if ([k caseInsensitiveCompare:@"icy-br"] == NSOrderedSame) br = [h[k] description];
        }
        NSString *kind = [ct containsString:@"mpegurl"] ? @"HLS" : ([ct containsString:@"mpeg"] ? @"MP3" :
                         ([ct containsString:@"aac"] ? @"AAC" : (ct.length ? ct : @"audio")));
        [self finish:YES detail:br.integerValue > 0 ? [NSString stringWithFormat:@"%@ · %@ kbps", kind, br] : kind];
    } else {
        [self finish:NO detail:code >= 400 ? [NSString stringWithFormat:@"il server risponde HTTP %ld", (long)code]
                                           : @"il server risponde con una pagina web, non con audio"];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (task != self.task || !self.completion) return;
    if (error.code == NSURLErrorCancelled) return;
    [self finish:NO detail:error.code == NSURLErrorTimedOut ? @"non risponde (tempo scaduto)"
                                                            : (error.localizedDescription ?: @"errore di rete")];
}

@end
