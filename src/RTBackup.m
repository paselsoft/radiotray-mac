#import "RTBackup.h"

static NSString *const RTBackupFormat = @"radiotray-mac-backup";

@implementation RTBackupContents
- (instancetype)init
{
    if ((self = [super init])) _settings = @{};
    return self;
}
@end

static id RTJSONFromData(NSData *data)
{
    return data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
}

static NSData *RTPrettyJSON(id object)
{
    NSData *out = [NSJSONSerialization dataWithJSONObject:object
                                                  options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] ?: @"{}";
    text = [[text stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"] stringByAppendingString:@"\n"];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

@implementation RTBackup

+ (NSISO8601DateFormatter *)iso
{
    static NSISO8601DateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSISO8601DateFormatter new]; });
    return f;
}

+ (NSData *)dataForContents:(RTBackupContents *)c
{
    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"format"] = RTBackupFormat;
    root[@"version"] = @1;
    root[@"app"] = c.appVersion ?: @"";
    root[@"created"] = [[self iso] stringFromDate:c.created ?: [NSDate date]];
    root[@"bookmarks"] = RTJSONFromData(c.bookmarks) ?: @[];
    root[@"favorites"] = RTJSONFromData(c.favorites) ?: @[];
    root[@"history"] = RTJSONFromData(c.history) ?: @[];
    root[@"settings"] = c.settings ?: @{};
    return RTPrettyJSON(root);
}

+ (RTBackupContents *)contentsFromData:(NSData *)data error:(NSString **)error
{
    id root = RTJSONFromData(data);
    if (![root isKindOfClass:[NSDictionary class]] || ![root[@"format"] isEqual:RTBackupFormat]) {
        if (error) *error = @"Il file non è un backup di RadioTray.";
        return nil;
    }
    if ([root[@"version"] integerValue] > 1) {
        if (error) *error = @"Il backup è stato creato da una versione più recente di RadioTray: aggiorna l'app e riprova.";
        return nil;
    }
    RTBackupContents *c = [RTBackupContents new];
    for (NSString *key in @[@"bookmarks", @"favorites", @"history"]) {
        id value = root[key];
        if (value && ![value isKindOfClass:[NSArray class]]) {
            if (error) *error = [NSString stringWithFormat:@"Il backup è danneggiato (sezione \"%@\").", key];
            return nil;
        }
    }
    c.bookmarks = [root[@"bookmarks"] count] ? RTPrettyJSON(root[@"bookmarks"]) : nil;
    c.favorites = [root[@"favorites"] count] ? RTPrettyJSON(root[@"favorites"]) : nil;
    c.history = [root[@"history"] count] ? RTPrettyJSON(root[@"history"]) : nil;
    c.settings = [root[@"settings"] isKindOfClass:[NSDictionary class]] ? [self exportableSettings:root[@"settings"]] : @{};
    c.appVersion = [root[@"app"] isKindOfClass:[NSString class]] ? root[@"app"] : nil;
    c.created = [root[@"created"] isKindOfClass:[NSString class]] ? [[self iso] dateFromString:root[@"created"]] : nil;
    return c;
}

+ (BOOL)isJSONValue:(id)v
{
    if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]) return YES;
    if ([v isKindOfClass:[NSArray class]]) {
        for (id x in (NSArray *)v) if (![self isJSONValue:x]) return NO;
        return YES;
    }
    if ([v isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)v) {
            if (![k isKindOfClass:[NSString class]] || ![self isJSONValue:((NSDictionary *)v)[k]]) return NO;
        }
        return YES;
    }
    return NO;
}

+ (NSDictionary<NSString *, id> *)exportableSettings:(NSDictionary<NSString *, id> *)defaults
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *key in defaults) {
        if (![key isKindOfClass:[NSString class]]) continue;
        // dati di sistema o legati a questo Mac
        if ([key hasPrefix:@"NS"] || [key hasPrefix:@"Apple"] || [key hasPrefix:@"com.apple"] ||
            [key isEqualToString:@"last-update-check"] || [key isEqualToString:@"alarm-last-fired"]) continue;
        id value = defaults[key];
        if ([self isJSONValue:value]) out[key] = value;
    }
    return out;
}

+ (NSString *)iCloudFolder
{
    NSString *drive = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Mobile Documents/com~apple~CloudDocs"];
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:drive isDirectory:&isDir] || !isDir) return nil;
    return [drive stringByAppendingPathComponent:@"RadioTray"];
}

+ (NSString *)writeBackup:(NSData *)data toFolder:(NSString *)folder keep:(NSUInteger)keep date:(NSDate *)date
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
        return error.localizedDescription ?: @"Impossibile creare la cartella dei backup";
    }
    if (![data writeToFile:[folder stringByAppendingPathComponent:@"RadioTray-backup.json"] options:NSDataWritingAtomic error:&error]) {
        return error.localizedDescription ?: @"Impossibile scrivere il backup";
    }
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"yyyy-MM-dd";
    NSString *dated = [NSString stringWithFormat:@"RadioTray-backup-%@.json", [df stringFromDate:date]];
    [data writeToFile:[folder stringByAppendingPathComponent:dated] options:NSDataWritingAtomic error:NULL];

    // si tengono solo le ultime copie datate (il nome contiene la data: l'ordine alfabetico è cronologico)
    NSMutableArray *copies = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:folder error:NULL]) {
        if ([name hasPrefix:@"RadioTray-backup-"] && [name hasSuffix:@".json"]) [copies addObject:name];
    }
    [copies sortUsingSelector:@selector(compare:)];
    while (keep > 0 && copies.count > keep) {
        [fm removeItemAtPath:[folder stringByAppendingPathComponent:copies.firstObject] error:NULL];
        [copies removeObjectAtIndex:0];
    }
    return nil;
}

@end
