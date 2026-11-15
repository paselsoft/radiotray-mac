#import "RTNotifier.h"
#import <Foundation/Foundation.h>

// NSUserNotification è deprecata da macOS 11, ma è l'API giusta per 10.13
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface RTNotifier () <NSUserNotificationCenterDelegate>
@end

@implementation RTNotifier

+ (instancetype)shared
{
    static RTNotifier *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [RTNotifier new];
        [NSUserNotificationCenter defaultUserNotificationCenter].delegate = shared;
    });
    return shared;
}

- (void)notifyTitle:(NSString *)title message:(NSString *)message
{
    NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
    [center removeAllDeliveredNotifications];
    NSUserNotification *n = [NSUserNotification new];
    n.title = title;
    n.informativeText = message;
    n.soundName = nil;
    [center deliverNotification:n];
}

// mostrarla anche se l'app è "in primo piano" (un'app nella barra dei menu lo è spesso)
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

@end

#pragma clang diagnostic pop
