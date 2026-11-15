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

/// ~/Library/Application Support/RadioTray (creata se manca)
- (NSString *)supportDirectory;
- (NSString *)bookmarksPath;
@end

NS_ASSUME_NONNULL_END
