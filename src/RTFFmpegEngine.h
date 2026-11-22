// Motore ffmpeg: per Ogg Vorbis, Opus e FLAC, che AVFoundation su 10.13 non riproduce.
// Lancia ffmpeg (NSTask), che decodifica lo stream in PCM float32 stereo a 44,1 kHz su stdout;
// il PCM va ad AVAudioEngine + AVAudioPlayerNode con circa 1,5 s di buffer. Da stderr si leggono
// codec, bitrate e titoli. Fermandolo, il processo termina sempre e le pipe si chiudono.
#import <Foundation/Foundation.h>
#import "RTAudioEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface RTFFmpegEngine : NSObject <RTAudioEngine>
/// YES se ffmpeg è installato (altrimenti questo motore non si usa).
+ (BOOL)isAvailable;
@end

NS_ASSUME_NONNULL_END
