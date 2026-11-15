// Avvisa quando lo schermo viene bloccato/sbloccato e quando l'audio passa dalle cuffie
// (o da altoparlanti esterni, USB, Bluetooth) agli altoparlanti interni del Mac.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RTAudioWatcherDelegate <NSObject>
- (void)audioWatcherScreenLocked;
- (void)audioWatcherScreenUnlocked;
/// Cuffie staccate: l'audio ora uscirebbe dagli altoparlanti interni.
- (void)audioWatcherHeadphonesRemoved;
/// Cuffie (o altro dispositivo) di nuovo collegate.
- (void)audioWatcherHeadphonesConnected;
@end

@interface RTAudioWatcher : NSObject
@property (nonatomic, weak, nullable) id<RTAudioWatcherDelegate> delegate;
- (void)start;
/// YES se l'audio esce ora dagli altoparlanti interni del Mac.
+ (BOOL)outputIsInternalSpeakers;
@end

NS_ASSUME_NONNULL_END
