#import "RTLyricsWindowController.h"
#import "RTLyrics.h"

@interface RTLyricsWindowController ()
@property (nonatomic, strong) NSTextField *heading;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, copy) NSString *key;
@end

@implementation RTLyricsWindowController

- (instancetype)init
{
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 520)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
                                                  backing:NSBackingStoreBuffered defer:YES];
    panel.title = @"Testo";
    panel.minSize = NSMakeSize(300, 240);
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    panel.frameAutosaveName = @"RadioTrayLyrics";
    if ((self = [super initWithWindow:panel])) {
        _key = @"";
        NSView *content = panel.contentView;
        CGFloat w = content.bounds.size.width, h = content.bounds.size.height;
        self.heading = [NSTextField labelWithString:@""];
        self.heading.font = [NSFont boldSystemFontOfSize:13];
        self.heading.lineBreakMode = NSLineBreakByTruncatingTail;
        self.heading.frame = NSMakeRect(14, h - 30, w - 28, 18);
        self.heading.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [content addSubview:self.heading];

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 22, w, h - 40)];
        scroll.hasVerticalScroller = YES;
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.textView = [[NSTextView alloc] initWithFrame:scroll.bounds];
        self.textView.editable = NO;
        self.textView.textContainerInset = NSMakeSize(10, 8);
        self.textView.font = [NSFont systemFontOfSize:13];
        self.textView.autoresizingMask = NSViewWidthSizable;
        scroll.documentView = self.textView;
        [content addSubview:scroll];

        NSTextField *source = [NSTextField labelWithString:@"Testi da LRCLIB (lrclib.net)"];
        source.font = [NSFont systemFontOfSize:10];
        source.textColor = [NSColor secondaryLabelColor];
        source.frame = NSMakeRect(14, 4, w - 28, 14);
        source.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        [content addSubview:source];
        [panel center];
    }
    return self;
}

- (void)setText:(NSString *)text secondary:(BOOL)secondary
{
    self.textView.string = text;
    self.textView.textColor = secondary ? [NSColor secondaryLabelColor] : [NSColor labelColor];
    [self.textView scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)load:(NSString *)title artist:(NSString *)artist
{
    NSString *key = [NSString stringWithFormat:@"%@\n%@", artist, title];
    if ([key isEqualToString:self.key]) return;
    self.key = key;
    self.heading.stringValue = [NSString stringWithFormat:@"%@ – %@", title, artist];
    self.window.title = [@"Testo: " stringByAppendingString:title];
    [self setText:@"Ricerca del testo…" secondary:YES];
    __weak typeof(self) weakSelf = self;
    [RTLyrics lyricsForTitle:title artist:artist completion:^(NSString *lyrics, NSString *problem) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.key isEqualToString:key]) return;   // nel frattempo è cambiato brano
        if (lyrics.length) [strongSelf setText:lyrics secondary:NO];
        else if (lyrics) [strongSelf setText:@"Brano strumentale: niente testo." secondary:YES];
        else [strongSelf setText:problem ?: @"Testo non trovato." secondary:YES];
    }];
}

- (void)showTitle:(NSString *)title artist:(NSString *)artist
{
    [self load:title artist:artist];
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)trackChangedTitle:(NSString *)title artist:(NSString *)artist
{
    if (!self.window.isVisible) return;
    if (title.length && artist.length) {
        [self load:title artist:artist];
    } else {
        self.key = @"";
        self.heading.stringValue = @"";
        [self setText:@"In attesa del prossimo brano…" secondary:YES];
    }
}

@end
