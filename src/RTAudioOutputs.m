#import "RTAudioOutputs.h"
#import <CoreAudio/CoreAudio.h>

@implementation RTAudioOutput
@end

static NSString *RTDeviceString(AudioDeviceID device, AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress addr = { selector, kAudioObjectPropertyScopeGlobal, 0 };
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(device, &addr, 0, NULL, &size, &value) != noErr || !value) return nil;
    return CFBridgingRelease(value);
}

static BOOL RTDeviceHasOutput(AudioDeviceID device)
{
    AudioObjectPropertyAddress addr = { kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput, 0 };
    UInt32 size = 0;
    return AudioObjectGetPropertyDataSize(device, &addr, 0, NULL, &size) == noErr && size > 0;
}

@implementation RTAudioOutputs

+ (NSArray<RTAudioOutput *> *)outputs
{
    AudioObjectPropertyAddress addr = { kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, 0 };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, NULL, &size) != noErr || size == 0) return @[];
    UInt32 count = size / sizeof(AudioDeviceID);
    AudioDeviceID *devices = calloc(count, sizeof(AudioDeviceID));
    if (!devices) return @[];
    NSMutableArray *out = [NSMutableArray array];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, devices) == noErr) {
        for (UInt32 i = 0; i < count; i++) {
            if (!RTDeviceHasOutput(devices[i])) continue;
            NSString *uid = RTDeviceString(devices[i], kAudioDevicePropertyDeviceUID);
            NSString *name = RTDeviceString(devices[i], kAudioObjectPropertyName);
            if (!uid.length) continue;
            RTAudioOutput *o = [RTAudioOutput new];
            o.uid = uid;
            o.name = name.length ? name : uid;
            [out addObject:o];
        }
    }
    free(devices);
    return out;
}

+ (NSString *)defaultOutputUID
{
    AudioObjectPropertyAddress addr = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, 0 };
    AudioDeviceID device = 0;
    UInt32 size = sizeof(device);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &device) != noErr || !device) return nil;
    return RTDeviceString(device, kAudioDevicePropertyDeviceUID);
}

@end
