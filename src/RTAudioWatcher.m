#import "RTAudioWatcher.h"
#import <CoreAudio/CoreAudio.h>

static AudioObjectPropertyAddress RTAddress(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress a = { selector, scope, kAudioObjectPropertyElementMaster };
    return a;
}

static AudioDeviceID RTDefaultOutputDevice(void)
{
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    AudioObjectPropertyAddress a = RTAddress(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &device);
    return device;
}

@interface RTAudioWatcher ()
@property (nonatomic) BOOL wasInternal;
@property (nonatomic) AudioDeviceID watchedDevice;
@end

@implementation RTAudioWatcher

+ (BOOL)outputIsInternalSpeakers
{
    AudioDeviceID device = RTDefaultOutputDevice();
    if (device == kAudioObjectUnknown) return NO;
    UInt32 transport = 0, size = sizeof(transport);
    AudioObjectPropertyAddress a = RTAddress(kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal);
    if (AudioObjectGetPropertyData(device, &a, 0, NULL, &size, &transport) != noErr) return NO;
    if (transport != kAudioDeviceTransportTypeBuiltIn) return NO;
    // uscita interna: altoparlanti ('ispk') o cuffie nel jack ('hdpn')
    UInt32 source = 0;
    size = sizeof(source);
    a = RTAddress(kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput);
    if (AudioObjectGetPropertyData(device, &a, 0, NULL, &size, &source) != noErr) return YES;
    return source != 'hdpn';
}

- (void)start
{
    NSDistributedNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
    [dnc addObserver:self selector:@selector(locked:) name:@"com.apple.screenIsLocked" object:nil];
    [dnc addObserver:self selector:@selector(unlocked:) name:@"com.apple.screenIsUnlocked" object:nil];

    self.wasInternal = [RTAudioWatcher outputIsInternalSpeakers];
    __weak typeof(self) weakSelf = self;
    AudioObjectPropertyAddress a = RTAddress(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal);
    AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &a, dispatch_get_main_queue(),
                                        ^(UInt32 n, const AudioObjectPropertyAddress *addresses) {
        [weakSelf watchDefaultDevice];
        [weakSelf outputChanged];
    });
    [self watchDefaultDevice];
}

/// Il jack delle cuffie cambia la "sorgente" del dispositivo interno, non il dispositivo: si osserva anche quella.
- (void)watchDefaultDevice
{
    AudioDeviceID device = RTDefaultOutputDevice();
    if (device == kAudioObjectUnknown || device == self.watchedDevice) return;
    self.watchedDevice = device;
    __weak typeof(self) weakSelf = self;
    AudioObjectPropertyAddress a = RTAddress(kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput);
    AudioObjectAddPropertyListenerBlock(device, &a, dispatch_get_main_queue(), ^(UInt32 n, const AudioObjectPropertyAddress *addresses) {
        [weakSelf outputChanged];
    });
}

- (void)outputChanged
{
    BOOL internal = [RTAudioWatcher outputIsInternalSpeakers];
    if (internal == self.wasInternal) return;
    self.wasInternal = internal;
    if (internal) {
        [self.delegate audioWatcherHeadphonesRemoved];
    } else {
        [self.delegate audioWatcherHeadphonesConnected];
    }
}

- (void)locked:(NSNotification *)note { [self.delegate audioWatcherScreenLocked]; }
- (void)unlocked:(NSNotification *)note { [self.delegate audioWatcherScreenUnlocked]; }

@end
