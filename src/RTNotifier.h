// Notifiche di sistema (NSUserNotificationCenter, disponibile su 10.13).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTNotifier : NSObject
+ (instancetype)shared;
/// Pulsante "★ Preferito" premuto in una notifica di brano: riceve i dati passati a notifyTrack….
@property (nonatomic, copy, nullable) void (^favoriteHandler)(NSDictionary<NSString *, NSString *> *track);

/// Sostituisce la notifica precedente, così il Centro notifiche non si riempie.
- (void)notifyTitle:(NSString *)title message:(nullable NSString *)message;
/// Notifica di cambio brano con il pulsante "★ Preferito" (visibile se le notifiche di RadioTray
/// sono di tipo "Avvisi", oppure passando sopra il banner con il puntatore).
- (void)notifyTrackTitle:(NSString *)title message:(nullable NSString *)message
                   track:(NSDictionary<NSString *, NSString *> *)track;
/// Come sopra, con la copertina dell'album a destra (image nil: nessuna); withButton NO = senza "★ Preferito".
- (void)notifyTrackTitle:(NSString *)title message:(nullable NSString *)message
                   track:(NSDictionary<NSString *, NSString *> *)track image:(nullable NSImage *)image withButton:(BOOL)withButton;
/// "Ascolta" premuto (o clic) in una notifica di notifyListenTitle…: riceve info.
@property (nonatomic, copy, nullable) void (^listenHandler)(NSDictionary<NSString *, NSString *> *info);
/// Notifica con il pulsante "Ascolta" (per esempio: un artista che aspettavi passa su un'altra radio).
- (void)notifyListenTitle:(NSString *)title message:(nullable NSString *)message info:(NSDictionary<NSString *, NSString *> *)info;
/// Notifica che apre un indirizzo quando ci si fa clic.
- (void)notifyTitle:(NSString *)title message:(nullable NSString *)message openURL:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END
