#import "RTFavoriteTracks.h"

static NSString *RTTrimmed(id v)
{
    return [v isKindOfClass:[NSString class]]
        ? [(NSString *)v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
}

static NSISO8601DateFormatter *RTDateFormatter(void)
{
    static NSISO8601DateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [NSISO8601DateFormatter new]; });
    return f;
}

@implementation RTFavoriteTrack

- (NSString *)displayText
{
    return self.artist.length ? [NSString stringWithFormat:@"%@ – %@", self.title, self.artist] : self.title;
}

- (NSString *)searchText
{
    return self.artist.length ? [NSString stringWithFormat:@"%@ %@", self.artist, self.title] : self.title;
}

@end

@interface RTFavoriteTracks ()
@property (nonatomic, strong) NSMutableArray<RTFavoriteTrack *> *list;
@end

@implementation RTFavoriteTracks

- (instancetype)init
{
    if ((self = [super init])) _list = [NSMutableArray array];
    return self;
}

- (NSArray<RTFavoriteTrack *> *)tracks
{
    return [self.list copy];
}

+ (instancetype)tracksWithContentsOfFile:(NSString *)path error:(NSString **)error
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return [self new];
    return [self tracksWithData:[NSData dataWithContentsOfFile:path] error:error];
}

+ (instancetype)tracksWithData:(NSData *)data error:(NSString **)error
{
    RTFavoriteTracks *result = [self new];
    if (data.length == 0) return result;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:[NSArray class]]) {
        if (error) *error = @"Il file dei brani preferiti non è un elenco JSON valido";
        return nil;
    }
    for (id item in (NSArray *)root) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        RTFavoriteTrack *t = [RTFavoriteTrack new];
        t.title = RTTrimmed(item[@"title"]);
        t.artist = RTTrimmed(item[@"artist"]);
        t.station = RTTrimmed(item[@"station"]);
        if (t.title.length == 0 && t.artist.length == 0) continue;
        if (t.title.length == 0) {   // solo artista: lo si mostra come titolo
            t.title = t.artist;
            t.artist = @"";
        }
        t.added = [RTDateFormatter() dateFromString:RTTrimmed(item[@"added"])] ?: [NSDate dateWithTimeIntervalSince1970:0];
        [result.list addObject:t];
    }
    return result;
}

- (NSData *)dataRepresentation
{
    NSMutableArray *root = [NSMutableArray array];
    for (RTFavoriteTrack *t in self.list) {
        [root addObject:@{ @"title": t.title, @"artist": t.artist, @"station": t.station,
                           @"added": [RTDateFormatter() stringFromDate:t.added] }];
    }
    NSData *out = [NSJSONSerialization dataWithJSONObject:root
                                                  options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] ?: @"[]";
    text = [[text stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"] stringByAppendingString:@"\n"];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

- (RTFavoriteTrack *)trackWithTitle:(NSString *)title artist:(NSString *)artist
{
    title = RTTrimmed(title);
    artist = RTTrimmed(artist);
    for (RTFavoriteTrack *t in self.list) {
        if ([t.title caseInsensitiveCompare:title] == NSOrderedSame && [t.artist caseInsensitiveCompare:artist] == NSOrderedSame) {
            return t;
        }
    }
    return nil;
}

- (RTFavoriteTrack *)addTitle:(NSString *)title artist:(NSString *)artist station:(NSString *)station
                         date:(NSDate *)date alreadyPresent:(BOOL *)alreadyPresent
{
    title = RTTrimmed(title);
    artist = RTTrimmed(artist);
    if (title.length == 0) {
        title = artist;
        artist = @"";
    }
    RTFavoriteTrack *existing = [self trackWithTitle:title artist:artist];
    if (alreadyPresent) *alreadyPresent = existing != nil;
    if (existing) return existing;
    RTFavoriteTrack *t = [RTFavoriteTrack new];
    t.title = title;
    t.artist = artist;
    t.station = RTTrimmed(station);
    t.added = date;
    [self.list addObject:t];
    return t;
}

- (void)removeTracks:(NSArray<RTFavoriteTrack *> *)tracks
{
    [self.list removeObjectsInArray:tracks];
}

- (void)removeAllTracks
{
    [self.list removeAllObjects];
}

- (BOOL)recordTitle:(NSString *)title artist:(NSString *)artist station:(NSString *)station
               date:(NSDate *)date limit:(NSUInteger)limit
{
    title = RTTrimmed(title);
    artist = RTTrimmed(artist);
    if (title.length == 0) {
        title = artist;
        artist = @"";
    }
    if (title.length == 0) return NO;
    RTFavoriteTrack *existing = [self trackWithTitle:title artist:artist];
    if (existing && existing == self.list.lastObject) return NO;
    if (existing) [self.list removeObject:existing];
    RTFavoriteTrack *t = [RTFavoriteTrack new];
    t.title = title;
    t.artist = artist;
    t.station = RTTrimmed(station);
    t.added = date;
    [self.list addObject:t];
    while (limit > 0 && self.list.count > limit) [self.list removeObjectAtIndex:0];
    return YES;
}

- (NSArray<NSString *> *)stations
{
    NSMutableSet *set = [NSMutableSet set];
    for (RTFavoriteTrack *t in self.list) if (t.station.length) [set addObject:t.station];
    return [set.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray<RTFavoriteTrack *> *)tracksMatching:(NSString *)query station:(NSString *)station
                               sortDescriptors:(NSArray<NSSortDescriptor *> *)sort
{
    query = RTTrimmed(query);
    NSStringCompareOptions opts = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray<RTFavoriteTrack *> *out = [NSMutableArray array];
    for (RTFavoriteTrack *t in self.list) {
        if (station.length && ![t.station isEqualToString:station]) continue;
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@", t.title, t.artist, t.station];
        BOOL ok = YES;
        for (NSString *w in words) {   // tutte le parole devono comparire, in qualsiasi ordine
            if (w.length && [haystack rangeOfString:w options:opts].location == NSNotFound) {
                ok = NO;
                break;
            }
        }
        if (ok) [out addObject:t];
    }
    if (sort.count) [out sortUsingDescriptors:sort];
    return out;
}

+ (NSData *)csvForTracks:(NSArray<RTFavoriteTrack *> *)tracks
{
    NSString *(^field)(NSString *) = ^NSString *(NSString *s) {
        return [NSString stringWithFormat:@"\"%@\"", [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
    };
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];
    df.dateFormat = @"dd/MM/yyyy HH:mm";
    NSMutableString *csv = [NSMutableString stringWithString:@"﻿Titolo;Artista;Stazione;Aggiunto il\r\n"];
    for (RTFavoriteTrack *t in tracks) {
        [csv appendFormat:@"%@;%@;%@;%@\r\n", field(t.title), field(t.artist), field(t.station), field([df stringFromDate:t.added])];
    }
    return [csv dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSURL *)searchURLForTrack:(RTFavoriteTrack *)track site:(RTTrackSearchSite)site
{
    // codifica esplicita: "&", "+", "/" e simili nei titoli non devono spezzare l'indirizzo
    NSMutableCharacterSet *allowed = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowed addCharactersInString:@"-._~"];
    NSCharacterSet *ascii = [NSCharacterSet characterSetWithRange:NSMakeRange(0, 128)];
    [allowed formIntersectionWithCharacterSet:ascii];   // lettere accentate codificate in UTF-8
    NSString *q = [track.searchText stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    NSString *url = @"";
    switch (site) {
        case RTTrackSearchYouTube:    url = [@"https://www.youtube.com/results?search_query=" stringByAppendingString:q]; break;
        case RTTrackSearchAppleMusic: url = [@"https://music.apple.com/it/search?term=" stringByAppendingString:q]; break;
        case RTTrackSearchSpotify:    url = [@"https://open.spotify.com/search/" stringByAppendingString:q]; break;
        case RTTrackSearchYouTubeMusic: url = [@"https://music.youtube.com/search?q=" stringByAppendingString:q]; break;
    }
    return [NSURL URLWithString:url];
}

@end
