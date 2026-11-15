// Radiosveglia: ora, giorni della settimana, stazione. Solo la logica (testabile senza interfaccia).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Giorni come maschera di bit: lunedì = 1 << 0 … domenica = 1 << 6.
typedef NS_OPTIONS(NSUInteger, RTAlarmDays) {
    RTAlarmMonday    = 1 << 0,
    RTAlarmTuesday   = 1 << 1,
    RTAlarmWednesday = 1 << 2,
    RTAlarmThursday  = 1 << 3,
    RTAlarmFriday    = 1 << 4,
    RTAlarmSaturday  = 1 << 5,
    RTAlarmSunday    = 1 << 6,
    RTAlarmWeekdays  = 0x1F,
    RTAlarmEveryDay  = 0x7F,
};

@interface RTAlarm : NSObject
/// La sveglia deve suonare adesso? Vero se oggi è un giorno scelto, sono passati da 0 a 10 minuti
/// dall'ora (minuti dalla mezzanotte) e non ha già suonato oggi. I 10 minuti coprono un Mac
/// che si risveglia poco dopo l'ora.
+ (BOOL)shouldFireAt:(NSDate *)now minutes:(NSInteger)minutes days:(RTAlarmDays)days
           lastFired:(nullable NSDate *)lastFired calendar:(NSCalendar *)calendar;
/// Prossima volta in cui suonerà, o nil se nessun giorno è scelto.
+ (nullable NSDate *)nextFireAfter:(NSDate *)now minutes:(NSInteger)minutes days:(RTAlarmDays)days
                          calendar:(NSCalendar *)calendar;
/// "Lu–Ve", "Tutti i giorni", "Sa, Do", "Lu, Me, Ve"…
+ (NSString *)describeDays:(RTAlarmDays)days;
/// "07:30"
+ (NSString *)describeMinutes:(NSInteger)minutes;
@end

NS_ASSUME_NONNULL_END
