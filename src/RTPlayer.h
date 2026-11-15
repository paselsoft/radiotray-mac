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
/// Nome della stazione dichiarato dal server (icy-name).
- (void)player:(RTPlayer *)player didReceiveStationName:(NSString *)name;
/// La connessione è caduta: nuovo tentativo n. attempt tra poco (stato "in connessione").
- (void)player:(RTPlayer *)player willReconnect:(NSUInteger)attempt error:(NSString *)error;
/// Chiamato quando nessun URL funziona: il lettore è già fermo.
- (void)player:(RTPlayer *)player didFailWithError:(NSString *)error;
@end

@interface RTPlayer : NSObject
@property (nonatomic, weak, nullable) id<RTPlayerDelegate> delegate;
@property (nonatomic, readonly) RTPlayerState state;
@property (nonatomic) NSInteger volume;   // 0–100
@property (nonatomic, copy, readonly, nullable) NSString *currentURL;

- (void)playStreams:(NSArray<NSString *> *)urls;
- (void)stop;
/// Ricollega subito lo stream in riproduzione (per esempio al risveglio dallo stop).
- (void)reconnectNow;
/// Mostra lo stato "in connessione" mentre si risolve la playlist.
- (void)markConnecting;
@end

NS_ASSUME_NONNULL_END
