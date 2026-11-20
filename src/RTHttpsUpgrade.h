// Usa https quando la radio lo offre: per ogni stream http si prova, una volta e in sottofondo,
// lo stesso indirizzo in https. Se risponde con audio, dalla volta dopo si usa quello
// (con l'indirizzo http come riserva). Il risultato si ricorda per 30 giorni.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTHttpsUpgrade : NSObject
+ (instancetype)shared;
/// "https://host/percorso" per un indirizzo http senza porta (o con la porta 80); nil se non ha senso
/// provarlo (già https, porta diversa, indirizzo IP) (testabile).
+ (nullable NSString *)httpsCandidateForURL:(NSString *)url;
/// Si usa l'https solo se suona e, quando l'http manda i titoli (ICY), li manda anche lui (testabile).
+ (BOOL)acceptHTTPSAudio:(BOOL)httpsAudio httpsTitles:(BOOL)httpsTitles httpTitles:(BOOL)httpTitles;
/// Gli indirizzi con la versione https davanti a quelli http per cui è già nota e funzionante.
- (NSArray<NSString *> *)upgradedURLs:(NSArray<NSString *> *)urls;
/// Prova in sottofondo la versione https degli indirizzi http non ancora provati (al massimo 3).
- (void)probeURLs:(NSArray<NSString *> *)urls;
@end

NS_ASSUME_NONNULL_END
