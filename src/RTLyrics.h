// Testi delle canzoni dall'archivio gratuito LRCLIB (lrclib.net): niente chiave né registrazione.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RTLyricsCompletion)(NSString *_Nullable lyrics, NSString *_Nullable problem);

@interface RTLyrics : NSObject
/// Completamento sulla coda principale: il testo, oppure il motivo per cui non c'è.
+ (void)lyricsForTitle:(NSString *)title artist:(NSString *)artist completion:(RTLyricsCompletion)completion;
/// Testo da una risposta di LRCLIB (un oggetto o un elenco); quello sincronizzato senza i tempi
/// se manca quello semplice; @"" per i brani strumentali (testabile).
+ (nullable NSString *)lyricsFromJSON:(nullable NSData *)data;
@end

NS_ASSUME_NONNULL_END
