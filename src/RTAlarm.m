#import "RTAlarm.h"

static const NSInteger RTAlarmGraceMinutes = 10;

@implementation RTAlarm

/// Bit del giorno della data (NSCalendar: domenica = 1 … sabato = 7).
+ (RTAlarmDays)dayBitFor:(NSDate *)date calendar:(NSCalendar *)calendar
{
    NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:date];
    NSInteger index = (weekday + 5) % 7;   // lunedì = 0 … domenica = 6
    return (RTAlarmDays)(1u << index);
}

+ (BOOL)shouldFireAt:(NSDate *)now minutes:(NSInteger)minutes days:(RTAlarmDays)days
           lastFired:(NSDate *)lastFired calendar:(NSCalendar *)calendar
{
    if (!(days & [self dayBitFor:now calendar:calendar])) return NO;
    if (lastFired && [calendar isDate:lastFired inSameDayAsDate:now]) return NO;
    NSDateComponents *c = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:now];
    NSInteger nowMinutes = c.hour * 60 + c.minute;
    NSInteger late = nowMinutes - minutes;
    return late >= 0 && late <= RTAlarmGraceMinutes;
}

+ (NSDate *)nextFireAfter:(NSDate *)now minutes:(NSInteger)minutes days:(RTAlarmDays)days calendar:(NSCalendar *)calendar
{
    if ((days & RTAlarmEveryDay) == 0) return nil;
    NSDate *startOfToday = [calendar startOfDayForDate:now];
    for (NSInteger offset = 0; offset <= 7; offset++) {
        NSDate *day = [calendar dateByAddingUnit:NSCalendarUnitDay value:offset toDate:startOfToday options:0];
        if (!(days & [self dayBitFor:day calendar:calendar])) continue;
        NSDate *fire = [calendar dateBySettingHour:minutes / 60 minute:minutes % 60 second:0 ofDate:day options:0];
        if ([fire compare:now] == NSOrderedDescending) return fire;
    }
    return nil;
}

+ (NSString *)describeDays:(RTAlarmDays)days
{
    days &= RTAlarmEveryDay;
    if (days == RTAlarmEveryDay) return @"Tutti i giorni";
    if (days == RTAlarmWeekdays) return @"Lu–Ve";
    if (days == (RTAlarmSaturday | RTAlarmSunday)) return @"Sa, Do";
    if (days == 0) return @"Nessun giorno";
    NSArray *names = @[@"Lu", @"Ma", @"Me", @"Gi", @"Ve", @"Sa", @"Do"];
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < 7; i++) if (days & (1u << i)) [out addObject:names[i]];
    return [out componentsJoinedByString:@", "];
}

+ (NSString *)describeMinutes:(NSInteger)minutes
{
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(minutes / 60), (long)(minutes % 60)];
}

@end
