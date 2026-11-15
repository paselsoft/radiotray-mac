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
/// NO per i formati che macOS non sa riprodurre (Ogg, Opus, FLAC, WMA).
@property (nonatomic, readonly) BOOL playable;
/// "MP3 128 kbps"
@property (nonatomic, readonly) NSString *formatDescription;
@end

typedef void (^RTSearchCompletion)(NSArray<RTFoundStation *> *_Nullable stations, NSString *_Nullable error);

@interface RTRadioBrowser : NSObject

/// Cerca per nome (e facoltativamente paese, codice ISO). Completamento sulla coda principale;
/// una nuova ricerca annulla la precedente. Le stazioni non riproducibili sono in fondo.
- (void)searchName:(NSString *)name country:(nullable NSString *)countryCode completion:(RTSearchCompletion)completion;
- (void)cancel;

/// Decodifica la risposta JSON dell'archivio (testabile senza rete).
+ (nullable NSArray<RTFoundStation *> *)stationsFromJSON:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
