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
#import "RTHotKeys.h"
#import "RTUpdateChecker.h"
#import "RTArtwork.h"
#import "RTAlarm.h"
#import "RTBackup.h"
#import "RTAudioWatcher.h"
#import "RTNowPlayingWindowController.h"
#import "RTSettings.h"
#import "RTStatusIcon.h"
#import "RTStreamResolver.h"
#import "RTTrackInfo.h"

static const NSUInteger RTMenuLineLength = 48;
static const NSInteger RTMaxSleepMinutes = 24 * 60;

@interface RTAppDelegate () <NSMenuDelegate, RTPlayerDelegate, RTMediaKeysDelegate, RTSearchWindowDelegate, RTStationEditorDelegate, RTFavoritesWindowDelegate, RTNowPlayingDelegate, RTAudioWatcherDelegate>
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
@property (nonatomic, strong) RTFavoriteTracks *history;          // brani ascoltati di recente
@property (nonatomic, strong) NSMenuItem *historyItem;
@property (nonatomic, strong) RTHotKeys *hotKeys;
@property (nonatomic, copy) NSArray<NSString *> *hotKeyFailures;
@property (nonatomic, copy, nullable) NSString *availableUpdate;   // versione più recente trovata su GitHub
@property (nonatomic, strong, nullable) NSURL *availableUpdateURL;
@property (nonatomic, strong, nullable) id scrollMonitor;
@property (nonatomic) CGFloat scrollAccumulator;
@property (nonatomic, strong, nullable) NSImage *trackArtwork;     // copertina del brano in ascolto
@property (nonatomic, strong) NSTimer *ticker;                     // ogni 30 s: sveglia e tempo di ascolto
@property (nonatomic, strong, nullable) NSDate *lastTick;
@property (nonatomic, strong, nullable) NSTimer *fadeTimer;        // volume crescente della sveglia
@property (nonatomic, strong) NSMenuItem *alarmItem;
@property (nonatomic, strong, nullable) NSImage *trackArtworkFull;  // copertina grande, per la finestra
@property (nonatomic, strong) NSMenuItem *qualityItem;
@property (nonatomic, strong) NSMenuItem *nowPlayingItem;
@property (nonatomic, strong, nullable) RTNowPlayingWindowController *nowPlayingWindow;
@property (nonatomic, strong) RTAudioWatcher *audioWatcher;
@property (nonatomic) BOOL pausedByLock;
@property (nonatomic) BOOL pausedByHeadphones;

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

    self.history = [RTFavoriteTracks tracksWithContentsOfFile:[self historyPath] error:NULL] ?: [RTFavoriteTracks new];

    // pulsante "★ Preferito" nelle notifiche dei brani
    __weak typeof(self) weakSelf2 = self;
    [RTNotifier shared].favoriteHandler = ^(NSDictionary<NSString *, NSString *> *track) {
        [weakSelf2 addFavoriteTitle:track[@"title"] ?: @"" artist:track[@"artist"] ?: @"" station:track[@"station"] ?: @""];
    };

    self.hotKeys = [RTHotKeys new];
    self.hotKeyFailures = @[];
    [self applyHotKeys];
    [self installScrollWheelVolume];
    [self checkForUpdatesManually:NO];

    // ogni 30 secondi: radiosveglia e tempo di ascolto delle stazioni
    self.lastTick = [NSDate date];
    self.ticker = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    self.ticker.tolerance = 5;
    [self tick:nil];

    self.audioWatcher = [RTAudioWatcher new];
    self.audioWatcher.delegate = self;
    [self.audioWatcher start];
    if (self.settings.nowPlayingVisible) [self showNowPlaying:NO];

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

    if (self.availableUpdate) {
        NSMenuItem *update = [self addItem:[NSString stringWithFormat:@"⬆︎ Scarica RadioTray %@…", self.availableUpdate]
                                    action:@selector(openUpdatePage:) to:self.menu];
        update.toolTip = @"È disponibile una versione più recente";
        [self.menu addItem:[NSMenuItem separatorItem]];
    }
    self.trackItem = [self addItem:@"Fermo" action:@selector(copyTrack:) to:self.menu];
    self.actionItem = [self addItem:@"Accendi" action:@selector(togglePlay:) to:self.menu];
    self.volumeItem = [self buildVolumeItem];
    [self.menu addItem:self.volumeItem];
    self.qualityItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    self.qualityItem.enabled = NO;
    self.qualityItem.indentationLevel = 1;
    [self.menu addItem:self.qualityItem];
    [self.menu addItem:[NSMenuItem separatorItem]];

    // le stazioni più ascoltate, sempre a portata di mano
    NSArray<NSArray<NSString *> *> *top = [self mostPlayedStations:5];
    if (top.count) {
        NSMenuItem *header = [self addItem:@"Più ascoltate" action:NULL to:self.menu];
        header.enabled = NO;
        for (NSArray<NSString *> *key in top) {
            RTGroup *g = [self.bookmarks groupNamed:key[0]];
            RTStation *st = [self.bookmarks stationNamed:key[1] inGroup:key[0]];
            NSMenuItem *item = [self stationItem:st group:g];
            item.indentationLevel = 1;
            double hours = [self.settings.listeningSeconds[[self listeningKeyForGroup:key[0] station:key[1]]] doubleValue] / 3600.0;
            item.toolTip = [NSString stringWithFormat:@"%@ · ascoltata per %@", g.isRoot ? @"senza gruppo" : g.name,
                            hours >= 1 ? [NSString stringWithFormat:@"%.0f ore", hours]
                                       : [NSString stringWithFormat:@"%.0f minuti", hours * 60]];
            [self.menu addItem:item];
        }
        [self.menu addItem:[NSMenuItem separatorItem]];
    }

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
    self.nowPlayingItem = [self addItem:@"Finestra In riproduzione" action:@selector(toggleNowPlaying:) to:self.menu];
    self.historyItem = [[NSMenuItem alloc] initWithTitle:@"Ascoltati di recente" action:NULL keyEquivalent:@""];
    [self.menu addItem:self.historyItem];
    [self addItem:@"Apri URL…" action:@selector(openURL:) to:self.menu];
    self.addStationItem = [self addItem:@"Aggiungi alle stazioni…" action:@selector(addCurrentStation:) to:self.menu];
    self.sleepItem = [self addItem:@"Timer di spegnimento…" action:@selector(sleepTimerChosen:) to:self.menu];
    self.alarmItem = [self addItem:@"Radiosveglia…" action:@selector(configureAlarm:) to:self.menu];
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
    [self addItem:@"Scorciatoie da tastiera (⌃⌥)" action:@selector(toggleHotKeys:) to:prefsMenu].tag = 6;
    NSMenuItem *keysInfo = [[NSMenuItem alloc] initWithTitle:@"Elenco delle scorciatoie" action:NULL keyEquivalent:@""];
    NSMenu *keysMenu = [[NSMenu alloc] initWithTitle:@"Scorciatoie"];
    keysMenu.autoenablesItems = NO;
    for (NSString *d in [RTHotKeys descriptions]) {
        NSMenuItem *k = [keysMenu addItemWithTitle:d action:NULL keyEquivalent:@""];
        k.enabled = NO;
        k.tag = 1;
    }
    NSMenuItem *wheel = [keysMenu addItemWithTitle:@"Rotella sull'icona   Volume" action:NULL keyEquivalent:@""];
    wheel.enabled = NO;
    keysInfo.submenu = keysMenu;
    keysInfo.tag = 7;
    [prefsMenu addItem:keysInfo];
    [self addItem:@"Controlla gli aggiornamenti automaticamente" action:@selector(toggleUpdateCheck:) to:prefsMenu].tag = 8;
    [prefsMenu addItem:[NSMenuItem separatorItem]];
    [self addItem:@"Titolo del brano nella barra dei menu" action:@selector(toggleTitleInBar:) to:prefsMenu].tag = 9;
    [self addItem:@"Copertine degli album" action:@selector(toggleArtwork:) to:prefsMenu].tag = 10;
    [self addItem:@"Azzera le stazioni più ascoltate" action:@selector(resetListening:) to:prefsMenu];

    [prefsMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *pauseItem = [[NSMenuItem alloc] initWithTitle:@"Pausa automatica" action:NULL keyEquivalent:@""];
    NSMenu *pauseMenu = [[NSMenu alloc] initWithTitle:@"Pausa automatica"];
    pauseMenu.autoenablesItems = NO;
    [self addItem:@"Quando blocchi lo schermo" action:@selector(togglePauseOnLock:) to:pauseMenu].tag = 11;
    [self addItem:@"Quando stacchi le cuffie" action:@selector(togglePauseOnHeadphones:) to:pauseMenu].tag = 12;
    [pauseMenu addItem:[NSMenuItem separatorItem]];
    [self addItem:@"Riprendi quando torni (sblocco, cuffie)" action:@selector(toggleResume:) to:pauseMenu].tag = 13;
    pauseItem.submenu = pauseMenu;
    pauseItem.tag = 15;
    [prefsMenu addItem:pauseItem];

    NSMenuItem *backupItem = [[NSMenuItem alloc] initWithTitle:@"Backup" action:NULL keyEquivalent:@""];
    NSMenu *backupMenu = [[NSMenu alloc] initWithTitle:@"Backup"];
    backupMenu.autoenablesItems = NO;
    [self addItem:@"Esporta un backup…" action:@selector(exportBackup:) to:backupMenu];
    [self addItem:@"Importa un backup…" action:@selector(importBackup:) to:backupMenu];
    [backupMenu addItem:[NSMenuItem separatorItem]];
    [self addItem:@"Backup automatico su iCloud Drive (ogni giorno)" action:@selector(toggleICloudBackup:) to:backupMenu].tag = 14;
    [self addItem:@"Mostra i backup su iCloud Drive" action:@selector(revealICloudBackups:) to:backupMenu].tag = 16;
    backupItem.submenu = backupMenu;
    backupItem.tag = 17;
    [prefsMenu addItem:backupItem];
    [self addItem:@"Controlla gli aggiornamenti ora" action:@selector(checkUpdatesNow:) to:prefsMenu];
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
    [self updateMenuBarTitle];
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
    self.trackItem.image = (state == RTPlayerStatePlaying && !self.track.isEmpty) ? self.trackArtwork : nil;
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
    [prefs itemWithTag:6].state = self.settings.hotKeys ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:6].toolTip = self.hotKeyFailures.count
        ? [NSString stringWithFormat:@"Già usate da un'altra app:\n%@", [self.hotKeyFailures componentsJoinedByString:@"\n"]] : nil;
    [prefs itemWithTag:8].state = self.settings.checkForUpdates ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:9].state = self.settings.titleInMenuBar ? NSControlStateValueOn : NSControlStateValueOff;
    [prefs itemWithTag:10].state = self.settings.artwork ? NSControlStateValueOn : NSControlStateValueOff;

    // radiosveglia
    if (self.settings.alarmEnabled && self.settings.alarmStation) {
        self.alarmItem.title = [NSString stringWithFormat:@"Radiosveglia: %@ %@…", [RTAlarm describeMinutes:self.settings.alarmMinutes],
                                [RTAlarm describeDays:self.settings.alarmDays]];
        self.alarmItem.state = NSControlStateValueOn;
        self.alarmItem.toolTip = [NSString stringWithFormat:@"Stazione: %@", self.settings.alarmStation];
    } else {
        self.alarmItem.title = @"Radiosveglia…";
        self.alarmItem.state = NSControlStateValueOff;
        self.alarmItem.toolTip = nil;
    }

    NSMenu *pauseMenu = [prefs itemWithTag:15].submenu;
    [pauseMenu itemWithTag:11].state = self.settings.pauseOnLock ? NSControlStateValueOn : NSControlStateValueOff;
    [pauseMenu itemWithTag:12].state = self.settings.pauseOnHeadphones ? NSControlStateValueOn : NSControlStateValueOff;
    [pauseMenu itemWithTag:13].state = self.settings.resumeAfterPause ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenu *backupMenu = [prefs itemWithTag:17].submenu;
    BOOL hasICloud = [RTBackup iCloudFolder] != nil;
    [backupMenu itemWithTag:14].state = self.settings.iCloudBackup && hasICloud ? NSControlStateValueOn : NSControlStateValueOff;
    [backupMenu itemWithTag:14].enabled = hasICloud;
    [backupMenu itemWithTag:14].toolTip = hasICloud ? @"Copia in iCloud Drive ▸ RadioTray; si tengono gli ultimi 10 giorni"
                                                    : @"iCloud Drive non è attivo su questo Mac";
    [backupMenu itemWithTag:16].enabled = hasICloud;

    // qualità dello stream, sotto il volume
    NSString *quality = [self qualityText];
    self.qualityItem.hidden = !(state == RTPlayerStatePlaying && quality);
    if (quality) {
        self.qualityItem.attributedTitle = [[NSAttributedString alloc] initWithString:quality attributes:@{
            NSFontAttributeName: [NSFont menuFontOfSize:[NSFont smallSystemFontSize]],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor] }];
    }
    self.nowPlayingItem.state = self.nowPlayingWindow.window.isVisible ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateNowPlaying];

    [self rebuildHistoryMenu];

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
    self.trackArtwork = nil;
    self.trackArtworkFull = nil;
    NSString *station = self.currentStation ?: @"";
    if ([self.history recordTitle:info.title artist:info.artist station:station date:[NSDate date] limit:50]) {
        [[self.history dataRepresentation] writeToFile:[self historyPath] atomically:YES];
    }
    BOOL notify = self.settings.notifications && [self stationWantsNotifications];
    if (!self.settings.artwork || !info.title.length || !info.artist.length) {
        if (notify) [self notifyTrack:info station:station image:nil];
        [self refresh];
        return;
    }
    // si aspetta la copertina al massimo 2 secondi, poi la notifica parte comunque
    __block BOOL notified = NO;
    __weak typeof(self) weakSelf = self;
    void (^deliver)(NSImage *) = ^(NSImage *image) {
        if (notified || !notify) return;
        notified = YES;
        [weakSelf notifyTrack:info station:station image:image];
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ deliver(nil); });
    [[RTArtwork shared] artworkForTitle:info.title artist:info.artist completion:^(NSData *data) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.track isEqualToInfo:info]) return;   // nel frattempo è cambiato brano
        NSImage *image = data ? [[NSImage alloc] initWithData:data] : nil;
        if (image) {
            strongSelf.trackArtwork = [strongSelf menuThumbnail:image];
            strongSelf.trackArtworkFull = image;
            [strongSelf refresh];
        }
        deliver(image);
    }];
    [self refresh];
}

- (void)notifyTrack:(RTTrackInfo *)info station:(NSString *)station image:(NSImage *)image
{
    NSDictionary *trackInfo = @{ @"title": info.title, @"artist": info.artist, @"station": station };
    BOOL favorite = [self.favorites trackWithTitle:info.title.length ? info.title : info.artist
                                            artist:info.title.length ? info.artist : @""] != nil;
    NSString *t = info.title.length ? info.title : info.artist;
    NSString *message = info.title.length && info.artist.length ? info.artist : station;
    // già tra i preferiti: una ★ nel titolo e niente pulsante
    [[RTNotifier shared] notifyTrackTitle:favorite ? [@"★ " stringByAppendingString:t] : t message:message
                                    track:trackInfo image:image withButton:!favorite];
}

/// Copertina piccola con gli angoli arrotondati, per il menu.
- (NSImage *)menuThumbnail:(NSImage *)image
{
    NSSize size = NSMakeSize(40, 40);
    return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4] addClip];
        [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
        return YES;
    }];
}

- (void)player:(RTPlayer *)player didUpdateStreamFormat:(NSString *)format bitrate:(NSInteger)kbps
{
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
    [self addFavoriteTitle:self.track.title artist:self.track.artist station:self.currentStation ?: @""];
}

/// Aggiunge un brano ai preferiti (dal menu, dalla cronologia, dalla notifica o da ⌃⌥F).
- (void)addFavoriteTitle:(NSString *)title artist:(NSString *)artist station:(NSString *)station
{
    if (title.length == 0 && artist.length == 0) return;
    BOOL already = NO;
    RTFavoriteTrack *t = [self.favorites addTitle:title artist:artist station:station date:[NSDate date] alreadyPresent:&already];
    if (already) {
        if (self.settings.notifications) [[RTNotifier shared] notifyTitle:@"★ Già nei brani preferiti" message:t.displayText];
    } else {
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

#pragma mark - Ascoltati di recente

- (NSString *)historyPath
{
    return [[self.settings supportDirectory] stringByAppendingPathComponent:@"ascoltati-di-recente.json"];
}

- (void)rebuildHistoryMenu
{
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@"Ascoltati di recente"];
    sub.autoenablesItems = NO;
    NSArray<RTFavoriteTrack *> *recent = self.history.tracks;
    if (recent.count == 0) {
        [self addItem:@"Nessun brano ancora" action:NULL to:sub].enabled = NO;
    } else {
        NSMenuItem *hint = [self addItem:@"Clic su un brano per aggiungerlo ai preferiti" action:NULL to:sub];
        hint.enabled = NO;
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm";
        NSUInteger shown = 0;
        for (RTFavoriteTrack *t in recent.reverseObjectEnumerator) {   // prima i più recenti
            if (shown++ >= 20) break;
            BOOL favorite = [self.favorites trackWithTitle:t.title artist:t.artist] != nil;
            NSString *title = [NSString stringWithFormat:@"%@%@", favorite ? @"★ " : @"", RTTruncate(t.displayText, 60)];
            NSMenuItem *item = [self addItem:title action:@selector(historyTrackChosen:) to:sub];
            item.representedObject = t;
            item.toolTip = [NSString stringWithFormat:@"%@, %@", t.station, [df stringFromDate:t.added]];
            item.enabled = !favorite;
        }
        [sub addItem:[NSMenuItem separatorItem]];
        [self addItem:@"Cancella la cronologia" action:@selector(clearHistory:) to:sub];
    }
    self.historyItem.submenu = sub;
}

- (void)historyTrackChosen:(NSMenuItem *)sender
{
    RTFavoriteTrack *t = sender.representedObject;
    if (t) [self addFavoriteTitle:t.title artist:t.artist station:t.station];
}

- (void)clearHistory:(id)sender
{
    [self.history removeAllTracks];
    [[NSFileManager defaultManager] removeItemAtPath:[self historyPath] error:NULL];
    [self refresh];
}

#pragma mark - Scorciatoie e rotella

- (void)applyHotKeys
{
    [self.hotKeys unregister];
    self.hotKeyFailures = @[];
    if (!self.settings.hotKeys) return;
    __weak typeof(self) weakSelf = self;
    self.hotKeyFailures = [self.hotKeys registerWithHandler:^(RTHotKey key) {
        [weakSelf hotKeyPressed:key];
    }];
    if (self.hotKeyFailures.count) {
        NSLog(@"RadioTray: scorciatoie già usate da un'altra app: %@", self.hotKeyFailures);
    }
}

- (void)hotKeyPressed:(RTHotKey)key
{
    switch (key) {
        case RTHotKeyTogglePlay:      [self togglePlay:nil]; break;
        case RTHotKeyNextStation:     [self nextStation:nil]; break;
        case RTHotKeyPreviousStation: [self previousStation:nil]; break;
        case RTHotKeyVolumeUp:        [self changeVolumeBy:+5 notify:YES]; break;
        case RTHotKeyVolumeDown:      [self changeVolumeBy:-5 notify:YES]; break;
        case RTHotKeyFavorite:
            if (self.player.state == RTPlayerStatePlaying && !self.track.isEmpty) {
                [self addCurrentTrackToFavorites:nil];
            } else {
                NSBeep();
            }
            break;
    }
}

- (void)changeVolumeBy:(NSInteger)delta notify:(BOOL)notify
{
    NSInteger before = self.player.volume;
    self.player.volume = before + delta;
    self.settings.volume = self.player.volume;
    if (notify && self.player.volume != before) {
        [[RTNotifier shared] notifyTitle:[NSString stringWithFormat:@"Volume %ld%%", (long)self.player.volume] message:nil];
    }
    [self refresh];
}

- (void)toggleHotKeys:(id)sender
{
    self.settings.hotKeys = !self.settings.hotKeys;
    [self applyHotKeys];
    if (self.settings.hotKeys && self.hotKeyFailures.count) {
        [self showAlert:@"Alcune scorciatoie non sono disponibili"
                   text:[NSString stringWithFormat:@"Sono già usate da un'altra app:\n\n%@",
                         [self.hotKeyFailures componentsJoinedByString:@"\n"]]];
    }
    [self refresh];
}

/// Rotella del mouse (o due dita sul trackpad) sopra l'icona nella barra dei menu: volume.
- (void)installScrollWheelVolume
{
    __weak typeof(self) weakSelf = self;
    self.scrollMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel handler:^NSEvent *(NSEvent *event) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || event.window != strongSelf.statusItem.button.window) return event;
        CGFloat dy = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX;
        if (event.isDirectionInvertedFromDevice) dy = -dy;   // "scorrimento naturale": su = più volume
        if (event.hasPreciseScrollingDeltas) {
            // trackpad: si accumula, 1% ogni 4 punti
            strongSelf.scrollAccumulator += dy;
            NSInteger steps = (NSInteger)(strongSelf.scrollAccumulator / 4.0);
            if (steps != 0) {
                strongSelf.scrollAccumulator -= steps * 4.0;
                [strongSelf changeVolumeBy:steps notify:NO];
            }
        } else if (dy != 0) {
            [strongSelf changeVolumeBy:dy > 0 ? 2 : -2 notify:NO];   // rotella: 2% per scatto
        }
        strongSelf.statusItem.button.toolTip = [NSString stringWithFormat:@"Volume %ld%%", (long)strongSelf.player.volume];
        return nil;
    }];
}

#pragma mark - Aggiornamenti

- (void)checkForUpdatesManually:(BOOL)manual
{
    if (!manual) {
        if (!self.settings.checkForUpdates) return;
        NSDate *last = self.settings.lastUpdateCheck;
        if (last && -last.timeIntervalSinceNow < 24 * 60 * 60) return;   // al massimo una volta al giorno
    }
    NSString *current = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
    [RTUpdateChecker checkWithCurrentVersion:current completion:^(NSString *newVersion, NSURL *pageURL, NSString *error) {
        if (!error) self.settings.lastUpdateCheck = [NSDate date];
        if (newVersion) {
            BOOL isNew = ![newVersion isEqualToString:self.availableUpdate ?: @""];
            self.availableUpdate = newVersion;
            self.availableUpdateURL = pageURL;
            [self buildMenu];
            [self refresh];
            if (isNew || manual) {
                [[RTNotifier shared] notifyTitle:[NSString stringWithFormat:@"È disponibile RadioTray %@", newVersion]
                                         message:[NSString stringWithFormat:@"Stai usando la %@. Clic per scaricarla.", current]
                                         openURL:pageURL];
            }
        } else if (manual) {
            if (error) {
                [self showAlert:@"Controllo non riuscito" text:error];
            } else {
                [[RTNotifier shared] notifyTitle:@"RadioTray è aggiornato"
                                         message:[NSString stringWithFormat:@"La %@ è la versione più recente.", current]];
            }
        }
    }];
}

- (void)checkUpdatesNow:(id)sender { [self checkForUpdatesManually:YES]; }

- (void)toggleUpdateCheck:(id)sender
{
    self.settings.checkForUpdates = !self.settings.checkForUpdates;
    if (self.settings.checkForUpdates) [self checkForUpdatesManually:NO];
    [self refresh];
}

- (void)openUpdatePage:(id)sender
{
    if (self.availableUpdateURL) [[NSWorkspace sharedWorkspace] openURL:self.availableUpdateURL];
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

#pragma mark - Titolo nella barra, copertine

- (void)updateMenuBarTitle
{
    NSStatusBarButton *button = self.statusItem.button;
    BOOL show = self.settings.titleInMenuBar && self.player.state == RTPlayerStatePlaying && !self.track.isEmpty;
    if (show) {
        NSString *text = self.track.artist.length && self.track.title.length
            ? [NSString stringWithFormat:@"%@ – %@", self.track.artist, self.track.title]
            : (self.track.title.length ? self.track.title : self.track.artist);
        button.title = [@" " stringByAppendingString:RTTruncate(text, 40)];
        button.imagePosition = NSImageLeft;
        self.statusItem.length = NSVariableStatusItemLength;
    } else {
        button.title = @"";
        button.imagePosition = NSImageOnly;
        self.statusItem.length = NSSquareStatusItemLength;
    }
}

- (void)toggleTitleInBar:(id)sender
{
    self.settings.titleInMenuBar = !self.settings.titleInMenuBar;
    [self refresh];
}

- (void)toggleArtwork:(id)sender
{
    self.settings.artwork = !self.settings.artwork;
    if (!self.settings.artwork) self.trackArtwork = nil;
    [self refresh];
}

#pragma mark - Tempo di ascolto e stazioni più ascoltate

- (NSString *)listeningKeyForGroup:(NSString *)group station:(NSString *)station
{
    return [NSString stringWithFormat:@"%@\n%@", group, station];
}

/// Fino a n stazioni (ancora tra i preferiti) ascoltate almeno 10 minuti, dalla più ascoltata: [gruppo, nome].
- (NSArray<NSArray<NSString *> *> *)mostPlayedStations:(NSUInteger)n
{
    NSDictionary<NSString *, NSNumber *> *seconds = self.settings.listeningSeconds;
    NSArray *keys = [seconds keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in keys) {
        if (out.count >= n) break;
        if (seconds[key].doubleValue < 600) break;
        NSArray *parts = [key componentsSeparatedByString:@"\n"];
        if (parts.count != 2 || ![self.bookmarks stationNamed:parts[1] inGroup:parts[0]]) continue;
        [out addObject:parts];
    }
    return out;
}

- (void)tick:(NSTimer *)timer
{
    NSDate *now = [NSDate date];
    NSTimeInterval elapsed = self.lastTick ? [now timeIntervalSinceDate:self.lastTick] : 0;
    self.lastTick = now;

    // tempo di ascolto (solo stazioni dei preferiti; salti lunghi = Mac in stop, non contano)
    if (self.player.state == RTPlayerStatePlaying && self.currentGroup && self.currentStation && elapsed > 0 && elapsed < 120) {
        NSMutableDictionary *seconds = [self.settings.listeningSeconds mutableCopy];
        NSString *key = [self listeningKeyForGroup:self.currentGroup station:self.currentStation];
        NSArray *before = [self mostPlayedStations:5];
        seconds[key] = @([seconds[key] doubleValue] + elapsed);
        self.settings.listeningSeconds = seconds;
        if (![[self mostPlayedStations:5] isEqualToArray:before]) [self buildMenu];
    }

    // backup giornaliero su iCloud Drive
    if (self.settings.iCloudBackup && [RTBackup iCloudFolder] &&
        (!self.settings.lastBackup || -self.settings.lastBackup.timeIntervalSinceNow > 24 * 60 * 60)) {
        NSString *problem = [RTBackup writeBackup:[RTBackup dataForContents:[self currentBackupContents]]
                                         toFolder:[RTBackup iCloudFolder] keep:10 date:now];
        if (problem) NSLog(@"RadioTray: backup su iCloud Drive non riuscito: %@", problem);
        else self.settings.lastBackup = now;
    }

    // radiosveglia
    if (self.settings.alarmEnabled && self.settings.alarmStation &&
        [RTAlarm shouldFireAt:now minutes:self.settings.alarmMinutes days:self.settings.alarmDays
                    lastFired:self.settings.alarmLastFired calendar:[NSCalendar currentCalendar]]) {
        self.settings.alarmLastFired = now;
        [self fireAlarm];
    }
}

- (void)resetListening:(id)sender
{
    self.settings.listeningSeconds = @{};
    [self buildMenu];
    [self refresh];
}

#pragma mark - Qualità dello stream

- (NSString *)qualityText
{
    NSString *format = self.player.streamFormat;
    NSInteger kbps = self.player.streamBitrate;
    if (!format && kbps <= 0) return nil;
    if (format && kbps > 0) return [NSString stringWithFormat:@"%@ · %ld kbps", format, (long)kbps];
    return format ?: [NSString stringWithFormat:@"%ld kbps", (long)kbps];
}

#pragma mark - Finestra "In riproduzione"

- (void)showNowPlaying:(BOOL)activate
{
    if (!self.nowPlayingWindow) {
        self.nowPlayingWindow = [[RTNowPlayingWindowController alloc] initFloating:self.settings.nowPlayingFloating];
        self.nowPlayingWindow.delegate = self;
    }
    self.settings.nowPlayingVisible = YES;
    [self updateNowPlaying];
    if (activate) {
        [NSApp activateIgnoringOtherApps:YES];
        [self.nowPlayingWindow showWindow:nil];
    } else {
        [self.nowPlayingWindow showWithoutActivating];
    }
    [self refresh];
}

- (void)toggleNowPlaying:(id)sender
{
    if (self.nowPlayingWindow.window.isVisible) {
        [self.nowPlayingWindow close];   // windowWillClose → nowPlayingClosed
    } else {
        [self showNowPlaying:YES];
    }
}

- (void)updateNowPlaying
{
    if (!self.nowPlayingWindow.window.isVisible && !self.settings.nowPlayingVisible) return;
    RTPlayerState state = self.player.state;
    BOOL active = state != RTPlayerStateStopped, playing = state == RTPlayerStatePlaying;
    NSString *title, *artist = nil;
    if (playing && !self.track.isEmpty) {
        title = self.track.title.length ? self.track.title : self.track.artist;
        artist = self.track.title.length ? self.track.artist : nil;
    } else if (playing) {
        title = @"In riproduzione";
    } else if (active) {
        title = @"Connessione in corso…";
    } else {
        title = self.currentStation ? @"Radio spenta" : @"Scegli una stazione dal menu";
    }
    NSUInteger index;
    NSArray *stations = [self currentGroupStations:&index];
    [self.nowPlayingWindow updateTitle:title artist:artist station:self.currentStation
                               quality:playing ? [self qualityText] : nil
                               artwork:playing ? self.trackArtworkFull : nil playing:playing active:active
                              favorite:playing && [self currentTrackIsFavorite]
                           canFavorite:playing && !self.track.isEmpty
                           hasPrevious:index != NSNotFound && index > 0
                               hasNext:index != NSNotFound && index + 1 < stations.count
                                volume:self.player.volume];
}

- (void)nowPlayingPrevious { [self previousStation:nil]; }
- (void)nowPlayingNext { [self nextStation:nil]; }
- (void)nowPlayingTogglePlay { [self togglePlay:nil]; }
- (void)nowPlayingFavorite { [self addCurrentTrackToFavorites:nil]; }

- (void)nowPlayingVolumeChanged:(NSInteger)volume
{
    self.player.volume = volume;
    self.settings.volume = self.player.volume;
    [self refresh];
}

- (void)nowPlayingFloatingChanged:(BOOL)floating
{
    self.settings.nowPlayingFloating = floating;
}

- (void)nowPlayingClosed
{
    self.settings.nowPlayingVisible = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

#pragma mark - Pausa automatica

- (void)pauseForReason:(NSString *)reason
{
    if (self.player.state == RTPlayerStateStopped) return;
    [self stopPlayback];
    if (self.settings.notifications) [[RTNotifier shared] notifyTitle:@"Radio in pausa" message:reason];
}

- (void)audioWatcherScreenLocked
{
    if (!self.settings.pauseOnLock || self.player.state == RTPlayerStateStopped) return;
    self.pausedByLock = YES;
    [self stopPlayback];
}

- (void)audioWatcherScreenUnlocked
{
    if (!self.pausedByLock) return;
    self.pausedByLock = NO;
    if (self.settings.resumeAfterPause && self.player.state == RTPlayerStateStopped) {
        // si lascia alla rete un attimo per tornare su
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.player.state == RTPlayerStateStopped) [self startCurrentStation];
        });
    }
}

- (void)audioWatcherHeadphonesRemoved
{
    if (!self.settings.pauseOnHeadphones || self.player.state == RTPlayerStateStopped) return;
    self.pausedByHeadphones = YES;
    [self pauseForReason:@"Cuffie staccate: l'audio non esce dagli altoparlanti"];
}

- (void)audioWatcherHeadphonesConnected
{
    if (!self.pausedByHeadphones) return;
    self.pausedByHeadphones = NO;
    if (self.settings.resumeAfterPause && self.player.state == RTPlayerStateStopped) [self startCurrentStation];
}

- (void)togglePauseOnLock:(id)sender { self.settings.pauseOnLock = !self.settings.pauseOnLock; [self refresh]; }
- (void)togglePauseOnHeadphones:(id)sender { self.settings.pauseOnHeadphones = !self.settings.pauseOnHeadphones; [self refresh]; }
- (void)toggleResume:(id)sender { self.settings.resumeAfterPause = !self.settings.resumeAfterPause; [self refresh]; }

#pragma mark - Backup

- (RTBackupContents *)currentBackupContents
{
    RTBackupContents *c = [RTBackupContents new];
    c.bookmarks = [NSData dataWithContentsOfFile:self.settings.bookmarksPath];
    c.favorites = [self.favorites dataRepresentation];
    c.history = [self.history dataRepresentation];
    NSString *domain = [NSBundle mainBundle].bundleIdentifier ?: @"io.github.paselsoft.radiotray-mac";
    c.settings = [RTBackup exportableSettings:[[NSUserDefaults standardUserDefaults] persistentDomainForName:domain] ?: @{}];
    c.appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    c.created = [NSDate date];
    return c;
}

- (void)exportBackup:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"yyyy-MM-dd";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"RadioTray backup %@.json", [df stringFromDate:[NSDate date]]];
    panel.message = @"Stazioni, brani preferiti, ascoltati di recente e impostazioni in un solo file";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *error = nil;
    if (![[RTBackup dataForContents:[self currentBackupContents]] writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
        [self showAlert:@"Backup non riuscito" text:error.localizedDescription];
        return;
    }
    if (self.settings.notifications) [[RTNotifier shared] notifyTitle:@"Backup salvato" message:panel.URL.lastPathComponent];
}

- (void)importBackup:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.message = @"Scegli un backup di RadioTray (.json)";
    NSString *folder = [RTBackup iCloudFolder];
    if (folder && [[NSFileManager defaultManager] fileExistsAtPath:folder]) panel.directoryURL = [NSURL fileURLWithPath:folder];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;

    NSString *error = nil;
    RTBackupContents *c = [RTBackup contentsFromData:[NSData dataWithContentsOfURL:panel.URL] ?: [NSData data] error:&error];
    if (!c) {
        [self showAlert:@"Backup non importato" text:error];
        return;
    }
    RTBookmarks *bm = c.bookmarks ? [RTBookmarks bookmarksWithData:c.bookmarks error:NULL] : nil;
    RTFavoriteTracks *fav = c.favorites ? [RTFavoriteTracks tracksWithData:c.favorites error:NULL] : nil;
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];
    df.dateStyle = NSDateFormatterLongStyle;
    df.timeStyle = NSDateFormatterShortStyle;

    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Importa il backup";
    alert.informativeText = [NSString stringWithFormat:
        @"Backup del %@: %lu stazioni, %lu brani preferiti.

"
        @"«Unisci» aggiunge stazioni e preferiti che mancano e lascia il resto com'è.
"
        @"«Sostituisci tutto» rimette stazioni, preferiti, cronologia e impostazioni come nel backup "
        @"(prima viene salvata una copia dello stato attuale).",
        c.created ? [df stringFromDate:c.created] : @"data sconosciuta",
        (unsigned long)bm.stationCount, (unsigned long)fav.tracks.count];
    [alert addButtonWithTitle:@"Unisci"];
    [alert addButtonWithTitle:@"Sostituisci tutto"];
    [alert addButtonWithTitle:@"Annulla"];
    NSModalResponse choice = [alert runModal];
    if (choice == NSAlertThirdButtonReturn) return;

    NSString *path = self.settings.bookmarksPath;
    if (choice == NSAlertFirstButtonReturn) {
        // unione
        NSUInteger addedStations = 0, addedTracks = 0;
        if (bm) {
            NSData *current = [NSData dataWithContentsOfFile:path] ?: [@"[]" dataUsingEncoding:NSUTF8StringEncoding];
            NSData *merged = [RTBookmarks dataByMergingStations:bm intoData:current added:&addedStations error:&error];
            if (!merged) {
                [self showAlert:@"Stazioni non unite" text:error];
                return;
            }
            if (addedStations) [merged writeToFile:path atomically:YES];
        }
        for (RTFavoriteTrack *t in fav.tracks) {
            BOOL already = NO;
            [self.favorites addTitle:t.title artist:t.artist station:t.station date:t.added alreadyPresent:&already];
            if (!already) addedTracks++;
        }
        if (addedTracks) [[self.favorites dataRepresentation] writeToFile:[self favoritesPath] atomically:YES];
        [self reloadAfterImport];
        [self showAlert:@"Backup importato"
                   text:[NSString stringWithFormat:@"Aggiunte %lu stazioni e %lu brani preferiti.",
                         (unsigned long)addedStations, (unsigned long)addedTracks]];
        return;
    }

    // sostituzione: prima una copia dello stato attuale
    NSString *safety = [[self.settings supportDirectory] stringByAppendingPathComponent:@"backup-prima-dell-importazione.json"];
    [[RTBackup dataForContents:[self currentBackupContents]] writeToFile:safety atomically:YES];
    if (c.bookmarks && bm) [c.bookmarks writeToFile:path atomically:YES];
    if (c.favorites) [c.favorites writeToFile:[self favoritesPath] atomically:YES];
    if (c.history) [c.history writeToFile:[self historyPath] atomically:YES];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in c.settings) [d setObject:c.settings[key] forKey:key];
    self.favorites = [RTFavoriteTracks tracksWithContentsOfFile:[self favoritesPath] error:NULL] ?: [RTFavoriteTracks new];
    self.history = [RTFavoriteTracks tracksWithContentsOfFile:[self historyPath] error:NULL] ?: [RTFavoriteTracks new];
    [self.favoritesWindow close];
    self.favoritesWindow = nil;   // si riapre con i brani nuovi
    self.player.volume = self.settings.volume;
    [self applyHotKeys];
    [self reloadAfterImport];
    [self showAlert:@"Backup importato"
               text:[NSString stringWithFormat:@"Tutto è stato ripristinato. Lo stato precedente è salvato in
%@", safety]];
}

- (void)reloadAfterImport
{
    [self.bookmarksWatcher rememberCurrentContents];
    RTBookmarks *b = [RTBookmarks bookmarksWithContentsOfFile:self.settings.bookmarksPath error:NULL];
    if (b) self.bookmarks = b;
    [self.stationEditor reloadFromDisk];
    [self.favoritesWindow reload];
    [self buildMenu];
    [self refresh];
}

- (void)toggleICloudBackup:(id)sender
{
    self.settings.iCloudBackup = !self.settings.iCloudBackup;
    if (self.settings.iCloudBackup) {
        self.settings.lastBackup = nil;   // il primo backup subito
        [self tick:nil];
    }
    [self refresh];
}

- (void)revealICloudBackups:(id)sender
{
    NSString *folder = [RTBackup iCloudFolder];
    if (!folder) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *file = [folder stringByAppendingPathComponent:@"RadioTray-backup.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:file]) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:file]]];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:folder]];
    }
}

#pragma mark - Radiosveglia

- (void)fireAlarm
{
    NSString *group = self.settings.alarmGroup, *name = self.settings.alarmStation;
    if (!group || !name || ![self.bookmarks stationNamed:name inGroup:group]) {
        [[RTNotifier shared] notifyTitle:@"Radiosveglia" message:@"La stazione scelta non è più nell'elenco"];
        return;
    }
    NSLog(@"RadioTray: radiosveglia, %@", name);
    [self.fadeTimer invalidate];
    self.fadeTimer = nil;
    NSInteger target = self.settings.volume;
    if (self.settings.alarmFadeIn && target > 5) {
        // da 5% al volume abituale in 2 minuti (40 passi da 3 secondi)
        self.player.volume = 5;
        __block NSInteger steps = 0;
        __block NSInteger lastSet = 5;
        __weak typeof(self) weakSelf = self;
        self.fadeTimer = [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *t) {
            typeof(self) strongSelf = weakSelf;
            // ci si ferma se la radio è stata spenta o se il volume è stato cambiato a mano
            if (!strongSelf || strongSelf.player.volume != lastSet) {
                [t invalidate];
                return;
            }
            if (strongSelf.player.state == RTPlayerStateStopped) {
                strongSelf.player.volume = strongSelf.settings.volume;   // si torna al volume abituale
                [t invalidate];
                return;
            }
            steps++;
            lastSet = steps >= 40 ? target : 5 + (target - 5) * steps / 40;
            strongSelf.player.volume = lastSet;
            [strongSelf refresh];
            if (steps >= 40) [t invalidate];
        }];
    }
    [self playStationNamed:name inGroup:group];
    [[RTNotifier shared] notifyTitle:@"⏰ Radiosveglia" message:[NSString stringWithFormat:@"Buongiorno! %@", name]];
}

- (void)configureAlarm:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Radiosveglia";
    alert.informativeText = @"La radio si accende all'ora scelta. Il Mac deve essere acceso (lo stop dello schermo va bene, lo stop del computer no).";
    [alert addButtonWithTitle:@"Salva"];
    [alert addButtonWithTitle:@"Annulla"];

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380, 150)];
    NSButton *enabled = [NSButton checkboxWithTitle:@"Attiva la radiosveglia" target:nil action:NULL];
    enabled.frame = NSMakeRect(0, 126, 300, 20);
    enabled.state = self.settings.alarmEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:enabled];

    NSTextField *timeLabel = [NSTextField labelWithString:@"Ora:"];
    timeLabel.frame = NSMakeRect(0, 96, 70, 20);
    [view addSubview:timeLabel];
    NSDatePicker *picker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(76, 93, 90, 26)];
    picker.datePickerStyle = NSTextFieldAndStepperDatePickerStyle;
    picker.datePickerElements = NSHourMinuteDatePickerElementFlag;
    picker.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];
    NSCalendar *cal = [NSCalendar currentCalendar];
    picker.dateValue = [cal dateBySettingHour:self.settings.alarmMinutes / 60 minute:self.settings.alarmMinutes % 60 second:0
                                       ofDate:[NSDate date] options:0];
    [view addSubview:picker];

    NSTextField *daysLabel = [NSTextField labelWithString:@"Giorni:"];
    daysLabel.frame = NSMakeRect(0, 64, 70, 20);
    [view addSubview:daysLabel];
    NSArray *dayNames = @[@"Lu", @"Ma", @"Me", @"Gi", @"Ve", @"Sa", @"Do"];
    NSMutableArray<NSButton *> *dayBoxes = [NSMutableArray array];
    for (NSUInteger i = 0; i < 7; i++) {
        NSButton *b = [NSButton checkboxWithTitle:dayNames[i] target:nil action:NULL];
        b.frame = NSMakeRect(76 + i * 43, 64, 43, 20);
        b.state = (self.settings.alarmDays & (1u << i)) ? NSControlStateValueOn : NSControlStateValueOff;
        [view addSubview:b];
        [dayBoxes addObject:b];
    }

    NSTextField *stationLabel = [NSTextField labelWithString:@"Stazione:"];
    stationLabel.frame = NSMakeRect(0, 33, 70, 20);
    [view addSubview:stationLabel];
    NSPopUpButton *stations = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(72, 28, 308, 26) pullsDown:NO];
    for (RTGroup *g in self.bookmarks.groups) {
        for (RTStation *st in g.stations) {
            NSString *title = g.isRoot ? st.name : [NSString stringWithFormat:@"%@ ▸ %@", g.name, st.name];
            [stations addItemWithTitle:title];
            stations.lastItem.representedObject = @[g.name, st.name];
        }
    }
    NSString *wantGroup = self.settings.alarmGroup ?: self.currentGroup, *wantName = self.settings.alarmStation ?: self.currentStation;
    for (NSMenuItem *item in stations.itemArray) {
        NSArray *key = item.representedObject;
        if ([key[0] isEqualToString:wantGroup ?: @""] && [key[1] isEqualToString:wantName ?: @""]) [stations selectItem:item];
    }
    [view addSubview:stations];

    NSButton *fade = [NSButton checkboxWithTitle:@"Volume crescente (da basso al volume abituale in 2 minuti)" target:nil action:NULL];
    fade.frame = NSMakeRect(0, 2, 380, 20);
    fade.state = self.settings.alarmFadeIn ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:fade];

    alert.accessoryView = view;
    if (stations.numberOfItems == 0) {
        [self showAlert:@"Nessuna stazione" text:@"Aggiungi prima almeno una stazione."];
        return;
    }
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSUInteger days = 0;
    for (NSUInteger i = 0; i < 7; i++) if (dayBoxes[i].state == NSControlStateValueOn) days |= (1u << i);
    NSDateComponents *c = [cal components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:picker.dateValue];
    NSArray *key = stations.selectedItem.representedObject;
    BOOL on = enabled.state == NSControlStateValueOn;
    if (on && days == 0) {
        [self showAlert:@"Radiosveglia non attivata" text:@"Scegli almeno un giorno della settimana."];
        return;
    }
    self.settings.alarmEnabled = on;
    self.settings.alarmMinutes = c.hour * 60 + c.minute;
    self.settings.alarmDays = days;
    self.settings.alarmGroup = key[0];
    self.settings.alarmStation = key[1];
    self.settings.alarmFadeIn = fade.state == NSControlStateValueOn;
    // se si imposta per un'ora appena passata, non deve suonare subito
    NSDate *now = [NSDate date];
    if ([RTAlarm shouldFireAt:now minutes:self.settings.alarmMinutes days:days lastFired:nil calendar:cal]) {
        self.settings.alarmLastFired = now;
    }
    if (on && self.settings.notifications) {
        NSDate *next = [RTAlarm nextFireAfter:now minutes:self.settings.alarmMinutes days:days calendar:cal];
        NSDateFormatter *df = [NSDateFormatter new];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];
        df.dateFormat = @"EEEE d MMMM 'alle' HH:mm";
        [[RTNotifier shared] notifyTitle:@"⏰ Radiosveglia attivata"
                                 message:next ? [NSString stringWithFormat:@"Prossima: %@", [df stringFromDate:next]] : nil];
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
