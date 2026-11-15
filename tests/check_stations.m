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

/// Content-Type del primo blocco dello stream (richiesta interrotta subito dopo la risposta).
static NSString *probe(NSString *url)
{
    __block NSString *result = nil;
    __block BOOL done = NO;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.timeoutInterval = 10;
    [req setValue:@"RadioTray-Mac/1.0" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"bytes=0-1023" forHTTPHeaderField:@"Range"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                result = [NSString stringWithFormat:@"errore: %@", error.localizedDescription];
            } else {
                NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
                result = [NSString stringWithFormat:@"HTTP %ld %@", (long)code, response.MIMEType ?: @"?"];
            }
            done = YES;
        }];
    [task resume];
    if (!waitFor(&done, 15)) {
        [task cancel];
        return @"errore: nessuna risposta";
    }
    return result;
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
