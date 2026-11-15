// Titolo e artista del brano a partire dal metadato ICY "StreamTitle"
// (come Radiotray-NG: divisione al primo " - ", estrazione di text="..." di iHeartRadio).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTTrackInfo : NSObject
@property (nonatomic, copy, readonly) NSString *title;    // vuoto se non c'è
@property (nonatomic, copy, readonly) NSString *artist;   // vuoto se non c'è

+ (instancetype)infoWithStreamTitle:(nullable NSString *)streamTitle split:(BOOL)split;
+ (instancetype)infoWithTitle:(nullable NSString *)title artist:(nullable NSString *)artist;
- (BOOL)isEmpty;
/// Lo stesso brano con titolo e artista scambiati (per le radio che scrivono "Titolo - Artista").
- (RTTrackInfo *)swapped;
/// YES se il "brano" è solo il nome o lo slogan della stazione ("Radio 105", "RadioFreccia",
/// "Radio Kiss Kiss - Play everywhere!"): durante jingle e pubblicità molte radio mandano questo.
- (BOOL)isFillerForStation:(nullable NSString *)station;

/// Titoli Mediaset ("…~DURATA~INIZIO~…") con l'ora d'inizio e la durata: YES se il brano è finito
/// da più di 10 minuti (alcuni canali web restano bloccati per giorni su un brano vecchio).
+ (BOOL)isStaleStreamTitle:(nullable NSString *)streamTitle now:(NSDate *)now;
- (BOOL)isEqualToInfo:(nullable RTTrackInfo *)other;
/// "Titolo\nArtista" (o solo il titolo): per gli appunti.
- (NSString *)clipboardText;
@end

/// Accorcia un testo a max caratteri aggiungendo "…".
NSString *RTTruncate(NSString *text, NSUInteger max);

NS_ASSUME_NONNULL_END
