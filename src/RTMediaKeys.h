// Tasti multimediali e "In riproduzione" di sistema (MediaPlayer, macOS 10.12.2+).
// Su 10.13 i tasti F7–F9 arrivano all'app che ha pubblicato per ultima le informazioni
// "In riproduzione"; in alcuni casi il sistema continua ad aprire iTunes.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RTMediaKeysDelegate <NSObject>
- (void)mediaKeysTogglePlay;
- (void)mediaKeysPlay;
- (void)mediaKeysPause;
- (void)mediaKeysNext;
- (void)mediaKeysPrevious;
@end

@interface RTMediaKeys : NSObject
@property (nonatomic, weak, nullable) id<RTMediaKeysDelegate> delegate;
- (void)start;
/// Aggiorna le informazioni "In riproduzione" (titolo, artista, stazione).
- (void)updateWithStation:(nullable NSString *)station title:(nullable NSString *)title
                   artist:(nullable NSString *)artist playing:(BOOL)playing;
@end

NS_ASSUME_NONNULL_END
