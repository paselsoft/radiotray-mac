#import "RTRadioBrowser.h"

// server dell'archivio: si prova il primo, poi gli altri se non risponde
static NSArray<NSString *> *RTServers(void)
{
    return @[@"de1.api.radio-browser.info", @"de2.api.radio-browser.info", @"fi1.api.radio-browser.info",
             @"all.api.radio-browser.info"];
}

static NSString *RTStr(id v)
{
    if ([v isKindOfClass:[NSString class]]) {
        return [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([v isKindOfClass:[NSNumber class]]) return [v description];
    return @"";
}

@implementation RTFoundStation

- (BOOL)playable
{
    NSString *c = self.codec.uppercaseString;
    for (NSString *bad in @[@"OGG", @"OPUS", @"FLAC", @"WMA", @"VORBIS"]) {
        if ([c containsString:bad]) return NO;
    }
    return YES;
}

- (NSString *)formatDescription
{
    NSString *codec = self.codec.length && ![self.codec isEqualToString:@"UNKNOWN"] ? self.codec : (self.hls ? @"HLS" : @"?");
    return self.bitrate > 0 ? [NSString stringWithFormat:@"%@ %ld kbps", codec, (long)self.bitrate] : codec;
}

@end

@interface RTRadioBrowser ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@property (nonatomic) NSUInteger generation;
@end

@implementation RTRadioBrowser

- (instancetype)init
{
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 12;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"RadioTray-Mac/0.3", @"Accept": @"application/json" };
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (void)dealloc
{
    [_session invalidateAndCancel];
}

- (void)cancel
{
    self.generation++;
    [self.task cancel];
    self.task = nil;
}

+ (NSArray<RTFoundStation *> *)stationsFromJSON:(NSData *)data
{
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<RTFoundStation *> *playable = [NSMutableArray array], *other = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in (NSArray *)root) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        RTFoundStation *s = [RTFoundStation new];
        s.name = RTStr(item[@"name"]);
        NSString *resolved = RTStr(item[@"url_resolved"]);
        s.url = resolved.length ? resolved : RTStr(item[@"url"]);
        if (s.name.length == 0 || s.url.length == 0) continue;
        NSString *lowerURL = s.url.lowercaseString;
        if (!([lowerURL hasPrefix:@"http://"] || [lowerURL hasPrefix:@"https://"])) continue;
        // stessa stazione registrata più volte: si tiene la prima (la più ascoltata)
        NSString *key = [NSString stringWithFormat:@"%@|%@", s.name.lowercaseString, lowerURL];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        s.country = RTStr(item[@"countrycode"]).uppercaseString;
        s.codec = RTStr(item[@"codec"]).uppercaseString;
        s.bitrate = [RTStr(item[@"bitrate"]) integerValue];
        s.tags = [RTStr(item[@"tags"]) stringByReplacingOccurrencesOfString:@"," withString:@", "];
        s.votes = [RTStr(item[@"votes"]) integerValue];
        s.hls = [RTStr(item[@"hls"]) integerValue] != 0;
        [(s.playable ? playable : other) addObject:s];
    }
    [playable addObjectsFromArray:other];
    return playable;
}

- (void)searchName:(NSString *)name country:(NSString *)countryCode completion:(RTSearchCompletion)completion
{
    [self cancel];
    NSUInteger generation = self.generation;
    [self searchName:name country:countryCode serverIndex:0 generation:generation completion:completion];
}

- (void)searchName:(NSString *)name country:(NSString *)countryCode serverIndex:(NSUInteger)index
        generation:(NSUInteger)generation completion:(RTSearchCompletion)completion
{
    NSURLComponents *c = [NSURLComponents new];
    c.scheme = @"https";
    c.host = RTServers()[index];
    c.path = @"/json/stations/search";
    NSMutableArray *query = [NSMutableArray arrayWithArray:@[
        [NSURLQueryItem queryItemWithName:@"name" value:name],
        [NSURLQueryItem queryItemWithName:@"hidebroken" value:@"true"],
        [NSURLQueryItem queryItemWithName:@"order" value:@"clickcount"],
        [NSURLQueryItem queryItemWithName:@"reverse" value:@"true"],
        [NSURLQueryItem queryItemWithName:@"limit" value:@"100"],
    ]];
    if (countryCode.length) [query addObject:[NSURLQueryItem queryItemWithName:@"countrycode" value:countryCode]];
    c.queryItems = query;

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithURL:c.URL
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            NSArray<RTFoundStation *> *stations = (!error && code == 200 && data) ? [RTRadioBrowser stationsFromJSON:data] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                RTRadioBrowser *strongSelf = weakSelf;
                if (!strongSelf || strongSelf.generation != generation) return;
                if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
                if (stations) {
                    strongSelf.task = nil;
                    completion(stations, nil);
                } else if (index + 1 < RTServers().count) {
                    NSLog(@"RadioTray: archivio %@ non disponibile (%@), provo il successivo", RTServers()[index],
                          error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %ld", (long)code]);
                    [strongSelf searchName:name country:countryCode serverIndex:index + 1 generation:generation completion:completion];
                } else {
                    strongSelf.task = nil;
                    completion(nil, error.localizedDescription ?: @"L'archivio delle stazioni non risponde");
                }
            });
        }];
    self.task = task;
    [task resume];
}

@end
