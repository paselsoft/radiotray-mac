// Finestra "Brani preferiti": ricerca istantanea, filtro per stazione, ordinamento per colonna,
// elimina, copia, cerca sul web, esporta in CSV. Ogni modifica è salvata subito.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class RTFavoriteTracks;

@protocol RTFavoritesWindowDelegate <NSObject>
/// L'elenco è cambiato (per esempio dopo un'eliminazione) ed è già stato salvato.
- (void)favoritesWindowDidChangeTracks;
@end

@interface RTFavoritesWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<RTFavoritesWindowDelegate> delegate;
- (instancetype)initWithTracks:(RTFavoriteTracks *)tracks path:(NSString *)path;
- (void)showAndFocus;
/// Da chiamare quando un brano viene aggiunto dal menu.
- (void)reload;
@end

NS_ASSUME_NONNULL_END
