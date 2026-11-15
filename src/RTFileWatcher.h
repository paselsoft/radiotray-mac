// Avvisa quando un file cambia, anche se l'editor lo salva sostituendolo (come fa TextEdit).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTFileWatcher : NSObject
/// Il blocco viene chiamato sul thread principale, al massimo una volta ogni mezzo secondo,
/// e solo se il contenuto del file è davvero cambiato.
- (instancetype)initWithPath:(NSString *)path changeHandler:(void (^)(void))handler NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)start;
- (void)stop;
/// Da chiamare dopo aver letto il file di propria iniziativa, per non ricevere un avviso inutile.
- (void)rememberCurrentContents;
@end

NS_ASSUME_NONNULL_END
