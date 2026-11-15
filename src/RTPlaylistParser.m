#import "RTPlaylistParser.h"

static NSString *RTLower(NSString *s)
{
    return s ? s.lowercaseString : @"";
}

static NSString *RTTextFromData(NSData *data)
{
    if (data.length == 0) return nil;
    // dati binari (audio): niente testo
    const unsigned char *bytes = data.bytes;
    NSUInteger probe = MIN(data.length, (NSUInteger)512);
    for (NSUInteger i = 0; i < probe; i++) {
        if (bytes[i] == 0) return nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        // il blocco letto (4 KB) può tagliare a metà un carattere UTF-8: si riprova senza l'ultimo byte
        for (NSUInteger cut = 1; cut <= 3 && !text && data.length > cut; cut++) {
            text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, data.length - cut)]
                                         encoding:NSUTF8StringEncoding];
        }
    }
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if ([text hasPrefix:@"\uFEFF"]) text = [text substringFromIndex:1];
    return text;
}

static NSArray<NSString *> *RTLines(NSString *text)
{
    NSMutableArray *lines = [NSMutableArray array];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length) [lines addObject:t];
    }];
    return lines;
}

static NSString *RTXMLUnescape(NSString *s)
{
    s = [s stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    s = [s stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    s = [s stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    s = [s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/// URL assoluto, oppure relativo risolto rispetto a base; nil se non è un URL utilizzabile.
static NSString *RTResolve(NSString *candidate, NSURL *base)
{
    if (candidate.length == 0) return nil;
    NSString *lower = candidate.lowercaseString;
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"mms://"] ||
        [lower hasPrefix:@"rtsp://"] || [lower hasPrefix:@"icy://"]) {
        return candidate;
    }
    if ([candidate rangeOfString:@"://"].location != NSNotFound) return nil;   // schema sconosciuto
    if (!base) return nil;
    NSURL *url = [NSURL URLWithString:candidate relativeToURL:base];
    return url.absoluteString;
}

static NSArray<NSString *> *RTMatches(NSString *text, NSString *pattern)
{
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                                          error:NULL];
    NSMutableArray *out = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        for (NSUInteger i = 1; i < m.numberOfRanges; i++) {
            NSRange r = [m rangeAtIndex:i];
            if (r.location != NSNotFound) {
                [out addObject:RTXMLUnescape([text substringWithRange:r])];
                break;
            }
        }
    }
    return out;
}

static NSArray<NSString *> *RTUnique(NSArray<NSString *> *urls)
{
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *u in urls) {
        if (u.length && ![seen containsObject:u]) {
            [seen addObject:u];
            [out addObject:u];
        }
    }
    return out;
}

@implementation RTPlaylistParser

+ (BOOL)urlLooksDirect:(NSString *)url
{
    NSURL *u = [NSURL URLWithString:url];
    NSString *ext = RTLower(u.path.pathExtension);
    static NSSet *audio;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        audio = [NSSet setWithArray:@[@"mp3", @"aac", @"aacp", @"m4a", @"mp4", @"ogg", @"oga", @"opus",
                                      @"flac", @"wav", @"m3u8"]];
    });
    return [audio containsObject:ext];
}

+ (BOOL)contentTypeIsAudio:(NSString *)contentType
{
    NSString *ct = RTLower(contentType);
    NSRange semi = [ct rangeOfString:@";"];
    if (semi.location != NSNotFound) ct = [ct substringToIndex:semi.location];
    ct = [ct stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([ct hasPrefix:@"audio/"]) {
        return !([ct containsString:@"mpegurl"] || [ct containsString:@"scpls"] || [ct containsString:@"x-ms-wax"]);
    }
    return [ct isEqualToString:@"application/ogg"] || [ct isEqualToString:@"video/mp2t"] ||
           [ct isEqualToString:@"application/aacp"];
}

+ (BOOL)isHLSContentType:(NSString *)contentType data:(NSData *)data
{
    NSString *ct = RTLower(contentType);
    NSString *text = RTTextFromData(data);
    BOOL hlsTags = text && [text rangeOfString:@"#EXT-X-"].location != NSNotFound;
    if ([ct containsString:@"application/vnd.apple.mpegurl"]) return YES;
    return hlsTags;
}

+ (NSArray<NSString *> *)urlsFromData:(NSData *)data contentType:(NSString *)contentType
                              baseURL:(NSURL *)baseURL formatName:(NSString **)formatName
{
    NSString *ct = RTLower(contentType);
    NSString *text = RTTextFromData(data);
    if (!text) return nil;
    NSString *lower = text.lowercaseString;
    NSString *format = nil;
    NSMutableArray<NSString *> *urls = [NSMutableArray array];

    if ([ct containsString:@"scpls"] || [ct containsString:@"pls+xml"] || [lower containsString:@"[playlist]"]) {
        format = @"PLS";
        for (NSString *line in RTLines(text)) {
            if (![line.lowercaseString hasPrefix:@"file"]) continue;
            NSRange eq = [line rangeOfString:@"="];
            if (eq.location == NSNotFound) continue;
            NSString *u = RTResolve([[line substringFromIndex:eq.location + 1]
                                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]], baseURL);
            if (u) [urls addObject:u];
        }
    } else if ([ct containsString:@"x-ms-asf"] || [ct containsString:@"x-ms-wax"] || [ct containsString:@"x-ms-asx"] ||
               [lower containsString:@"<asx"]) {
        format = @"ASX";
        for (NSString *u in RTMatches(text, @"<ref\\s+href\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")) {
            NSString *r = RTResolve(u, baseURL);
            if (r) [urls addObject:r];
        }
    } else if ([ct containsString:@"xspf"] || ([lower containsString:@"<playlist"] && [lower containsString:@"xspf"])) {
        format = @"XSPF";
        for (NSString *u in RTMatches(text, @"<location>\\s*(.*?)\\s*</location>")) {
            NSString *r = RTResolve(u, baseURL);
            if (r) [urls addObject:r];
        }
    } else {
        BOOL declared = [ct containsString:@"mpegurl"] || [ct containsString:@"text/uri-list"] ||
                        [lower hasPrefix:@"#extm3u"];
        BOOL loose = [ct hasPrefix:@"text/"] || ct.length == 0 || [ct containsString:@"octet-stream"];
        if (!declared && !loose) return nil;
        // M3U o elenco di URL: ogni riga non commentata è un URL; se il tipo non lo dichiara,
        // tutte le righe devono essere commenti o URL (altrimenti è, per esempio, una pagina HTML)
        for (NSString *line in RTLines(text)) {
            if ([line hasPrefix:@"#"]) continue;
            NSString *u = RTResolve(line, declared ? baseURL : nil);
            if (u) {
                [urls addObject:u];
            } else if (!declared) {
                return nil;
            }
        }
        if (!declared && urls.count == 0) return nil;
        format = @"M3U";
    }

    if (formatName) *formatName = format;
    return RTUnique(urls);
}

@end
