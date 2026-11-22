#import "RTStreamResolver.h"
#import "RTPlaylistParser.h"

static const NSUInteger RTMaxPlaylistBytes = 4096;

@interface RTStreamResolver () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, copy, nullable) RTResolveCompletion completion;
@property (nonatomic, copy) NSString *originalURL;
@property (nonatomic, copy, nullable) NSString *contentType;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *streamContentTypes;
@property (nonatomic, copy, readwrite, nullable) NSString *lastDecision;
@end

@implementation RTStreamResolver

- (instancetype)init
{
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 10;
        cfg.timeoutIntervalForResource = 20;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"RadioTray-Mac/1.0", @"Accept": @"*/*" };
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
        _buffer = [NSMutableData data];
        _originalURL = @"";
        _streamContentTypes = @{};
    }
    return self;
}

- (void)dealloc
{
    [_session invalidateAndCancel];
}

- (void)cancel
{
    self.completion = nil;
    [self.task cancel];
    self.task = nil;
}

- (void)resolve:(NSString *)url direct:(BOOL)direct completion:(RTResolveCompletion)completion
{
    [self cancel];
    self.originalURL = url;
    self.contentType = nil;
    self.streamContentTypes = @{};
    [self.buffer setLength:0];

    NSURL *u = [NSURL URLWithString:url];
    NSString *scheme = u.scheme.lowercaseString;
    if (!u || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        // mms://, rtsp:// e simili non sono supportati da AVPlayer: lo si dice subito
        NSString *msg = u ? [NSString stringWithFormat:@"Protocollo \"%@\" non supportato", u.scheme ?: @"?"]
                          : @"URL della stazione non valido";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, msg); });
        return;
    }

    if (direct || [RTPlaylistParser urlLooksDirect:url]) {
        self.lastDecision = direct ? @"stream diretto (direct=true)" : @"stream diretto (estensione)";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(@[url], nil); });
        return;
    }

    self.completion = completion;
    self.task = [self.session dataTaskWithURL:u];
    [self.task resume];
}

- (void)finishWithStreams:(NSArray<NSString *> *)streams error:(NSString *)error decision:(NSString *)decision
{
    RTResolveCompletion completion = self.completion;
    self.completion = nil;
    NSURLSessionDataTask *task = self.task;
    self.task = nil;
    [task cancel];
    self.lastDecision = decision;
    if (completion) completion(streams, error);
}

- (NSString *)effectiveURL:(NSURLSessionTask *)task
{
    NSString *u = task.response.URL.absoluteString ?: task.currentRequest.URL.absoluteString;
    return u.length ? u : self.originalURL;
}

- (void)decideWithTask:(NSURLSessionTask *)task
{
    NSString *effective = [self effectiveURL:task];
    if ([RTPlaylistParser isHLSContentType:self.contentType data:self.buffer]) {
        [self finishWithStreams:@[effective] error:nil decision:@"stream HLS"];
        return;
    }
    NSString *format = nil;
    NSArray<NSString *> *urls = [RTPlaylistParser urlsFromData:self.buffer contentType:self.contentType
                                                       baseURL:[NSURL URLWithString:effective] formatName:&format];
    if (!urls) {
        [self finishWithStreams:@[effective] error:nil
                       decision:[NSString stringWithFormat:@"nessuna playlist riconosciuta (%@): stream diretto",
                                 self.contentType ?: @"tipo sconosciuto"]];
        return;
    }
    if (urls.count == 0) {
        [self finishWithStreams:nil error:@"La playlist della stazione è vuota"
                       decision:[NSString stringWithFormat:@"playlist %@ vuota", format]];
        return;
    }
    [self finishWithStreams:urls error:nil
                   decision:[NSString stringWithFormat:@"playlist %@ con %lu voci", format, (unsigned long)urls.count]];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    if (dataTask != self.task) {
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    self.contentType = response.MIMEType;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger code = [(NSHTTPURLResponse *)response statusCode];
        NSString *ct = [(NSHTTPURLResponse *)response allHeaderFields][@"Content-Type"];
        if (ct.length) self.contentType = ct;
        if (code == 404 || code == 410) {
            completionHandler(NSURLSessionResponseCancel);
            [self finishWithStreams:nil error:[NSString stringWithFormat:@"Stazione non trovata (HTTP %ld)", (long)code]
                           decision:@"HTTP 404"];
            return;
        }
        if (code >= 400) {
            // come Radiotray-NG: con altri errori si prova comunque a suonarlo direttamente
            completionHandler(NSURLSessionResponseCancel);
            [self finishWithStreams:@[[self effectiveURL:dataTask]] error:nil
                           decision:[NSString stringWithFormat:@"HTTP %ld: tentativo come stream diretto", (long)code]];
            return;
        }
    }
    if ([RTPlaylistParser contentTypeIsAudio:self.contentType]) {
        completionHandler(NSURLSessionResponseCancel);
        self.streamContentTypes = @{ [self effectiveURL:dataTask]: self.contentType ?: @"" };
        [self finishWithStreams:@[[self effectiveURL:dataTask]] error:nil
                       decision:[NSString stringWithFormat:@"stream diretto (%@)", self.contentType]];
        return;
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    if (dataTask != self.task) return;
    [self.buffer appendData:data];
    if (self.buffer.length >= RTMaxPlaylistBytes) {
        [self.buffer setLength:RTMaxPlaylistBytes];
        [self decideWithTask:dataTask];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (task != self.task || !self.completion) return;
    if (!error) {
        [self decideWithTask:task];
        return;
    }
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorCancelled:
                return;
            case NSURLErrorCannotParseResponse:
            case NSURLErrorBadServerResponse:
                // tipico dei vecchi server Shoutcast ("ICY 200 OK"): si lascia provare al lettore
                [self finishWithStreams:@[self.originalURL] error:nil decision:@"risposta non HTTP (ICY?): stream diretto"];
                return;
            case NSURLErrorTimedOut:
                [self finishWithStreams:nil error:@"La stazione non risponde (tempo scaduto)" decision:@"timeout"];
                return;
            case NSURLErrorCannotFindHost:
            case NSURLErrorDNSLookupFailed:
                [self finishWithStreams:nil error:@"Server della stazione non trovato" decision:@"host sconosciuto"];
                return;
            case NSURLErrorNotConnectedToInternet:
                [self finishWithStreams:nil error:@"Nessuna connessione a Internet" decision:@"offline"];
                return;
            default:
                break;
        }
    }
    [self finishWithStreams:nil error:error.localizedDescription ?: @"Errore di rete" decision:@"errore di rete"];
}

@end
