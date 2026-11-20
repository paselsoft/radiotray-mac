// Palinsesto personale: i programmi che segui, con stazione, giorni, orari e foto.
// Ogni programma è un dizionario: name, host ("con …"), group, station, days (RTAlarmDays),
// slots ("12:15-13:00, 23:10-24:00"), image (percorso del file).
// Solo Foundation: testabile.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTShows : NSObject
/// "12:15-13:00, 23:10-24:00" → [[735, 780], [1390, 1440]] (minuti dalla mezzanotte); nil se non valido.
+ (nullable NSArray<NSArray<NSNumber *> *> *)slotsFromString:(NSString *)text;
/// Il programma in onda su quella stazione in quel momento (gli orari che passano la mezzanotte valgono
/// anche nelle prime ore del giorno dopo); nil se nessuno.
+ (nullable NSDictionary *)showOnAir:(NSArray<NSDictionary *> *)shows group:(NSString *)group station:(NSString *)station
                                date:(NSDate *)date calendar:(NSCalendar *)calendar;
@end

NS_ASSUME_NONNULL_END
