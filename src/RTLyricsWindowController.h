// Finestra del testo della canzone in ascolto (si aggiorna da sola quando cambia brano).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTLyricsWindowController : NSWindowController
- (void)showTitle:(NSString *)title artist:(NSString *)artist;
/// Brano cambiato: si aggiorna solo se la finestra è aperta.
- (void)trackChangedTitle:(nullable NSString *)title artist:(nullable NSString *)artist;
@end

NS_ASSUME_NONNULL_END
