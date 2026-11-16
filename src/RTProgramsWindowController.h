// Finestra "Programmi": più accensioni programmate oltre alla radiosveglia, per esempio
// "alle 18:00, lunedì–venerdì, Radio 24 per 30 minuti (giornale radio)".
// Ogni programma è un dizionario: name, enabled, minutes, days, group, station, duration (minuti, 0 = resta accesa),
// lastFired (data).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class RTBookmarks;

@protocol RTProgramsDelegate <NSObject>
- (RTBookmarks *)programsBookmarks;
- (void)programsDidChange:(NSArray<NSDictionary *> *)programs;
@end

@interface RTProgramsWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<RTProgramsDelegate> delegate;
- (void)showPrograms:(NSArray<NSDictionary *> *)programs;
/// "18:00 Lu–Ve · Radio 24 · 30 min" (testabile).
+ (NSString *)describeProgram:(NSDictionary *)program;
@end

NS_ASSUME_NONNULL_END
