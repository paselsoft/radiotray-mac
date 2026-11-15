// Notifiche di sistema (NSUserNotificationCenter, disponibile su 10.13).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTNotifier : NSObject
+ (instancetype)shared;
/// Sostituisce la notifica precedente, così il Centro notifiche non si riempie.
- (void)notifyTitle:(NSString *)title message:(nullable NSString *)message;
@end

NS_ASSUME_NONNULL_END
