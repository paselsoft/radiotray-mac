#import "RTLyrics.h"

static NSString *RTStr(id v) { return [v isKindOfClass:[NSString class]] ? v : @""; }

@implementation RTLyrics

+ (NSString *)lyricsFromDictionary:(NSDictionary *)d
{
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    if ([d[@"instrumental"] isKindOfClass:[NSNumber class]] && [d[@"instrumental"] boolValue]) return @"";
    NSString *plain = [RTStr(d[@"plainLyrics"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (plain.length) return plain;
    NSString *synced = RTStr(d[@"syncedLyrics"]);
    if (!synced.length) return nil;
    // "[01:23.45] parole" → "parole"
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\[[0-9:.]+\\]\\s?" options:NSRegularExpressionAnchorsMatchLines error:NULL];
    NSString *text = [re stringByReplacingMatchesInString:synced options:0 range:NSMakeRange(0, synced.length) withTemplate:@""];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return text.length ? text : nil;
}

+ (NSString *)lyricsFromJSON:(NSData *)data
{
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if ([json isKindOfClass:[NSDictionary class]]) return [self lyricsFromDictionary:json];
    if ([json isKindOfClass:[NSArray class]]) {
        for (id d in (NSArray *)json) {
            NSString *t = [self lyricsFromDictionary:d];
            if (t.length) return t;
        }
    }
    return nil;
}

+ (NSURLSession *)session
{
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"RadioTray-Mac (https://github.com/paselsoft/radiotray-mac)" };
        session = [NSURLSession sessionWithConfiguration:cfg];
    });
    return session;
}

+ (void)get:(NSString *)path items:(NSArray<NSURLQueryItem *> *)items completion:(void (^)(NSData *data, NSInteger code))completion
{
    NSURLComponents *c = [NSURLComponents componentsWithString:[@"https://lrclib.net/api/" stringByAppendingString:path]];
    c.queryItems = items;
    [[[self session] dataTaskWithURL:c.URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : (error ? -1 : 0);
        completion(data, code);
    }] resume];
}

+ (void)lyricsForTitle:(NSString *)title artist:(NSString *)artist completion:(RTLyricsCompletion)completion
{
    void (^done)(NSString *, NSString *) = ^(NSString *l, NSString *p) { dispatch_async(dispatch_get_main_queue(), ^{ completion(l, p); }); };
    // prima la corrispondenza esatta, poi la ricerca (titoli con "Radio edit", artisti con "feat."…)
    [self get:@"get" items:@[[NSURLQueryItem queryItemWithName:@"artist_name" value:artist],
                             [NSURLQueryItem queryItemWithName:@"track_name" value:title]]
   completion:^(NSData *data, NSInteger code) {
        NSString *lyrics = code == 200 ? [RTLyrics lyricsFromJSON:data] : nil;
        if (lyrics) {
            done(lyrics, nil);
            return;
        }
        if (code == -1) {
            done(nil, @"LRCLIB non risponde: controlla la connessione.");
            return;
        }
        NSString *cleanTitle = [title stringByReplacingOccurrencesOfString:@"\\s*[\\(\\[].*?[\\)\\]]" withString:@""
                                                                   options:NSRegularExpressionSearch range:NSMakeRange(0, title.length)];
        NSString *firstArtist = [[artist componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",&"]].firstObject
                                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self get:@"search" items:@[[NSURLQueryItem queryItemWithName:@"track_name" value:cleanTitle],
                                    [NSURLQueryItem queryItemWithName:@"artist_name" value:firstArtist ?: artist]]
       completion:^(NSData *data2, NSInteger code2) {
            NSString *found = code2 == 200 ? [RTLyrics lyricsFromJSON:data2] : nil;
            if (found) done(found, nil);
            else done(nil, @"Testo non trovato nell'archivio LRCLIB.");
        }];
    }];
}

@end
