#import "RTRemote.h"
#import <Security/Security.h>
#include <arpa/inet.h>

const uint16_t RTRemotePort = 8765;
static const NSUInteger RTRemoteMaxRequest = 16 * 1024;

@interface RTRemoteRequest ()
@property (nonatomic, copy, readwrite) NSString *method;
@property (nonatomic, copy, readwrite) NSString *path;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *query;
@end

@implementation RTRemoteRequest

+ (instancetype)requestFromData:(NSData *)data invalid:(BOOL *)invalid
{
    if (invalid) *invalid = NO;
    if (data.length > RTRemoteMaxRequest) {
        if (invalid) *invalid = YES;
        return nil;
    }
    NSRange end = [data rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4] options:0 range:NSMakeRange(0, data.length)];
    if (end.location == NSNotFound) return nil;   // intestazioni non ancora complete
    NSString *head = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, end.location)] encoding:NSISOLatin1StringEncoding];
    NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray<NSString *> *first = [lines.firstObject componentsSeparatedByString:@" "];
    if (first.count != 3 || ![first[2] hasPrefix:@"HTTP/1."] || ![first[1] hasPrefix:@"/"]) {
        if (invalid) *invalid = YES;
        return nil;
    }
    // corpo (i comandi non ne hanno bisogno, ma si legge per non lasciare dati a metà)
    NSUInteger contentLength = 0;
    for (NSString *line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        if ([[line substringToIndex:colon.location] caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame) {
            NSInteger n = [[[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] integerValue];
            if (n < 0 || n > 4096) {
                if (invalid) *invalid = YES;
                return nil;
            }
            contentLength = (NSUInteger)n;
        }
    }
    if (data.length < NSMaxRange(end) + contentLength) return nil;

    NSURLComponents *c = [NSURLComponents componentsWithString:[@"http://x" stringByAppendingString:first[1]]];
    if (!c || !c.path) {
        if (invalid) *invalid = YES;
        return nil;
    }
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *q in c.queryItems) if (q.value) query[q.name] = q.value;
    RTRemoteRequest *r = [self new];
    r.method = first[0].uppercaseString;
    r.path = c.path;
    r.query = query;
    return r;
}

@end

@implementation RTRemote

+ (NSString *)generateToken
{
    static const char alphabet[] = "abcdefghijkmnpqrstuvwxyz23456789";   // 32 caratteri, niente 0/o, 1/l
    uint8_t bytes[12];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof bytes, bytes) != errSecSuccess) {
        for (size_t i = 0; i < sizeof bytes; i++) bytes[i] = (uint8_t)arc4random_uniform(256);
    }
    char out[13];
    for (size_t i = 0; i < sizeof bytes; i++) out[i] = alphabet[bytes[i] % 32];
    out[12] = 0;
    return [NSString stringWithUTF8String:out];
}

+ (BOOL)token:(NSString *)given matches:(NSString *)expected
{
    if (given.length == 0 || expected.length == 0) return NO;
    NSData *a = [given dataUsingEncoding:NSUTF8StringEncoding], *b = [expected dataUsingEncoding:NSUTF8StringEncoding];
    if (a.length != b.length) return NO;
    const uint8_t *x = a.bytes, *y = b.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < a.length; i++) diff |= x[i] ^ y[i];
    return diff == 0;
}

static BOOL RTIsLocalIPv4(const uint8_t *b)
{
    return b[0] == 10 || b[0] == 127 || (b[0] == 172 && (b[1] & 0xF0) == 16) ||
           (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
}

+ (BOOL)isLocalAddressString:(NSString *)address
{
    NSString *a = address;
    NSRange percent = [a rangeOfString:@"%"];   // "fe80::1%en0"
    if (percent.location != NSNotFound) a = [a substringToIndex:percent.location];
    struct in_addr v4;
    if (inet_pton(AF_INET, a.UTF8String, &v4) == 1) return RTIsLocalIPv4((const uint8_t *)&v4.s_addr);
    struct in6_addr v6;
    if (inet_pton(AF_INET6, a.UTF8String, &v6) != 1) return NO;
    const uint8_t *b = v6.s6_addr;
    static const uint8_t loopback[16] = { 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1 };
    if (memcmp(b, loopback, 16) == 0) return YES;
    if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return YES;    // fe80::/10
    if ((b[0] & 0xFE) == 0xFC) return YES;                     // fc00::/7
    static const uint8_t mapped[12] = { 0,0,0,0, 0,0,0,0, 0,0,0xFF,0xFF };
    if (memcmp(b, mapped, 12) == 0) return RTIsLocalIPv4(b + 12);
    return NO;
}

+ (RTRemoteRoute)routeForRequest:(RTRemoteRequest *)request token:(NSString *)token
{
    NSArray<NSString *> *parts = [request.path componentsSeparatedByString:@"/"];
    // "/t/<codice>/resto" → ["", "t", "<codice>", "resto"…]
    if (parts.count < 3 || ![parts[1] isEqualToString:@"t"]) return RTRemoteRouteNotFound;
    if (![self token:parts[2] matches:token]) return RTRemoteRouteForbidden;
    if (parts.count == 3) return RTRemoteRouteRedirect;
    NSString *rest = [[parts subarrayWithRange:NSMakeRange(3, parts.count - 3)] componentsJoinedByString:@"/"];
    BOOL get = [request.method isEqualToString:@"GET"] || [request.method isEqualToString:@"HEAD"];
    if (get) {
        if ([rest isEqualToString:@""] || [rest isEqualToString:@"index.html"]) return RTRemoteRoutePage;
        if ([rest isEqualToString:@"icon.png"]) return RTRemoteRouteIcon;
        if ([rest isEqualToString:@"api/state"]) return RTRemoteRouteState;
        if ([rest isEqualToString:@"api/stations"]) return RTRemoteRouteStations;
        if ([rest isEqualToString:@"api/recent"]) return RTRemoteRouteRecent;
        if ([rest isEqualToString:@"img/cover"]) return RTRemoteRouteCover;
        if ([rest isEqualToString:@"img/logo"]) return RTRemoteRouteLogo;
    }
    if ([request.method isEqualToString:@"POST"] && [rest isEqualToString:@"api/cmd"]) return RTRemoteRouteCommand;
    return RTRemoteRouteNotFound;
}

+ (NSString *)addressForHost:(NSString *)host token:(NSString *)token
{
    NSString *h = [host containsString:@":"] && ![host hasPrefix:@"["] ? [NSString stringWithFormat:@"[%@]", host] : host;
    return [NSString stringWithFormat:@"http://%@:%u/t/%@/", h, (unsigned)RTRemotePort, token];
}

+ (NSDictionary<NSString *, NSString *> *)commandFromRequest:(RTRemoteRequest *)request
{
    NSString *action = request.query[@"do"] ?: @"";
    NSDictionary *q = request.query;
    if ([@[@"toggle", @"next", @"prev", @"favorite"] containsObject:action]) return @{ @"action": action };
    if ([action isEqualToString:@"volume"]) {
        NSString *v = q[@"value"] ?: @"";
        NSScanner *s = [NSScanner scannerWithString:v];
        NSInteger n;
        if (![s scanInteger:&n] || !s.isAtEnd) return nil;
        return @{ @"action": action, @"value": [NSString stringWithFormat:@"%ld", (long)MAX(0, MIN(100, n))] };
    }
    if ([action isEqualToString:@"play"]) {
        NSString *g = q[@"group"], *st = q[@"station"];
        if (g.length == 0 || st.length == 0) return nil;
        return @{ @"action": action, @"group": g, @"station": st };
    }
    if ([action isEqualToString:@"favorite-recent"]) {
        NSString *t = q[@"title"] ?: @"", *a = q[@"artist"] ?: @"";
        if (t.length == 0 && a.length == 0) return nil;
        return @{ @"action": action, @"title": t, @"artist": a, @"station": q[@"station"] ?: @"" };
    }
    return nil;
}

+ (NSDictionary *)stationsJSONForBookmarks:(RTBookmarks *)bookmarks mostPlayed:(NSArray<NSArray<NSString *> *> *)top
                              currentGroup:(NSString *)group currentStation:(NSString *)station
{
    NSMutableArray *groups = [NSMutableArray array];
    NSDictionary *(^entry)(NSString *, NSString *) = ^NSDictionary *(NSString *g, NSString *s) {
        return @{ @"group": g, @"name": s, @"current": @([g isEqualToString:group ?: @""] && [s isEqualToString:station ?: @""]) };
    };
    NSMutableArray *topList = [NSMutableArray array];
    for (NSArray<NSString *> *key in top) {
        if (key.count == 2 && [bookmarks stationNamed:key[1] inGroup:key[0]]) [topList addObject:entry(key[0], key[1])];
    }
    if (topList.count) [groups addObject:@{ @"name": @"Più ascoltate", @"stations": topList, @"top": @YES }];
    NSMutableArray *rootList = [NSMutableArray array];
    for (RTGroup *g in bookmarks.groups) {
        NSMutableArray *list = g.isRoot ? rootList : [NSMutableArray array];
        for (RTStation *s in g.stations) [list addObject:entry(g.name, s.name)];
        if (!g.isRoot && list.count) [groups addObject:@{ @"name": g.name, @"stations": list }];
    }
    if (rootList.count) [groups addObject:@{ @"name": @"Stazioni", @"stations": rootList }];
    return @{ @"groups": groups };
}

+ (NSDictionary *)recentJSONForHistory:(RTFavoriteTracks *)history favorites:(RTFavoriteTracks *)favorites limit:(NSUInteger)limit
{
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm";
    NSMutableArray *out = [NSMutableArray array];
    for (RTFavoriteTrack *t in history.tracks.reverseObjectEnumerator) {
        if (out.count >= limit) break;
        [out addObject:@{ @"title": t.title, @"artist": t.artist, @"station": t.station,
                          @"time": [f stringFromDate:t.added],
                          @"favorite": @([favorites trackWithTitle:t.title artist:t.artist] != nil) }];
    }
    return @{ @"tracks": out };
}

+ (NSString *)reasonForStatus:(NSInteger)status
{
    switch (status) {
        case 200: return @"OK";
        case 301: return @"Moved Permanently";
        case 400: return @"Bad Request";
        case 403: return @"Forbidden";
        case 404: return @"Not Found";
        default: return @"Error";
    }
}

+ (NSData *)responseWithStatus:(NSInteger)status type:(NSString *)type body:(NSData *)body extra:(NSString *)extra
{
    NSMutableString *head = [NSMutableString stringWithFormat:@"HTTP/1.1 %ld %@\r\n", (long)status, [self reasonForStatus:status]];
    if (type) [head appendFormat:@"Content-Type: %@\r\n", type];
    [head appendFormat:@"Content-Length: %lu\r\n", (unsigned long)body.length];
    // il codice di sicurezza è nell'indirizzo: non deve finire in cache o in un "referrer"
    [head appendString:@"Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n"];
    if (extra) [head appendString:extra];
    [head appendString:@"\r\n"];
    NSMutableData *out = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (body) [out appendData:body];
    return out;
}

+ (NSData *)responseWithStatus:(NSInteger)status type:(NSString *)type body:(NSData *)body
{
    return [self responseWithStatus:status type:type body:body extra:nil];
}

+ (NSData *)JSONResponse:(id)object
{
    NSData *body = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL] ?: [NSData dataWithBytes:"{}" length:2];
    return [self responseWithStatus:200 type:@"application/json; charset=utf-8" body:body];
}

+ (NSData *)redirectTo:(NSString *)location
{
    return [self responseWithStatus:301 type:nil body:nil extra:[NSString stringWithFormat:@"Location: %@\r\n", location]];
}

@end
