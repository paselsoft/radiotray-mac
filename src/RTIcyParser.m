#import "RTIcyParser.h"

typedef NS_ENUM(NSInteger, RTIcyPhase) {
    RTIcyPhaseAudio,
    RTIcyPhaseLength,
    RTIcyPhaseMeta,
};

@implementation RTIcyParser {
    NSUInteger _metaInterval;
    RTIcyPhase _phase;
    NSUInteger _remaining;      // byte ancora da leggere nella fase corrente
    NSMutableData *_meta;
}

- (instancetype)initWithMetaInterval:(NSUInteger)metaInterval
{
    if ((self = [super init])) {
        _metaInterval = MAX((NSUInteger)1, metaInterval);
        _phase = RTIcyPhaseAudio;
        _remaining = _metaInterval;
        _meta = [NSMutableData data];
    }
    return self;
}

- (NSArray<NSString *> *)feed:(NSData *)data
{
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    const unsigned char *bytes = data.bytes;
    NSUInteger length = data.length, i = 0;
    while (i < length) {
        switch (_phase) {
            case RTIcyPhaseAudio: {
                NSUInteger skip = MIN(_remaining, length - i);
                i += skip;
                _remaining -= skip;
                if (_remaining == 0) _phase = RTIcyPhaseLength;
                break;
            }
            case RTIcyPhaseLength: {
                NSUInteger metaLength = (NSUInteger)bytes[i++] * 16;
                if (metaLength == 0) {
                    _phase = RTIcyPhaseAudio;
                    _remaining = _metaInterval;
                } else {
                    _phase = RTIcyPhaseMeta;
                    _remaining = metaLength;
                    [_meta setLength:0];
                }
                break;
            }
            case RTIcyPhaseMeta: {
                NSUInteger take = MIN(_remaining, length - i);
                [_meta appendBytes:bytes + i length:take];
                i += take;
                _remaining -= take;
                if (_remaining == 0) {
                    NSString *title = [RTIcyParser streamTitleFromMetadata:_meta];
                    if (title) [titles addObject:title];
                    _phase = RTIcyPhaseAudio;
                    _remaining = _metaInterval;
                }
                break;
            }
        }
    }
    return titles;
}

+ (NSString *)streamTitleFromMetadata:(NSData *)metadata
{
    // il blocco è riempito di zeri fino a un multiplo di 16
    NSUInteger n = metadata.length;
    const unsigned char *b = metadata.bytes;
    while (n > 0 && b[n - 1] == 0) n--;
    NSData *trimmed = [metadata subdataWithRange:NSMakeRange(0, n)];
    NSString *text = [[NSString alloc] initWithData:trimmed encoding:NSUTF8StringEncoding]
                  ?: [[NSString alloc] initWithData:trimmed encoding:NSISOLatin1StringEncoding];
    if (!text) return nil;

    NSRange key = [text rangeOfString:@"StreamTitle=" options:NSCaseInsensitiveSearch];
    if (key.location == NSNotFound) return nil;
    NSUInteger start = NSMaxRange(key);
    if (start >= text.length) return @"";
    unichar quote = [text characterAtIndex:start];
    if (quote == '\'' || quote == '"') {
        start++;
        // il titolo può contenere apostrofi: la fine è la virgoletta seguita da ";" (o la fine del testo)
        NSString *terminator = [NSString stringWithFormat:@"%C;", quote];
        NSRange end = [text rangeOfString:terminator options:0 range:NSMakeRange(start, text.length - start)];
        NSUInteger stop = end.location;
        if (stop == NSNotFound) {
            stop = text.length;
            if (stop > start && [text characterAtIndex:stop - 1] == quote) stop--;
        }
        return [text substringWithRange:NSMakeRange(start, stop - start)];
    }
    NSRange semi = [text rangeOfString:@";" options:0 range:NSMakeRange(start, text.length - start)];
    NSUInteger stop = semi.location == NSNotFound ? text.length : semi.location;
    return [text substringWithRange:NSMakeRange(start, stop - start)];
}

@end
