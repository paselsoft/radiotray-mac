// Finestra "In riproduzione": copertina grande, titolo, artista, stazione, formato,
// pulsanti ◀︎ ⏯ ▶︎ ★ e volume. Può restare sempre in primo piano.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RTNowPlayingDelegate <NSObject>
- (void)nowPlayingPrevious;
- (void)nowPlayingTogglePlay;
- (void)nowPlayingNext;
- (void)nowPlayingFavorite;
- (void)nowPlayingVolumeChanged:(NSInteger)volume;
- (void)nowPlayingFloatingChanged:(BOOL)floating;
- (void)nowPlayingAtLaunchChanged:(BOOL)atLaunch;
- (void)nowPlayingClosed;
@end

@interface RTNowPlayingWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<RTNowPlayingDelegate> delegate;
- (instancetype)initFloating:(BOOL)floating;
- (void)showWithoutActivating;
/// Stato della casella "Apri all'avvio".
- (void)setOpensAtLaunch:(BOOL)atLaunch;
- (void)updateTitle:(NSString *)title artist:(nullable NSString *)artist station:(nullable NSString *)station
            quality:(nullable NSString *)quality artwork:(nullable NSImage *)artwork playing:(BOOL)playing
             active:(BOOL)active favorite:(BOOL)favorite canFavorite:(BOOL)canFavorite
        hasPrevious:(BOOL)hasPrevious hasNext:(BOOL)hasNext volume:(NSInteger)volume;
@end

NS_ASSUME_NONNULL_END
