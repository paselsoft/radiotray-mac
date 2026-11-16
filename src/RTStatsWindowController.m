#import "RTStatsWindowController.h"
#import "RTStats.h"

@interface RTStatsWindowController ()
@property (nonatomic, strong) NSTextView *textView;
@end

@implementation RTStatsWindowController

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 560)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = @"Statistiche";
    window.minSize = NSMakeSize(420, 300);
    window.releasedWhenClosed = NO;
    window.frameAutosaveName = @"RadioTrayStats";
    if ((self = [super initWithWindow:window])) {
        NSView *content = window.contentView;
        CGFloat w = content.bounds.size.width, h = content.bounds.size.height;
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 52, w, h - 52)];
        scroll.hasVerticalScroller = YES;
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.textView = [[NSTextView alloc] initWithFrame:scroll.bounds];
        self.textView.editable = NO;
        self.textView.textContainerInset = NSMakeSize(14, 12);
        self.textView.autoresizingMask = NSViewWidthSizable;
        scroll.documentView = self.textView;
        [content addSubview:scroll];

        NSButton *reset = [NSButton buttonWithTitle:@"Azzera…" target:self action:@selector(reset:)];
        reset.bezelStyle = NSBezelStyleRounded;
        reset.frame = NSMakeRect(14, 10, 110, 32);
        reset.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
        [content addSubview:reset];
        [window center];
    }
    return self;
}

- (void)reset:(id)sender
{
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Azzerare le statistiche?";
    alert.informativeText = @"Si cancellano il tempo di ascolto delle stazioni (anche le \"Più ascoltate\" del menu) e il conteggio degli artisti. I brani preferiti restano.";
    [alert addButtonWithTitle:@"Azzera"];
    [alert addButtonWithTitle:@"Annulla"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertFirstButtonReturn && self.resetHandler) self.resetHandler();
    }];
}

- (void)showListening:(NSDictionary<NSString *, NSNumber *> *)seconds artists:(NSDictionary<NSString *, NSNumber *> *)artists
            favorites:(NSUInteger)favorites since:(NSDate *)since
{
    NSFont *body = [NSFont systemFontOfSize:13], *bold = [NSFont boldSystemFontOfSize:15];
    NSFont *mono = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    NSMutableParagraphStyle *tabs = [NSMutableParagraphStyle new];
    tabs.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:250 options:@{}],
                      [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:340 options:@{}]];
    NSMutableAttributedString *out = [NSMutableAttributedString new];
    void (^add)(NSString *, NSFont *, NSColor *) = ^(NSString *text, NSFont *font, NSColor *color) {
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: color ?: [NSColor labelColor], NSParagraphStyleAttributeName: tabs }]];
    };

    double total = 0;
    for (NSNumber *n in seconds.allValues) total += n.doubleValue;
    add(@"Tempo di ascolto\n", bold, nil);
    add([NSString stringWithFormat:@"%@ in tutto%@ · %lu brani preferiti\n\n", [RTStats describeSeconds:total],
         since ? [NSString stringWithFormat:@" (da %@)", [NSDateFormatter localizedStringFromDate:since dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterNoStyle]] : @"",
         (unsigned long)favorites], body, [NSColor secondaryLabelColor]);

    add(@"Stazioni\n", bold, nil);
    NSArray *stations = [RTStats top:seconds limit:15];
    double maxS = [[stations.firstObject lastObject] doubleValue];
    if (!stations.count) add(@"Ancora nessun dato: ascolta qualche stazione.\n", body, [NSColor secondaryLabelColor]);
    for (NSArray *e in stations) {
        NSString *name = [[e[0] componentsSeparatedByString:@"\n"] lastObject];
        if (name.length > 34) name = [[name substringToIndex:33] stringByAppendingString:@"…"];
        add([NSString stringWithFormat:@"%@\t%@\t", name, [RTStats describeSeconds:[e[1] doubleValue]]], body, nil);
        add([[RTStats barFor:[e[1] doubleValue] max:maxS width:14] stringByAppendingString:@"\n"], mono, [NSColor systemBlueColor]);
    }

    add(@"\nArtisti più sentiti\n", bold, nil);
    NSArray *top = [RTStats top:artists limit:20];
    double maxA = [[top.firstObject lastObject] doubleValue];
    if (!top.count) add(@"Ancora nessun dato: i brani si contano da questa versione in poi.\n", body, [NSColor secondaryLabelColor]);
    for (NSArray *e in top) {
        NSString *name = e[0];
        if (name.length > 34) name = [[name substringToIndex:33] stringByAppendingString:@"…"];
        NSInteger n = [e[1] integerValue];
        add([NSString stringWithFormat:@"%@\t%ld %@\t", name, (long)n, n == 1 ? @"brano" : @"brani"], body, nil);
        add([[RTStats barFor:n max:maxA width:14] stringByAppendingString:@"\n"], mono, [NSColor systemOrangeColor]);
    }
    [self.textView.textStorage setAttributedString:out];
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
}

@end
