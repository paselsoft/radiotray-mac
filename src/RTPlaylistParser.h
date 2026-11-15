// Riconosce e decodifica le playlist delle radio (PLS, M3U, ASX, XSPF) e decide quando un URL
// o un Content-Type è già uno stream audio. Solo Foundation: testabile senza interfaccia.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTPlaylistParser : NSObject

/// YES se l'URL va dato direttamente al lettore (estensione audio, oppure HLS .m3u8).
+ (BOOL)urlLooksDirect:(NSString *)url;

/// YES se il Content-Type indica audio vero e proprio (non una playlist).
+ (BOOL)contentTypeIsAudio:(nullable NSString *)contentType;

/// YES se il contenuto è una playlist HLS (va suonata direttamente, non decodificata).
+ (BOOL)isHLSContentType:(nullable NSString *)contentType data:(NSData *)data;

/// Decodifica una playlist. Restituisce gli URL trovati (relativi risolti rispetto a baseURL),
/// un array vuoto se il formato è riconosciuto ma senza voci, nil se non è una playlist.
+ (nullable NSArray<NSString *> *)urlsFromData:(NSData *)data
                                   contentType:(nullable NSString *)contentType
                                       baseURL:(nullable NSURL *)baseURL
                                    formatName:(NSString *_Nullable *_Nullable)formatName;

@end

NS_ASSUME_NONNULL_END
