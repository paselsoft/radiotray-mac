// Titoli per le radio che non li mandano nello stream ma li pubblicano sul loro sito:
// Radio Deejay, Radio Capital e m2o (brano in onda con copertina) e le radio Rai (programma in onda).
// Gli indirizzi dei siti non sono ufficiali: se cambiano, semplicemente non arriva nulla.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RTOnAirDelegate <NSObject>
/// Brano in onda (artista può essere vuoto se il sito non lo distingue).
- (void)onAirSong:(NSString *)title artist:(NSString *)artist cover:(nullable NSString *)cover;
/// Programma in onda (nil: nessun programma, oppure va in onda un brano).
- (void)onAirProgram:(nullable NSString *)program;
@end

@interface RTOnAir : NSObject
@property (nonatomic, weak, nullable) id<RTOnAirDelegate> delegate;
/// "gedi:https://www.deejay.it", "rai:rai-radio-2"… per gli indirizzi della stazione; nil se non si sa (testabile).
+ (nullable NSString *)sourceForURLs:(NSArray<NSString *> *)urls;
- (void)startWithSource:(NSString *)source;
- (void)stop;

/// Pagina ufficiale del palinsesto della radio (si apre nel browser), per l'indirizzo della stazione;
/// nil se non la si conosce (testabile).
+ (nullable NSURL *)scheduleURLForStationURL:(NSString *)url name:(nullable NSString *)name;
/// {"title", "artist", "cover"} dal JSON "onair" dei siti GEDI; senza "artist" se è un programma (testabile).
+ (nullable NSDictionary<NSString *, NSString *> *)songFromGediJSON:(nullable NSData *)data;
/// Titolo del programma Rai in onda in quel momento, dal palinsesto del giorno (testabile).
+ (nullable NSString *)programFromRaiJSON:(nullable NSData *)data atDate:(NSDate *)date;
@end

NS_ASSUME_NONNULL_END
