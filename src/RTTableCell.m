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

+ (instancetype)imageCellInTable:(NSTableView *)table identifier:(NSString *)identifier owner:(id)owner
{
    RTTableCell *cell = [table makeViewWithIdentifier:identifier owner:owner];
    if ([cell isKindOfClass:[RTTableCell class]] && cell.imageView) return cell;
    cell = [[RTTableCell alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)];
    cell.identifier = identifier;
    NSImageView *imageView = [NSImageView new];
    imageView.imageScaling = NSImageScaleProportionallyDown;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:imageView];
    cell.imageView = imageView;
    NSTextField *field = [NSTextField labelWithString:@""];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:field];
    cell.textField = field;
    [NSLayoutConstraint activateConstraints:@[
        [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
        [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [imageView.widthAnchor constraintEqualToConstant:16],
        [imageView.heightAnchor constraintEqualToConstant:16],
        [field.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:5],
        [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
        [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    cell.normalColor = [NSColor labelColor];
    return cell;
}

+ (NSImage *)thumbnail:(NSImage *)image side:(CGFloat)side
{
    NSSize src = image.size;
    return [NSImage imageWithSize:NSMakeSize(side, side) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        CGFloat scale = MIN(side / MAX(src.width, 1), side / MAX(src.height, 1));
        NSSize s = NSMakeSize(src.width * scale, src.height * scale);
        NSRect r = NSMakeRect((side - s.width) / 2, (side - s.height) / 2, s.width, s.height);
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3] addClip];
        [image drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
        return YES;
    }];
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
