// Storico degli ascolti su ListenBrainz (listenbrainz.org): "in ascolto ora" quando inizia un brano,
// e l'ascolto registrato quando il brano finisce dopo almeno un minuto. Gli ascolti che non si possono
// mandare (rete assente) restano in coda e partono alla volta dopo.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RTTokenCheck)(NSString *_Nullable userName, NSString *_Nullable error);

@interface RTScrobbler : NSObject
+ (instancetype)shared;
/// Nome utente ListenBrainz collegato, nil se non collegato.
@property (nonatomic, copy, readonly, nullable) NSString *userName;
@property (nonatomic, readonly) BOOL linked;

/// Controlla il token sul sito e, se valido, lo salva nel portachiavi.
- (void)linkWithToken:(NSString *)token completion:(RTTokenCheck)completion;
- (void)unlink;

/// È iniziato un brano (artista e titolo riconosciuti).
- (void)trackStarted:(NSString *)title artist:(NSString *)artist station:(nullable NSString *)station;
/// Il brano in corso aveva titolo e artista scambiati: si corregge senza ricominciare.
- (void)correctCurrentTitle:(NSString *)title artist:(NSString *)artist;
/// Radio spenta o stazione cambiata: il brano in corso finisce qui.
- (void)stop;

/// Il corpo JSON di un invio a ListenBrainz (testabile).
+ (NSDictionary *)payloadWithType:(NSString *)type listens:(NSArray<NSDictionary *> *)listens version:(NSString *)version;
/// Secondi minimi di ascolto perché un brano conti.
+ (NSTimeInterval)minimumListen;
@end

NS_ASSUME_NONNULL_END
