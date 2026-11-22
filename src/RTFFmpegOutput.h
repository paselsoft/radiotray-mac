// Motore ffmpeg, la parte di sola logica (testabile senza audio): dove si trova ffmpeg, quando serve
// (Ogg, Opus, FLAC, che AVFoundation su 10.13 non riproduce), con quali argomenti lanciarlo e come
// leggere le sue righe su stderr (codec, bitrate, titolo del brano, nome della stazione, errori).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTFFmpegOutput : NSObject

/// Percorso di ffmpeg (/usr/local/bin/ffmpeg, o un'altra posizione abituale), nil se non è installato.
+ (nullable NSString *)ffmpegPath;
/// YES se l'indirizzo o il Content-Type indicano un formato che AVFoundation non sa riprodurre.
+ (BOOL)needsFFmpegForURL:(NSString *)url contentType:(nullable NSString *)contentType;
/// Argomenti di ffmpeg: audio PCM float32 little-endian, 44,1 kHz, stereo, su stdout.
+ (NSArray<NSString *> *)argumentsForURL:(NSString *)url;
/// "flac" → "FLAC", "aac (HE-AAC)" → "HE-AAC"…
+ (NSString *)displayNameForCodec:(NSString *)codec;

// Lettura di stderr, una riga alla volta (i valori trovati restano nelle proprietà).
/// Restituisce YES se la riga ha cambiato codec o bitrate.
- (BOOL)consumeLine:(NSString *)line;
/// Titolo completo ("Artista - Titolo") quando un blocco di metadati è finito; nil se non ce n'è uno nuovo.
- (nullable NSString *)takeTitle;
/// Nome della stazione dichiarato (icy-name), una volta sola; nil se non c'è.
- (nullable NSString *)takeStationName;
/// Chiude il blocco di metadati in corso (si chiama quando ffmpeg tace per un attimo).
- (void)flushMetadata;

@property (nonatomic, copy, readonly, nullable) NSString *codec;   // "FLAC", "Opus", "Vorbis", "MP3"…
@property (nonatomic, readonly) NSInteger bitrate;                 // kbps, 0 se sconosciuto
@property (nonatomic, copy, readonly, nullable) NSString *lastError;
@end

NS_ASSUME_NONNULL_END
