// Prova se una stazione risponde: risolve la playlist come l'app e controlla che il primo stream
// risponda con audio (si legge solo l'intestazione della risposta, poi si chiude).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RTCheckCompletion)(BOOL ok, NSString *detail);

@interface RTStationChecker : NSObject
/// Completamento sulla coda principale. detail: "MP3 · 128 kbps", "HTTP 404", "non risponde"…
- (void)checkURL:(NSString *)url direct:(BOOL)direct completion:(RTCheckCompletion)completion;
- (void)cancel;
/// La risposta indica uno stream audio funzionante? (testabile)
+ (BOOL)isAudioResponseStatus:(NSInteger)status contentType:(nullable NSString *)contentType;
@end

NS_ASSUME_NONNULL_END
