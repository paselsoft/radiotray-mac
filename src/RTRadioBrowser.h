// Ricerca di stazioni nell'archivio pubblico e gratuito Radio Browser (www.radio-browser.info),
// lo stesso usato da molte app di radio via Internet. Nessuna chiave o registrazione.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTFoundStation : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;          // url_resolved se c'è, altrimenti url
@property (nonatomic, copy) NSString *country;      // codice ISO, per esempio "IT"
@property (nonatomic, copy) NSString *codec;        // "MP3", "AAC", "AAC+", "OGG"…
@property (nonatomic) NSInteger bitrate;            // kbps, 0 se sconosciuto
@property (nonatomic, copy) NSString *tags;
@property (nonatomic) NSInteger votes;
@property (nonatomic) BOOL hls;
@property (nonatomic, copy) NSString *favicon;      // logo della stazione (indirizzo), può essere vuoto
/// NO per i formati che macOS non sa riprodurre: WMA, e Ogg/Opus/FLAC se ffmpeg non è installato.
@property (nonatomic, readonly) BOOL playable;
/// Ogg/Opus/FLAC riproducibili con ffmpeg (di solito: ffmpeg è installato). Impostabile per i test.
+ (void)setFFmpegAvailable:(BOOL)available;
/// "MP3 128 kbps"
@property (nonatomic, readonly) NSString *formatDescription;
@end

typedef void (^RTSearchCompletion)(NSArray<RTFoundStation *> *_Nullable stations, NSString *_Nullable error);

@interface RTRadioBrowser : NSObject

/// Cerca per nome (e facoltativamente paese, codice ISO). Completamento sulla coda principale;
/// una nuova ricerca annulla la precedente. Le stazioni non riproducibili sono in fondo.
- (void)searchName:(NSString *)name country:(nullable NSString *)countryCode completion:(RTSearchCompletion)completion;
/// Cerca per genere ("jazz", "rock", "news"…), le più ascoltate per prime.
- (void)searchTag:(NSString *)tag country:(nullable NSString *)countryCode completion:(RTSearchCompletion)completion;
/// Le stazioni più ascoltate del paese (tutte se countryCode è vuoto).
- (void)topStationsInCountry:(nullable NSString *)countryCode completion:(RTSearchCompletion)completion;
- (void)cancel;

/// Segnala all'archivio che la stazione con questo indirizzo è stata ascoltata (il "clic" che
/// Radio Browser chiede alle app: serve a ordinare le stazioni per popolarità e a segnare quelle che
/// funzionano). Si cerca la stazione per indirizzo; se non è nell'archivio non si fa nulla.
/// Al massimo una volta al giorno per indirizzo.
+ (void)reportListeningToURL:(NSString *)url;

/// Estrae lo "stationuuid" del primo risultato (testabile).
+ (nullable NSString *)stationUUIDFromJSON:(nullable NSData *)data;

/// Nomi alternativi da provare quando la ricerca non trova nulla, nell'ordine:
/// sigle note ("Radio Monte Carlo Hits" → "RMC Hits"), nome senza "Radio", iniziali
/// ("Radio Dimensione Suono" → "RDS"). Mai il nome di partenza (testabile).
+ (NSArray<NSString *> *)alternativeNamesFor:(NSString *)name;

/// Decodifica la risposta JSON dell'archivio (testabile senza rete).
+ (nullable NSArray<RTFoundStation *> *)stationsFromJSON:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
