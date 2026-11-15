// Diagnostica: cerca la copertina di alcuni brani nei due ordini (artista/titolo e scambiati)
// con lo stesso codice dell'app, e stampa la risposta grezza del catalogo.
// Uso: build/check_artwork "Artista|Titolo" …
#import <Foundation/Foundation.h>
#import "../src/RTArtwork.h"

static NSData *fetch(NSString *term)
{
    NSURLComponents *c = [NSURLComponents componentsWithString:@"https://itunes.apple.com/search"];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"term" value:term],
                     [NSURLQueryItem queryItemWithName:@"media" value:@"music"],
                     [NSURLQueryItem queryItemWithName:@"entity" value:@"song"],
                     [NSURLQueryItem queryItemWithName:@"limit" value:@"10"]];
    __block NSData *result = nil;
    __block BOOL done = NO;
    __block NSInteger code = 0;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:c.URL];
    [req setValue:@"RadioTray-Mac" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        result = d;
        code = [r isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r statusCode] : 0;
        if (e) printf("   errore di rete: %s\n", e.localizedDescription.UTF8String);
        done = YES;
    }] resume];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    printf("   HTTP %ld, %lu byte\n", (long)code, (unsigned long)result.length);
    return result;
}

static void show(NSString *artist, NSString *title)
{
    printf("  artista «%s», titolo «%s»\n", artist.UTF8String, title.UTF8String);
    NSData *json = fetch([NSString stringWithFormat:@"%@ %@", artist, title]);
    id root = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL] : nil;
    NSUInteger n = 0;
    for (NSDictionary *r in ([root isKindOfClass:[NSDictionary class]] ? root[@"results"] : @[])) {
        if (n++ >= 4) break;
        printf("   - %s | %s\n", [[r[@"artistName"] description] UTF8String], [[r[@"trackName"] description] UTF8String]);
    }
    NSString *url = [RTArtwork artworkURLFromJSON:json title:title artist:artist];
    printf("   → copertina scelta: %s\n", url ? url.UTF8String : "NESSUNA");
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            NSArray *p = [[NSString stringWithUTF8String:argv[i]] componentsSeparatedByString:@"|"];
            if (p.count != 2) continue;
            printf("== %s\n", argv[i]);
            show(p[0], p[1]);
            show(p[1], p[0]);
            [NSThread sleepForTimeInterval:1];
        }
    }
    return 0;
}
