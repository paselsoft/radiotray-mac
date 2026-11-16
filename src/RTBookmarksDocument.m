#import "RTBookmarksDocument.h"
#import "RTBookmarks.h"

static NSString *RTClean(NSString *s)
{
    return s ? [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
}

static BOOL RTValidURL(NSString *url)
{
    NSURL *u = [NSURL URLWithString:url];
    NSString *scheme = u.scheme.lowercaseString;
    return u.host.length > 0 && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]);
}

#pragma mark - Stazione

@interface RTDocStation ()
@property (nonatomic, strong) NSMutableDictionary *raw;
@end

@implementation RTDocStation
- (NSString *)name { return self.raw[@"name"] ?: @""; }
- (void)setName:(NSString *)name { self.raw[@"name"] = [name copy]; }
- (NSString *)url { return self.raw[@"url"] ?: @""; }
- (NSString *)image { id v = self.raw[@"image"]; return [v isKindOfClass:[NSString class]] && [v length] ? v : nil; }
- (void)setUrl:(NSString *)url { self.raw[@"url"] = [url copy]; }
@end

#pragma mark - Gruppo

@interface RTDocGroup ()
@property (nonatomic, strong) NSMutableDictionary *raw;   // senza "stations"
@property (nonatomic, readwrite) NSMutableArray<RTDocStation *> *stations;
@end

@implementation RTDocGroup
- (NSString *)name { return self.raw[@"group"] ?: @""; }
- (void)setName:(NSString *)name { self.raw[@"group"] = [name copy]; }
- (BOOL)isRoot { return [self.name isEqualToString:RTRootGroupName]; }

- (RTDocStation *)stationNamed:(NSString *)name except:(RTDocStation *)except
{
    for (RTDocStation *s in self.stations) {
        if (s != except && [s.name caseInsensitiveCompare:name] == NSOrderedSame) return s;
    }
    return nil;
}
@end

#pragma mark - Documento

@interface RTBookmarksDocument ()
@property (nonatomic, readwrite) NSMutableArray<RTDocGroup *> *groups;
@end

@implementation RTBookmarksDocument

+ (instancetype)documentWithData:(NSData *)data error:(NSString **)error
{
    // stesse regole dell'app: un file che l'app rifiuta non si apre nell'editor
    if (![RTBookmarks bookmarksWithData:data error:error]) return nil;
    NSArray *root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:NULL];
    RTBookmarksDocument *doc = [self new];
    doc.groups = [NSMutableArray array];
    for (NSMutableDictionary *g in root) {
        RTDocGroup *group = [RTDocGroup new];
        group.raw = [g mutableCopy];
        [group.raw removeObjectForKey:@"stations"];
        group.raw[@"group"] = RTClean(g[@"group"]);
        group.stations = [NSMutableArray array];
        NSArray *stations = [g[@"stations"] isKindOfClass:[NSArray class]] ? g[@"stations"] : @[];
        for (id s in stations) {
            if (![s isKindOfClass:[NSDictionary class]]) continue;
            RTDocStation *station = [RTDocStation new];
            station.raw = [s mutableCopy];
            station.raw[@"name"] = RTClean(s[@"name"]);
            station.raw[@"url"] = RTClean(s[@"url"]);
            station.group = group;
            [group.stations addObject:station];
        }
        [doc.groups addObject:group];
    }
    return doc;
}

- (instancetype)init
{
    if ((self = [super init])) _groups = [NSMutableArray array];
    return self;
}

- (NSData *)dataRepresentation
{
    NSMutableArray *root = [NSMutableArray array];
    for (RTDocGroup *g in self.groups) {
        NSMutableDictionary *dict = [g.raw mutableCopy];
        NSMutableArray *stations = [NSMutableArray array];
        for (RTDocStation *s in g.stations) [stations addObject:s.raw];
        dict[@"stations"] = stations;
        [root addObject:dict];
    }
    NSData *out = [NSJSONSerialization dataWithJSONObject:root
                                                  options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] ?: @"[]";
    text = [[text stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"] stringByAppendingString:@"\n"];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSString *)displayNameForGroup:(RTDocGroup *)group
{
    return group.isRoot ? @"(senza gruppo)" : group.name;
}

- (RTDocGroup *)groupNamed:(NSString *)name
{
    for (RTDocGroup *g in self.groups) {
        if ([g.name caseInsensitiveCompare:name] == NSOrderedSame) return g;
    }
    return nil;
}

- (RTDocGroup *)rootGroup
{
    RTDocGroup *g = [self groupNamed:RTRootGroupName];
    if (g) return g;
    g = [RTDocGroup new];
    g.raw = [@{ @"group": RTRootGroupName } mutableCopy];
    g.stations = [NSMutableArray array];
    [self.groups addObject:g];
    return g;
}

#pragma mark - Gruppi

- (NSString *)checkGroupName:(NSString *)name except:(RTDocGroup *)except
{
    if (name.length == 0) return @"Il nome del gruppo non può essere vuoto.";
    if ([name caseInsensitiveCompare:RTRootGroupName] == NSOrderedSame)
        return @"\"root\" è riservato alle stazioni senza gruppo: scegli un altro nome.";
    RTDocGroup *other = [self groupNamed:name];
    if (other && other != except) return [NSString stringWithFormat:@"Esiste già un gruppo chiamato \"%@\".", other.name];
    return nil;
}

- (NSString *)addGroupNamed:(NSString *)name atIndex:(NSUInteger)index group:(RTDocGroup **)created
{
    name = RTClean(name);
    NSString *problem = [self checkGroupName:name except:nil];
    if (problem) return problem;
    RTDocGroup *g = [RTDocGroup new];
    g.raw = [@{ @"group": name } mutableCopy];
    g.stations = [NSMutableArray array];
    [self.groups insertObject:g atIndex:MIN(index, self.groups.count)];
    if (created) *created = g;
    return nil;
}

- (NSString *)renameGroup:(RTDocGroup *)group to:(NSString *)name
{
    name = RTClean(name);
    if (group.isRoot) return @"Le stazioni senza gruppo non hanno un nome da cambiare.";
    if ([name isEqualToString:group.name]) return nil;
    NSString *problem = [self checkGroupName:name except:group];
    if (problem) return problem;
    group.name = name;
    return nil;
}

- (NSString *)removeGroup:(RTDocGroup *)group
{
    if (![self.groups containsObject:group]) return @"Gruppo non trovato.";
    [self.groups removeObject:group];
    return nil;
}

- (NSString *)moveGroup:(RTDocGroup *)group toIndex:(NSUInteger)index
{
    if (![self.groups containsObject:group]) return @"Gruppo non trovato.";
    [self.groups removeObject:group];
    [self.groups insertObject:group atIndex:MIN(index, self.groups.count)];
    return nil;
}

#pragma mark - Stazioni

- (NSString *)checkStationName:(NSString *)name inGroup:(RTDocGroup *)group except:(RTDocStation *)except
{
    if (name.length == 0) return @"Il nome della stazione non può essere vuoto.";
    RTDocStation *other = [group stationNamed:name except:except];
    if (other) return [NSString stringWithFormat:@"In \"%@\" c'è già una stazione chiamata \"%@\".",
                       [RTBookmarksDocument displayNameForGroup:group], other.name];
    return nil;
}

- (NSString *)addStationNamed:(NSString *)name url:(NSString *)url toGroup:(RTDocGroup *)group
                      atIndex:(NSUInteger)index station:(RTDocStation **)created
{
    name = RTClean(name);
    url = RTClean(url);
    if (![self.groups containsObject:group]) return @"Gruppo non trovato.";
    NSString *problem = [self checkStationName:name inGroup:group except:nil];
    if (problem) return problem;
    if (!RTValidURL(url)) return @"L'indirizzo deve iniziare con http:// o https://";
    RTDocStation *s = [RTDocStation new];
    s.raw = [@{ @"name": name, @"url": url } mutableCopy];
    s.group = group;
    [group.stations insertObject:s atIndex:MIN(index, group.stations.count)];
    if (created) *created = s;
    return nil;
}

- (NSString *)renameStation:(RTDocStation *)station to:(NSString *)name
{
    name = RTClean(name);
    if ([name isEqualToString:station.name]) return nil;
    NSString *problem = [self checkStationName:name inGroup:station.group except:station];
    if (problem) return problem;
    station.name = name;
    return nil;
}

- (NSString *)setURL:(NSString *)url forStation:(RTDocStation *)station
{
    url = RTClean(url);
    if ([url isEqualToString:station.url]) return nil;
    if (!RTValidURL(url)) return @"L'indirizzo deve iniziare con http:// o https://";
    station.url = url;
    [station.raw removeObjectForKey:@"mirrors"];   // i server di riserva erano dell'indirizzo vecchio
    return nil;
}

- (void)setMirrors:(NSArray<NSString *> *)mirrors forStation:(RTDocStation *)station
{
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *m in mirrors) {
        NSString *u = RTClean(m);
        if (RTValidURL(u) && ![u isEqualToString:station.url] && ![clean containsObject:u]) [clean addObject:u];
    }
    if (clean.count) station.raw[@"mirrors"] = clean;
    else [station.raw removeObjectForKey:@"mirrors"];
}

- (void)setImage:(NSString *)image forStation:(RTDocStation *)station
{
    if (image.length) station.raw[@"image"] = [image copy];
    else [station.raw removeObjectForKey:@"image"];
}

- (NSString *)removeStation:(RTDocStation *)station
{
    RTDocGroup *g = station.group;
    if (!g || ![g.stations containsObject:station]) return @"Stazione non trovata.";
    [g.stations removeObject:station];
    station.group = nil;
    return nil;
}

- (NSString *)moveStation:(RTDocStation *)station toGroup:(RTDocGroup *)group atIndex:(NSUInteger)index
{
    RTDocGroup *from = station.group;
    if (!from || ![self.groups containsObject:group]) return @"Gruppo non trovato.";
    if (from != group) {
        NSString *problem = [self checkStationName:station.name inGroup:group except:nil];
        if (problem) return problem;
    }
    [from.stations removeObject:station];
    [group.stations insertObject:station atIndex:MIN(index, group.stations.count)];
    station.group = group;
    return nil;
}

@end
