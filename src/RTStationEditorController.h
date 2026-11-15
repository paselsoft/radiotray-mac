// Finestra "Stazioni": modifica di gruppi e stazioni senza aprire il JSON.
// Ogni modifica viene salvata subito in bookmarks.json.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RTStationEditorDelegate <NSObject>
/// Il file è stato appena riscritto dall'editor: aggiornare il menu (senza notifiche).
- (void)stationEditorDidSaveBookmarks;
- (void)stationEditorPlayStation:(NSString *)name group:(NSString *)group;
- (void)stationEditorOpenJSON;
@end

@interface RTStationEditorController : NSWindowController
@property (nonatomic, weak, nullable) id<RTStationEditorDelegate> delegate;
- (instancetype)initWithBookmarksPath:(NSString *)path;
- (void)showAndFocus;
/// Rilegge il file (per esempio dopo una modifica fatta altrove).
- (void)reloadFromDisk;
@end

NS_ASSUME_NONNULL_END
