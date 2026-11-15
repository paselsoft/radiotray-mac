#import "RTBookmarks.h"

NSString *const RTRootGroupName = @"root";

@implementation RTStation
- (instancetype)init
{
    if ((self = [super init])) {
        _name = @"";
        _url = @"";
        _notifications = YES;
    }
    return self;
}
@end

@implementation RTGroup
- (instancetype)init
{
    if ((self = [super init])) {
        _name = @"";
        _stations = @[];
    }
    return self;
}
- (BOOL)isRoot
{
    return [self.name isEqualToString:RTRootGroupName];
}
@end

@interface RTBookmarks ()
@property (nonatomic, copy, readwrite) NSArray<RTGroup *> *groups;
@end

static NSString *RTString(id value)
{
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length ? s : nil;
    }
    return nil;
}

static BOOL RTBool(id value, BOOL fallback)
{
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)value lowercaseString];
        if ([s isEqualToString:@"true"] || [s isEqualToString:@"1"]) return YES;
        if ([s isEqualToString:@"false"] || [s isEqualToString:@"0"]) return NO;
    }
    return fallback;
}

@implementation RTBookmarks

+ (instancetype)bookmarksWithContentsOfFile:(NSString *)path error:(NSString **)error
{
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    if (!data) {
        if (error) *error = [NSString stringWithFormat:@"Impossibile leggere %@: %@", path.lastPathComponent,
                             readError.localizedDescription ?: @"errore sconosciuto"];
        return nil;
    }
    return [self bookmarksWithData:data error:error];
}

+ (instancetype)bookmarksWithData:(NSData *)data error:(NSString **)error
{
    NSError *jsonError = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (!root) {
        NSString *detail = jsonError.userInfo[@"NSDebugDescription"] ?: jsonError.localizedDescription;
        if (error) *error = [NSString stringWithFormat:@"Il file delle stazioni non è un JSON valido: %@", detail ?: @"?"];
        return nil;
    }
    if (![root isKindOfClass:[NSArray class]]) {
        if (error) *error = @"Il file delle stazioni deve contenere un elenco di gruppi: [ { \"group\": ..., \"stations\": [...] } ]";
        return nil;
    }

    NSMutableArray<RTGroup *> *groups = [NSMutableArray array];
    NSMutableSet<NSString *> *groupNames = [NSMutableSet set];
    NSUInteger index = 0;
    for (id g in (NSArray *)root) {
        index++;
        if (![g isKindOfClass:[NSDictionary class]]) {
            if (error) *error = [NSString stringWithFormat:@"Il gruppo n. %lu non è un oggetto JSON", (unsigned long)index];
            return nil;
        }
        NSString *groupName = RTString(g[@"group"]);
        if (!groupName) {
            if (error) *error = [NSString stringWithFormat:@"Il gruppo n. %lu non ha il campo \"group\"", (unsigned long)index];
            return nil;
        }
        if ([groupNames containsObject:groupName]) {
            if (error) *error = [NSString stringWithFormat:@"Il gruppo \"%@\" compare due volte", groupName];
            return nil;
        }
        [groupNames addObject:groupName];

        id stationsValue = g[@"stations"];
        if (stationsValue && ![stationsValue isKindOfClass:[NSArray class]]) {
            if (error) *error = [NSString stringWithFormat:@"Nel gruppo \"%@\" il campo \"stations\" deve essere un elenco", groupName];
            return nil;
        }

        NSMutableArray<RTStation *> *stations = [NSMutableArray array];
        NSMutableSet<NSString *> *stationNames = [NSMutableSet set];
        for (id s in (NSArray *)stationsValue) {
            if (![s isKindOfClass:[NSDictionary class]]) continue;
            NSString *name = RTString(s[@"name"]);
            NSString *url = RTString(s[@"url"]);
            if (!name || !url) {
                if (error) *error = [NSString stringWithFormat:@"Nel gruppo \"%@\" c'è una stazione senza \"name\" o \"url\"", groupName];
                return nil;
            }
            if ([stationNames containsObject:name]) {
                // come Radiotray-NG: i nomi doppi nello stesso gruppo vengono ignorati
                continue;
            }
            [stationNames addObject:name];
            RTStation *station = [RTStation new];
            station.name = name;
            station.url = url;
            station.image = RTString(s[@"image"]);
            station.notifications = RTBool(s[@"notifications"], YES);
            station.direct = RTBool(s[@"direct"], NO);
            [stations addObject:station];
        }

        RTGroup *group = [RTGroup new];
        group.name = groupName;
        group.image = RTString(g[@"image"]);
        group.stations = stations;
        [groups addObject:group];
    }

    RTBookmarks *bookmarks = [self new];
    bookmarks.groups = groups;
    return bookmarks;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _groups = @[];
    }
    return self;
}

- (RTGroup *)groupNamed:(NSString *)name
{
    for (RTGroup *g in self.groups) {
        if ([g.name isEqualToString:name]) return g;
    }
    return nil;
}

- (RTStation *)stationNamed:(NSString *)name inGroup:(NSString *)group
{
    for (RTStation *s in [self groupNamed:group].stations) {
        if ([s.name isEqualToString:name]) return s;
    }
    return nil;
}

- (NSUInteger)stationCount
{
    NSUInteger n = 0;
    for (RTGroup *g in self.groups) n += g.stations.count;
    return n;
}

@end
