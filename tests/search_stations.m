// Cerca stazioni nell'archivio Radio Browser con lo stesso codice della finestra "Cerca stazioni".
// Uso: build/search_stations IT "Radio Deejay" "Radio Capital" …   (paese "" = tutti)
#import <Foundation/Foundation.h>
#import "../src/RTRadioBrowser.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "uso: %s PAESE nome [nome…]\n", argv[0]);
            return 2;
        }
        NSString *country = [NSString stringWithUTF8String:argv[1]];
        RTRadioBrowser *browser = [RTRadioBrowser new];
        int failures = 0;
        for (int i = 2; i < argc; i++) {
            NSString *name = [NSString stringWithUTF8String:argv[i]];
            __block NSArray<RTFoundStation *> *found = nil;
            __block NSString *error = nil;
            __block BOOL done = NO;
            [browser searchName:name country:country completion:^(NSArray<RTFoundStation *> *stations, NSString *e) {
                found = stations;
                error = e;
                done = YES;
            }];
            NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:40];
            while (!done && [limit timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            if (!found) {
                printf("== %s: ERRORE %s\n", name.UTF8String, (error ?: @"nessuna risposta").UTF8String);
                failures++;
                continue;
            }
            printf("== %s: %lu risultati\n", name.UTF8String, (unsigned long)found.count);
            NSUInteger shown = 0;
            for (RTFoundStation *s in found) {
                if (shown++ >= 4) break;
                printf("   %s%s | %s | %s | voti %ld | %s | logo: %s\n", s.playable ? "" : "[non riproducibile] ", s.name.UTF8String,
                       s.country.UTF8String, s.formatDescription.UTF8String, (long)s.votes, s.url.UTF8String,
                       s.favicon.length ? s.favicon.UTF8String : "-");
            }
        }
        return failures ? 1 : 0;
    }
}
