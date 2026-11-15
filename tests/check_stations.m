// Prova a risolvere ogni stazione di un bookmarks.json con lo stesso codice dell'app
// e controlla che il primo stream risponda con audio. Serve a scoprire URL morti.
// Uso: build/check_stations resources/bookmarks.json
#import <Foundation/Foundation.h>
#import "../src/RTBookmarks.h"
#import "../src/RTPlaylistParser.h"
#import "../src/RTStreamResolver.h"

static BOOL waitFor(BOOL *done, NSTimeInterval seconds)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!*done && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return *done;
}

/// Legge solo la risposta (stato e Content-Type) e interrompe subito: gli stream sono infiniti.
@interface RTProbe : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy) NSString *result;
@end

@implementation RTProbe
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
    self.result = [NSString stringWithFormat:@"HTTP %ld %@", (long)code, response.MIMEType ?: @"?"];
    completionHandler(NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (!self.result) self.result = [NSString stringWithFormat:@"errore: %@", error.localizedDescription ?: @"?"];
}
@end

static NSString *probe(NSString *url)
{
    RTProbe *p = [RTProbe new];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 10;
    cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"RadioTray-Mac/1.0" };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:p delegateQueue:[NSOperationQueue mainQueue]];
    [[session dataTaskWithURL:[NSURL URLWithString:url]] resume];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:15];
    while (!p.result && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    [session invalidateAndCancel];
    return p.result ?: @"errore: nessuna risposta";
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "uso: %s bookmarks.json\n", argv[0]);
            return 2;
        }
        NSString *error = nil;
        RTBookmarks *b = [RTBookmarks bookmarksWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] error:&error];
        if (!b) {
            fprintf(stderr, "%s\n", error.UTF8String);
            return 2;
        }
        RTStreamResolver *resolver = [RTStreamResolver new];
        int bad = 0;
        for (RTGroup *g in b.groups) {
            for (RTStation *s in g.stations) {
                __block NSArray *streams = nil;
                __block NSString *err = nil;
                __block BOOL done = NO;
                [resolver resolve:s.url direct:s.direct completion:^(NSArray<NSString *> *st, NSString *e) {
                    streams = st;
                    err = e;
                    done = YES;
                }];
                if (!waitFor(&done, 25)) err = @"nessuna risposta";
                NSString *status;
                BOOL ok = NO;
                if (streams.count) {
                    NSString *p = probe(streams[0]);
                    ok = [p hasPrefix:@"HTTP 2"] &&
                         ([p rangeOfString:@"audio/"].location != NSNotFound || [p rangeOfString:@"mpegurl"].location != NSNotFound ||
                          [p rangeOfString:@"ogg"].location != NSNotFound);
                    status = [NSString stringWithFormat:@"%@ → %@ [%@]", resolver.lastDecision, streams[0], p];
                } else {
                    status = [NSString stringWithFormat:@"ERRORE: %@", err];
                }
                if (!ok) bad++;
                printf("%s %s / %s: %s\n", ok ? "OK " : "KO ", g.name.UTF8String, s.name.UTF8String, status.UTF8String);
            }
        }
        printf("%d stazioni non funzionanti\n", bad);
        return bad ? 1 : 0;
    }
}
