#import "RTAppDelegate.h"
#import "RTBookmarks.h"
#import "RTFileWatcher.h"
#import "RTMediaKeys.h"
#import "RTNotifier.h"
#import "RTPlayer.h"
#import "RTSearchWindowController.h"
#import "RTStationEditorController.h"
#import "RTLoginItem.h"
#import "RTFavoriteTracks.h"
#import "RTFavoritesWindowController.h"
#import "RTSettings.h"
#import "RTStatusIcon.h"
#import "RTStreamResolver.h"
#import "RTTrackInfo.h"

static const NSUInteger RTMenuLineLength = 48;
static const NSInteger RTMaxSleepMinutes = 24 * 60;

@interface RTAppDelegate () <NSMenuDelegate, RTPlayerDelegate, RTMediaKeysDelegate, RTSearchWindowDelegate, RTStationEditorDelegate, RTFavoritesWindowDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, strong) NSMenuItem *trackItem;
@property (nonatomic, strong) NSMenuItem *actionItem;
@property (nonatomic, strong) NSMenuItem *volumeItem;
@property (nonatomic, strong) NSMenuItem *previousItem;
@property (nonatomic, strong) NSMenuItem *nextItem;
@property (nonatomic, strong) NSMenuItem *sleepItem;
@property (nonatomic, strong) NSMenuItem *addStationItem;
@property (nonatomic, strong) NSSlider *volumeSlider;
@property (nonatomic, strong) NSTextField *volumeValue;
@property (nonatomic, strong) NSMutableArray<NSMenuItem *> *stationItems;

@property (nonatomic, strong) RTSettings *settings;
@property (nonatomic, strong) RTBookmarks *bookmarks;
@property (nonatomic, strong) RTPlayer *player;
@property (nonatomic, strong) RTStreamResolver *resolver;
@property (nonatomic, strong) RTFileWatcher *bookmarksWatcher;
@property (nonatomic, strong) RTMediaKeys *mediaKeys;
@property (nonatomic, strong, nullable) RTSearchWindowController *searchWindow;
@property (nonatomic, strong, nullable) RTStationEditorController *stationEditor;
@property (nonatomic, strong) RTFavoriteTracks *favorites;
@property (nonatomic, strong, nullable) RTFavoritesWindowController *favoritesWindow;

// stazione scelta (anche se spenta). currentGroup nil = indirizzo aperto con "Apri URL…"
@property (nonatomic, copy, nullable) NSString *currentGroup;
@property (nonatomic, copy, nullable) NSString *currentStation;
@property (nonatomic, strong, nullable) RTStation *adhocStation;
@property (nonatomic) BOOL adhocNamed;   // il nome viene dal server (icy-name), non dall'indirizzo
@property (nonatomic, strong) RTTrackInfo *track;
@property (nonatomic) BOOL playingNotified;
@property (nonatomic) BOOL userStopped;

@property (nonatomic, strong, nullable) NSTimer *sleepTimer;
@end

@implementation RTAppDelegate

#pragma mark - Avvio

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    self.settings = [RTSettings shared];
    [self installMainMenu];
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

    // ricarica automatica quando il file delle stazioni viene salvato
    __weak typeof(self) weakSelf = self;
    self.bookmarksWatcher = [[RTFileWatcher alloc] initWithPath:self.settings.bookmarksPath changeHandler:^{
        [weakSelf reloadBookmarksInteractive:NO];
        [weakSelf.stationEditor reloadFromDisk];
    }];
    [self.bookmarksWatcher start];

    self.mediaKeys = [RTMediaKeys new];
    self.mediaKeys.delegate = self;
    [self.mediaKeys start];

    NSString *favoritesError = nil;
    self.favorites = [RTFavoriteTracks tracksWithContentsOfFile:[self favoritesPath] error:&favoritesError];
    if (!self.favorites) {
        // file illeggibile: si riparte con un elenco vuoto (il file viene riscritto al primo brano aggiunto)
        NSLog(@"RadioTray: %@", favoritesError);
        self.favorites = [RTFavoriteTracks new];
    }

    // se l'app è stata spostata, l'avvio al login deve puntare al nuovo percorso
    [RTLoginItem refreshAppPath:[NSBundle mainBundle].bundlePath];

    // al risveglio dallo stop la connessione è quasi sempre morta: si ricollega
    [[NSWorkspace sharedWorkspace].notificationCenter addObserver:self selector:@selector(systemDidWake:)
                                                             name:NSWorkspaceDidWakeNotification object:nil];
    [self refresh];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self.player stop];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

/// Un'app della barra dei menu non mostra un menu principale, ma serve lo stesso perché nei campi
/// di testo (ricerca, Apri URL…) funzionino ⌘X ⌘C ⌘V ⌘A ⌘Z e perché ⌘W chiuda le finestre.
- (void)installMainMenu
{
    NSMenu *main = [NSMenu new];
    NSMenuItem *appItem = [main addItemWithTitle:@"RadioTray" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"RadioTray"];
    [appMenu addItemWithTitle:@"Esci da RadioTray" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *editItem = [main addItemWithTitle:@"Composizione" action:NULL keyEquivalent:@""];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Composizione"];
    [edit addItemWithTitle:@"Annulla" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [edit addItemWithTitle:@"Ripeti" action:@selector(redo:) keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [edit addItem:[NSMenuItem separatorItem]];
    [edit addItemWithTitle:@"Taglia" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copia" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Incolla" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Seleziona tutto" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = edit;

    NSMenuItem *windowItem = [main addItemWithTitle:@"Finestra" action:NULL keyEquivalent:@""];
    NSMenu *window = [[NSMenu alloc] initWithTitle:@"Finestra"];
    [window addItemWithTitle:@"Chiudi" action:@selector(performClose:) keyEquivalent:@"w"];
    [window addItemWithTitle:@"Contrai" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    windowItem.submenu = window;

    NSApp.mainMenu = main;
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

- (void)systemDidWake:(NSNotification *)note
{
    if (self.player.state == RTPlayerStateStopped) return;
    // si lascia alla rete qualche secondo per tornare su
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.player.state != RTPlayerStateStopped) [self.player reconnectNow];
    });
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
        NSMenuItem *none = [self addItem:@"Nessuna stazione: usa Cerca stazioni… o Preferenze ▸ Modifica stazioni…" action:NULL to:self.menu];
        none.enabled = NO;
    }
    [self.menu addItem:[NSMenuItem separatorItem]];

    self.previousItem = [self addItem:@"Stazione precedente" action:@selector(previousStation:) to:self.menu];
    self.nextItem = [self addItem:@"Stazione successiva" action:@selector(nextStation:) to:self.menu];
    [self addItem:@"Cerca stazioni…" action:@selector(searchStations:) to:self.menu];
    [self addItem:@"Brani preferiti…" action:@selector(openFavorites:) to:self.menu];
    [self addItem:@"Apri URL…" action:@selector(openURL:) to:self.menu];
    self.addStationItem = [self addItem:@"Aggiungi alle stazioni…" action:@selector(addCurrentStation:) to:self.menu];
    self.sleepItem = [self addItem:@"Timer di spegnimento…" action:@selector(sleepTimerChosen:) to:self.menu];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *prefs = [[NSMenuItem alloc] initWithTitle:@"Preferenze" action:NULL keyEquivalent:@""];
    NSMenu *prefsMenu = [[NSMenu alloc] initWithTitle:@"Preferenze"];
    prefsMenu.autoenablesItems = NO;
    [self addItem:@"Modifica stazioni…" action:@selector(openStationEditor:) to:prefsMenu];
    [self addItem:@"Modifica il file JSON in TextEdit…" action:@selector(editBookmarks:) to:prefsMenu];
    [self addItem:@"Mostra il file delle stazioni nel Finder" action:@selector(revealBookmarks:) to:prefsMenu];
    [self addItem:@"Ricarica stazioni" action:@selector(reloadBookmarks:) to:prefsMenu];
    [self addItem:@"Aggiungi le radio italiane consigliate" action:@selector(addItalianStations:) to:prefsMenu];
    [prefsMenu addItem:[NSMenuItem separatorItem]];
    [self addItem:@"Notifiche" action:@selector(toggleNotifications:) to:prefsMenu].tag = 1;
    [self addItem:@"Notifiche dettagliate (connessione, arresto)" action:@selector(toggleVerbose:) to:prefsMenu].tag = 2;
    [self addItem:@"Separa titolo e artista" action:@selector(toggleSplit:) to:prefsMenu].tag = 3;
    [self addItem:@"Stazioni senza gruppo in fondo al menu" action:@selector(toggleRootBottom:) to:prefsMenu].tag = 4;
    [prefsMenu addItem:[NSMenuItem separatorItem]];
    [self addItem:@"Avvia RadioTray al login" action:@selector(toggleLoginItem:) to:prefsMenu].tag = 5;
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

/// La stazione scelta: dai preferiti, oppure quella aperta con "Apri URL…".
- (RTStation *)currentStationObject
{
    if (!self.currentStation) return nil;
    if (!self.currentGroup) return self.adhocStation;
    return [self.bookmarks stationNamed:self.currentStation inGroup:self.currentGroup];
}

/// Stazioni del gruppo corrente e posizione di quella scelta (NSNotFound se non c'è).
- (NSArray<RTStation *> *)currentGroupStations:(NSUInteger *)index
{
    *index = NSNotFound;
    if (!self.currentGroup || !self.currentStation) return @[];
    NSArray<RTStation *> *stations = [self.bookmarks groupNamed:self.currentGroup].stations ?: @[];
    for (NSUInteger i = 0; i < stations.count; i++) {
        if ([stations[i].name isEqualToString:self.currentStation]) {
            *index = i;
            break;
        }
    }
    return stations;
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
                if ([self currentTrackIsFavorite]) line1 = [@"★ " stringByAppendingString:line1];
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
    self.trackItem.toolTip = nil;
    if (self.trackItem.enabled) {
        // sottomenu del brano: preferiti e appunti
        NSMenu *sub = [[NSMenu alloc] initWithTitle:@"Brano"];
        sub.autoenablesItems = NO;
        BOOL favorite = [self currentTrackIsFavorite];
        NSMenuItem *add = [self addItem:favorite ? @"★ Già nei brani preferiti" : @"★ Aggiungi ai brani preferiti"
                                 action:@selector(addCurrentTrackToFavorites:) to:sub];
        add.enabled = !favorite;
        [self addItem:@"Copia titolo e artista" action:@selector(copyTrack:) to:sub];
        [sub addItem:[NSMenuItem separatorItem]];
        [self addItem:@"Brani preferiti…" action:@selector(openFavorites:) to:sub];
        self.trackItem.submenu = sub;
    } else {
        self.trackItem.submenu = nil;
    }

    // accendi/spegni
    NSString *label = [self currentStationLabel];
    if (active) {
        self.actionItem.title = label ? [NSString stringWithFormat:@"Spegni %@", label] : @"Spegni";
        self.actionItem.enabled = YES;
    } else {
        self.actionItem.title = label ? [NSString stringWithFormat:@"Accendi %@", label] : @"Accendi";
        self.actionItem.enabled = [self currentStationObject] != nil;
    }

    // volume
    self.volumeSlider.integerValue = self.player.volume;
    self.volumeValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)self.player.volume];

    // spunta sulla stazione corrente
    for (NSMenuItem *item in self.stationItems) {
        NSArray *key = item.representedObject;
        BOOL current = active && self.currentGroup && [key[0] isEqualToString:self.currentGroup] &&
                       [key[1] isEqualToString:self.currentStation ?: @""];
        item.state = current ? NSControlStateValueOn : NSControlStateValueOff;
    }

    // precedente / successiva nel gruppo
    NSUInteger index;
    NSArray<RTStation *> *stations = [self currentGroupStations:&index];
    BOOL found = index != NSNotFound;
    self.previousItem.enabled = found && index > 0;
    self.nextItem.enabled = found && index + 1 < stations.count;
    self.previousItem.title = self.previousItem.enabled
        ? [NSString stringWithFormat:@"Stazione precedente: %@", RTTruncate(stations[index - 1].name, 32)] : @"Stazione precedente";
    self.nextItem.title = self.nextItem.enabled
        ? [NSString stringWithFormat:@"Stazione successiva: %@", RTTruncate(stations[index + 1].name, 32)] : @"Stazione successiva";

    // stazione aperta con "Apri URL…": si può aggiungere ai preferiti
    BOOL adhoc = !self.currentGroup && self.adhocStation && self.currentStation;
    self.addStationItem.hidden = !adhoc;
    if (adhoc) {
        self.addStationItem.title = [NSString stringWithFormat:@"Aggiungi %@ alle stazioni…", [self currentStationLabel]];
    }

    // timer di spegnimento
    if (self.sleepTimer) {
        NSInteger minutes = (NSInteger)ceil(self.sleepTimer.fireDate.timeIntervalSinceNow / 60.0);
        self.sleepItem.title = [NSString stringWithFormat:@"Timer di spegnimento: %ld min (clic per annullare)", (long)MAX(1, minutes)];
        self.sleepItem.state = NSControlStateValueOn;
    } else {
        self.sleepItem.title = @"Timer di spegnimento…";
        self.sleepItem.state = NSControlStateValueOff;
    }

    // preferenze
    NSMenu *prefs = [self.menu itemWithTitle:@"Preferenze"].submenu;
    [prefs itemWithTag:1].state = self.settings.notifications ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:2].state = self.settings.verboseNotifications ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:2].enabled = self.settings.notifications;
    [prefs itemWithTag:3].state = self.settings.splitTitle ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:4].state = self.settings.rootGroupAtBottom ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:5].state = [RTLoginItem isEnabled] ? NSControlStateValueOn : NSControlStateValueOff;

    // "In riproduzione" di sistema (tasti multimediali)
    [self.mediaKeys updateWithStation:self.currentStation title:self.track.title artist:self.track.artist
                              playing:state == RTPlayerStatePlaying];
}

#pragma mark - Riproduzione

- (void)playStationNamed:(NSString *)name inGroup:(NSString *)groupName
{
    RTStation *station = [self.bookmarks stationNamed:name inGroup:groupName];
    if (!station) {
        [[RTNotifier shared] notifyTitle:@"Errore" message:@"La stazione non è più nell'elenco"];
        return;
    }
    self.settings.lastGroup = groupName;
    self.settings.lastStation = name;
    [self playStation:station group:groupName];
}

/// group nil = indirizzo aperto con "Apri URL…" (non diventa l'ultima stazione ascoltata).
- (void)playStation:(RTStation *)station group:(NSString *)groupName
{
    NSString *name = station.name;
    self.currentGroup = groupName;
    self.currentStation = name;
    if (!groupName) self.adhocStation = station;
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

- (void)startCurrentStation
{
    RTStation *station = [self currentStationObject];
    if (!station) return;
    if (self.currentGroup) {
        [self playStationNamed:station.name inGroup:self.currentGroup];
    } else {
        [self playStation:station group:nil];
    }
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
    RTStation *s = [self currentStationObject];
    return s ? s.notifications : YES;
}

#pragma mark - RTPlayerDelegate

- (void)player:(RTPlayer *)player didChangeState:(RTPlayerState)state
{
    if (state == RTPlayerStatePlaying && !self.playingNotified) {
        self.playingNotified = YES;
        if (self.settings.notifications) {
            // per un indirizzo aperto a mano si aspetta un attimo il nome vero mandato dal server
            BOOL waitForName = !self.currentGroup && !self.adhocNamed;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((waitForName ? 1.5 : 0) * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (self.player.state == RTPlayerStatePlaying) {
                    [[RTNotifier shared] notifyTitle:self.currentStation ?: @"RadioTray" message:@"RadioTray"];
                }
            });
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

- (void)player:(RTPlayer *)player didReceiveStationName:(NSString *)name
{
    if (self.currentGroup || !self.adhocStation || self.adhocNamed) return;
    self.adhocNamed = YES;
    self.adhocStation.name = name;
    self.currentStation = name;
    [self refresh];
}

- (void)player:(RTPlayer *)player willReconnect:(NSUInteger)attempt error:(NSString *)error
{
    if (attempt == 1 && self.settings.notifications) {
        [[RTNotifier shared] notifyTitle:@"Connessione persa"
                                 message:[NSString stringWithFormat:@"%@: nuovo tentativo in corso…", self.currentStation ?: @"RadioTray"]];
    }
    self.playingNotified = YES;   // alla ripresa non si ripete la notifica della stazione
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

#pragma mark - RTMediaKeysDelegate

- (void)mediaKeysTogglePlay { [self togglePlay:nil]; }
- (void)mediaKeysPlay { if (self.player.state == RTPlayerStateStopped) [self startCurrentStation]; }
- (void)mediaKeysPause { if (self.player.state != RTPlayerStateStopped) [self stopPlayback]; }
- (void)mediaKeysNext { [self nextStation:nil]; }
- (void)mediaKeysPrevious { [self previousStation:nil]; }

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
    } else {
        [self startCurrentStation];
    }
}

- (void)stepStation:(NSInteger)delta
{
    NSUInteger index;
    NSArray<RTStation *> *stations = [self currentGroupStations:&index];
    if (index == NSNotFound) return;
    NSInteger target = (NSInteger)index + delta;
    if (target < 0 || target >= (NSInteger)stations.count) return;
    [self playStationNamed:stations[(NSUInteger)target].name inGroup:self.currentGroup];
}

- (void)previousStation:(id)sender { [self stepStation:-1]; }
- (void)nextStation:(id)sender { [self stepStation:+1]; }

- (void)volumeChanged:(NSSlider *)sender
{
    self.player.volume = sender.integerValue;
    self.settings.volume = self.player.volume;
    self.volumeValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)self.player.volume];
}

- (NSString *)favoritesPath
{
    return [[self.settings supportDirectory] stringByAppendingPathComponent:@"brani-preferiti.json"];
}

- (BOOL)currentTrackIsFavorite
{
    if (self.track.isEmpty) return NO;
    NSString *title = self.track.title.length ? self.track.title : self.track.artist;
    NSString *artist = self.track.title.length ? self.track.artist : @"";
    return [self.favorites trackWithTitle:title artist:artist] != nil;
}

- (void)addCurrentTrackToFavorites:(id)sender
{
    if (self.track.isEmpty) return;
    BOOL already = NO;
    RTFavoriteTrack *t = [self.favorites addTitle:self.track.title artist:self.track.artist
                                          station:self.currentStation ?: @"" date:[NSDate date] alreadyPresent:&already];
    if (!already) {
        NSError *error = nil;
        if (![[self.favorites dataRepresentation] writeToFile:[self favoritesPath] options:NSDataWritingAtomic error:&error]) {
            [self.favorites removeTracks:@[t]];
            [self showAlert:@"Brano non salvato" text:error.localizedDescription];
            return;
        }
        if (self.settings.notifications) {
            [[RTNotifier shared] notifyTitle:@"★ Aggiunto ai brani preferiti" message:t.displayText];
        }
    }
    [self.favoritesWindow reload];
    [self refresh];
}

- (void)openFavorites:(id)sender
{
    if (!self.favoritesWindow) {
        self.favoritesWindow = [[RTFavoritesWindowController alloc] initWithTracks:self.favorites path:[self favoritesPath]];
        self.favoritesWindow.delegate = self;
    } else {
        [self.favoritesWindow reload];
    }
    [self.favoritesWindow showAndFocus];
}

- (void)favoritesWindowDidChangeTracks
{
    [self refresh];
}

- (void)copyTrack:(id)sender
{
    if (self.track.isEmpty) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:self.track.clipboardText forType:NSPasteboardTypeString];
}

/// Finestra con un campo di testo; restituisce il testo inserito o nil se annullata.
- (NSString *)askText:(NSString *)title info:(NSString *)info value:(NSString *)value width:(CGFloat)width
{
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = info;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Annulla"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, width, 24)];
    field.stringValue = value ?: @"";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    return [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)openURL:(id)sender
{
    // proposta: l'URL negli appunti, se c'è, altrimenti l'ultimo aperto
    NSString *proposal = self.settings.lastOpenedURL;
    NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    clip = [clip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([clip.lowercaseString hasPrefix:@"http://"] || [clip.lowercaseString hasPrefix:@"https://"]) proposal = clip;

    NSString *text = [self askText:@"Apri URL"
                              info:@"Indirizzo di uno stream o di una playlist (PLS, M3U, ASX, XSPF):"
                             value:proposal width:380];
    if (!text.length) return;
    NSURL *url = [NSURL URLWithString:text];
    NSString *scheme = url.scheme.lowercaseString;
    if (!url || !url.host.length || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        [self showAlert:@"Indirizzo non valido" text:@"Serve un indirizzo che inizi con http:// o https://"];
        return;
    }
    self.settings.lastOpenedURL = text;
    self.adhocNamed = NO;
    RTStation *station = [RTStation new];
    station.name = url.host;
    station.url = text;
    [self playStation:station group:nil];
}

- (void)searchStations:(id)sender
{
    if (!self.searchWindow) {
        self.searchWindow = [RTSearchWindowController new];
        self.searchWindow.delegate = self;
    }
    [self.searchWindow showAndFocus];
}

- (void)searchWindowPlayStation:(NSString *)name url:(NSString *)url
{
    RTStation *station = [RTStation new];
    station.name = name;
    station.url = url;
    self.adhocNamed = YES;   // il nome dell'archivio è già quello giusto
    [self playStation:station group:nil];
}

- (void)searchWindowAddStation:(NSString *)name url:(NSString *)url
{
    [self askToAddStationNamed:name url:url];
}

- (void)addCurrentStation:(id)sender
{
    RTStation *station = self.adhocStation;
    if (self.currentGroup || !station) return;
    [self askToAddStationNamed:station.name url:station.url];
}

- (void)askToAddStationNamed:(NSString *)stationName url:(NSString *)stationURL
{
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Aggiungi alle stazioni";
    alert.informativeText = stationURL;
    [alert addButtonWithTitle:@"Aggiungi"];
    [alert addButtonWithTitle:@"Annulla"];

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 58)];
    NSTextField *nameLabel = [NSTextField labelWithString:@"Nome:"];
    nameLabel.frame = NSMakeRect(0, 36, 60, 18);
    nameLabel.alignment = NSTextAlignmentRight;
    [view addSubview:nameLabel];
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(66, 33, 274, 24)];
    nameField.stringValue = stationName;
    [view addSubview:nameField];

    NSTextField *groupLabel = [NSTextField labelWithString:@"Gruppo:"];
    groupLabel.frame = NSMakeRect(0, 5, 60, 18);
    groupLabel.alignment = NSTextAlignmentRight;
    [view addSubview:groupLabel];
    // si può scegliere un gruppo esistente o scriverne uno nuovo
    NSString *noGroup = @"(nessun gruppo)";
    NSComboBox *groupBox = [[NSComboBox alloc] initWithFrame:NSMakeRect(66, 0, 274, 26)];
    for (RTGroup *g in self.bookmarks.groups) {
        if (!g.isRoot) [groupBox addItemWithObjectValue:g.name];
    }
    [groupBox addItemWithObjectValue:noGroup];
    groupBox.completes = YES;
    groupBox.stringValue = self.settings.lastGroup.length && ![self.settings.lastGroup isEqualToString:RTRootGroupName]
                         ? self.settings.lastGroup : (self.bookmarks.groups.firstObject.isRoot ? noGroup : self.bookmarks.groups.firstObject.name ?: noGroup);
    [view addSubview:groupBox];

    alert.accessoryView = view;
    alert.window.initialFirstResponder = nameField;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *name = [nameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *group = [groupBox.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (group.length == 0 || [group isEqualToString:noGroup]) group = RTRootGroupName;
    if (name.length == 0) {
        [self showAlert:@"Stazione non aggiunta" text:@"Serve un nome per la stazione."];
        return;
    }

    NSString *path = self.settings.bookmarksPath;
    NSData *data = [NSData dataWithContentsOfFile:path] ?: [@"[]" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *error = nil;
    NSData *updated = [RTBookmarks dataByAddingStation:name url:stationURL toGroup:group inData:data error:&error];
    if (!updated) {
        [self showAlert:@"Stazione non aggiunta" text:error];
        return;
    }
    NSError *writeError = nil;
    if (![updated writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        [self showAlert:@"Stazione non aggiunta" text:writeError.localizedDescription];
        return;
    }
    RTBookmarks *b = [RTBookmarks bookmarksWithData:updated error:NULL];
    [self.bookmarksWatcher rememberCurrentContents];
    if (b) {
        self.bookmarks = b;
        [self buildMenu];
    }
    // se è quella in ascolto, da ora è una stazione come le altre (spunta nel menu, ultima stazione ascoltata)
    if (!self.currentGroup && [self.adhocStation.url isEqualToString:stationURL]) {
        self.currentGroup = group;
        self.currentStation = name;
        self.adhocStation = nil;
        self.settings.lastGroup = group;
        self.settings.lastStation = name;
    }
    if (self.settings.notifications) {
        NSString *where = [group isEqualToString:RTRootGroupName] ? @"senza gruppo" : [NSString stringWithFormat:@"nel gruppo «%@»", group];
        [[RTNotifier shared] notifyTitle:@"Stazione aggiunta" message:[NSString stringWithFormat:@"%@, %@", name, where]];
    }
    [self refresh];
}

- (void)sleepTimerChosen:(id)sender
{
    if (self.sleepTimer) {
        [self.sleepTimer invalidate];
        self.sleepTimer = nil;
        if (self.settings.notifications) [[RTNotifier shared] notifyTitle:@"Timer di spegnimento annullato" message:nil];
        [self refresh];
        return;
    }
    NSString *text = [self askText:@"Timer di spegnimento"
                              info:@"Dopo quanti minuti spegnere la radio?"
                             value:[NSString stringWithFormat:@"%ld", (long)self.settings.sleepTimerMinutes] width:80];
    if (!text) return;
    NSInteger minutes = text.integerValue;
    if (minutes < 1 || minutes > RTMaxSleepMinutes) {
        [self showAlert:@"Valore non valido" text:[NSString stringWithFormat:@"Inserisci un numero di minuti tra 1 e %ld.", (long)RTMaxSleepMinutes]];
        return;
    }
    self.settings.sleepTimerMinutes = minutes;
    self.sleepTimer = [NSTimer scheduledTimerWithTimeInterval:minutes * 60.0 target:self
                                                     selector:@selector(sleepTimerFired:) userInfo:nil repeats:NO];
    self.sleepTimer.tolerance = 5;
    if (self.settings.notifications) {
        [[RTNotifier shared] notifyTitle:@"Timer di spegnimento"
                                 message:[NSString stringWithFormat:@"La radio si spegnerà tra %ld minuti", (long)minutes]];
    }
    [self refresh];
}

- (void)sleepTimerFired:(NSTimer *)timer
{
    self.sleepTimer = nil;
    if (self.player.state != RTPlayerStateStopped) [self stopPlayback];
    if (self.settings.notifications) [[RTNotifier shared] notifyTitle:@"Timer di spegnimento" message:@"La radio è stata spenta"];
    [self refresh];
}

- (void)toggleLoginItem:(id)sender
{
    BOOL enable = ![RTLoginItem isEnabled];
    NSString *problem = [RTLoginItem setEnabled:enable appPath:[NSBundle mainBundle].bundlePath];
    if (problem) {
        [self showAlert:enable ? @"Avvio automatico non attivato" : @"Avvio automatico non disattivato" text:problem];
    } else if (self.settings.notifications) {
        [[RTNotifier shared] notifyTitle:enable ? @"Avvio automatico attivato" : @"Avvio automatico disattivato"
                                 message:enable ? @"RadioTray partirà da solo a ogni accesso" : nil];
    }
    [self refresh];
}

- (void)openStationEditor:(id)sender
{
    [self installDefaultBookmarksIfNeeded];
    if (!self.stationEditor) {
        self.stationEditor = [[RTStationEditorController alloc] initWithBookmarksPath:self.settings.bookmarksPath];
        self.stationEditor.delegate = self;
    } else {
        [self.stationEditor reloadFromDisk];
    }
    [self.stationEditor showAndFocus];
}

- (void)stationEditorDidSaveBookmarks
{
    // l'editor ha già scritto il file: si aggiorna il menu senza notifiche
    [self.bookmarksWatcher rememberCurrentContents];
    RTBookmarks *b = [RTBookmarks bookmarksWithContentsOfFile:self.settings.bookmarksPath error:NULL];
    if (!b) return;
    self.bookmarks = b;
    // la stazione scelta potrebbe essere stata rinominata o eliminata: si tiene solo se esiste ancora
    if (self.currentGroup && ![b stationNamed:self.currentStation ?: @"" inGroup:self.currentGroup] &&
        self.player.state == RTPlayerStateStopped) {
        self.currentGroup = nil;
        self.currentStation = nil;
    }
    [self buildMenu];
    [self refresh];
}

- (void)stationEditorPlayStation:(NSString *)name group:(NSString *)group
{
    [self playStationNamed:name inGroup:group];
}

- (void)stationEditorOpenJSON
{
    [self editBookmarks:nil];
}

- (void)editBookmarks:(id)sender
{
    [self installDefaultBookmarksIfNeeded];
    NSURL *file = [NSURL fileURLWithPath:self.settings.bookmarksPath];
    NSURL *textEdit = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
    BOOL opened = NO;
    if (textEdit) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        opened = [[NSWorkspace sharedWorkspace] openURLs:@[file] withApplicationAtURL:textEdit
                                                 options:NSWorkspaceLaunchDefault configuration:@{} error:NULL] != nil;
#pragma clang diagnostic pop
    }
    if (!opened) [[NSWorkspace sharedWorkspace] openURL:file];
}

- (void)revealBookmarks:(id)sender
{
    [self installDefaultBookmarksIfNeeded];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:self.settings.bookmarksPath]]];
}

- (void)addItalianStations:(id)sender
{
    NSString *listPath = [[NSBundle mainBundle] pathForResource:@"stazioni-italiane" ofType:@"json"];
    NSString *error = nil;
    RTBookmarks *list = listPath ? [RTBookmarks bookmarksWithContentsOfFile:listPath error:&error] : nil;
    if (!list) {
        [self showAlert:@"Elenco non disponibile" text:error ?: @"Il file delle radio italiane manca dall'app."];
        return;
    }
    [self installDefaultBookmarksIfNeeded];
    NSString *path = self.settings.bookmarksPath;
    NSData *data = [NSData dataWithContentsOfFile:path] ?: [@"[]" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger added = 0;
    NSData *updated = [RTBookmarks dataByMergingStations:list intoData:data added:&added error:&error];
    if (!updated) {
        [self showAlert:@"Stazioni non aggiunte" text:error];
        return;
    }
    if (added == 0) {
        [self showAlert:@"Nessuna stazione da aggiungere" text:@"Le radio italiane consigliate sono già tutte nelle tue stazioni."];
        return;
    }
    NSError *writeError = nil;
    if (![updated writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        [self showAlert:@"Stazioni non aggiunte" text:writeError.localizedDescription];
        return;
    }
    [self reloadBookmarksInteractive:YES];
    [[RTNotifier shared] notifyTitle:@"Radio italiane aggiunte"
                             message:[NSString stringWithFormat:@"%lu stazioni nei gruppi «Radio italiane» e «Rai»", (unsigned long)added]];
}

- (void)reloadBookmarks:(id)sender
{
    [self reloadBookmarksInteractive:YES];
}

/// interactive: richiesta dal menu (errori in una finestra); altrimenti dopo un salvataggio (errori in una notifica).
- (void)reloadBookmarksInteractive:(BOOL)interactive
{
    NSString *error = nil;
    RTBookmarks *b = [RTBookmarks bookmarksWithContentsOfFile:self.settings.bookmarksPath error:&error];
    if (interactive) [self.bookmarksWatcher rememberCurrentContents];
    if (!b) {
        if (interactive) {
            [self showAlert:@"Stazioni non ricaricate" text:[error stringByAppendingString:@"\n\nRimane in uso l'elenco precedente."]];
        } else {
            [[RTNotifier shared] notifyTitle:@"Errore nel file delle stazioni" message:error];
        }
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
