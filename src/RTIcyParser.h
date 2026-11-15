// Estrae i metadati ICY (Shoutcast/Icecast) da uno stream richiesto con "Icy-MetaData: 1".
// Lo stream alterna `metaint` byte di audio e un blocco di metadati: 1 byte di lunghezza (×16)
// seguito da testo come "StreamTitle='Artista - Titolo';StreamUrl='';".
// Solo Foundation: testabile senza rete.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTIcyParser : NSObject

- (instancetype)initWithMetaInterval:(NSUInteger)metaInterval NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Elabora un blocco di dati; restituisce i titoli trovati (anche ripetuti) in ordine.
- (NSArray<NSString *> *)feed:(NSData *)data;

/// Nome della stazione dall'intestazione "icy-name": ripulito, con la codifica corretta
/// (UTF-8 letto come Latin-1); nil se vuoto o generico ("no name", "Unspecified"…).
+ (nullable NSString *)stationNameFromHeader:(nullable NSString *)value;

/// Valore di StreamTitle in un blocco di metadati (UTF-8 o Latin-1); nil se manca.
+ (nullable NSString *)streamTitleFromMetadata:(NSData *)metadata;

@end

NS_ASSUME_NONNULL_END
