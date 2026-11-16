// Cella di tabella con un campo di testo che diventa bianco quando la riga è selezionata
// (su 10.13 un colore impostato a mano resterebbe scuro sul blu della selezione).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTTableCell : NSTableCellView
/// Colore del testo quando la riga non è selezionata.
@property (nonatomic, strong) NSColor *normalColor;
+ (instancetype)cellInTable:(NSTableView *)table identifier:(NSString *)identifier owner:(id)owner;
/// Come sopra, con un'immagine 16×16 prima del testo (imageView).
+ (instancetype)imageCellInTable:(NSTableView *)table identifier:(NSString *)identifier owner:(id)owner;
/// Logo rimpicciolito in un quadrato di lato side, senza deformarlo.
+ (NSImage *)thumbnail:(NSImage *)image side:(CGFloat)side;
@end

NS_ASSUME_NONNULL_END
