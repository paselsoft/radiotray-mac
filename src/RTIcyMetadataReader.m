#import "RTIcyMetadataReader.h"
#import "RTIcyParser.h"

static const NSUInteger RTIcyMaxRetries = 5;
static const NSTimeInterval RTIcyRetryDelay = 10.0;

@interface RTIcyMetadataReader () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@property (nonatomic, strong, nullable) RTIcyParser *parser;
@property (nonatomic, copy, nullable) NSString *url;
@property (nonatomic, copy, nullable) NSString *lastTitle;
@property (nonatomic) NSUInteger retries;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, readwrite) BOOL unsupported;
@end

@implementation RTIcyMetadataReader

- (instancetype)init
{
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 30;
        cfg.timeoutIntervalForResource = 60 * 60 * 24 * 7;   // lo stream non finisce mai
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"RadioTray-Mac/1.0", @"Icy-MetaData": @"1" };
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (void)dealloc
{
    [_session invalidateAndCancel];
}

- (void)startWithURL:(NSString *)url
{
    [self stop];
    self.url = url;
    self.lastTitle = nil;
    self.retries = 0;
    self.unsupported = NO;
    [self connect];
}

- (void)stop
{
    self.generation++;
    self.url = nil;
    self.parser = nil;
    [self.task cancel];
    self.task = nil;
}

- (void)connect
{
    NSURL *u = self.url ? [NSURL URLWithString:self.url] : nil;
    if (!u) return;
    self.parser = nil;
    self.task = [self.session dataTaskWithURL:u];
    [self.task resume];
}

- (void)retryLater
{
    if (!self.url || self.unsupported || self.retries >= RTIcyMaxRetries) return;
    self.retries++;
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RTIcyRetryDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.generation == generation && !strongSelf.task) [strongSelf connect];
    });
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    if (dataTask != self.task) {
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    NSInteger metaint = 0, bitrate = 0;
    NSString *stationName = nil;
    NSString *contentType = response.MIMEType;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
        for (NSString *key in headers) {
            if ([key caseInsensitiveCompare:@"icy-metaint"] == NSOrderedSame) {
                metaint = [[headers[key] description] integerValue];
            } else if ([key caseInsensitiveCompare:@"icy-br"] == NSOrderedSame) {
                // a volte "128,128": si prende il primo numero
                bitrate = [[[headers[key] description] componentsSeparatedByString:@","].firstObject integerValue];
            } else if ([key caseInsensitiveCompare:@"icy-name"] == NSOrderedSame) {
                stationName = [RTIcyParser stationNameFromHeader:[headers[key] description]];
            }
        }
    }
    if (stationName && [self.delegate respondsToSelector:@selector(metadataReader:didReadStationName:)]) {
        [self.delegate metadataReader:self didReadStationName:stationName];
    }
    if ([self.delegate respondsToSelector:@selector(metadataReader:didReadBitrate:contentType:)]) {
        [self.delegate metadataReader:self didReadBitrate:bitrate contentType:contentType];
    }
    if (metaint <= 0) {
        NSLog(@"RadioTray: lo stream non invia metadati ICY (%@)", self.url);
        self.unsupported = YES;
        self.task = nil;
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    self.retries = 0;
    self.parser = [[RTIcyParser alloc] initWithMetaInterval:(NSUInteger)metaint];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    if (dataTask != self.task || !self.parser) return;
    for (NSString *title in [self.parser feed:data]) {
        if ([title isEqualToString:self.lastTitle ?: @""]) continue;
        self.lastTitle = title;
        [self.delegate metadataReader:self didReadStreamTitle:title];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (task != self.task) return;
    self.task = nil;
    self.parser = nil;
    if (error.code == NSURLErrorCancelled && [error.domain isEqualToString:NSURLErrorDomain]) return;
    NSLog(@"RadioTray: lettura dei metadati interrotta (%@), nuovo tentativo", error.localizedDescription ?: @"fine dello stream");
    [self retryLater];
}

@end
