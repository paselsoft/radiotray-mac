// Riproduzione con AVPlayer: prova gli URL della playlist uno dopo l'altro, segnala stato,
// titolo ICY ed errori. Volume 0–100.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RTPlayerState) {
    RTPlayerStateStopped,
    RTPlayerStateConnecting,
    RTPlayerStateBuffering,
    RTPlayerStatePlaying,
};

@class RTPlayer;

@protocol RTPlayerDelegate <NSObject>
- (void)player:(RTPlayer *)player didChangeState:(RTPlayerState)state;
- (void)player:(RTPlayer *)player didReceiveStreamTitle:(NSString *)title;
/// Copertina indicata dalla radio stessa per il titolo che segue (RDS); arriva prima del titolo.
- (void)player:(RTPlayer *)player didReceiveCoverURL:(NSString *)coverURL forStreamTitle:(NSString *)title;
/// Nome della stazione dichiarato dal server (icy-name).
- (void)player:(RTPlayer *)player didReceiveStationName:(NSString *)name;
/// Formato ("MP3", "AAC", "HE-AAC"…) e bitrate (kbps, 0 se sconosciuto) dello stream in ascolto.
- (void)player:(RTPlayer *)player didUpdateStreamFormat:(nullable NSString *)format bitrate:(NSInteger)kbps;
/// La connessione è caduta: nuovo tentativo n. attempt tra poco (stato "in connessione").
- (void)player:(RTPlayer *)player willReconnect:(NSUInteger)attempt error:(NSString *)error;
/// Chiamato quando nessun URL funziona: il lettore è già fermo.
- (void)player:(RTPlayer *)player didFailWithError:(NSString *)error;
@end

@interface RTPlayer : NSObject
@property (nonatomic, weak, nullable) id<RTPlayerDelegate> delegate;
@property (nonatomic, readonly) RTPlayerState state;
@property (nonatomic) NSInteger volume;   // 0–100
/// NO: non si apre la seconda connessione che legge i titoli (stazioni con titoli ignorati).
@property (nonatomic) BOOL readsTitles;
@property (nonatomic, copy, readonly, nullable) NSString *currentURL;
@property (nonatomic, copy, readonly, nullable) NSString *streamFormat;
@property (nonatomic, readonly) NSInteger streamBitrate;

/// "MP3" da un Content-Type ("audio/mpeg"), nil se sconosciuto (testabile).
+ (nullable NSString *)formatForContentType:(nullable NSString *)contentType;

- (void)playStreams:(NSArray<NSString *> *)urls;
- (void)stop;
/// Ricollega subito lo stream in riproduzione (per esempio al risveglio dallo stop).
- (void)reconnectNow;
/// Mostra lo stato "in connessione" mentre si risolve la playlist.
- (void)markConnecting;
@end

NS_ASSUME_NONNULL_END
