#import "RTStatusIcon.h"

static void RTDrawRadio(BOOL filled, CGFloat alpha)
{
    [[NSColor colorWithCalibratedWhite:0 alpha:alpha] set];

    // antenna
    NSBezierPath *antenna = [NSBezierPath bezierPath];
    antenna.lineWidth = 1.3;
    antenna.lineCapStyle = NSRoundLineCapStyle;
    [antenna moveToPoint:NSMakePoint(4.5, 12.0)];
    [antenna lineToPoint:NSMakePoint(14.0, 16.5)];
    [antenna stroke];

    // corpo
    NSRect bodyRect = NSMakeRect(1.5, 2.5, 15.0, 9.5);
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:bodyRect xRadius:2.0 yRadius:2.0];
    body.lineWidth = 1.3;
    NSBezierPath *speaker = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3.6, 4.4, 5.6, 5.6)];
    NSRect dial1 = NSMakeRect(10.8, 8.0, 3.8, 1.3);
    NSRect dial2 = NSMakeRect(10.8, 5.2, 3.8, 1.3);

    if (filled) {
        [body fill];
        // altoparlante e manopole "scavati" nel corpo
        NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
        NSCompositingOperation old = ctx.compositingOperation;
        ctx.compositingOperation = NSCompositingOperationClear;
        [speaker fill];
        NSRectFill(dial1);
        NSRectFill(dial2);
        ctx.compositingOperation = old;
        // centro dell'altoparlante
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.4, 6.2, 2.0, 2.0)] fill];
    } else {
        [body stroke];
        speaker.lineWidth = 1.1;
        [speaker stroke];
        NSRectFill(dial1);
        NSRectFill(dial2);
    }
}

NSImage *RTStatusIconImage(RTStatusIconStyle style)
{
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        switch (style) {
            case RTStatusIconOff:        RTDrawRadio(NO, 1.0); break;
            case RTStatusIconConnecting: RTDrawRadio(YES, 0.45); break;
            case RTStatusIconOn:         RTDrawRadio(YES, 1.0); break;
        }
        return YES;
    }];
    image.template = YES;
    return image;
}
