// Calcoli per la finestra Statistiche (solo Foundation, testabile).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTStats : NSObject
/// Le voci con il valore più alto, in ordine decrescente (a parità, per nome): [[nome, valore], …].
+ (NSArray<NSArray *> *)top:(NSDictionary<NSString *, NSNumber *> *)values limit:(NSUInteger)limit;
/// "45 min", "3 h 20 min", "12 h"
+ (NSString *)describeSeconds:(double)seconds;
/// Chiave per contare gli ascolti di un artista: senza maiuscole, accenti e spazi doppi.
+ (NSString *)artistKey:(NSString *)artist;
/// Barra di lunghezza proporzionale (al massimo width caratteri).
+ (NSString *)barFor:(double)value max:(double)max width:(NSUInteger)width;
@end

NS_ASSUME_NONNULL_END
