#import "RTUpdateChecker.h"

static NSString *const RTLatestReleaseAPI = @"https://api.github.com/repos/paselsoft/radiotray-mac/releases/latest";

@implementation RTUpdateChecker

+ (NSArray<NSNumber *> *)parts:(NSString *)version
{
    NSString *v = [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([v.lowercaseString hasPrefix:@"v"]) v = [v substringFromIndex:1];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *p in [v componentsSeparatedByString:@"."]) [out addObject:@(p.integerValue)];
    return out;
}

+ (BOOL)version:(NSString *)candidate isNewerThan:(NSString *)current
{
    NSArray<NSNumber *> *a = [self parts:candidate], *b = [self parts:current];
    for (NSUInteger i = 0; i < MAX(a.count, b.count); i++) {
        NSInteger x = i < a.count ? a[i].integerValue : 0, y = i < b.count ? b[i].integerValue : 0;
        if (x != y) return x > y;
    }
    return NO;
}

+ (NSDictionary<NSString *, NSString *> *)releaseFromJSON:(NSData *)data
{
    id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    NSString *tag = root[@"tag_name"], *url = root[@"html_url"];
    if (![tag isKindOfClass:[NSString class]] || ![url isKindOfClass:[NSString class]] || tag.length == 0) return nil;
    if ([root[@"draft"] boolValue] || [root[@"prerelease"] boolValue]) return nil;
    return @{ @"version": [tag.lowercaseString hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag, @"url": url };
}

+ (void)checkWithCurrentVersion:(NSString *)current completion:(RTUpdateCompletion)completion
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:RTLatestReleaseAPI]];
    req.timeoutInterval = 15;
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:[NSString stringWithFormat:@"RadioTray-Mac/%@", current] forHTTPHeaderField:@"User-Agent"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSDictionary *release = [RTUpdateChecker releaseFromJSON:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!release) {
                    completion(nil, nil, error.localizedDescription ?: @"Risposta di GitHub non valida");
                } else if ([RTUpdateChecker version:release[@"version"] isNewerThan:current]) {
                    completion(release[@"version"], [NSURL URLWithString:release[@"url"]], nil);
                } else {
                    completion(nil, nil, nil);
                }
            });
        }];
    [task resume];
}

@end
