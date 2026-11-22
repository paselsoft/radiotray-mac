#import "RTFFmpegOutput.h"

@interface RTFFmpegOutput ()
@property (nonatomic, copy, readwrite, nullable) NSString *codec;
@property (nonatomic, readwrite) NSInteger bitrate;
@property (nonatomic, copy, readwrite, nullable) NSString *lastError;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *block;   // metadati del blocco in corso
@property (nonatomic) BOOL inMetadata;
@property (nonatomic) NSUInteger metadataIndent;   // rientro della riga "Metadata:": i valori hanno un rientro maggiore
@property (nonatomic, copy, nullable) NSString *pendingTitle;
@property (nonatomic, copy, nullable) NSString *lastTitle;
@property (nonatomic, copy, nullable) NSString *pendingStation;
@property (nonatomic) BOOL stationGiven;
@end

@implementation RTFFmpegOutput

- (instancetype)init
{
    if ((self = [super init])) _block = [NSMutableDictionary dictionary];
    return self;
}

+ (NSString *)ffmpegPath
{
    for (NSString *p in @[@"/usr/local/bin/ffmpeg", @"/opt/local/bin/ffmpeg", @"/opt/homebrew/bin/ffmpeg"]) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) return p;
    }
    return nil;
}

+ (BOOL)needsFFmpegForURL:(NSString *)url contentType:(NSString *)contentType
{
    NSString *ct = contentType.lowercaseString ?: @"";
    for (NSString *t in @[@"application/ogg", @"audio/ogg", @"audio/opus", @"audio/flac", @"audio/x-flac", @"audio/vorbis", @"video/ogg"]) {
        if ([ct hasPrefix:t]) return YES;
    }
    NSString *ext = [NSURL URLWithString:url].path.pathExtension.lowercaseString ?: @"";
    if ([@[@"ogg", @"oga", @"opus", @"flac", @"spx"] containsObject:ext]) return YES;
    // indirizzi senza estensione ma con il formato nel nome (Radio Paradise: .../mellow-flac)
    NSString *last = [NSURL URLWithString:url].path.lastPathComponent.lowercaseString ?: @"";
    for (NSString *suffix in @[@"-flac", @"_flac", @"-ogg", @"_ogg", @"-opus", @"_opus"]) {
        if ([last hasSuffix:suffix]) return YES;
    }
    return NO;
}

+ (NSArray<NSString *> *)argumentsForURL:(NSString *)url
{
    NSMutableArray *args = [@[@"-nostdin", @"-hide_banner", @"-nostats", @"-loglevel", @"info"] mutableCopy];
    NSString *scheme = [NSURL URLWithString:url].scheme.lowercaseString ?: @"";
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        // opzioni del protocollo http: con altri protocolli ffmpeg le rifiuterebbe
        [args addObjectsFromArray:@[@"-reconnect", @"1", @"-reconnect_streamed", @"1", @"-reconnect_delay_max", @"5",
                                    @"-user_agent", @"RadioTray-Mac"]];
    }
    [args addObjectsFromArray:@[@"-i", url, @"-vn", @"-f", @"f32le", @"-acodec", @"pcm_f32le",
                                @"-ar", @"44100", @"-ac", @"2", @"pipe:1"]];
    return args;
}

+ (NSString *)displayNameForCodec:(NSString *)codec
{
    NSString *c = codec.lowercaseString;
    if ([c hasPrefix:@"flac"]) return @"FLAC";
    if ([c hasPrefix:@"opus"]) return @"Opus";
    if ([c hasPrefix:@"vorbis"]) return @"Vorbis";
    if ([c hasPrefix:@"mp3"]) return @"MP3";
    if ([c hasPrefix:@"aac"]) return [c containsString:@"he"] ? @"HE-AAC" : @"AAC";
    if ([c hasPrefix:@"speex"]) return @"Speex";
    if ([c hasPrefix:@"wma"]) return @"WMA";
    return codec.uppercaseString;
}

static NSUInteger RTIndent(NSString *s)
{
    NSUInteger i = 0;
    while (i < s.length && [s characterAtIndex:i] == ' ') i++;
    return i;
}

static NSString *RTTrim(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)flushMetadata
{
    if (!self.inMetadata && self.block.count == 0) return;
    self.inMetadata = NO;
    NSDictionary *b = [self.block copy];
    [self.block removeAllObjects];
    NSString *title = nil;
    NSString *stream = b[@"streamtitle"], *t = b[@"title"], *a = b[@"artist"];
    if (stream.length) title = stream;
    else if (t.length && a.length) title = [NSString stringWithFormat:@"%@ - %@", a, t];
    else if (t.length) title = t;
    if (title.length && ![title isEqualToString:self.lastTitle ?: @""]) {
        self.lastTitle = title;
        self.pendingTitle = title;
    }
    NSString *name = b[@"icy-name"];
    if (name.length && !self.stationGiven) self.pendingStation = name;
}

- (BOOL)consumeLine:(NSString *)raw
{
    NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *trimmed = RTTrim(line);
    if (!trimmed.length) return NO;

    // inizio di un blocco "Metadata:" (all'apertura dello stream e a ogni brano nuovo degli Ogg concatenati)
    if ([trimmed isEqualToString:@"Metadata:"] || [trimmed hasSuffix:@"Metadata:"]) {
        [self flushMetadata];
        self.inMetadata = YES;
        self.metadataIndent = RTIndent(line);
        return NO;
    }
    // riga "    chiave          : valore" dentro un blocco di metadati
    NSRange colon = [line rangeOfString:@":"];
    if (self.inMetadata && RTIndent(line) > self.metadataIndent && colon.location != NSNotFound) {
        NSString *key = RTTrim([line substringToIndex:colon.location]).lowercaseString;
        NSString *value = RTTrim([line substringFromIndex:colon.location + 1]);
        if (key.length && ![key containsString:@" "]) {
            if (self.block[key].length && value.length) value = [NSString stringWithFormat:@"%@\n%@", self.block[key], value];
            if (value.length) self.block[key] = value;
            return NO;
        }
    }
    [self flushMetadata];

    // "  Stream #0:0: Audio: flac, 44100 Hz, stereo, s16, 1411 kb/s" (l'uscita "pcm_f32le" non conta)
    NSRange audio = [line rangeOfString:@"Audio: "];
    if (audio.location != NSNotFound && [line containsString:@"Stream #"] && ![line containsString:@"pcm_f32le"]) {
        NSString *rest = [line substringFromIndex:NSMaxRange(audio)];
        NSString *codecName = RTTrim([rest componentsSeparatedByString:@","].firstObject ?: @"");
        NSRange paren = [codecName rangeOfString:@" ("];
        NSString *display = [RTFFmpegOutput displayNameForCodec:codecName];
        if (paren.location != NSNotFound && ![display isEqualToString:@"HE-AAC"]) {
            display = [RTFFmpegOutput displayNameForCodec:[codecName substringToIndex:paren.location]];
        }
        NSInteger kbps = 0;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d+) kb/s" options:0 error:NULL];
        NSTextCheckingResult *m = [re firstMatchInString:rest options:0 range:NSMakeRange(0, rest.length)];
        if (m) kbps = [[rest substringWithRange:[m rangeAtIndex:1]] integerValue];
        BOOL changed = ![display isEqualToString:self.codec ?: @""] || (kbps > 0 && kbps != self.bitrate);
        self.codec = display;
        if (kbps > 0) self.bitrate = kbps;
        return changed;
    }
    // "  Duration: N/A, start: 0.000000, bitrate: 128 kb/s" (prima della riga Audio)
    NSRange br = [line rangeOfString:@"bitrate: "];
    if (br.location != NSNotFound && [line containsString:@"Duration:"]) {
        NSInteger kbps = [[line substringFromIndex:NSMaxRange(br)] integerValue];
        if (kbps > 0 && self.bitrate == 0) {
            self.bitrate = kbps;
            return YES;
        }
        return NO;
    }
    // errori da mostrare se lo stream non parte
    NSString *lower = trimmed.lowercaseString;
    if ([lower containsString:@"error"] || [lower containsString:@"invalid data"] || [lower containsString:@"server returned"] ||
        [lower containsString:@"connection refused"] || [lower containsString:@"no such file"] || [lower containsString:@"timed out"]) {
        NSRange bracket = [trimmed rangeOfString:@"] "];
        self.lastError = bracket.location != NSNotFound && [trimmed hasPrefix:@"["] ? [trimmed substringFromIndex:NSMaxRange(bracket)] : trimmed;
    }
    return NO;
}

- (NSString *)takeTitle
{
    NSString *t = self.pendingTitle;
    self.pendingTitle = nil;
    return t;
}

- (NSString *)takeStationName
{
    NSString *n = self.pendingStation;
    if (n) {
        self.pendingStation = nil;
        self.stationGiven = YES;
    }
    return n;
}

@end
