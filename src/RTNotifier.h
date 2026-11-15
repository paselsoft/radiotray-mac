// Notifiche di sistema (NSUserNotificationCenter, disponibile su 10.13).
#import <Foundation/Foundation.h>

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
/// Notifica che apre un indirizzo quando ci si fa clic.
- (void)notifyTitle:(NSString *)title message:(nullable NSString *)message openURL:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END
