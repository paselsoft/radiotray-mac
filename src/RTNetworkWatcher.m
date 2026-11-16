#import "RTNetworkWatcher.h"
#import <SystemConfiguration/SystemConfiguration.h>

static NSString *const RTGlobalIPv4Key = @"State:/Network/Global/IPv4";

@interface RTNetworkWatcher ()
@property (nonatomic) SCDynamicStoreRef store;
@property (nonatomic, copy, nullable) NSString *lastSignature;   // interfaccia + indirizzo del router
@property (nonatomic) BOOL pending;
- (void)changed;
@end

static void RTStoreCallback(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info)
{
    RTNetworkWatcher *watcher = (__bridge RTNetworkWatcher *)info;
    [watcher changed];
}

@implementation RTNetworkWatcher

- (void)dealloc
{
    [self stop];
}

/// "en1 192.168.1.1" per la rete in uso, nil se il Mac non è collegato.
- (NSString *)currentSignature
{
    if (!self.store) return nil;
    CFPropertyListRef value = SCDynamicStoreCopyValue(self.store, (__bridge CFStringRef)RTGlobalIPv4Key);
    NSDictionary *d = CFBridgingRelease(value);
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    NSString *iface = d[@"PrimaryInterface"], *router = d[@"Router"];
    if (!iface.length) return nil;
    return [NSString stringWithFormat:@"%@ %@", iface, router ?: @""];
}

- (void)start
{
    if (self.store) return;
    SCDynamicStoreContext ctx = { 0, (__bridge void *)self, NULL, NULL, NULL };
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("RadioTray"), RTStoreCallback, &ctx);
    if (!store) return;
    NSArray *keys = @[RTGlobalIPv4Key];
    SCDynamicStoreSetNotificationKeys(store, (__bridge CFArrayRef)keys, NULL);
    SCDynamicStoreSetDispatchQueue(store, dispatch_get_main_queue());
    self.store = store;
    self.lastSignature = [self currentSignature];
}

- (void)stop
{
    if (!self.store) return;
    SCDynamicStoreSetDispatchQueue(self.store, NULL);
    CFRelease(self.store);
    self.store = NULL;
}

- (void)changed
{
    // più notifiche di fila mentre la rete si assesta: si guarda una volta sola, dopo 2 secondi
    if (self.pending) return;
    self.pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.pending = NO;
        NSString *now = [self currentSignature];
        NSString *before = self.lastSignature;
        self.lastSignature = now;
        if (!now || [now isEqualToString:before ?: @""]) return;   // rete sparita, o nessun cambio vero
        NSLog(@"RadioTray: rete cambiata (%@ → %@)", before ?: @"nessuna", now);
        [self.delegate networkWatcherDidChangeNetwork:self];
    });
}

@end
