#import "RTTrackInfo.h"

static NSString *RTTrim(NSString *s)
{
    return s ? [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
}

NSString *RTTruncate(NSString *text, NSUInteger max)
{
    if (text.length <= max || max < 2) return text;
    NSRange r = [text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, max - 1)];
    return [RTTrim([text substringWithRange:r]) stringByAppendingString:@"…"];
}

@interface RTTrackInfo ()
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSString *artist;
@end

@implementation RTTrackInfo

+ (instancetype)infoWithTitle:(NSString *)title artist:(NSString *)artist
{
    RTTrackInfo *info = [self new];
    info.title = RTTrim(title);
    info.artist = RTTrim(artist);
    // un titolo fatto solo di "-" è un tag vuoto
    if ([info.title isEqualToString:@"-"]) info.title = @"";
    if ([info.artist isEqualToString:@"-"]) info.artist = @"";
    return info;
}

+ (instancetype)infoWithStreamTitle:(NSString *)streamTitle split:(BOOL)split
{
    NSString *raw = RTTrim(streamTitle);
    if (!split) return [self infoWithTitle:raw artist:nil];

    NSRange sep = [raw rangeOfString:@" - "];
    if (sep.location == NSNotFound) return [self infoWithTitle:raw artist:nil];

    NSString *artist = RTTrim([raw substringToIndex:sep.location]);
    NSString *title = RTTrim([raw substringFromIndex:NSMaxRange(sep)]);

    // iHeartRadio: title="..." text="Titolo vero" song_spot=...
    NSRange text = [title rangeOfString:@"text=\""];
    if (text.location != NSNotFound) {
        NSUInteger start = NSMaxRange(text);
        NSRange end = [title rangeOfString:@"\"" options:0 range:NSMakeRange(start, title.length - start)];
        if (end.location != NSNotFound) {
            title = [title substringWithRange:NSMakeRange(start, end.location - start)];
        }
    }

    if (title.length == 0) {
        // "Artista - " senza titolo: meglio mostrare il testo intero
        return [self infoWithTitle:artist artist:nil];
    }
    return [self infoWithTitle:title artist:artist];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _title = @"";
        _artist = @"";
    }
    return self;
}

- (BOOL)isEmpty
{
    return self.title.length == 0 && self.artist.length == 0;
}

- (BOOL)isEqualToInfo:(RTTrackInfo *)other
{
    return other && [self.title isEqualToString:other.title] && [self.artist isEqualToString:other.artist];
}

- (NSString *)clipboardText
{
    if (self.artist.length == 0) return self.title;
    if (self.title.length == 0) return self.artist;
    return [NSString stringWithFormat:@"%@\n%@", self.title, self.artist];
}

@end
