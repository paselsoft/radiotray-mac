// Impostazioni salvate in NSUserDefaults (equivalente di radiotray-ng.json).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTSettings : NSObject
+ (instancetype)shared;
@property (nonatomic) NSInteger volume;                       // 0–100, predefinito 80
@property (nonatomic, copy, nullable) NSString *lastGroup;
@property (nonatomic, copy, nullable) NSString *lastStation;
@property (nonatomic) BOOL notifications;                     // predefinito YES
@property (nonatomic) BOOL verboseNotifications;              // predefinito NO
@property (nonatomic) BOOL splitTitle;                        // predefinito YES
@property (nonatomic) BOOL rootGroupAtBottom;                 // predefinito YES
@property (nonatomic) NSInteger sleepTimerMinutes;            // predefinito 30
@property (nonatomic, copy, nullable) NSString *lastOpenedURL; // ultimo indirizzo di "Apri URL…"
@property (nonatomic) BOOL hotKeys;                           // scorciatoie ⌃⌥, predefinito YES
@property (nonatomic) BOOL checkForUpdates;                   // predefinito YES
@property (nonatomic, strong, nullable) NSDate *lastUpdateCheck;
@property (nonatomic) BOOL titleInMenuBar;                    // "Artista – Titolo" accanto all'icona, predefinito NO
@property (nonatomic) BOOL artwork;                           // copertine degli album, predefinito YES

// radiosveglia
@property (nonatomic) BOOL alarmEnabled;
@property (nonatomic) NSInteger alarmMinutes;                 // minuti dalla mezzanotte, predefinito 7:00
@property (nonatomic) NSUInteger alarmDays;                   // RTAlarmDays, predefinito lunedì–venerdì
@property (nonatomic, copy, nullable) NSString *alarmGroup;
@property (nonatomic, copy, nullable) NSString *alarmStation;
@property (nonatomic) BOOL alarmFadeIn;                       // volume crescente, predefinito YES
@property (nonatomic, strong, nullable) NSDate *alarmLastFired;

// finestra "In riproduzione"
@property (nonatomic) BOOL nowPlayingVisible;                 // predefinito NO
@property (nonatomic) BOOL nowPlayingFloating;                // sempre in primo piano, predefinito YES
// pausa automatica
@property (nonatomic) BOOL pauseOnLock;                       // predefinito YES
@property (nonatomic) BOOL pauseOnHeadphones;                 // predefinito YES
@property (nonatomic) BOOL resumeAfterPause;                  // predefinito YES
// backup
@property (nonatomic) BOOL iCloudBackup;                      // copia giornaliera in iCloud Drive, predefinito YES
@property (nonatomic, strong, nullable) NSDate *lastBackup;

/// Stazioni che scrivono "Titolo - Artista" al contrario (chiave come per il tempo di ascolto).
@property (nonatomic, copy) NSArray<NSString *> *swappedStations;
/// Stazioni di cui ignorare i titoli (sbagliati o vecchi): si mostra il logo.
@property (nonatomic, copy) NSArray<NSString *> *ignoredTitleStations;

/// Secondi di ascolto per stazione (chiave "gruppo\nstazione").
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *listeningSeconds;

/// ~/Library/Application Support/RadioTray (creata se manca)
- (NSString *)supportDirectory;
- (NSString *)bookmarksPath;
@end

NS_ASSUME_NONNULL_END
