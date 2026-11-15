#import "RTArtwork.h"
#import <CommonCrypto/CommonDigest.h>

@interface RTArtwork ()
@property (nonatomic, strong) NSCache<NSString *, NSData *> *memory;
@property (nonatomic, strong) NSMutableSet<NSString *> *missing;     // cercate senza risultato (in questa sessione)
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<RTArtworkCompletion> *> *pending;
@property (nonatomic, copy) NSString *cacheDir;
@end

@implementation RTArtwork

+ (instancetype)shared
{
    static RTArtwork *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [RTArtwork new]; });
    return shared;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _memory = [NSCache new];
        _memory.countLimit = 200;
        _missing = [NSMutableSet set];
        _pending = [NSMutableDictionary dictionary];
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
                           ?: NSTemporaryDirectory();
        _cacheDir = [caches stringByAppendingPathComponent:@"io.github.paselsoft.radiotray-mac/copertine"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return self;
}

+ (NSString *)normalized:(NSString *)text
{
    NSString *folded = [text ?: @"" stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
                                                         locale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    NSMutableString *out = [NSMutableString string];
    NSCharacterSet *keep = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < folded.length; i++) {
        unichar c = [folded characterAtIndex:i];
        if ([keep characterIsMember:c]) [out appendFormat:@"%C", c];
    }
    return out;
}

/// Parte principale di un titolo: senza "(Radio Edit)", "[Live]", "- Remastered", "feat. …"
+ (NSString *)coreTitle:(NSString *)title
{
    NSString *t = title ?: @"";
    for (NSString *cut in @[@" (", @" [", @" - ", @" feat.", @" ft."]) {
        NSRange r = [t rangeOfString:cut options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound && r.location > 0) t = [t substringToIndex:r.location];
    }
    return t;
}

+ (BOOL)text:(NSString *)a matches:(NSString *)b
{
    NSString *x = [self normalized:a], *y = [self normalized:b];
    if (x.length == 0 || y.length == 0) return NO;
    return [x isEqualToString:y] || [x containsString:y] || [y containsString:x];
}

+ (NSString *)artworkURLFromJSON:(NSData *)data title:(NSString *)title artist:(NSString *)artist
{
    id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSArray *results = [root isKindOfClass:[NSDictionary class]] ? root[@"results"] : nil;
    if (![results isKindOfClass:[NSArray class]]) return nil;
    NSString *bestURL = nil;
    NSInteger bestScore = 0;
    for (NSDictionary *r in results) {
        if (![r isKindOfClass:[NSDictionary class]]) continue;
        NSString *art = r[@"artworkUrl100"];
        NSString *rArtist = r[@"artistName"], *rTrack = r[@"trackName"];
        if (![art isKindOfClass:[NSString class]] || ![rArtist isKindOfClass:[NSString class]]) continue;
        // l'artista deve corrispondere (anche solo in parte: "Mina" e "Mina & Celentano")
        NSString *firstArtist = [[artist componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"&,/"]]
                                 firstObject];
        if (![self text:rArtist matches:artist] && ![self text:rArtist matches:firstArtist ?: @""]) continue;
        NSInteger score = 1;
        if ([rTrack isKindOfClass:[NSString class]] && [self text:[self coreTitle:rTrack] matches:[self coreTitle:title]]) score = 2;
        if (score > bestScore) {
            bestScore = score;
            bestURL = art;
        }
    }
    // copertina più grande: ".../100x100bb.jpg" → ".../600x600bb.jpg"
    return [bestURL stringByReplacingOccurrencesOfString:@"100x100" withString:@"600x600"];
}

- (NSString *)keyForTitle:(NSString *)title artist:(NSString *)artist
{
    return [NSString stringWithFormat:@"%@|%@", [RTArtwork normalized:artist], [RTArtwork normalized:[RTArtwork coreTitle:title]]];
}

- (NSString *)fileForKey:(NSString *)key
{
    const char *s = key.UTF8String;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(s, (CC_LONG)strlen(s), digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [self.cacheDir stringByAppendingPathComponent:[hex stringByAppendingString:@".jpg"]];
}

- (NSData *)cachedArtworkForTitle:(NSString *)title artist:(NSString *)artist
{
    if (artist.length == 0 || title.length == 0) return nil;
    NSString *key = [self keyForTitle:title artist:artist];
    NSData *data = [self.memory objectForKey:key];
    if (!data) {
        data = [NSData dataWithContentsOfFile:[self fileForKey:key]];
        if (data) [self.memory setObject:data forKey:key];
    }
    return data;
}

- (void)artworkForTitle:(NSString *)title artist:(NSString *)artist completion:(RTArtworkCompletion)completion
{
    NSData *cached = [self cachedArtworkForTitle:title artist:artist];
    NSString *key = (artist.length && title.length) ? [self keyForTitle:title artist:artist] : nil;
    if (cached || !key || [self.missing containsObject:key]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
        return;
    }
    // la stessa copertina chiesta più volte insieme: una sola richiesta
    if (self.pending[key]) {
        [self.pending[key] addObject:[completion copy]];
        return;
    }
    self.pending[key] = [NSMutableArray arrayWithObject:[completion copy]];

    NSURLComponents *c = [NSURLComponents componentsWithString:@"https://itunes.apple.com/search"];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"term" value:[NSString stringWithFormat:@"%@ %@", artist, [RTArtwork coreTitle:title]]],
                     [NSURLQueryItem queryItemWithName:@"media" value:@"music"],
                     [NSURLQueryItem queryItemWithName:@"entity" value:@"song"],
                     [NSURLQueryItem queryItemWithName:@"limit" value:@"10"]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:c.URL];
    req.timeoutInterval = 10;
    [req setValue:@"RadioTray-Mac" forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *json, NSURLResponse *r1, NSError *e1) {
        NSString *imageURL = [RTArtwork artworkURLFromJSON:json title:title artist:artist];
        void (^finish)(NSData *) = ^(NSData *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                if (image) {
                    [strongSelf.memory setObject:image forKey:key];
                    [image writeToFile:[strongSelf fileForKey:key] atomically:YES];
                } else if (!e1) {
                    [strongSelf.missing addObject:key];   // nessun risultato: non si richiede di nuovo
                }
                NSArray *waiting = strongSelf.pending[key];
                [strongSelf.pending removeObjectForKey:key];
                for (RTArtworkCompletion done in waiting) done(image);
            });
        };
        NSURL *u = imageURL ? [NSURL URLWithString:imageURL] : nil;
        if (!u) {
            finish(nil);
            return;
        }
        [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *image, NSURLResponse *r2, NSError *e2) {
            NSInteger code = [r2 isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r2 statusCode] : 0;
            finish(code == 200 && image.length > 100 ? image : nil);
        }] resume];
    }] resume];
}

@end
