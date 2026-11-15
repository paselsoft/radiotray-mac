// Logo della stazione, da mostrare quando non c'è la copertina del brano (jingle, parlato, radio
// che non mandano titoli). Prima l'immagine indicata nel file delle stazioni (campo "image",
// come in Radiotray-NG: percorso di un file o indirizzo web), poi quella dell'archivio Radio Browser
// cercata per indirizzo e poi per nome. Cache su disco.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RTLogoCompletion)(NSData *_Nullable imageData);

@interface RTStationLogo : NSObject
+ (instancetype)shared;
/// Completamento sulla coda principale; nil se non c'è nessun logo.
- (void)logoForStation:(NSString *)name url:(NSString *)url image:(nullable NSString *)image
            completion:(RTLogoCompletion)completion;
/// Dimentica il logo in cache di una stazione (per esempio dopo averne scelto uno nuovo).
- (void)forgetStationURL:(NSString *)url;

/// Logo migliore tra i risultati JSON dell'archivio: niente SVG (macOS 10.13 non li legge)
/// né pagine di Facebook (testabile).
+ (nullable NSString *)bestFaviconFromJSON:(NSData *)data;
/// Tutti i loghi utilizzabili, nell'ordine (testabile).
+ (NSArray<NSString *> *)faviconsFromJSON:(nullable NSData *)data;
@end

NS_ASSUME_NONNULL_END
