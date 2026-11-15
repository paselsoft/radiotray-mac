// Diagnostica: stampa con l'ora ogni titolo ICY inviato da uno stream per N secondi.
// Uso: build/dump_icy SECONDI url [url…]
#import <Foundation/Foundation.h>
#import "../src/RTIcyMetadataReader.h"

@interface RTDump : NSObject <RTIcyMetadataReaderDelegate>
@property (nonatomic, copy) NSString *label;
@end
@implementation RTDump
- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStreamTitle:(NSString *)title
{
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm:ss";
    f.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Rome"];
    printf("%s [%s] %s\n", [f stringFromDate:[NSDate date]].UTF8String, self.label.UTF8String, title.UTF8String);
    fflush(stdout);
}
- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStationName:(NSString *)name
{
    printf("[%s] nome: %s\n", self.label.UTF8String, name.UTF8String);
}
- (void)metadataReader:(RTIcyMetadataReader *)reader didReadBitrate:(NSInteger)kbps contentType:(NSString *)ct
{
    printf("[%s] %ld kbps, %s\n", self.label.UTF8String, (long)kbps, ct.UTF8String ?: "?");
}
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 3) return 2;
        double seconds = atof(argv[1]);
        NSMutableArray *keep = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            RTDump *d = [RTDump new];
            d.label = [[NSString stringWithUTF8String:argv[i]] lastPathComponent];
            RTIcyMetadataReader *r = [RTIcyMetadataReader new];
            r.delegate = d;
            [r startWithURL:[NSString stringWithUTF8String:argv[i]]];
            [keep addObject:@[d, r]];
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
        for (NSArray *p in keep) {
            RTIcyMetadataReader *r = p[1];
            if (r.unsupported) printf("[%s] nessun metadato ICY\n", [p[0] label].UTF8String);
        }
    }
    return 0;
}
