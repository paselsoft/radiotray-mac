#import "RTTableCell.h"

@implementation RTTableCell

+ (instancetype)cellInTable:(NSTableView *)table identifier:(NSString *)identifier owner:(id)owner
{
    RTTableCell *cell = [table makeViewWithIdentifier:identifier owner:owner];
    if ([cell isKindOfClass:[RTTableCell class]]) return cell;
    cell = [[RTTableCell alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
    cell.identifier = identifier;
    NSTextField *field = [NSTextField labelWithString:@""];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:field];
    cell.textField = field;
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
        [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
        [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    cell.normalColor = [NSColor labelColor];
    return cell;
}

- (void)setNormalColor:(NSColor *)normalColor
{
    _normalColor = normalColor;
    [self applyColor];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    [self applyColor];
}

- (void)applyColor
{
    // 1 = NSBackgroundStyleDark su 10.13 (NSBackgroundStyleEmphasized dal 10.14): riga selezionata in blu
    BOOL selected = (NSInteger)self.backgroundStyle == 1;
    self.textField.textColor = selected ? [NSColor alternateSelectedControlTextColor] : (self.normalColor ?: [NSColor labelColor]);
}

@end
