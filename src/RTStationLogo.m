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
    id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSArray class]]) return nil;
    for (NSDictionary *s in (NSArray *)root) {
        if (![s isKindOfClass:[NSDictionary class]]) continue;
        NSString *f = [s[@"favicon"] isKindOfClass:[NSString class]] ? s[@"favicon"] : @"";
        f = [f stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *lower = f.lowercaseString;
        if (!([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"])) continue;
        if ([lower containsString:@".svg"] || [lower containsString:@"facebook.com"]) continue;
        return f;
    }
    return nil;
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

- (void)forgetStationURL:(NSString *)url
{
    [self.memory removeObjectForKey:url];
    [self.missing removeObject:url];
    [[NSFileManager defaultManager] removeItemAtPath:[self fileForKey:url] error:NULL];
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
    [req setValue:@"RadioTray-Mac/1.4 (https://github.com/paselsoft/radiotray-mac)" forHTTPHeaderField:@"User-Agent"];
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
            [self get:[NSURL URLWithString:image] completion:done];
        } else {
            done([NSData dataWithContentsOfFile:image.stringByExpandingTildeInPath]);
        }
        return;
    }

    // 2. cache
    NSData *cached = [self.memory objectForKey:url] ?: [NSData dataWithContentsOfFile:[self fileForKey:url]];
    if (cached || [self.missing containsObject:url]) {
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
            }
            completion(logo);
        });
    };
    void (^download)(NSString *) = ^(NSString *favicon) {
        if (!favicon) {
            store(nil);
            return;
        }
        [self get:[NSURL URLWithString:favicon] completion:^(NSData *d) { store(d.length > 100 ? d : nil); }];
    };
    NSURLComponents *byURL = [NSURLComponents new];
    byURL.scheme = @"https";
    byURL.host = RTRadioBrowserHost;
    byURL.path = @"/json/stations/byurl";
    byURL.queryItems = @[[NSURLQueryItem queryItemWithName:@"url" value:url]];
    [self get:byURL.URL completion:^(NSData *d1) {
        NSString *favicon = [RTStationLogo bestFaviconFromJSON:d1];
        if (favicon) {
            download(favicon);
            return;
        }
        NSURLComponents *byName = [NSURLComponents new];
        byName.scheme = @"https";
        byName.host = RTRadioBrowserHost;
        byName.path = @"/json/stations/search";
        byName.queryItems = @[[NSURLQueryItem queryItemWithName:@"name" value:name],
                              [NSURLQueryItem queryItemWithName:@"order" value:@"clickcount"],
                              [NSURLQueryItem queryItemWithName:@"reverse" value:@"true"],
                              [NSURLQueryItem queryItemWithName:@"limit" value:@"10"]];
        [self get:byName.URL completion:^(NSData *d2) {
            download([RTStationLogo bestFaviconFromJSON:d2]);
        }];
    }];
}

@end
