#import "RTShows.h"

@implementation RTShows

static NSInteger RTMinutes(NSString *hhmm)
{
    NSArray *p = [[hhmm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                  componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":."]];
    if (p.count != 2) return -1;
    NSString *h = p[0], *m = p[1];
    NSCharacterSet *notDigit = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (!h.length || h.length > 2 || m.length != 2 || [h rangeOfCharacterFromSet:notDigit].location != NSNotFound ||
        [m rangeOfCharacterFromSet:notDigit].location != NSNotFound) return -1;
    NSInteger hours = h.integerValue, minutes = m.integerValue;
    if (minutes > 59 || hours > 24 || (hours == 24 && minutes > 0)) return -1;
    return hours * 60 + minutes;
}

+ (NSArray<NSArray<NSNumber *> *> *)slotsFromString:(NSString *)text
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *part in [text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",;"]]) {
        NSString *t = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!t.length) continue;
        NSArray *range = [t componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-–"]];
        if (range.count != 2) return nil;
        NSInteger a = RTMinutes(range[0]), b = RTMinutes(range[1]);
        if (a < 0 || b < 0 || a == b || a >= 1440) return nil;
        [out addObject:@[@(a), @(b)]];
    }
    return out.count ? out : nil;
}

/// lunedì = bit 0 … domenica = bit 6
static NSUInteger RTDayBit(NSDate *date, NSCalendar *cal)
{
    NSInteger weekday = [cal component:NSCalendarUnitWeekday fromDate:date];   // 1 = domenica
    return 1u << (NSUInteger)((weekday + 5) % 7);
}

+ (NSDictionary *)showOnAir:(NSArray<NSDictionary *> *)shows group:(NSString *)group station:(NSString *)station
                       date:(NSDate *)date calendar:(NSCalendar *)calendar
{
    NSDateComponents *c = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:date];
    NSInteger now = c.hour * 60 + c.minute;
    NSUInteger today = RTDayBit(date, calendar);
    NSUInteger yesterday = RTDayBit([date dateByAddingTimeInterval:-24 * 3600], calendar);
    for (NSDictionary *show in shows) {
        if (![show isKindOfClass:[NSDictionary class]]) continue;
        if (![show[@"group"] isEqual:group] || ![show[@"station"] isEqual:station]) continue;
        NSUInteger days = [show[@"days"] unsignedIntegerValue];
        NSArray *slots = [show[@"slots"] isKindOfClass:[NSString class]] ? [self slotsFromString:show[@"slots"]] : nil;
        for (NSArray<NSNumber *> *slot in slots) {
            NSInteger a = slot[0].integerValue, b = slot[1].integerValue;
            if (a < b) {
                if ((days & today) && now >= a && now < b) return show;
            } else {
                // passa la mezzanotte: la sera del giorno scelto e le prime ore del giorno dopo
                if (((days & today) && now >= a) || ((days & yesterday) && now < b)) return show;
            }
        }
    }
    return nil;
}

@end
