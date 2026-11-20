// Finestra "Palinsesto personale": i programmi che segui, con orari e foto del conduttore,
// da mostrare al posto del logo quando vanno in onda.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class RTBookmarks;

@protocol RTShowsDelegate <NSObject>
- (RTBookmarks *)showsBookmarks;
- (void)showsDidChange:(NSArray<NSDictionary *> *)shows;
/// Cartella in cui copiare le foto dei programmi.
- (NSString *)showsImageFolder;
@end

@interface RTShowsWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<RTShowsDelegate> delegate;
- (void)showShows:(NSArray<NSDictionary *> *)shows;
@end

NS_ASSUME_NONNULL_END
