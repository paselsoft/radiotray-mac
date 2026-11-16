#import "RTStats.h"

@implementation RTStats

+ (NSArray<NSArray *> *)top:(NSDictionary<NSString *, NSNumber *> *)values limit:(NSUInteger)limit
{
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *k in values) {
        if ([values[k] isKindOfClass:[NSNumber class]] && values[k].doubleValue > 0) [pairs addObject:@[k, values[k]]];
    }
    [pairs sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        NSComparisonResult r = [b[1] compare:a[1]];
        return r != NSOrderedSame ? r : [a[0] localizedCaseInsensitiveCompare:b[0]];
    }];
    return pairs.count > limit ? [pairs subarrayWithRange:NSMakeRange(0, limit)] : pairs;
}

+ (NSString *)describeSeconds:(double)seconds
{
    long minutes = (long)(seconds / 60.0 + 0.5);
    if (minutes < 60) return [NSString stringWithFormat:@"%ld min", minutes];
    long h = minutes / 60, m = minutes % 60;
    return m ? [NSString stringWithFormat:@"%ld h %ld min", h, m] : [NSString stringWithFormat:@"%ld h", h];
}

+ (NSString *)artistKey:(NSString *)artist
{
    NSString *s = [artist stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil];
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([s containsString:@"  "]) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    return s;
}

+ (NSString *)barFor:(double)value max:(double)max width:(NSUInteger)width
{
    if (max <= 0 || value <= 0) return @"";
    NSUInteger n = MAX((NSUInteger)1, (NSUInteger)(value / max * width + 0.5));
    return [@"" stringByPaddingToLength:MIN(n, width) withString:@"▇" startingAtIndex:0];
}

@end
