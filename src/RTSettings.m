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
static NSString *const kMenuLogos = @"menu-logos";
static NSString *const kReportListening = @"report-listening";
static NSString *const kPreferHTTPS = @"prefer-https";
static NSString *const kPrograms = @"programs";
static NSString *const kDockIcon = @"dock-icon";
static NSString *const kWatchArtists = @"watch-artists";
static NSString *const kArtistPlays = @"artist-plays";
static NSString *const kArtistNames = @"artist-names";
static NSString *const kStatsSince = @"stats-since";
static NSString *const kStationVolumes = @"station-volumes-enabled";
static NSString *const kVolumeForStation = @"station-volumes";
static NSString *const kOutputDevice = @"output-device";
static NSString *const kAlarmEnabled = @"alarm-enabled";
static NSString *const kAlarmMinutes = @"alarm-minutes";
static NSString *const kAlarmDays = @"alarm-days";
static NSString *const kAlarmGroup = @"alarm-group";
static NSString *const kAlarmStation = @"alarm-station";
static NSString *const kAlarmFadeIn = @"alarm-fade-in";
static NSString *const kAlarmLastFired = @"alarm-last-fired";
static NSString *const kListening = @"listening-seconds";
static NSString *const kSwapped = @"swapped-title-artist-stations";
static NSString *const kIgnoredTitles = @"ignored-title-stations";
static NSString *const kNowPlayingVisible = @"now-playing-visible";
static NSString *const kNowPlayingFloating = @"now-playing-floating";
static NSString *const kNowPlayingAtLaunch = @"now-playing-at-launch";
static NSString *const kPauseOnLock = @"pause-on-lock";
static NSString *const kPauseOnHeadphones = @"pause-on-headphones";
static NSString *const kResumeAfterPause = @"resume-after-pause";
static NSString *const kICloudBackup = @"icloud-backup";
static NSString *const kLastBackup = @"last-backup";

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
            kMenuLogos: @YES,
            kReportListening: @YES,
            kPreferHTTPS: @YES,
            kDockIcon: @YES,
            kStationVolumes: @YES,
            kAlarmEnabled: @NO,
            kAlarmMinutes: @(7 * 60),
            kAlarmDays: @(0x1F),
            kAlarmFadeIn: @YES,
            kNowPlayingVisible: @NO,
            kNowPlayingFloating: @YES,
            kNowPlayingAtLaunch: @NO,
            kPauseOnLock: @YES,
            kPauseOnHeadphones: @YES,
            kResumeAfterPause: @YES,
            kICloudBackup: @YES,
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
- (NSArray<NSDictionary *> *)programs { return [self.d arrayForKey:kPrograms] ?: @[]; }
- (void)setPrograms:(NSArray<NSDictionary *> *)v { [self.d setObject:v ?: @[] forKey:kPrograms]; }
- (NSArray<NSString *> *)watchArtists { return [self.d stringArrayForKey:kWatchArtists] ?: @[]; }
- (void)setWatchArtists:(NSArray<NSString *> *)v { [self.d setObject:v ?: @[] forKey:kWatchArtists]; }
- (NSDictionary<NSString *, NSNumber *> *)artistPlays { return [self.d dictionaryForKey:kArtistPlays] ?: @{}; }
- (void)setArtistPlays:(NSDictionary<NSString *, NSNumber *> *)v { [self.d setObject:v ?: @{} forKey:kArtistPlays]; }
- (NSDictionary<NSString *, NSString *> *)artistNames { return [self.d dictionaryForKey:kArtistNames] ?: @{}; }
- (void)setArtistNames:(NSDictionary<NSString *, NSString *> *)v { [self.d setObject:v ?: @{} forKey:kArtistNames]; }
- (NSDate *)statsSince { return [self.d objectForKey:kStatsSince]; }
- (void)setStatsSince:(NSDate *)v { if (v) [self.d setObject:v forKey:kStatsSince]; else [self.d removeObjectForKey:kStatsSince]; }
- (BOOL)dockIcon { return [self.d boolForKey:kDockIcon]; }
- (void)setDockIcon:(BOOL)v { [self.d setBool:v forKey:kDockIcon]; }
- (BOOL)preferHTTPS { return [self.d boolForKey:kPreferHTTPS]; }
- (void)setPreferHTTPS:(BOOL)v { [self.d setBool:v forKey:kPreferHTTPS]; }
- (BOOL)stationVolumes { return [self.d boolForKey:kStationVolumes]; }
- (void)setStationVolumes:(BOOL)v { [self.d setBool:v forKey:kStationVolumes]; }
- (NSDictionary<NSString *, NSNumber *> *)volumeForStation { return [self.d dictionaryForKey:kVolumeForStation] ?: @{}; }
- (void)setVolumeForStation:(NSDictionary<NSString *, NSNumber *> *)v { [self.d setObject:v ?: @{} forKey:kVolumeForStation]; }
- (NSString *)outputDeviceUID { return [self.d stringForKey:kOutputDevice]; }
- (void)setOutputDeviceUID:(NSString *)v { if (v) [self.d setObject:v forKey:kOutputDevice]; else [self.d removeObjectForKey:kOutputDevice]; }
- (BOOL)reportListening { return [self.d boolForKey:kReportListening]; }
- (void)setReportListening:(BOOL)v { [self.d setBool:v forKey:kReportListening]; }
- (BOOL)menuLogos { return [self.d boolForKey:kMenuLogos]; }
- (void)setMenuLogos:(BOOL)v { [self.d setBool:v forKey:kMenuLogos]; }

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

- (BOOL)nowPlayingVisible { return [self.d boolForKey:kNowPlayingVisible]; }
- (void)setNowPlayingVisible:(BOOL)v { [self.d setBool:v forKey:kNowPlayingVisible]; }
- (BOOL)nowPlayingFloating { return [self.d boolForKey:kNowPlayingFloating]; }
- (void)setNowPlayingFloating:(BOOL)v { [self.d setBool:v forKey:kNowPlayingFloating]; }
- (BOOL)nowPlayingAtLaunch { return [self.d boolForKey:kNowPlayingAtLaunch]; }
- (void)setNowPlayingAtLaunch:(BOOL)v { [self.d setBool:v forKey:kNowPlayingAtLaunch]; }
- (BOOL)pauseOnLock { return [self.d boolForKey:kPauseOnLock]; }
- (void)setPauseOnLock:(BOOL)v { [self.d setBool:v forKey:kPauseOnLock]; }
- (BOOL)pauseOnHeadphones { return [self.d boolForKey:kPauseOnHeadphones]; }
- (void)setPauseOnHeadphones:(BOOL)v { [self.d setBool:v forKey:kPauseOnHeadphones]; }
- (BOOL)resumeAfterPause { return [self.d boolForKey:kResumeAfterPause]; }
- (void)setResumeAfterPause:(BOOL)v { [self.d setBool:v forKey:kResumeAfterPause]; }
- (BOOL)iCloudBackup { return [self.d boolForKey:kICloudBackup]; }
- (void)setICloudBackup:(BOOL)v { [self.d setBool:v forKey:kICloudBackup]; }
- (NSDate *)lastBackup { return [self.d objectForKey:kLastBackup]; }
- (void)setLastBackup:(NSDate *)v { [self.d setObject:v forKey:kLastBackup]; }

- (NSArray<NSString *> *)swappedStations
{
    NSArray *a = [self.d arrayForKey:kSwapped];
    return a ?: @[];
}
- (void)setSwappedStations:(NSArray<NSString *> *)v { [self.d setObject:v forKey:kSwapped]; }
- (NSArray<NSString *> *)ignoredTitleStations { return [self.d arrayForKey:kIgnoredTitles] ?: @[]; }
- (void)setIgnoredTitleStations:(NSArray<NSString *> *)v { [self.d setObject:v forKey:kIgnoredTitles]; }

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
