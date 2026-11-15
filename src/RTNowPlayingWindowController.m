#import "RTNowPlayingWindowController.h"
#import "RTStatusIcon.h"

@interface RTNowPlayingWindowController () <NSWindowDelegate>
@property (nonatomic, strong) NSImageView *artworkView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *artistLabel;
@property (nonatomic, strong) NSTextField *stationLabel;
@property (nonatomic, strong) NSButton *previousButton;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSButton *nextButton;
@property (nonatomic, strong) NSButton *favoriteButton;
@property (nonatomic, strong) NSSlider *volumeSlider;
@property (nonatomic, strong) NSTextField *volumeValue;
@property (nonatomic, strong) NSButton *floatingBox;
@end

@implementation RTNowPlayingWindowController

- (instancetype)initFloating:(BOOL)floating
{
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 440, 170)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskUtilityWindow
                                                  backing:NSBackingStoreBuffered defer:YES];
    panel.title = @"In riproduzione";
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;   // resta visibile anche quando si usa un'altra app
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.frameAutosaveName = @"RadioTrayNowPlaying";
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces;
    if ((self = [super initWithWindow:panel])) {
        panel.delegate = self;
        [self buildContent];
        [self setFloating:floating];
        if (![panel setFrameUsingName:@"RadioTrayNowPlaying"]) {
            NSRect screen = NSScreen.mainScreen.visibleFrame;
            [panel setFrameTopLeftPoint:NSMakePoint(NSMaxX(screen) - 460, NSMaxY(screen) - 20)];
        }
    }
    return self;
}

- (NSTextField *)label:(NSFont *)font frame:(NSRect)frame color:(NSColor *)color
{
    NSTextField *l = [NSTextField labelWithString:@""];
    l.font = font;
    l.textColor = color;
    l.frame = frame;
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    l.allowsDefaultTighteningForTruncation = YES;
    [self.window.contentView addSubview:l];
    return l;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame tip:(NSString *)tip
{
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.frame = frame;
    b.toolTip = tip;
    b.font = [NSFont systemFontOfSize:15];
    [self.window.contentView addSubview:b];
    return b;
}

- (void)buildContent
{
    NSView *content = self.window.contentView;
    self.artworkView = [[NSImageView alloc] initWithFrame:NSMakeRect(14, 14, 142, 142)];
    self.artworkView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.artworkView.imageFrameStyle = NSImageFrameNone;
    self.artworkView.wantsLayer = YES;
    self.artworkView.layer.cornerRadius = 6;
    self.artworkView.layer.masksToBounds = YES;
    [content addSubview:self.artworkView];

    CGFloat x = 170, w = 256;
    self.titleLabel = [self label:[NSFont boldSystemFontOfSize:15] frame:NSMakeRect(x, 132, w, 20) color:[NSColor labelColor]];
    self.artistLabel = [self label:[NSFont systemFontOfSize:13] frame:NSMakeRect(x, 112, w, 18) color:[NSColor labelColor]];
    self.stationLabel = [self label:[NSFont systemFontOfSize:11] frame:NSMakeRect(x, 92, w, 16) color:[NSColor secondaryLabelColor]];

    self.previousButton = [self button:@"◀︎" action:@selector(previous:) frame:NSMakeRect(x - 6, 52, 52, 32) tip:@"Stazione precedente"];
    self.playButton = [self button:@"▶︎" action:@selector(togglePlay:) frame:NSMakeRect(x + 44, 52, 60, 32) tip:@"Accendi / spegni"];
    self.nextButton = [self button:@"▶︎▶︎" action:@selector(next:) frame:NSMakeRect(x + 102, 52, 56, 32) tip:@"Stazione successiva"];
    self.favoriteButton = [self button:@"☆" action:@selector(favorite:) frame:NSMakeRect(x + 162, 52, 52, 32) tip:@"Aggiungi ai brani preferiti"];

    NSTextField *vol = [self label:[NSFont systemFontOfSize:11] frame:NSMakeRect(x, 30, 30, 16) color:[NSColor secondaryLabelColor]];
    vol.stringValue = @"🔈";
    self.volumeSlider = [NSSlider sliderWithValue:80 minValue:0 maxValue:100 target:self action:@selector(volumeChanged:)];
    self.volumeSlider.controlSize = NSControlSizeSmall;
    self.volumeSlider.continuous = YES;
    self.volumeSlider.frame = NSMakeRect(x + 22, 28, w - 70, 20);
    [content addSubview:self.volumeSlider];
    self.volumeValue = [self label:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular]
                             frame:NSMakeRect(x + w - 42, 30, 42, 16) color:[NSColor secondaryLabelColor]];
    self.volumeValue.alignment = NSTextAlignmentRight;

    self.floatingBox = [NSButton checkboxWithTitle:@"Sempre in primo piano" target:self action:@selector(floatingChanged:)];
    self.floatingBox.controlSize = NSControlSizeSmall;
    self.floatingBox.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    self.floatingBox.frame = NSMakeRect(x, 6, w, 18);
    [content addSubview:self.floatingBox];
}

- (void)setFloating:(BOOL)floating
{
    self.window.level = floating ? NSFloatingWindowLevel : NSNormalWindowLevel;
    ((NSPanel *)self.window).floatingPanel = floating;
    self.floatingBox.state = floating ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)showWithoutActivating
{
    [self.window orderFrontRegardless];
}

- (void)updateTitle:(NSString *)title artist:(NSString *)artist station:(NSString *)station quality:(NSString *)quality
            artwork:(NSImage *)artwork playing:(BOOL)playing active:(BOOL)active favorite:(BOOL)favorite
        canFavorite:(BOOL)canFavorite hasPrevious:(BOOL)hasPrevious hasNext:(BOOL)hasNext volume:(NSInteger)volume
{
    self.titleLabel.stringValue = title ?: @"";
    self.titleLabel.toolTip = title;
    self.artistLabel.stringValue = artist ?: @"";
    self.artistLabel.toolTip = artist;
    NSMutableArray *bits = [NSMutableArray array];
    if (station.length) [bits addObject:station];
    if (quality.length) [bits addObject:quality];
    self.stationLabel.stringValue = [bits componentsJoinedByString:@" · "];
    self.artworkView.image = artwork ?: [self placeholder:playing];
    self.playButton.title = active ? @"❚❚" : @"▶︎";
    self.playButton.toolTip = active ? @"Spegni" : @"Accendi";
    self.previousButton.enabled = hasPrevious;
    self.nextButton.enabled = hasNext;
    self.favoriteButton.title = favorite ? @"★" : @"☆";
    self.favoriteButton.enabled = canFavorite && !favorite;
    self.favoriteButton.toolTip = favorite ? @"Già nei brani preferiti" : @"Aggiungi ai brani preferiti (⌃⌥F)";
    if (self.volumeSlider.integerValue != volume) self.volumeSlider.integerValue = volume;
    self.volumeValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)volume];
}

/// Al posto della copertina: l'icona della radio in grigio su fondo chiaro.
- (NSImage *)placeholder:(BOOL)playing
{
    NSImage *radio = RTStatusIconImage(playing ? RTStatusIconOn : RTStatusIconOff);
    return [NSImage imageWithSize:NSMakeSize(142, 142) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor colorWithCalibratedWhite:0.5 alpha:0.12] setFill];
        NSRectFill(rect);
        NSRect r = NSInsetRect(rect, 40, 40);
        [radio drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.35];
        return YES;
    }];
}

#pragma mark - Azioni

- (void)previous:(id)sender { [self.delegate nowPlayingPrevious]; }
- (void)togglePlay:(id)sender { [self.delegate nowPlayingTogglePlay]; }
- (void)next:(id)sender { [self.delegate nowPlayingNext]; }
- (void)favorite:(id)sender { [self.delegate nowPlayingFavorite]; }
- (void)volumeChanged:(NSSlider *)sender
{
    self.volumeValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)sender.integerValue];   // subito, mentre si trascina
    [self.delegate nowPlayingVolumeChanged:sender.integerValue];
}

- (void)floatingChanged:(NSButton *)sender
{
    BOOL floating = sender.state == NSControlStateValueOn;
    [self setFloating:floating];
    [self.delegate nowPlayingFloatingChanged:floating];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self.delegate nowPlayingClosed];
}

@end
