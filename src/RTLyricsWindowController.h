// Finestra del testo della canzone in ascolto (si aggiorna da sola quando cambia brano).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTLyricsWindowController : NSWindowController
/// Finestra a cui la finestra del testo si "attacca" quando le si avvicina (In riproduzione):
/// da attaccate si spostano insieme; trascinando via il testo si staccano.
@property (nonatomic, weak, nullable) NSWindow *anchorWindow;
- (void)showTitle:(NSString *)title artist:(NSString *)artist;
/// Brano cambiato: si aggiorna solo se la finestra è aperta.
- (void)trackChangedTitle:(nullable NSString *)title artist:(nullable NSString *)artist;
@end

NS_ASSUME_NONNULL_END
