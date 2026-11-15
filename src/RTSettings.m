#import "RTSettings.h"

static NSString *const kVolume = @"volume-level";
static NSString *const kLastGroup = @"last-station-group";
static NSString *const kLastStation = @"last-station";
static NSString *const kNotifications = @"notifications";
static NSString *const kVerbose = @"notification-verbose";
static NSString *const kSplitTitle = @"split-title";
static NSString *const kRootBottom = @"root-group-bottom-pos";
static NSString *const kSleepTimer = @"sleep-timer";
static NSString *const kLastURL = @"last-opened-url";
static NSString *const kHotKeys = @"hot-keys";
static NSString *const kCheckUpdates = @"check-for-updates";
static NSString *const kLastUpdateCheck = @"last-update-check";
static NSString *const kTitleInBar = @"tag-info-in-label";
static NSString *const kArtwork = @"artwork";
static NSString *const kAlarmEnabled = @"alarm-enabled";
static NSString *const kAlarmMinutes = @"alarm-minutes";
static NSString *const kAlarmDays = @"alarm-days";
static NSString *const kAlarmGroup = @"alarm-group";
static NSString *const kAlarmStation = @"alarm-station";
static NSString *const kAlarmFadeIn = @"alarm-fade-in";
static NSString *const kAlarmLastFired = @"alarm-last-fired";
static NSString *const kListening = @"listening-seconds";

@implementation RTSettings

+ (instancetype)shared
{
    static RTSettings *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [RTSettings new];
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            kVolume: @80,
            kNotifications: @YES,
            kVerbose: @NO,
            kSplitTitle: @YES,
            kRootBottom: @YES,
            kSleepTimer: @30,
            kHotKeys: @YES,
            kCheckUpdates: @YES,
            kTitleInBar: @NO,
            kArtwork: @YES,
            kAlarmEnabled: @NO,
            kAlarmMinutes: @(7 * 60),
            kAlarmDays: @(0x1F),
            kAlarmFadeIn: @YES,
        }];
    });
    return shared;
}

- (NSUserDefaults *)d
{
    return [NSUserDefaults standardUserDefaults];
}

- (NSInteger)volume { return MAX(0, MIN(100, [self.d integerForKey:kVolume])); }
- (void)setVolume:(NSInteger)volume { [self.d setInteger:MAX(0, MIN(100, volume)) forKey:kVolume]; }

- (NSString *)lastGroup { return [self.d stringForKey:kLastGroup]; }
- (void)setLastGroup:(NSString *)lastGroup { [self.d setObject:lastGroup forKey:kLastGroup]; }

- (NSString *)lastStation { return [self.d stringForKey:kLastStation]; }
- (void)setLastStation:(NSString *)lastStation { [self.d setObject:lastStation forKey:kLastStation]; }

- (BOOL)notifications { return [self.d boolForKey:kNotifications]; }
- (void)setNotifications:(BOOL)v { [self.d setBool:v forKey:kNotifications]; }

- (BOOL)verboseNotifications { return [self.d boolForKey:kVerbose]; }
- (void)setVerboseNotifications:(BOOL)v { [self.d setBool:v forKey:kVerbose]; }

- (BOOL)splitTitle { return [self.d boolForKey:kSplitTitle]; }
- (void)setSplitTitle:(BOOL)v { [self.d setBool:v forKey:kSplitTitle]; }

- (BOOL)rootGroupAtBottom { return [self.d boolForKey:kRootBottom]; }
- (void)setRootGroupAtBottom:(BOOL)v { [self.d setBool:v forKey:kRootBottom]; }

- (NSInteger)sleepTimerMinutes { return MAX(1, [self.d integerForKey:kSleepTimer]); }
- (void)setSleepTimerMinutes:(NSInteger)v { [self.d setInteger:MAX(1, v) forKey:kSleepTimer]; }

- (NSString *)lastOpenedURL { return [self.d stringForKey:kLastURL]; }
- (void)setLastOpenedURL:(NSString *)v { [self.d setObject:v forKey:kLastURL]; }

- (BOOL)hotKeys { return [self.d boolForKey:kHotKeys]; }
- (void)setHotKeys:(BOOL)v { [self.d setBool:v forKey:kHotKeys]; }

- (BOOL)checkForUpdates { return [self.d boolForKey:kCheckUpdates]; }
- (void)setCheckForUpdates:(BOOL)v { [self.d setBool:v forKey:kCheckUpdates]; }

- (NSDate *)lastUpdateCheck { return [self.d objectForKey:kLastUpdateCheck]; }
- (void)setLastUpdateCheck:(NSDate *)v { [self.d setObject:v forKey:kLastUpdateCheck]; }

- (BOOL)titleInMenuBar { return [self.d boolForKey:kTitleInBar]; }
- (void)setTitleInMenuBar:(BOOL)v { [self.d setBool:v forKey:kTitleInBar]; }
- (BOOL)artwork { return [self.d boolForKey:kArtwork]; }
- (void)setArtwork:(BOOL)v { [self.d setBool:v forKey:kArtwork]; }

- (BOOL)alarmEnabled { return [self.d boolForKey:kAlarmEnabled]; }
- (void)setAlarmEnabled:(BOOL)v { [self.d setBool:v forKey:kAlarmEnabled]; }
- (NSInteger)alarmMinutes { return MAX(0, MIN(24 * 60 - 1, [self.d integerForKey:kAlarmMinutes])); }
- (void)setAlarmMinutes:(NSInteger)v { [self.d setInteger:v forKey:kAlarmMinutes]; }
- (NSUInteger)alarmDays { return (NSUInteger)[self.d integerForKey:kAlarmDays] & 0x7F; }
- (void)setAlarmDays:(NSUInteger)v { [self.d setInteger:(NSInteger)(v & 0x7F) forKey:kAlarmDays]; }
- (NSString *)alarmGroup { return [self.d stringForKey:kAlarmGroup]; }
- (void)setAlarmGroup:(NSString *)v { [self.d setObject:v forKey:kAlarmGroup]; }
- (NSString *)alarmStation { return [self.d stringForKey:kAlarmStation]; }
- (void)setAlarmStation:(NSString *)v { [self.d setObject:v forKey:kAlarmStation]; }
- (BOOL)alarmFadeIn { return [self.d boolForKey:kAlarmFadeIn]; }
- (void)setAlarmFadeIn:(BOOL)v { [self.d setBool:v forKey:kAlarmFadeIn]; }
- (NSDate *)alarmLastFired { return [self.d objectForKey:kAlarmLastFired]; }
- (void)setAlarmLastFired:(NSDate *)v { [self.d setObject:v forKey:kAlarmLastFired]; }

- (NSDictionary<NSString *, NSNumber *> *)listeningSeconds
{
    NSDictionary *d = [self.d dictionaryForKey:kListening];
    return d ?: @{};
}
- (void)setListeningSeconds:(NSDictionary<NSString *, NSNumber *> *)v { [self.d setObject:v forKey:kListening]; }

- (NSString *)supportDirectory
{
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                     ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *dir = [base stringByAppendingPathComponent:@"RadioTray"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return dir;
}

- (NSString *)bookmarksPath
{
    return [[self supportDirectory] stringByAppendingPathComponent:@"bookmarks.json"];
}

@end
