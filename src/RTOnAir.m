#import "RTOnAir.h"

static NSString *RTStr(id v) { return [v isKindOfClass:[NSString class]] ? v : @""; }

@interface RTOnAir ()
@property (nonatomic, copy, nullable) NSString *source;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic) NSUInteger generation;
@end

@implementation RTOnAir

- (instancetype)init
{
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"Mozilla/5.0 (Macintosh) RadioTray-Mac" };
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

+ (NSString *)sourceForURLs:(NSArray<NSString *> *)urls
{
    NSDictionary *gedi = @{ @"/radiodeejay/": @"https://www.deejay.it", @"/radiocapital/": @"https://www.capital.it",
                            @"/radiom2o/": @"https://www.m2o.it" };
    NSDictionary *raiCont = @{ @"162834": @"rai-radio-1", @"162063": @"rai-radio-2", @"162841": @"rai-radio-3",
                               @"173875": @"rai-isoradio", @"8842124": @"rai-radio-1-sport", @"173832": @"rai-radio-3-classica",
                               @"174078": @"rai-radio-techete", @"174086": @"rai-radio-kids", @"173799": @"rai-radio-tutta-italiana" };
    NSDictionary *raiIce = @{ @"/1.mp3": @"rai-radio-1", @"/2.mp3": @"rai-radio-2", @"/3.mp3": @"rai-radio-3", @"/6.mp3": @"rai-isoradio" };
    for (NSString *raw in urls) {
        NSString *u = raw.lowercaseString;
        // Radio Paradise: canale dal nome dello stream (…/mellow-flac, …/rock-128, …/aac-320 = Main Mix)
        if ([u containsString:@"radioparadise.com"]) {
            NSString *last = [NSURL URLWithString:u].path.lastPathComponent ?: @"";
            NSString *chan = [last hasPrefix:@"mellow"] ? @"1" : [last hasPrefix:@"rock"] ? @"2"
                           : ([last hasPrefix:@"global"] || [last hasPrefix:@"world"] || [last hasPrefix:@"eclectic"]) ? @"3" : @"0";
            return [@"rp:" stringByAppendingString:chan];
        }
        if ([u containsString:@"msvdn.net"]) {
            for (NSString *k in gedi) if ([u containsString:k]) return [@"gedi:" stringByAppendingString:gedi[k]];
        }
        if ([u containsString:@"mediapolis.rai.it"]) {
            NSURLComponents *c = [NSURLComponents componentsWithString:raw];
            for (NSURLQueryItem *q in c.queryItems) {
                if ([q.name isEqualToString:@"cont"] && raiCont[q.value]) return [@"rai:" stringByAppendingString:raiCont[q.value]];
            }
        }
        if ([u containsString:@"icestreaming.rai.it"]) {
            for (NSString *k in raiIce) if ([u hasSuffix:k]) return [@"rai:" stringByAppendingString:raiIce[k]];
        }
    }
    return nil;
}

+ (NSURL *)scheduleURLForStationURL:(NSString *)url name:(NSString *)name
{
    NSString *u = url.lowercaseString ?: @"";
    NSString *n = name.lowercaseString ?: @"";
    // indirizzo dello stream → pagina del palinsesto (controllate a novembre 2026)
    NSArray<NSArray<NSString *> *> *byURL = @[
        @[@"radio24", @"https://www.radio24.ilsole24ore.com/palinsesto"],
        @[@"/radiodeejay/", @"https://www.deejay.it/palinsesto/"],
        @[@"/radiocapital/", @"https://www.capital.it/palinsesto/"],
        @[@"/radiom2o/", @"https://www.m2o.it/palinsesto/"],
        @[@"rds.radio", @"https://www.rds.it/palinsesto"],
        @[@"edge.radiomontecarlo.net/rmc.", @"https://www.radiomontecarlo.net/palinsesto/"],
        @[@"unitedradio.it/rmc.", @"https://www.radiomontecarlo.net/palinsesto/"],
        @[@"unitedradio.it/virgin", @"https://www.virginradio.it/palinsesto/"],
        @[@"unitedradio.it/radio105", @"https://www.105.net/palinsesto/"],
        @[@"unitedradio.it/r101", @"https://www.r101.it/palinsesto/"],
        @[@"unitedradio.it/subasio", @"https://www.radiosubasio.it/palinsesto/"],
        @[@"kisskiss", @"https://kisskiss.it/palinsesto/"],
        @[@"radioitalia", @"https://www.radioitalia.it/palinsesto"],
        @[@"icestreaming.rai.it/1.mp3", @"https://www.raiplaysound.it/radio1/palinsesto"],
        @[@"icestreaming.rai.it/2.mp3", @"https://www.raiplaysound.it/radio2/palinsesto"],
        @[@"icestreaming.rai.it/3.mp3", @"https://www.raiplaysound.it/radio3/palinsesto"],
        @[@"icestreaming.rai.it/6.mp3", @"https://www.raiplaysound.it/isoradio/palinsesto"],
        @[@"cont=162834", @"https://www.raiplaysound.it/radio1/palinsesto"],
        @[@"cont=162063", @"https://www.raiplaysound.it/radio2/palinsesto"],
        @[@"cont=162841", @"https://www.raiplaysound.it/radio3/palinsesto"],
        @[@"cont=173875", @"https://www.raiplaysound.it/isoradio/palinsesto"],
    ];
    for (NSArray<NSString *> *e in byURL) if ([u containsString:e[0]]) return [NSURL URLWithString:e[1]];
    // indirizzi diversi (trovati con Cerca stazioni): si riconosce il nome esatto della radio
    NSDictionary<NSString *, NSString *> *byName = @{
        @"radio 24": @"https://www.radio24.ilsole24ore.com/palinsesto",
        @"radio deejay": @"https://www.deejay.it/palinsesto/", @"radio capital": @"https://www.capital.it/palinsesto/",
        @"radio monte carlo": @"https://www.radiomontecarlo.net/palinsesto/", @"virgin radio": @"https://www.virginradio.it/palinsesto/",
        @"radio 105": @"https://www.105.net/palinsesto/", @"r101": @"https://www.r101.it/palinsesto/",
        @"rai radio 1": @"https://www.raiplaysound.it/radio1/palinsesto", @"rai radio 2": @"https://www.raiplaysound.it/radio2/palinsesto",
        @"rai radio 3": @"https://www.raiplaysound.it/radio3/palinsesto", @"rai isoradio": @"https://www.raiplaysound.it/isoradio/palinsesto",
    };
    NSString *page = byName[[n stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    return page ? [NSURL URLWithString:page] : nil;
}

/// Parola tutta maiuscola ("SARAH", "GLOCKENBACH,", "&"), con almeno una lettera o un simbolo da nome d'artista.
static BOOL RTIsUpperWord(NSString *w)
{
    if (!w.length) return NO;
    if ([w isEqualToString:@"&"] || [w isEqualToString:@"X"] || [w isEqualToString:@"+"]) return YES;
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    if ([w rangeOfCharacterFromSet:letters].location == NSNotFound) return NO;
    return [w isEqualToString:w.uppercaseString] && ![w isEqualToString:w.lowercaseString];
}

+ (NSDictionary<NSString *, NSString *> *)songFromGediJSON:(NSData *)data
{
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSString *full = [RTStr(json[@"title"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!full.length) return nil;
    NSString *cover = RTStr(json[@"image"]);
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if ([cover hasPrefix:@"http"]) out[@"cover"] = cover;

    // "Titolo del brano ARTISTA IN MAIUSCOLO": l'artista sono le parole maiuscole in fondo
    NSArray<NSString *> *words = [full componentsSeparatedByString:@" "];
    NSInteger cut = (NSInteger)words.count;
    while (cut > 0 && RTIsUpperWord(words[(NSUInteger)cut - 1])) cut--;
    if (cut > 0 && cut < (NSInteger)words.count) {
        out[@"title"] = [[words subarrayWithRange:NSMakeRange(0, (NSUInteger)cut)] componentsJoinedByString:@" "];
        out[@"artist"] = [[words subarrayWithRange:NSMakeRange((NSUInteger)cut, words.count - (NSUInteger)cut)] componentsJoinedByString:@" "];
        return out;
    }
    // tutto maiuscolo: si prova il nome del file della copertina, "ARTISTA_-_Titolo__AI_….jpg"
    NSString *file = [[NSURL URLWithString:cover].lastPathComponent stringByRemovingPercentEncoding] ?: @"";
    NSRange end = [file rangeOfString:@"__"];
    if (end.location != NSNotFound) file = [file substringToIndex:end.location];
    NSRange dash = [file rangeOfString:@"_-_"];
    if (cut == 0 && dash.location != NSNotFound) {
        out[@"artist"] = [[file substringToIndex:dash.location] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        out[@"title"] = full;
        return out;
    }
    out[@"title"] = full;   // programma o titolo che non si sa dividere
    return out;
}

+ (NSDictionary<NSString *, NSString *> *)songFromRadioParadiseJSON:(NSData *)data
{
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSString *title = [RTStr(json[@"title"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *artist = [RTStr(json[@"artist"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!title.length || !artist.length) return nil;
    NSMutableDictionary *out = [@{ @"title": title, @"artist": artist } mutableCopy];
    NSString *cover = RTStr(json[@"cover"]).length ? RTStr(json[@"cover"]) : RTStr(json[@"cover_med"]);
    if ([cover hasPrefix:@"http"]) out[@"cover"] = cover;
    return out;
}

+ (NSString *)programFromRaiJSON:(NSData *)data atDate:(NSDate *)date
{
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:[NSDictionary class]] || ![json[@"events"] isKindOfClass:[NSArray class]]) return nil;
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    for (NSDictionary *e in json[@"events"]) {
        if (![e isKindOfClass:[NSDictionary class]]) continue;
        NSDate *start = [f dateFromString:RTStr(e[@"start_date"])], *stop = [f dateFromString:RTStr(e[@"end_date"])];
        if (!start || !stop) continue;
        if ([date compare:start] != NSOrderedAscending && [date compare:stop] == NSOrderedAscending) {
            NSString *title = RTStr(e[@"title"]).length ? RTStr(e[@"title"]) : RTStr(e[@"name"]);
            return title.length ? title : nil;
        }
    }
    return nil;
}

- (void)startWithSource:(NSString *)source
{
    [self stop];
    self.source = source;
    BOOL rai = [source hasPrefix:@"rai:"];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:rai ? 120 : 20 target:self selector:@selector(poll) userInfo:nil repeats:YES];
    self.timer.tolerance = 5;
    [self poll];
}

- (void)stop
{
    [self.timer invalidate];
    self.timer = nil;
    self.source = nil;
    self.generation++;
}

- (void)poll
{
    NSString *source = self.source;
    if (!source) return;
    NSUInteger generation = self.generation;
    NSURL *url;
    BOOL rai = [source hasPrefix:@"rai:"];
    BOOL paradise = [source hasPrefix:@"rp:"];
    if (paradise) {
        url = [NSURL URLWithString:[@"https://api.radioparadise.com/api/now_playing?chan=" stringByAppendingString:[source substringFromIndex:3]]];
    } else if (rai) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Rome"];
        f.dateFormat = @"dd-MM-yyyy";
        url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.raiplaysound.it/palinsesto/app/%@/%@.json",
                                    [source substringFromIndex:4], [f stringFromDate:[NSDate date]]]];
    } else {
        url = [NSURL URLWithString:[[source substringFromIndex:5] stringByAppendingString:@"/api/pub/v2/all/gdwc-audio-player/onair?format=json"]];
    }
    __weak typeof(self) weakSelf = self;
    [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.generation != generation || !data) return;
            if (rai) {
                [strongSelf.delegate onAirProgram:[RTOnAir programFromRaiJSON:data atDate:[NSDate date]]];
                return;
            }
            if (paradise) {
                NSDictionary *rp = [RTOnAir songFromRadioParadiseJSON:data];
                if (rp) [strongSelf.delegate onAirSong:rp[@"title"] artist:rp[@"artist"] cover:rp[@"cover"]];
                return;
            }
            NSDictionary *song = [RTOnAir songFromGediJSON:data];
            if (!song) return;
            if ([song[@"artist"] length]) {
                [strongSelf.delegate onAirSong:song[@"title"] artist:song[@"artist"] cover:song[@"cover"]];
            } else {
                [strongSelf.delegate onAirProgram:song[@"title"]];
            }
        });
    }] resume];
}

@end
