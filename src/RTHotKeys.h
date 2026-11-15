// Scorciatoie da tastiera valide in qualsiasi app (Carbon RegisterEventHotKey: su 10.13 non serve
// nessun permesso di accessibilità). Tutte con ⌃⌥ (Control + Option).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RTHotKey) {
    RTHotKeyTogglePlay = 1,   // ⌃⌥P
    RTHotKeyFavorite,         // ⌃⌥F
    RTHotKeyNextStation,      // ⌃⌥→
    RTHotKeyPreviousStation,  // ⌃⌥←
    RTHotKeyVolumeUp,         // ⌃⌥↑
    RTHotKeyVolumeDown,       // ⌃⌥↓
};

@interface RTHotKeys : NSObject
/// Registra le scorciatoie; il blocco viene chiamato sul thread principale.
/// Restituisce le descrizioni di quelle già usate da un'altra app (non registrate).
- (NSArray<NSString *> *)registerWithHandler:(void (^)(RTHotKey key))handler;
- (void)unregister;
/// Elenco leggibile: "⌃⌥P  Accendi / spegni"…
+ (NSArray<NSString *> *)descriptions;
@end

NS_ASSUME_NONNULL_END
