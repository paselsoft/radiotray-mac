// Finestra "Statistiche": tempo di ascolto per stazione e artisti più sentiti.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTStatsWindowController : NSWindowController
@property (nonatomic, copy, nullable) void (^resetHandler)(void);
/// seconds: chiave "gruppo\nstazione" → secondi; artists: nome dell'artista → ascolti.
- (void)showListening:(NSDictionary<NSString *, NSNumber *> *)seconds artists:(NSDictionary<NSString *, NSNumber *> *)artists
            favorites:(NSUInteger)favorites since:(nullable NSDate *)since;
@end

NS_ASSUME_NONNULL_END
