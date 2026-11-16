#import "RTLyricsWindowController.h"
#import "RTLyrics.h"

static NSString *const kAttachedKey = @"lyrics-attached";
static NSString *const kSizeKey = @"lyrics-size";
static const CGFloat RTSnapDistance = 16;

@interface RTLyricsWindowController () <NSWindowDelegate>
@property (nonatomic) BOOL placing;
@property (nonatomic) BOOL attached;
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
    if ((self = [super initWithWindow:panel])) {
        _key = @"";
        panel.delegate = self;
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
        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kSizeKey];
        NSSize size = saved ? NSSizeFromString(saved) : NSZeroSize;
        if (size.width >= panel.minSize.width && size.height >= panel.minSize.height) {
            [panel setFrame:(NSRect){ panel.frame.origin, size } display:NO];
        }
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

#pragma mark - Finestre attaccate

- (void)attach
{
    NSWindow *anchor = self.anchorWindow;
    if (!anchor || self.attached) return;
    self.window.level = anchor.level;
    [anchor addChildWindow:self.window ordered:NSWindowAbove];
    self.attached = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAttachedKey];
}

- (void)detach
{
    if (!self.attached) return;
    [self.anchorWindow removeChildWindow:self.window];
    self.window.level = NSNormalWindowLevel;
    self.attached = NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kAttachedKey];
}

/// Se la finestra del testo è vicina a un bordo della finestra In riproduzione, la si accosta
/// esattamente e la si attacca; altrimenti la si stacca.
- (void)snapIfNear
{
    NSWindow *anchor = self.anchorWindow;
    if (!anchor.isVisible) {
        [self detach];
        return;
    }
    NSRect a = anchor.frame, l = self.window.frame;
    BOOL overlapX = NSMaxX(l) > NSMinX(a) + 20 && NSMinX(l) < NSMaxX(a) - 20;
    BOOL overlapY = NSMaxY(l) > NSMinY(a) + 20 && NSMinY(l) < NSMaxY(a) - 20;
    CGFloat alignTop = fabs(NSMaxY(l) - NSMaxY(a)) < 30 ? NSMaxY(a) - NSHeight(l) : NSMinY(l);
    NSPoint origin = l.origin;
    CGFloat width = NSWidth(l);
    BOOL near = NO;
    if (overlapX && fabs(NSMaxY(l) - NSMinY(a)) < RTSnapDistance) {         // sotto: larga come In riproduzione
        origin = NSMakePoint(NSMinX(a), NSMinY(a) - NSHeight(l)); width = NSWidth(a); near = YES;
    } else if (overlapX && fabs(NSMinY(l) - NSMaxY(a)) < RTSnapDistance) {  // sopra
        origin = NSMakePoint(NSMinX(a), NSMaxY(a)); width = NSWidth(a); near = YES;
    } else if (overlapY && fabs(NSMinX(l) - NSMaxX(a)) < RTSnapDistance) {  // a destra
        origin = NSMakePoint(NSMaxX(a), alignTop); near = YES;
    } else if (overlapY && fabs(NSMaxX(l) - NSMinX(a)) < RTSnapDistance) {  // a sinistra
        origin = NSMakePoint(NSMinX(a) - NSWidth(l), alignTop); near = YES;
    }
    if (!near) {
        [self detach];
        return;
    }
    if (!NSEqualPoints(origin, l.origin) || width != NSWidth(l)) {
        self.placing = YES;
        [self.window setFrame:NSMakeRect(origin.x, origin.y, width, NSHeight(l)) display:YES];
        self.placing = NO;
    }
    [self attach];
}

- (void)windowDidResize:(NSNotification *)notification
{
    if (self.placing) return;
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromSize(self.window.frame.size) forKey:kSizeKey];
}

- (void)windowDidMove:(NSNotification *)notification
{
    if (self.placing) return;
    [self snapIfNear];
}

- (void)windowWillClose:(NSNotification *)notification
{
    if (self.attached) {
        [self.anchorWindow removeChildWindow:self.window];
        self.window.level = NSNormalWindowLevel;
        self.attached = NO;   // la preferenza resta: alla prossima apertura si riattacca
    }
}

- (void)showTitle:(NSString *)title artist:(NSString *)artist
{
    [self load:title artist:artist];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL wantsAttached = [d objectForKey:kAttachedKey] ? [d boolForKey:kAttachedKey] : YES;
    if (!self.window.isVisible && wantsAttached && self.anchorWindow.isVisible) {
        // si apre attaccata sotto la finestra In riproduzione
        NSRect a = self.anchorWindow.frame;
        CGFloat h = NSHeight(self.window.frame);
        self.placing = YES;
        [self.window setFrame:NSMakeRect(NSMinX(a), NSMinY(a) - h, NSWidth(a), h) display:NO];
        self.placing = NO;
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self snapIfNear];
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
