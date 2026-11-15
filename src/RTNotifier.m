#import "RTNotifier.h"
#import <Cocoa/Cocoa.h>

// NSUserNotification è deprecata da macOS 11, ma è l'API giusta per 10.13
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSString *const kKindKey = @"kind";
static NSString *const kKindTrack = @"track";
static NSString *const kKindURL = @"url";

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

- (void)deliver:(NSUserNotification *)n
{
    NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
    [center removeAllDeliveredNotifications];
    n.soundName = nil;
    [center deliverNotification:n];
}

- (void)notifyTitle:(NSString *)title message:(NSString *)message
{
    NSUserNotification *n = [NSUserNotification new];
    n.title = title;
    n.informativeText = message;
    n.hasActionButton = NO;
    [self deliver:n];
}

- (void)notifyTrackTitle:(NSString *)title message:(NSString *)message track:(NSDictionary<NSString *, NSString *> *)track
{
    NSUserNotification *n = [NSUserNotification new];
    n.title = title;
    n.informativeText = message;
    n.hasActionButton = YES;
    n.actionButtonTitle = @"★ Preferito";
    n.otherButtonTitle = @"Chiudi";
    NSMutableDictionary *info = [track mutableCopy];
    info[kKindKey] = kKindTrack;
    n.userInfo = info;
    [self deliver:n];
}

- (void)notifyTitle:(NSString *)title message:(NSString *)message openURL:(NSURL *)url
{
    NSUserNotification *n = [NSUserNotification new];
    n.title = title;
    n.informativeText = message;
    n.hasActionButton = YES;
    n.actionButtonTitle = @"Apri";
    n.otherButtonTitle = @"Più tardi";
    n.userInfo = @{ kKindKey: kKindURL, @"url": url.absoluteString };
    [self deliver:n];
}

// mostrarla anche se l'app è "in primo piano" (un'app nella barra dei menu lo è spesso)
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    NSString *kind = info[kKindKey];
    if ([kind isEqualToString:kKindTrack]) {
        // solo il pulsante "★ Preferito": un clic sul resto della notifica non aggiunge nulla
        if (notification.activationType == NSUserNotificationActivationTypeActionButtonClicked && self.favoriteHandler) {
            NSMutableDictionary *track = [info mutableCopy];
            [track removeObjectForKey:kKindKey];
            self.favoriteHandler(track);
        }
    } else if ([kind isEqualToString:kKindURL]) {
        NSURL *url = [NSURL URLWithString:info[@"url"] ?: @""];
        if (url) [[NSWorkspace sharedWorkspace] openURL:url];
    }
    [center removeDeliveredNotification:notification];
}

@end

#pragma clang diagnostic pop
