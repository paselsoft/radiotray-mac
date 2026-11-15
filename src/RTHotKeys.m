#import "RTHotKeys.h"
#import <Carbon/Carbon.h>

static const OSType RTHotKeySignature = 'RTnG';

typedef struct {
    RTHotKey key;
    UInt32 keyCode;
    const char *label;
} RTHotKeySpec;

static const RTHotKeySpec RTSpecs[] = {
    { RTHotKeyTogglePlay,      kVK_ANSI_P,     "⌃⌥P   Accendi / spegni la radio" },
    { RTHotKeyFavorite,        kVK_ANSI_F,     "⌃⌥F   Aggiungi il brano ai preferiti" },
    { RTHotKeyNextStation,     kVK_RightArrow, "⌃⌥→   Stazione successiva" },
    { RTHotKeyPreviousStation, kVK_LeftArrow,  "⌃⌥←   Stazione precedente" },
    { RTHotKeyVolumeUp,        kVK_UpArrow,    "⌃⌥↑   Alza il volume" },
    { RTHotKeyVolumeDown,      kVK_DownArrow,  "⌃⌥↓   Abbassa il volume" },
};
static const NSUInteger RTSpecCount = sizeof(RTSpecs) / sizeof(RTSpecs[0]);

@interface RTHotKeys ()
@property (nonatomic, copy, nullable) void (^handler)(RTHotKey key);
@end

@implementation RTHotKeys {
    EventHotKeyRef _refs[sizeof(RTSpecs) / sizeof(RTSpecs[0])];
    EventHandlerRef _eventHandler;
}

static OSStatus RTHotKeyCallback(EventHandlerCallRef next, EventRef event, void *userData)
{
    EventHotKeyID hotKeyID;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID) != noErr) {
        return eventNotHandledErr;
    }
    if (hotKeyID.signature != RTHotKeySignature) return eventNotHandledErr;
    RTHotKeys *self_ = (__bridge RTHotKeys *)userData;
    RTHotKey key = (RTHotKey)hotKeyID.id;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self_.handler) self_.handler(key);
    });
    return noErr;
}

+ (NSArray<NSString *> *)descriptions
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < RTSpecCount; i++) [out addObject:[NSString stringWithUTF8String:RTSpecs[i].label]];
    return out;
}

- (NSArray<NSString *> *)registerWithHandler:(void (^)(RTHotKey))handler
{
    [self unregister];
    self.handler = handler;
    EventTypeSpec type = { kEventClassKeyboard, kEventHotKeyPressed };
    InstallApplicationEventHandler(&RTHotKeyCallback, 1, &type, (__bridge void *)self, &_eventHandler);
    NSMutableArray *failed = [NSMutableArray array];
    for (NSUInteger i = 0; i < RTSpecCount; i++) {
        EventHotKeyID hotKeyID = { RTHotKeySignature, (UInt32)RTSpecs[i].key };
        OSStatus status = RegisterEventHotKey(RTSpecs[i].keyCode, controlKey | optionKey, hotKeyID,
                                              GetApplicationEventTarget(), 0, &_refs[i]);
        if (status != noErr) {
            _refs[i] = NULL;
            [failed addObject:[NSString stringWithUTF8String:RTSpecs[i].label]];
        }
    }
    return failed;
}

- (void)unregister
{
    for (NSUInteger i = 0; i < RTSpecCount; i++) {
        if (_refs[i]) UnregisterEventHotKey(_refs[i]);
        _refs[i] = NULL;
    }
    if (_eventHandler) {
        RemoveEventHandler(_eventHandler);
        _eventHandler = NULL;
    }
    self.handler = nil;
}

- (void)dealloc
{
    [self unregister];
}

@end
