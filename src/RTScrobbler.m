#import "RTScrobbler.h"
#import <Security/Security.h>

static NSString *const RTAPI = @"https://api.listenbrainz.org/1/";
static NSString *const kKeychainService = @"io.github.paselsoft.radiotray-mac.listenbrainz";
static NSString *const kUserKey = @"listenbrainz-user";
static NSString *const kPendingKey = @"listenbrainz-pending";
static const NSUInteger RTMaxPending = 500;

@interface RTScrobbler ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, copy, nullable) NSString *station;
@property (nonatomic, strong, nullable) NSDate *startedAt;
@property (nonatomic) BOOL sending;
@end

@implementation RTScrobbler

+ (instancetype)shared
{
    static RTScrobbler *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [RTScrobbler new]; });
    return shared;
}

+ (NSTimeInterval)minimumListen { return 60; }

- (instancetype)init
{
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 20;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

#pragma mark - Token nel portachiavi

- (NSDictionary *)keychainQuery
{
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: kKeychainService,
              (__bridge id)kSecAttrAccount: @"token" };
}

- (NSString *)token
{
    NSMutableDictionary *q = [[self keychainQuery] mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess || !result) return nil;
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (BOOL)saveToken:(NSString *)token
{
    SecItemDelete((__bridge CFDictionaryRef)[self keychainQuery]);
    NSMutableDictionary *q = [[self keychainQuery] mutableCopy];
    q[(__bridge id)kSecValueData] = [token dataUsingEncoding:NSUTF8StringEncoding];
    q[(__bridge id)kSecAttrLabel] = @"RadioTray – ListenBrainz";
    return SecItemAdd((__bridge CFDictionaryRef)q, NULL) == errSecSuccess;
}

- (NSString *)userName { return [[NSUserDefaults standardUserDefaults] stringForKey:kUserKey]; }
- (BOOL)linked { return self.userName.length > 0 && [self token].length > 0; }

- (NSMutableURLRequest *)request:(NSString *)path token:(NSString *)token
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[RTAPI stringByAppendingString:path]]];
    [req setValue:[@"Token " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"RadioTray-Mac (https://github.com/paselsoft/radiotray-mac)" forHTTPHeaderField:@"User-Agent"];
    return req;
}

- (void)linkWithToken:(NSString *)token completion:(RTTokenCheck)completion
{
    token = [token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (token.length < 10) {
        completion(nil, @"Incolla il token che trovi su listenbrainz.org, in Settings (\"User token\").");
        return;
    }
    [[self.session dataTaskWithRequest:[self request:@"validate-token" token:token]
                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        BOOL valid = [json isKindOfClass:[NSDictionary class]] && [json[@"valid"] boolValue];
        NSString *user = valid && [json[@"user_name"] isKindOfClass:[NSString class]] ? json[@"user_name"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                completion(nil, [NSString stringWithFormat:@"ListenBrainz non risponde: %@", error.localizedDescription]);
            } else if (!user) {
                completion(nil, @"Il token non è valido. Copialo di nuovo da listenbrainz.org ▸ Settings ▸ User token.");
            } else if (![self saveToken:token]) {
                completion(nil, @"Impossibile salvare il token nel portachiavi del Mac.");
            } else {
                [[NSUserDefaults standardUserDefaults] setObject:user forKey:kUserKey];
                completion(user, nil);
                [self flushPending];
            }
        });
    }] resume];
}

- (void)unlink
{
    SecItemDelete((__bridge CFDictionaryRef)[self keychainQuery]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingKey];
    self.title = nil;
}

#pragma mark - Brani

+ (NSDictionary *)payloadWithType:(NSString *)type listens:(NSArray<NSDictionary *> *)listens version:(NSString *)version
{
    NSMutableArray *payload = [NSMutableArray array];
    for (NSDictionary *l in listens) {
        NSMutableDictionary *info = [@{ @"media_player": @"RadioTray",
                                        @"submission_client": @"RadioTray per Mac",
                                        @"submission_client_version": version ?: @"" } mutableCopy];
        if ([l[@"station"] length]) info[@"music_service_name"] = l[@"station"];
        NSMutableDictionary *item = [@{ @"track_metadata": @{ @"artist_name": l[@"artist"] ?: @"",
                                                             @"track_name": l[@"title"] ?: @"",
                                                             @"additional_info": info } } mutableCopy];
        if (![type isEqualToString:@"playing_now"] && l[@"listened_at"]) item[@"listened_at"] = l[@"listened_at"];
        [payload addObject:item];
    }
    return @{ @"listen_type": type, @"payload": payload };
}

- (NSString *)version
{
    return [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"";
}

- (void)send:(NSString *)type listens:(NSArray<NSDictionary *> *)listens completion:(nullable void (^)(BOOL ok))completion
{
    NSString *token = [self token];
    if (!token.length || !listens.count) {
        if (completion) completion(NO);
        return;
    }
    NSMutableURLRequest *req = [self request:@"submit-listens" token:token];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:[RTScrobbler payloadWithType:type listens:listens version:[self version]]
                                                   options:0 error:NULL];
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        BOOL ok = !error && code == 200;
        if (!ok) NSLog(@"RadioTray: ListenBrainz %@ non riuscito (%@)", type, error.localizedDescription ?: @(code));
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(ok || (code >= 400 && code < 500 && code != 429)); });
    }] resume];
}

- (void)trackStarted:(NSString *)title artist:(NSString *)artist station:(NSString *)station
{
    if ([title isEqualToString:self.title ?: @""] && [artist isEqualToString:self.artist ?: @""]) return;   // stesso brano
    [self stop];
    if (!self.linked || !title.length || !artist.length) return;
    self.title = title;
    self.artist = artist;
    self.station = station;
    self.startedAt = [NSDate date];
    [self send:@"playing_now" listens:@[@{ @"title": title, @"artist": artist, @"station": station ?: @"" }] completion:nil];
}

- (void)correctCurrentTitle:(NSString *)title artist:(NSString *)artist
{
    if (!self.title) return;
    self.title = title;
    self.artist = artist;
}

- (void)stop
{
    NSString *title = self.title, *artist = self.artist;
    NSDate *start = self.startedAt;
    self.title = nil;
    if (!title || !start || -start.timeIntervalSinceNow < [RTScrobbler minimumListen]) return;
    NSDictionary *listen = @{ @"title": title, @"artist": artist ?: @"", @"station": self.station ?: @"",
                              @"listened_at": @((long long)start.timeIntervalSince1970) };
    NSMutableArray *pending = [[[NSUserDefaults standardUserDefaults] arrayForKey:kPendingKey] ?: @[] mutableCopy];
    [pending addObject:listen];
    if (pending.count > RTMaxPending) [pending removeObjectsInRange:NSMakeRange(0, pending.count - RTMaxPending)];
    [[NSUserDefaults standardUserDefaults] setObject:pending forKey:kPendingKey];
    [self flushPending];
}

/// Manda gli ascolti in coda (fino a 100 alla volta); quelli inviati si tolgono dalla coda.
- (void)flushPending
{
    if (self.sending || !self.linked) return;
    NSArray *pending = [[NSUserDefaults standardUserDefaults] arrayForKey:kPendingKey] ?: @[];
    if (!pending.count) return;
    NSArray *batch = [pending subarrayWithRange:NSMakeRange(0, MIN(pending.count, (NSUInteger)100))];
    self.sending = YES;
    [self send:batch.count == 1 ? @"single" : @"import" listens:batch completion:^(BOOL done) {
        self.sending = NO;
        if (!done) return;   // rete assente: si riprova al prossimo brano
        NSMutableArray *left = [[[NSUserDefaults standardUserDefaults] arrayForKey:kPendingKey] ?: @[] mutableCopy];
        [left removeObjectsInArray:batch];
        [[NSUserDefaults standardUserDefaults] setObject:left forKey:kPendingKey];
        if (left.count) [self flushPending];
    }];
}

@end
