// Trasforma l'URL di una stazione in uno o più URL di stream da dare al lettore:
// scarica al massimo 4 KB, guarda Content-Type e contenuto, decodifica la playlist.
// Se non riconosce nulla, considera l'URL stesso uno stream (come Radiotray-NG).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RTResolveCompletion)(NSArray<NSString *> *_Nullable streams, NSString *_Nullable error);

@interface RTStreamResolver : NSObject

/// Il completamento arriva sulla coda principale. Una nuova richiesta annulla la precedente.
- (void)resolve:(NSString *)url direct:(BOOL)direct completion:(RTResolveCompletion)completion;
- (void)cancel;

/// Descrizione di come è stato interpretato l'ultimo URL (per il registro).
@property (nonatomic, copy, readonly, nullable) NSString *lastDecision;

@end

NS_ASSUME_NONNULL_END
