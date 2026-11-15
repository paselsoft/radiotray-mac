// Copertine degli album dal catalogo pubblico di Apple (iTunes Search API: gratuita, senza chiave).
// Si accetta un risultato solo se l'artista corrisponde, per evitare copertine sbagliate.
// Cache in memoria e su disco (~/Library/Caches/io.github.paselsoft.radiotray-mac/copertine).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RTArtworkCompletion)(NSData *_Nullable imageData);

@interface RTArtwork : NSObject
+ (instancetype)shared;
/// Dati dell'immagine (JPEG) o nil se non trovata; completamento sulla coda principale.
- (void)artworkForTitle:(NSString *)title artist:(NSString *)artist completion:(RTArtworkCompletion)completion;
/// Solo dalla cache (memoria o disco), senza rete.
- (nullable NSData *)cachedArtworkForTitle:(NSString *)title artist:(NSString *)artist;

/// Indirizzo della copertina (600×600) scelto tra i risultati JSON, o nil (testabile).
+ (nullable NSString *)artworkURLFromJSON:(NSData *)data title:(NSString *)title artist:(NSString *)artist;
/// Testo semplificato per i confronti: minuscolo, senza accenti, solo lettere e cifre (testabile).
+ (NSString *)normalized:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
