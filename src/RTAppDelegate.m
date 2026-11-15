#import "RTAppDelegate.h"
#import "RTBookmarks.h"
#import "RTNotifier.h"
#import "RTPlayer.h"
#import "RTSettings.h"
#import "RTStatusIcon.h"
#import "RTStreamResolver.h"
#import "RTTrackInfo.h"

static const NSUInteger RTMenuLineLength = 48;

@interface RTAppDelegate () <NSMenuDelegate, RTPlayerDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, strong) NSMenuItem *trackItem;
@property (nonatomic, strong) NSMenuItem *actionItem;
@property (nonatomic, strong) NSMenuItem *volumeItem;
@property (nonatomic, strong) NSSlider *volumeSlider;
@property (nonatomic, strong) NSTextField *volumeValue;
@property (nonatomic, strong) NSMutableArray<NSMenuItem *> *stationItems;

@property (nonatomic, strong) RTSettings *settings;
@property (nonatomic, strong) RTBookmarks *bookmarks;
@property (nonatomic, strong) RTPlayer *player;
@property (nonatomic, strong) RTStreamResolver *resolver;

@property (nonatomic, copy) NSString *currentGroup;     // stazione scelta (anche se spenta)
@property (nonatomic, copy) NSString *currentStation;
@property (nonatomic, strong) RTTrackInfo *track;
@property (nonatomic) BOOL playingNotified;
@property (nonatomic) BOOL userStopped;
@end

@implementation RTAppDelegate

#pragma mark - Avvio

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    self.settings = [RTSettings shared];
    self.stationItems = [NSMutableArray array];
    self.track = [RTTrackInfo infoWithTitle:nil artist:nil];
    self.resolver = [RTStreamResolver new];
    self.player = [RTPlayer new];
    self.player.delegate = self;
    self.player.volume = self.settings.volume;
    [RTNotifier shared];

    [self installDefaultBookmarksIfNeeded];
    NSString *error = nil;
    self.bookmarks = [RTBookmarks bookmarksWithContentsOfFile:self.settings.bookmarksPath error:&error];
    if (!self.bookmarks) {
        self.bookmarks = [RTBookmarks new];
        [self showAlert:@"Impossibile caricare le stazioni" text:error];
    }

    // ultima stazione ascoltata (se esiste ancora)
    NSString *g = self.settings.lastGroup, *s = self.settings.lastStation;
    if (g && s && [self.bookmarks stationNamed:s inGroup:g]) {
        self.currentGroup = g;
        self.currentStation = s;
    }

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.menu = [NSMenu new];
    self.menu.delegate = self;
    self.menu.autoenablesItems = NO;
    self.statusItem.menu = self.menu;
    [self buildMenu];
    [self refresh];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self.player stop];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)installDefaultBookmarksIfNeeded
{
    NSString *path = self.settings.bookmarksPath;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSString *bundled = [[NSBundle mainBundle] pathForResource:@"bookmarks" ofType:@"json"];
    if (bundled) {
        [[NSFileManager defaultManager] copyItemAtPath:bundled toPath:path error:NULL];
    } else {
        [@"[]\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}

#pragma mark - Menu

- (NSMenuItem *)addItem:(NSString *)title action:(SEL)action to:(NSMenu *)menu
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return item;
}

- (NSMenuItem *)stationItem:(RTStation *)station group:(RTGroup *)group
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:station.name action:@selector(stationChosen:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = @[group.name, station.name];
    item.toolTip = station.url;
    [self.stationItems addObject:item];
    return item;
}

- (void)addRootStationsTo:(NSMenu *)menu
{
    RTGroup *root = [self.bookmarks groupNamed:RTRootGroupName];
    for (RTStation *s in root.stations) [menu addItem:[self stationItem:s group:root]];
}

- (NSMenuItem *)buildVolumeItem
{
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 26)];

    NSTextField *label = [NSTextField labelWithString:@"Volume"];
    label.font = [NSFont menuFontOfSize:0];
    label.frame = NSMakeRect(20, 4, 56, 18);
    [view addSubview:label];

    NSSlider *slider = [NSSlider sliderWithValue:self.player.volume minValue:0 maxValue:100
                                          target:self action:@selector(volumeChanged:)];
    slider.continuous = YES;
    slider.controlSize = NSControlSizeSmall;
    slider.frame = NSMakeRect(76, 3, 124, 20);
    [view addSubview:slider];
    self.volumeSlider = slider;

    NSTextField *value = [NSTextField labelWithString:@""];
    value.font = [NSFont monospacedDigitSystemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightRegular];
    value.alignment = NSTextAlignmentRight;
    value.frame = NSMakeRect(202, 5, 38, 16);
    [view addSubview:value];
    self.volumeValue = value;

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Volume" action:NULL keyEquivalent:@""];
    item.view = view;
    return item;
}

- (void)buildMenu
{
    [self.menu removeAllItems];
    [self.stationItems removeAllObjects];

    self.trackItem = [self addItem:@"Fermo" action:@selector(copyTrack:) to:self.menu];
    self.actionItem = [self addItem:@"Accendi" action:@selector(togglePlay:) to:self.menu];
    self.volumeItem = [self buildVolumeItem];
    [self.menu addItem:self.volumeItem];
    [self.menu addItem:[NSMenuItem separatorItem]];

    BOOL rootBottom = self.settings.rootGroupAtBottom;
    if (!rootBottom) [self addRootStationsTo:self.menu];
    for (RTGroup *group in self.bookmarks.groups) {
        if (group.isRoot) continue;
        NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:group.name action:NULL keyEquivalent:@""];
        NSMenu *sub = [[NSMenu alloc] initWithTitle:group.name];
        sub.autoenablesItems = NO;
        for (RTStation *s in group.stations) [sub addItem:[self stationItem:s group:group]];
        if (group.stations.count == 0) {
            NSMenuItem *empty = [self addItem:@"(nessuna stazione)" action:NULL to:sub];
            empty.enabled = NO;
        }
        groupItem.submenu = sub;
        [self.menu addItem:groupItem];
    }
    if (rootBottom) [self addRootStationsTo:self.menu];
    if (self.bookmarks.stationCount == 0) {
        NSMenuItem *none = [self addItem:@"Nessuna stazione: usa Preferenze ▸ Modifica stazioni…" action:NULL to:self.menu];
        none.enabled = NO;
    }
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *prefs = [[NSMenuItem alloc] initWithTitle:@"Preferenze" action:NULL keyEquivalent:@""];
    NSMenu *prefsMenu = [[NSMenu alloc] initWithTitle:@"Preferenze"];
    prefsMenu.autoenablesItems = NO;
    [self addItem:@"Modifica stazioni…" action:@selector(editBookmarks:) to:prefsMenu];
    [self addItem:@"Mostra il file delle stazioni nel Finder" action:@selector(revealBookmarks:) to:prefsMenu];
    [self addItem:@"Ricarica stazioni" action:@selector(reloadBookmarks:) to:prefsMenu];
    [prefsMenu addItem:[NSMenuItem separatorItem]];
    [self addItem:@"Notifiche" action:@selector(toggleNotifications:) to:prefsMenu].tag = 1;
    [self addItem:@"Notifiche dettagliate (connessione, arresto)" action:@selector(toggleVerbose:) to:prefsMenu].tag = 2;
    [self addItem:@"Separa titolo e artista" action:@selector(toggleSplit:) to:prefsMenu].tag = 3;
    [self addItem:@"Stazioni senza gruppo in fondo al menu" action:@selector(toggleRootBottom:) to:prefsMenu].tag = 4;
    prefs.submenu = prefsMenu;
    [self.menu addItem:prefs];

    [self addItem:@"Informazioni su RadioTray" action:@selector(about:) to:self.menu];
    NSMenuItem *quit = [self addItem:@"Esci da RadioTray" action:@selector(quit:) to:self.menu];
    quit.keyEquivalent = @"q";
}

- (void)menuWillOpen:(NSMenu *)menu
{
    [self refresh];
}

- (NSString *)currentStationLabel
{
    return self.currentStation ? [NSString stringWithFormat:@"«%@»", RTTruncate(self.currentStation, 36)] : nil;
}

- (void)refresh
{
    RTPlayerState state = self.player.state;
    BOOL active = state != RTPlayerStateStopped;

    // icona e suggerimento
    RTStatusIconStyle style = state == RTPlayerStatePlaying ? RTStatusIconOn
                            : (active ? RTStatusIconConnecting : RTStatusIconOff);
    self.statusItem.button.image = RTStatusIconImage(style);
    NSMutableString *tip = [NSMutableString stringWithString:@"RadioTray"];
    if (active && self.currentStation) [tip appendFormat:@"\n%@", self.currentStation];
    if (active && !self.track.isEmpty) [tip appendFormat:@"\n%@", self.track.clipboardText];
    self.statusItem.button.toolTip = tip;

    // riga di stato
    NSString *line1 = nil, *line2 = nil;
    switch (state) {
        case RTPlayerStateStopped:    line1 = @"Fermo"; break;
        case RTPlayerStateConnecting: line1 = @"Connessione in corso…"; break;
        case RTPlayerStateBuffering:  line1 = @"Caricamento…"; break;
        case RTPlayerStatePlaying:
            if (self.track.isEmpty) {
                line1 = @"In riproduzione";
            } else if (self.track.title.length) {
                line1 = self.track.title;
                line2 = self.track.artist.length ? self.track.artist : nil;
            } else {
                line1 = self.track.artist;
            }
            break;
    }
    NSMutableAttributedString *status = [[NSMutableAttributedString alloc]
        initWithString:RTTruncate(line1, RTMenuLineLength)
            attributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize]] }];
    if (line2) {
        [status appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@"\n" stringByAppendingString:RTTruncate(line2, RTMenuLineLength)]
                attributes:@{ NSFontAttributeName: [NSFont menuFontOfSize:0] }]];
    }
    self.trackItem.attributedTitle = status;
    self.trackItem.enabled = state == RTPlayerStatePlaying && !self.track.isEmpty;
    self.trackItem.toolTip = self.trackItem.enabled ? @"Clic per copiare titolo e artista" : nil;

    // accendi/spegni
    NSString *label = [self currentStationLabel];
    if (active) {
        self.actionItem.title = label ? [NSString stringWithFormat:@"Spegni %@", label] : @"Spegni";
        self.actionItem.enabled = YES;
    } else {
        self.actionItem.title = label ? [NSString stringWithFormat:@"Accendi %@", label] : @"Accendi";
        self.actionItem.enabled = self.currentStation &&
            [self.bookmarks stationNamed:self.currentStation inGroup:self.currentGroup] != nil;
    }

    // volume
    self.volumeSlider.integerValue = self.player.volume;
    self.volumeValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)self.player.volume];

    // spunta sulla stazione corrente
    for (NSMenuItem *item in self.stationItems) {
        NSArray *key = item.representedObject;
        BOOL current = active && [key[0] isEqualToString:self.currentGroup ?: @""] &&
                       [key[1] isEqualToString:self.currentStation ?: @""];
        item.state = current ? NSControlStateValueOn : NSControlStateValueOff;
    }

    // preferenze
    NSMenu *prefs = [self.menu itemWithTitle:@"Preferenze"].submenu;
    [prefs itemWithTag:1].state = self.settings.notifications ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:2].state = self.settings.verboseNotifications ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:2].enabled = self.settings.notifications;
    [prefs itemWithTag:3].state = self.settings.splitTitle ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:4].state = self.settings.rootGroupAtBottom ? NSControlStateValueOn : NSControlStateValueOff;
}

#pragma mark - Riproduzione

- (void)playStationNamed:(NSString *)name inGroup:(NSString *)groupName
{
    RTStation *station = [self.bookmarks stationNamed:name inGroup:groupName];
    if (!station) {
        [[RTNotifier shared] notifyTitle:@"Errore" message:@"La stazione non è più nell'elenco"];
        return;
    }
    self.currentGroup = groupName;
    self.currentStation = name;
    self.settings.lastGroup = groupName;
    self.settings.lastStation = name;
    self.track = [RTTrackInfo infoWithTitle:nil artist:nil];
    self.playingNotified = NO;
    self.userStopped = NO;

    [self.player markConnecting];
    [self notifyVerbose:@"Connessione in corso…" message:name];
    [self refresh];

    __weak typeof(self) weakSelf = self;
    [self.resolver resolve:station.url direct:station.direct completion:^(NSArray<NSString *> *streams, NSString *error) {
        typeof(self) self_ = weakSelf;
        if (!self_ || self_.userStopped) return;
        NSLog(@"RadioTray: %@ → %@", station.url, self_.resolver.lastDecision ?: @"?");
        if (!streams) {
            [self_.player stop];
            [[RTNotifier shared] notifyTitle:@"Errore" message:[NSString stringWithFormat:@"%@: %@", name, error]];
            [self_ refresh];
            return;
        }
        [self_.player playStreams:streams];
    }];
}

- (void)stopPlayback
{
    self.userStopped = YES;
    [self.resolver cancel];
    [self.player stop];
    self.track = [RTTrackInfo infoWithTitle:nil artist:nil];
    [self notifyVerbose:@"Fermo" message:self.currentStation];
    [self refresh];
}

- (void)notifyVerbose:(NSString *)title message:(NSString *)message
{
    if (self.settings.notifications && self.settings.verboseNotifications) {
        [[RTNotifier shared] notifyTitle:title message:message];
    }
}

- (BOOL)stationWantsNotifications
{
    RTStation *s = [self.bookmarks stationNamed:self.currentStation ?: @"" inGroup:self.currentGroup ?: @""];
    return s ? s.notifications : YES;
}

#pragma mark - RTPlayerDelegate

- (void)player:(RTPlayer *)player didChangeState:(RTPlayerState)state
{
    if (state == RTPlayerStatePlaying && !self.playingNotified) {
        self.playingNotified = YES;
        if (self.settings.notifications) {
            [[RTNotifier shared] notifyTitle:self.currentStation ?: @"RadioTray" message:@"RadioTray"];
        }
    } else if (state == RTPlayerStateBuffering) {
        [self notifyVerbose:@"Caricamento…" message:self.currentStation];
    }
    [self refresh];
}

- (void)player:(RTPlayer *)player didReceiveStreamTitle:(NSString *)title
{
    RTTrackInfo *info = [RTTrackInfo infoWithStreamTitle:title split:self.settings.splitTitle];
    if (info.isEmpty || [info isEqualToInfo:self.track]) return;
    self.track = info;
    if (self.settings.notifications && [self stationWantsNotifications]) {
        if (info.title.length && info.artist.length) {
            [[RTNotifier shared] notifyTitle:info.title message:info.artist];
        } else {
            [[RTNotifier shared] notifyTitle:info.title.length ? info.title : info.artist message:self.currentStation];
        }
    }
    [self refresh];
}

- (void)player:(RTPlayer *)player didFailWithError:(NSString *)error
{
    // gli errori si mostrano sempre, anche con le notifiche spente (come Radiotray-NG)
    NSString *msg = self.currentStation ? [NSString stringWithFormat:@"%@: %@", self.currentStation, error] : error;
    [[RTNotifier shared] notifyTitle:@"Errore" message:msg];
    self.track = [RTTrackInfo infoWithTitle:nil artist:nil];
    [self refresh];
}

#pragma mark - Azioni del menu

- (void)stationChosen:(NSMenuItem *)sender
{
    NSArray *key = sender.representedObject;
    [self playStationNamed:key[1] inGroup:key[0]];
}

- (void)togglePlay:(id)sender
{
    if (self.player.state != RTPlayerStateStopped) {
        [self stopPlayback];
    } else if (self.currentStation && self.currentGroup) {
        [self playStationNamed:self.currentStation inGroup:self.currentGroup];
    }
}

- (void)volumeChanged:(NSSlider *)sender
{
    self.player.volume = sender.integerValue;
    self.settings.volume = self.player.volume;
    self.volumeValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)self.player.volume];
}

- (void)copyTrack:(id)sender
{
    if (self.track.isEmpty) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:self.track.clipboardText forType:NSPasteboardTypeString];
}

- (void)editBookmarks:(id)sender
{
    [self installDefaultBookmarksIfNeeded];
    NSURL *file = [NSURL fileURLWithPath:self.settings.bookmarksPath];
    NSURL *textEdit = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
    BOOL opened = NO;
    if (textEdit) {
        opened = [[NSWorkspace sharedWorkspace] openURLs:@[file] withApplicationAtURL:textEdit
                                                 options:NSWorkspaceLaunchDefault configuration:@{} error:NULL] != nil;
    }
    if (!opened) [[NSWorkspace sharedWorkspace] openURL:file];
}

- (void)revealBookmarks:(id)sender
{
    [self installDefaultBookmarksIfNeeded];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:self.settings.bookmarksPath]]];
}

- (void)reloadBookmarks:(id)sender
{
    NSString *error = nil;
    RTBookmarks *b = [RTBookmarks bookmarksWithContentsOfFile:self.settings.bookmarksPath error:&error];
    if (!b) {
        [self showAlert:@"Stazioni non ricaricate" text:[error stringByAppendingString:@"\n\nRimane in uso l'elenco precedente."]];
        return;
    }
    self.bookmarks = b;
    [self buildMenu];
    [self refresh];
    if (self.settings.notifications) {
        [[RTNotifier shared] notifyTitle:@"Stazioni ricaricate"
                                 message:[NSString stringWithFormat:@"%lu stazioni", (unsigned long)b.stationCount]];
    }
}

- (void)toggleNotifications:(id)sender { self.settings.notifications = !self.settings.notifications; [self refresh]; }
- (void)toggleVerbose:(id)sender { self.settings.verboseNotifications = !self.settings.verboseNotifications; [self refresh]; }
- (void)toggleSplit:(id)sender { self.settings.splitTitle = !self.settings.splitTitle; [self refresh]; }

- (void)toggleRootBottom:(id)sender
{
    self.settings.rootGroupAtBottom = !self.settings.rootGroupAtBottom;
    [self buildMenu];
    [self refresh];
}

- (void)about:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:nil];
}

- (void)quit:(id)sender
{
    [NSApp terminate:nil];
}

- (void)showAlert:(NSString *)title text:(NSString *)text
{
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = text ?: @"";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end
