#import "RTStationLogo.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *const RTRadioBrowserHost = @"de1.api.radio-browser.info";

@interface RTStationLogo ()
@property (nonatomic, strong) NSCache<NSString *, NSData *> *memory;
@property (nonatomic, strong) NSMutableSet<NSString *> *missing;
@property (nonatomic, copy) NSString *cacheDir;
@end

@implementation RTStationLogo

+ (instancetype)shared
{
    static RTStationLogo *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [RTStationLogo new]; });
    return shared;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _memory = [NSCache new];
        _missing = [NSMutableSet set];
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
                           ?: NSTemporaryDirectory();
        _cacheDir = [caches stringByAppendingPathComponent:@"io.github.paselsoft.radiotray-mac/loghi"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return self;
}

+ (NSString *)bestFaviconFromJSON:(NSData *)data
{
    return [self faviconsFromJSON:data].firstObject;
}

+ (NSArray<NSString *> *)faviconsFromJSON:(NSData *)data
{
    NSMutableArray *out = [NSMutableArray array];
    id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSArray class]]) return out;
    for (NSDictionary *s in (NSArray *)root) {
        if (![s isKindOfClass:[NSDictionary class]]) continue;
        NSString *f = [s[@"favicon"] isKindOfClass:[NSString class]] ? s[@"favicon"] : @"";
        f = [f stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *lower = f.lowercaseString;
        if (!([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"])) continue;
        if ([lower containsString:@".svg"] || [lower containsString:@"facebook.com"]) continue;
        if (![out containsObject:f]) [out addObject:f];
    }
    return out;
}

- (NSString *)fileForKey:(NSString *)key
{
    const char *s = key.UTF8String;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(s, (CC_LONG)strlen(s), digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [self.cacheDir stringByAppendingPathComponent:hex];
}

- (NSString *)missingFileForKey:(NSString *)key
{
    return [[self fileForKey:key] stringByAppendingPathExtension:@"nessuno"];
}

- (void)forgetStationURL:(NSString *)url
{
    [self.memory removeObjectForKey:url];
    [self.missing removeObject:url];
    [[NSFileManager defaultManager] removeItemAtPath:[self fileForKey:url] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[self missingFileForKey:url] error:NULL];
}

- (BOOL)knownMissingForStationURL:(NSString *)url
{
    if ([self.missing containsObject:url]) return YES;
    // la ricerca senza risultati si ripete dopo una settimana (l'archivio si arricchisce)
    NSDate *date = [[NSFileManager defaultManager] attributesOfItemAtPath:[self missingFileForKey:url] error:NULL].fileModificationDate;
    if (date && -date.timeIntervalSinceNow < 7 * 24 * 3600) {
        [self.missing addObject:url];
        return YES;
    }
    return NO;
}

- (NSData *)cachedLogoForStationURL:(NSString *)url image:(NSString *)image
{
    if (image.length) {
        NSString *lower = image.lowercaseString;
        BOOL web = [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"];
        NSData *d = [self.memory objectForKey:image] ?: (web ? [NSData dataWithContentsOfFile:[self fileForKey:image]]
                                                            : [NSData dataWithContentsOfFile:image.stringByExpandingTildeInPath]);
        if (d) [self.memory setObject:d forKey:image];
        return d;
    }
    NSData *d = [self.memory objectForKey:url] ?: [NSData dataWithContentsOfFile:[self fileForKey:url]];
    if (d) [self.memory setObject:d forKey:url];
    return d;
}

- (void)get:(NSURL *)url completion:(void (^)(NSData *data))completion
{
    if (!url) {
        completion(nil);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 12;
    // alcuni siti (Wikipedia) rifiutano i programmi che non si presentano con nome e indirizzo
    [req setValue:@"RadioTray-Mac/1.5 (https://github.com/paselsoft/radiotray-mac)" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSInteger code = [r isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r statusCode] : 0;
        completion(code == 200 && d.length ? d : nil);
    }] resume];
}

- (void)logoForStation:(NSString *)name url:(NSString *)url image:(NSString *)image completion:(RTLogoCompletion)completion
{
    void (^done)(NSData *) = ^(NSData *d) { dispatch_async(dispatch_get_main_queue(), ^{ completion(d); }); };

    // 1. immagine scelta dall'utente nel file delle stazioni
    if (image.length) {
        NSString *lower = image.lowercaseString;
        if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) {
            NSData *cachedImage = [self cachedLogoForStationURL:url image:image];
            if (cachedImage) {
                done(cachedImage);
                return;
            }
            __weak typeof(self) weakSelf = self;
            [self get:[NSURL URLWithString:image] completion:^(NSData *d) {
                if (d.length) {
                    [d writeToFile:[weakSelf fileForKey:image] atomically:YES];
                    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf.memory setObject:d forKey:image]; });
                }
                done(d);
            }];
        } else {
            done([NSData dataWithContentsOfFile:image.stringByExpandingTildeInPath]);
        }
        return;
    }

    // 2. cache
    NSData *cached = [self.memory objectForKey:url] ?: [NSData dataWithContentsOfFile:[self fileForKey:url]];
    if (cached || [self knownMissingForStationURL:url]) {
        if (cached) [self.memory setObject:cached forKey:url];
        done(cached);
        return;
    }

    // 3. archivio Radio Browser: per indirizzo, poi per nome
    __weak typeof(self) weakSelf = self;
    void (^store)(NSData *) = ^(NSData *logo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (logo) {
                [strongSelf.memory setObject:logo forKey:url];
                [logo writeToFile:[strongSelf fileForKey:url] atomically:YES];
            } else {
                [strongSelf.missing addObject:url];
                [[NSData data] writeToFile:[strongSelf missingFileForKey:url] atomically:YES];
            }
            completion(logo);
        });
    };
    // si provano i loghi uno dopo l'altro finché uno si scarica
    __block void (^tryNext)(NSArray<NSString *> *);
    void (^download)(NSArray<NSString *> *) = ^(NSArray<NSString *> *candidates) { tryNext(candidates); };
    tryNext = ^(NSArray<NSString *> *candidates) {
        if (candidates.count == 0) {
            store(nil);
            tryNext = nil;   // spezza il riferimento circolare del blocco
            return;
        }
        NSArray *rest = [candidates subarrayWithRange:NSMakeRange(1, candidates.count - 1)];
        [self get:[NSURL URLWithString:candidates[0]] completion:^(NSData *d) {
            if (d.length > 100) {
                store(d);
                tryNext = nil;
            } else {
                NSLog(@"RadioTray: logo non scaricabile: %@", candidates[0]);
                tryNext(rest);
            }
        }];
    };
    NSURLComponents *byURL = [NSURLComponents new];
    byURL.scheme = @"https";
    byURL.host = RTRadioBrowserHost;
    byURL.path = @"/json/stations/byurl";
    byURL.queryItems = @[[NSURLQueryItem queryItemWithName:@"url" value:url]];
    [self get:byURL.URL completion:^(NSData *d1) {
        NSArray *byURLLogos = [RTStationLogo faviconsFromJSON:d1];
        NSURLComponents *byName = [NSURLComponents new];
        byName.scheme = @"https";
        byName.host = RTRadioBrowserHost;
        byName.path = @"/json/stations/search";
        byName.queryItems = @[[NSURLQueryItem queryItemWithName:@"name" value:name],
                              [NSURLQueryItem queryItemWithName:@"order" value:@"clickcount"],
                              [NSURLQueryItem queryItemWithName:@"reverse" value:@"true"],
                              [NSURLQueryItem queryItemWithName:@"limit" value:@"10"]];
        [self get:byName.URL completion:^(NSData *d2) {
            NSMutableArray *all = [byURLLogos mutableCopy];
            for (NSString *f in [RTStationLogo faviconsFromJSON:d2]) if (![all containsObject:f]) [all addObject:f];
            download(all);
        }];
    }];
}

@end
