// Motore AVPlayer: MP3, AAC, HLS (il comportamento di RadioTray fino alla 1.15, spostato qui da RTPlayer).
#import <Foundation/Foundation.h>
#import "RTAudioEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface RTAVPlayerEngine : NSObject <RTAudioEngine>
@end

NS_ASSUME_NONNULL_END
