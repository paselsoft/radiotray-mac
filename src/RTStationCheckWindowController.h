// Finestra "Verifica le stazioni": prova tutte le stazioni, mostra quelle che non rispondono e
// per ognuna propone un indirizzo nuovo trovato nell'archivio Radio Browser.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RTStationCheckDelegate <NSObject>
- (void)stationCheckPlayName:(NSString *)name url:(NSString *)url;
/// Il file delle stazioni è stato riscritto (indirizzo sostituito).
- (void)stationCheckDidSaveBookmarks;
@end

@interface RTStationCheckWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<RTStationCheckDelegate> delegate;
- (instancetype)initWithBookmarksPath:(NSString *)path;
/// Mostra la finestra e ricomincia la verifica.
- (void)showAndStart;
@end

NS_ASSUME_NONNULL_END
