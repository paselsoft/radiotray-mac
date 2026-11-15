#import "RTFavoritesWindowController.h"
#import "RTFavoriteTracks.h"

static NSString *const kColTitle = @"title";
static NSString *const kColArtist = @"artist";
static NSString *const kColStation = @"station";
static NSString *const kColAdded = @"added";

@interface RTFavoritesWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (nonatomic, strong) RTFavoriteTracks *store;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSArray<RTFavoriteTrack *> *shown;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSPopUpButton *stationPopup;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSButton *copyButton;
@property (nonatomic, strong) NSPopUpButton *webPopup;
@property (nonatomic, strong) NSButton *exportButton;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation RTFavoritesWindowController

- (instancetype)initWithTracks:(RTFavoriteTracks *)tracks path:(NSString *)path
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 780, 480)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = @"Brani preferiti";
    window.minSize = NSMakeSize(640, 300);
    window.releasedWhenClosed = NO;
    window.frameAutosaveName = @"RadioTrayFavorites";
    if ((self = [super initWithWindow:window])) {
        _store = tracks;
        _path = [path copy];
        _shown = @[];
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];
        _dateFormatter.dateFormat = @"d MMM yyyy, HH:mm";
        [self buildContent];
        [window center];
        [self reload];
    }
    return self;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.frame = frame;
    b.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [self.window.contentView addSubview:b];
    return b;
}

- (void)buildContent
{
    NSView *content = self.window.contentView;
    CGFloat w = content.bounds.size.width, h = content.bounds.size.height;

    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, h - 44, w - 270, 24)];
    self.searchField.placeholderString = @"Cerca per titolo, artista o stazione";
    self.searchField.sendsSearchStringImmediately = YES;
    self.searchField.target = self;
    self.searchField.action = @selector(filterChanged:);
    self.searchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:self.searchField];

    self.stationPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(w - 242, h - 46, 222, 26) pullsDown:NO];
    self.stationPopup.target = self;
    self.stationPopup.action = @selector(filterChanged:);
    self.stationPopup.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:self.stationPopup];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 84, w - 40, h - 140)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTableView *table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    table.usesAlternatingRowBackgroundColors = YES;
    table.allowsMultipleSelection = YES;
    table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    NSArray *cols = @[@[kColTitle, @"Titolo", @230, @YES], @[kColArtist, @"Artista", @190, @YES],
                      @[kColStation, @"Stazione", @170, @YES], @[kColAdded, @"Aggiunto il", @140, @NO]];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        col.editable = NO;
        // ordinamento con un clic sull'intestazione (testi senza distinguere maiuscole e accenti)
        col.sortDescriptorPrototype = [c[3] boolValue]
            ? [NSSortDescriptor sortDescriptorWithKey:c[0] ascending:YES selector:@selector(localizedStandardCompare:)]
            : [NSSortDescriptor sortDescriptorWithKey:c[0] ascending:NO];
        [table addTableColumn:col];
    }
    table.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:kColAdded ascending:NO]];   // prima i più recenti
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.doubleAction = @selector(searchYouTube:);
    scroll.documentView = table;
    [content addSubview:scroll];
    self.table = table;

    CGFloat y = 44;
    self.removeButton = [self button:@"Elimina" action:@selector(removeSelected:) frame:NSMakeRect(14, y, 100, 32)];
    // ⌘⌫ come nel Finder (il solo ⌫ cancellerebbe anche mentre si scrive nella ricerca)
    self.removeButton.keyEquivalent = @"\x7f";
    self.removeButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    self.removeButton.toolTip = @"Elimina i brani selezionati (⌘⌫)";
    self.copyButton = [self button:@"Copia" action:@selector(copy:) frame:NSMakeRect(114, y, 90, 32)];

    NSPopUpButton *web = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(212, y + 3, 160, 26) pullsDown:YES];
    [web addItemWithTitle:@"Cerca su…"];
    NSArray *sites = @[@[@"YouTube", @(RTTrackSearchYouTube)], @[@"Apple Music", @(RTTrackSearchAppleMusic)],
                       @[@"Spotify", @(RTTrackSearchSpotify)]];
    for (NSArray *site in sites) {
        [web addItemWithTitle:site[0]];
        web.lastItem.tag = [site[1] integerValue];
        web.lastItem.target = self;
        web.lastItem.action = @selector(searchWeb:);
    }
    web.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [content addSubview:web];
    self.webPopup = web;

    self.exportButton = [self button:@"Esporta…" action:@selector(export:) frame:NSMakeRect(w - 134, y, 120, 32)];
    self.exportButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;

    NSTextField *status = [NSTextField labelWithString:@""];
    status.frame = NSMakeRect(20, 16, w - 40, 18);
    status.textColor = [NSColor secondaryLabelColor];
    status.lineBreakMode = NSLineBreakByTruncatingTail;
    status.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:status];
    self.statusLabel = status;
}

- (void)showAndFocus
{
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.searchField];
}

#pragma mark - Dati

- (void)rebuildStationPopup
{
    NSString *selected = self.stationPopup.selectedItem.representedObject;
    [self.stationPopup removeAllItems];
    [self.stationPopup addItemWithTitle:@"Tutte le stazioni"];
    for (NSString *s in [self.store stations]) {
        [self.stationPopup addItemWithTitle:s];
        self.stationPopup.lastItem.representedObject = s;
    }
    NSInteger index = selected ? [self.stationPopup indexOfItemWithRepresentedObject:selected] : -1;
    [self.stationPopup selectItemAtIndex:MAX(0, index)];
}

- (void)reload
{
    [self rebuildStationPopup];
    [self applyFilter];
}

- (void)applyFilter
{
    NSArray *selected = [self selectedTracks];
    self.shown = [self.store tracksMatching:self.searchField.stringValue
                                    station:self.stationPopup.selectedItem.representedObject
                            sortDescriptors:self.table.sortDescriptors];
    [self.table reloadData];
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (RTFavoriteTrack *t in selected) {
        NSUInteger i = [self.shown indexOfObjectIdenticalTo:t];
        if (i != NSNotFound) [rows addIndex:i];
    }
    [self.table selectRowIndexes:rows byExtendingSelection:NO];

    NSUInteger total = self.store.tracks.count;
    if (total == 0) {
        self.statusLabel.stringValue = @"Nessun brano preferito. Mentre ascolti, clic sul titolo nel menu ▸ ★ Aggiungi ai brani preferiti.";
    } else if (self.shown.count == total) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu brani. Doppio clic per cercarlo su YouTube.", (unsigned long)total];
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu brani su %lu", (unsigned long)self.shown.count, (unsigned long)total];
    }
    [self updateButtons];
}

- (NSArray<RTFavoriteTrack *> *)selectedTracks
{
    NSMutableArray *out = [NSMutableArray array];
    [self.table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (i < self.shown.count) [out addObject:self.shown[i]];
    }];
    return out;
}

- (void)updateButtons
{
    NSUInteger n = self.table.selectedRowIndexes.count;
    self.removeButton.enabled = n > 0;
    self.copyButton.enabled = n > 0;
    self.webPopup.enabled = n == 1;
    self.exportButton.enabled = self.shown.count > 0;
}

- (BOOL)save
{
    NSError *error = nil;
    if (![[self.store dataRepresentation] writeToFile:self.path options:NSDataWritingAtomic error:&error]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Impossibile salvare i brani preferiti";
        alert.informativeText = error.localizedDescription ?: @"";
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return NO;
    }
    [self.delegate favoritesWindowDidChangeTracks];
    return YES;
}

#pragma mark - Azioni

- (void)filterChanged:(id)sender
{
    [self applyFilter];
}

- (void)removeSelected:(id)sender
{
    NSArray<RTFavoriteTrack *> *tracks = [self selectedTracks];
    if (tracks.count == 0) return;
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = tracks.count == 1
        ? [NSString stringWithFormat:@"Eliminare «%@» dai preferiti?", tracks[0].displayText]
        : [NSString stringWithFormat:@"Eliminare %lu brani dai preferiti?", (unsigned long)tracks.count];
    [alert addButtonWithTitle:@"Elimina"];
    [alert addButtonWithTitle:@"Annulla"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSInteger firstRow = (NSInteger)self.table.selectedRowIndexes.firstIndex;
        [self.store removeTracks:tracks];
        [self save];
        [self reload];
        NSInteger next = MIN(firstRow, (NSInteger)self.shown.count - 1);
        if (next >= 0) [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)next] byExtendingSelection:NO];
    }];
}

- (void)copy:(id)sender
{
    NSArray<RTFavoriteTrack *> *tracks = [self selectedTracks];
    if (tracks.count == 0) return;
    NSMutableArray *lines = [NSMutableArray array];
    for (RTFavoriteTrack *t in tracks) [lines addObject:t.displayText];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[lines componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = tracks.count == 1 ? @"Copiato negli appunti." :
        [NSString stringWithFormat:@"%lu brani copiati negli appunti.", (unsigned long)tracks.count];
}

- (void)openSearch:(RTTrackSearchSite)site
{
    NSArray<RTFavoriteTrack *> *tracks = [self selectedTracks];
    if (tracks.count != 1) return;
    [[NSWorkspace sharedWorkspace] openURL:[RTFavoriteTracks searchURLForTrack:tracks[0] site:site]];
}

- (void)searchWeb:(NSMenuItem *)sender { [self openSearch:(RTTrackSearchSite)sender.tag]; }
- (void)searchYouTube:(id)sender { if (self.table.clickedRow >= 0) [self openSearch:RTTrackSearchYouTube]; }

- (void)export:(id)sender
{
    NSArray<RTFavoriteTrack *> *tracks = self.shown;
    if (tracks.count == 0) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"Brani preferiti.csv";
    panel.allowedFileTypes = @[@"csv"];
    panel.message = tracks.count == self.store.tracks.count ? @"Esporta tutti i brani preferiti"
                                                            : @"Esporta i brani mostrati (ricerca e filtro attuali)";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSError *error = nil;
        if (![[RTFavoriteTracks csvForTracks:tracks] writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"Esportazione non riuscita";
            alert.informativeText = error.localizedDescription ?: @"";
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
            return;
        }
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Esportati %lu brani in %@",
                                        (unsigned long)tracks.count, panel.URL.lastPathComponent];
    }];
}

#pragma mark - Tabella

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.shown.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSTextField *cell = [tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = column.identifier;
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    RTFavoriteTrack *t = self.shown[(NSUInteger)row];
    NSString *value = @"";
    if ([column.identifier isEqualToString:kColTitle]) value = t.title;
    else if ([column.identifier isEqualToString:kColArtist]) value = t.artist;
    else if ([column.identifier isEqualToString:kColStation]) value = t.station;
    else value = [self.dateFormatter stringFromDate:t.added];
    cell.stringValue = value ?: @"";
    cell.textColor = [column.identifier isEqualToString:kColAdded] || [column.identifier isEqualToString:kColStation]
                   ? [NSColor secondaryLabelColor] : [NSColor labelColor];
    cell.toolTip = value;
    return cell;
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors
{
    [self applyFilter];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButtons];
}

@end
