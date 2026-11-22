// Il motore che suona uno stream: AVPlayer (MP3, AAC, HLS) oppure ffmpeg + AVAudioEngine (Ogg, Opus, FLAC).
// RTPlayer sceglie il motore per ogni indirizzo e tiene la logica comune (server di riserva,
// riconnessione, titoli ICY, stato). Tutti i messaggi al delegato arrivano sul thread principale.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AVMetadataItem;
@protocol RTAudioEngine;

@protocol RTAudioEngineDelegate <NSObject>
/// Suona (anche dopo un'interruzione del buffer).
- (void)audioEngineDidStartPlaying:(id<RTAudioEngine>)engine;
/// In attesa di dati: all'inizio o perché il buffer si è svuotato.
- (void)audioEngineIsWaiting:(id<RTAudioEngine>)engine;
/// Lo stream non suona più. formatProblem: il motore non sa leggere questo formato (si può provare l'altro).
- (void)audioEngine:(id<RTAudioEngine>)engine didFail:(NSString *)error formatProblem:(BOOL)formatProblem;
@optional
/// Metadati di AVPlayer (ID3/HLS, RDS…).
- (void)audioEngine:(id<RTAudioEngine>)engine didReceiveMetadataItems:(NSArray<AVMetadataItem *> *)items;
/// Titolo letto dallo stream ("Artista - Titolo" oppure StreamTitle).
- (void)audioEngine:(id<RTAudioEngine>)engine didReadTitle:(NSString *)title;
- (void)audioEngine:(id<RTAudioEngine>)engine didReadStationName:(NSString *)name;
/// Formato ("FLAC", "MP3"…) e bitrate (kbps, 0 se sconosciuto) riconosciuti dal motore.
- (void)audioEngine:(id<RTAudioEngine>)engine didReadFormat:(nullable NSString *)format bitrate:(NSInteger)kbps;
@end

@protocol RTAudioEngine <NSObject>
@property (nonatomic, weak, nullable) id<RTAudioEngineDelegate> delegate;
/// 0–1
@property (nonatomic) float volume;
/// Uscita audio (identificativo CoreAudio); nil = quella del Mac. Si può cambiare mentre suona.
@property (nonatomic, copy, nullable) NSString *outputDeviceUID;
/// "AVPlayer" o "ffmpeg", per il registro.
@property (nonatomic, readonly) NSString *engineName;
- (void)playURL:(NSString *)url;
/// Ferma tutto e libera le risorse (per ffmpeg: termina il processo e chiude le pipe).
- (void)stop;
@end

NS_ASSUME_NONNULL_END
