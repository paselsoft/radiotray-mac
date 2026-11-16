#import "RTStationEditorController.h"
#import "RTBookmarksDocument.h"
#import "RTTableCell.h"
#import "RTStationLogo.h"
#import "RTPlaylistParser.h"

static NSString *const kColName = @"name";
static NSString *const kColURL = @"url";
static NSPasteboardType const RTDragType = @"io.github.paselsoft.radiotray-mac.item";

@interface RTStationEditorController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate>
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong, nullable) RTBookmarksDocument *doc;
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSButton *upButton;
@property (nonatomic, strong) NSButton *downButton;
@property (nonatomic, strong) NSPopUpButton *movePopup;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSButton *logoButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong, nullable) id draggedItem;
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *logos;     // loghi 16×16 delle stazioni
@property (nonatomic, strong) NSMutableSet<NSString *> *loadingLogos;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, copy) NSString *filter;                            // testo cercato ("" = tutto)
@end

@implementation RTStationEditorController

- (instancetype)initWithBookmarksPath:(NSString *)path
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 860, 500)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = @"Stazioni";
    window.minSize = NSMakeSize(820, 320);
    window.releasedWhenClosed = NO;
    window.frameAutosaveName = @"RadioTrayStationEditor2";   // nuova misura (pulsante Logo…)
    if ((self = [super initWithWindow:window])) {
        _path = [path copy];
        _logos = [NSCache new];
        _loadingLogos = [NSMutableSet set];
        _filter = @"";
        [self buildContent];
        [window center];
        [self reloadFromDisk];
    }
    return self;
}

#pragma mark - Costruzione della finestra

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame tip:(NSString *)tip
{
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.frame = frame;
    b.toolTip = tip;
    b.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [self.window.contentView addSubview:b];
    return b;
}

- (void)buildContent
{
    NSView *content = self.window.contentView;
    CGFloat w = content.bounds.size.width, h = content.bounds.size.height;

    NSButton *import = [NSButton buttonWithTitle:@"Importa playlist…" target:self action:@selector(importPlaylist:)];
    import.bezelStyle = NSBezelStyleRounded;
    import.frame = NSMakeRect(14, h - 46, 170, 32);
    import.toolTip = @"Aggiunge le stazioni di un file .pls o .m3u scaricato dal sito di una radio (puoi anche trascinarlo nell'elenco)";
    import.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [content addSubview:import];

    NSSearchField *search = [[NSSearchField alloc] initWithFrame:NSMakeRect(w - 280, h - 40, 260, 22)];
    search.placeholderString = @"Cerca per nome, gruppo o indirizzo";
    search.target = self;
    search.action = @selector(searchChanged:);
    search.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:search];
    self.searchField = search;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 84, w - 40, h - 138)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:scroll.bounds];
    outline.usesAlternatingRowBackgroundColors = YES;
    outline.allowsMultipleSelection = NO;
    outline.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:kColName];
    nameCol.title = @"Nome";
    nameCol.width = 270;
    [outline addTableColumn:nameCol];
    outline.outlineTableColumn = nameCol;
    NSTableColumn *urlCol = [[NSTableColumn alloc] initWithIdentifier:kColURL];
    urlCol.title = @"Indirizzo";
    urlCol.width = 400;
    [outline addTableColumn:urlCol];
    outline.dataSource = self;
    outline.delegate = self;
    outline.target = self;
    outline.doubleAction = @selector(editClicked:);
    [outline registerForDraggedTypes:@[RTDragType, NSPasteboardTypeFileURL]];
    [outline setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    scroll.documentView = outline;
    [content addSubview:scroll];
    self.outline = outline;

    CGFloat y = 44;
    [self button:@"Nuovo gruppo…" action:@selector(addGroup:) frame:NSMakeRect(14, y, 130, 32) tip:@"Aggiunge un gruppo"];
    [self button:@"Nuova stazione…" action:@selector(addStation:) frame:NSMakeRect(144, y, 140, 32)
             tip:@"Aggiunge una stazione al gruppo selezionato"];
    self.removeButton = [self button:@"Elimina…" action:@selector(removeSelected:) frame:NSMakeRect(284, y, 100, 32)
                                 tip:@"Elimina la stazione o il gruppo selezionato"];
    self.upButton = [self button:@"▲" action:@selector(moveUp:) frame:NSMakeRect(392, y, 44, 32) tip:@"Sposta in su"];
    self.downButton = [self button:@"▼" action:@selector(moveDown:) frame:NSMakeRect(434, y, 44, 32) tip:@"Sposta in giù"];

    NSPopUpButton *move = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(484, y + 3, 150, 26) pullsDown:YES];
    move.toolTip = @"Sposta la stazione selezionata in un altro gruppo";
    move.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [content addSubview:move];
    self.movePopup = move;

    self.playButton = [self button:@"Ascolta" action:@selector(play:) frame:NSMakeRect(w - 114, y, 100, 32)
                               tip:@"Ascolta la stazione selezionata"];
    self.playButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.logoButton = [self button:@"Logo…" action:@selector(chooseLogo:) frame:NSMakeRect(w - 204, y, 90, 32)
                               tip:@"Scegli l'immagine da mostrare per questa stazione quando non c'è la copertina del brano"];
    self.logoButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;

    NSTextField *status = [NSTextField labelWithString:@""];
    status.frame = NSMakeRect(20, 16, w - 220, 18);
    status.textColor = [NSColor secondaryLabelColor];
    status.lineBreakMode = NSLineBreakByTruncatingTail;
    status.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:status];
    self.statusLabel = status;

    NSButton *json = [NSButton buttonWithTitle:@"Apri il file JSON…" target:self action:@selector(openJSON:)];
    json.bezelStyle = NSBezelStyleRecessed;
    json.controlSize = NSControlSizeSmall;
    json.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    json.frame = NSMakeRect(w - 174, 14, 160, 20);
    json.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:json];
}

- (void)showAndFocus
{
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.outline];
}

#pragma mark - Caricamento e salvataggio

- (void)reloadFromDisk
{
    id selected = [self selectedItem];
    NSString *selectedGroup = [selected isKindOfClass:[RTDocGroup class]] ? [(RTDocGroup *)selected name]
                            : [(RTDocStation *)selected group].name;
    NSString *selectedStation = [selected isKindOfClass:[RTDocStation class]] ? [(RTDocStation *)selected name] : nil;

    NSData *data = [NSData dataWithContentsOfFile:self.path] ?: [@"[]" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *error = nil;
    RTBookmarksDocument *doc = [RTBookmarksDocument documentWithData:data error:&error];
    self.doc = doc;
    [self.outline reloadData];
    [self.outline expandItem:nil expandChildren:YES];
    if (!doc) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Il file ha un errore: %@ Correggilo con \"Apri il file JSON…\".", error];
        self.statusLabel.textColor = [NSColor systemRedColor];
    } else {
        self.statusLabel.textColor = [NSColor secondaryLabelColor];
        [self showHint];
        // si ritrova la riga che era selezionata
        RTDocGroup *g = selectedGroup ? [doc groupNamed:selectedGroup] : nil;
        id item = g;
        if (g && selectedStation) {
            for (RTDocStation *s in g.stations) if ([s.name isEqualToString:selectedStation]) item = s;
        }
        [self selectItem:item];
    }
    [self updateControls];
}

- (void)showHint
{
    NSUInteger count = 0;
    for (RTDocGroup *g in self.doc.groups) count += g.stations.count;
    if ([self filtering]) {
        NSUInteger found = 0;
        for (RTDocGroup *g in [self visibleGroups]) found += [self visibleStationsOf:g].count;
        self.statusLabel.stringValue = found == 0
            ? [NSString stringWithFormat:@"Nessuna stazione trovata per «%@» (su %lu).", self.filter, (unsigned long)count]
            : [NSString stringWithFormat:@"%lu %@ su %lu. Cancella la ricerca per spostarle o riordinarle.",
                                         (unsigned long)found, found == 1 ? @"stazione trovata" : @"stazioni trovate", (unsigned long)count];
        return;
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:
        @"%lu stazioni. Doppio clic per modificare nome o indirizzo, trascina per spostare. Le modifiche sono salvate subito.",
        (unsigned long)count];
}

/// Salva dopo una modifica riuscita; problem != nil: modifica rifiutata, si avvisa e non si salva.
- (BOOL)commit:(NSString *)problem select:(id)item
{
    if (problem) {
        NSBeep();
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Modifica non possibile";
        alert.informativeText = problem;
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        [self.outline reloadData];
        return NO;
    }
    NSError *error = nil;
    if (![[self.doc dataRepresentation] writeToFile:self.path options:NSDataWritingAtomic error:&error]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Impossibile salvare le stazioni";
        alert.informativeText = error.localizedDescription ?: @"";
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return NO;
    }
    [self.outline reloadData];
    [self.outline expandItem:nil expandChildren:YES];
    if (item) [self selectItem:item];
    [self showHint];
    [self updateControls];
    [self.delegate stationEditorDidSaveBookmarks];
    return YES;
}

#pragma mark - Selezione

- (id)selectedItem
{
    NSInteger row = self.outline.selectedRow;
    return row >= 0 ? [self.outline itemAtRow:row] : nil;
}

- (void)selectItem:(id)item
{
    if (!item) return;
    if ([item isKindOfClass:[RTDocStation class]]) [self.outline expandItem:[(RTDocStation *)item group]];
    NSInteger row = [self.outline rowForItem:item];
    if (row >= 0) {
        [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self.outline scrollRowToVisible:row];
    }
}

/// Gruppo in cui aggiungere una stazione: quello selezionato o quello della stazione selezionata.
- (RTDocGroup *)targetGroup
{
    id item = [self selectedItem];
    if ([item isKindOfClass:[RTDocGroup class]]) return item;
    if ([item isKindOfClass:[RTDocStation class]]) return [(RTDocStation *)item group];
    return nil;
}

- (void)updateControls
{
    id item = [self selectedItem];
    BOOL ok = self.doc != nil;
    BOOL isStation = [item isKindOfClass:[RTDocStation class]];
    self.removeButton.enabled = ok && item != nil;
    self.playButton.enabled = ok && isStation;
    self.logoButton.enabled = ok && isStation;
    self.logoButton.title = isStation && [(RTDocStation *)item image] ? @"Logo ✓…" : @"Logo…";

    NSUInteger index = 0, count = 0;
    if (isStation) {
        RTDocStation *s = item;
        index = [s.group.stations indexOfObject:s];
        count = s.group.stations.count;
    } else if (item) {
        index = [self.doc.groups indexOfObject:item];
        count = self.doc.groups.count;
    }
    self.upButton.enabled = ok && item && index > 0 && ![self filtering];
    self.downButton.enabled = ok && item && index + 1 < count && ![self filtering];

    // "Sposta in…": gli altri gruppi, più uno nuovo
    [self.movePopup removeAllItems];
    [self.movePopup addItemWithTitle:@"Sposta in…"];
    if (isStation) {
        RTDocStation *s = item;
        for (RTDocGroup *g in self.doc.groups) {
            if (g == s.group) continue;
            [self.movePopup addItemWithTitle:[RTBookmarksDocument displayNameForGroup:g]];
            self.movePopup.lastItem.representedObject = g;
            self.movePopup.lastItem.target = self;
            self.movePopup.lastItem.action = @selector(moveToGroup:);
        }
        if (![self.doc groupNamed:@"root"]) {
            [self.movePopup addItemWithTitle:@"(senza gruppo)"];
            self.movePopup.lastItem.representedObject = @"root";
            self.movePopup.lastItem.target = self;
            self.movePopup.lastItem.action = @selector(moveToGroup:);
        }
    }
    self.movePopup.enabled = ok && isStation && self.movePopup.numberOfItems > 1;
}

#pragma mark - Azioni

- (NSString *)askTitle:(NSString *)title fields:(NSArray<NSArray<NSString *> *> *)fields values:(NSMutableArray<NSString *> *)values
{
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Annulla"];
    CGFloat rowH = 30, width = 420;
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, rowH * fields.count)];
    NSMutableArray<NSTextField *> *inputs = [NSMutableArray array];
    for (NSUInteger i = 0; i < fields.count; i++) {
        CGFloat y = rowH * (fields.count - 1 - i);
        NSTextField *label = [NSTextField labelWithString:fields[i][0]];
        label.alignment = NSTextAlignmentRight;
        label.frame = NSMakeRect(0, y + 4, 80, 18);
        [view addSubview:label];
        NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(86, y, width - 86, 24)];
        input.stringValue = values[i];
        input.placeholderString = fields[i][1];
        [view addSubview:input];
        [inputs addObject:input];
    }
    alert.accessoryView = view;
    alert.window.initialFirstResponder = inputs.firstObject;
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    for (NSUInteger i = 0; i < inputs.count; i++) values[i] = inputs[i].stringValue;
    return @"ok";
}

- (void)addGroup:(id)sender
{
    if (!self.doc) return;
    NSMutableArray *values = [@[@""] mutableCopy];
    if (![self askTitle:@"Nuovo gruppo" fields:@[@[@"Nome:", @"per esempio: Notizie"]] values:values]) return;
    RTDocGroup *created = nil;
    // in fondo, ma prima del gruppo delle stazioni senza gruppo
    NSUInteger index = self.doc.groups.count;
    if (index > 0 && self.doc.groups.lastObject.isRoot) index--;
    NSString *problem = [self.doc addGroupNamed:values[0] atIndex:index group:&created];
    [self commit:problem select:created];
}

- (void)addStation:(id)sender
{
    if (!self.doc) return;
    RTDocGroup *group = [self targetGroup];
    if (!group) {
        group = self.doc.groups.firstObject;
        if (!group) {
            [self.doc addGroupNamed:@"Stazioni" atIndex:0 group:&group];
        }
    }
    NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"";
    clip = [clip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL clipIsURL = [clip.lowercaseString hasPrefix:@"http://"] || [clip.lowercaseString hasPrefix:@"https://"];
    NSMutableArray *values = [@[@"", clipIsURL ? clip : @""] mutableCopy];
    NSString *title = [NSString stringWithFormat:@"Nuova stazione in «%@»", [RTBookmarksDocument displayNameForGroup:group]];
    if (![self askTitle:title fields:@[@[@"Nome:", @"per esempio: Radio 24"], @[@"Indirizzo:", @"http://… (stream o playlist)"]]
                 values:values]) return;
    RTDocStation *created = nil;
    NSUInteger index = group.stations.count;
    id selected = [self selectedItem];
    if ([selected isKindOfClass:[RTDocStation class]] && [(RTDocStation *)selected group] == group) {
        index = [group.stations indexOfObject:selected] + 1;   // subito dopo quella selezionata
    }
    NSString *problem = [self.doc addStationNamed:values[0] url:values[1] toGroup:group atIndex:index station:&created];
    [self commit:problem select:created];
}

- (void)removeSelected:(id)sender
{
    id item = [self selectedItem];
    if (!item) return;
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Elimina"];
    [alert addButtonWithTitle:@"Annulla"];
    if ([item isKindOfClass:[RTDocGroup class]]) {
        RTDocGroup *g = item;
        alert.messageText = [NSString stringWithFormat:@"Eliminare il gruppo «%@»?", [RTBookmarksDocument displayNameForGroup:g]];
        alert.informativeText = g.stations.count
            ? [NSString stringWithFormat:@"Verranno eliminate anche le sue %lu stazioni.", (unsigned long)g.stations.count]
            : @"Il gruppo è vuoto.";
    } else {
        RTDocStation *s = item;
        alert.messageText = [NSString stringWithFormat:@"Eliminare la stazione «%@»?", s.name];
        alert.informativeText = s.url;
    }
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSInteger row = [self.outline rowForItem:item];
        NSString *problem = [item isKindOfClass:[RTDocGroup class]] ? [self.doc removeGroup:item] : [self.doc removeStation:item];
        if ([self commit:problem select:nil]) {
            NSInteger next = MIN(row, self.outline.numberOfRows - 1);
            if (next >= 0) [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)next] byExtendingSelection:NO];
            [self updateControls];
        }
    }];
}

- (void)moveBy:(NSInteger)delta
{
    id item = [self selectedItem];
    if ([item isKindOfClass:[RTDocStation class]]) {
        RTDocStation *s = item;
        NSInteger index = (NSInteger)[s.group.stations indexOfObject:s] + delta;
        if (index < 0 || index >= (NSInteger)s.group.stations.count) return;
        [self commit:[self.doc moveStation:s toGroup:s.group atIndex:(NSUInteger)index] select:s];
    } else if (item) {
        NSInteger index = (NSInteger)[self.doc.groups indexOfObject:item] + delta;
        if (index < 0 || index >= (NSInteger)self.doc.groups.count) return;
        [self commit:[self.doc moveGroup:item toIndex:(NSUInteger)index] select:item];
    }
}

- (void)moveUp:(id)sender { [self moveBy:-1]; }
- (void)moveDown:(id)sender { [self moveBy:+1]; }

- (void)moveToGroup:(NSMenuItem *)sender
{
    RTDocStation *s = [self selectedItem];
    if (![s isKindOfClass:[RTDocStation class]]) return;
    id target = sender.representedObject;
    if ([target isKindOfClass:[NSString class]]) target = [self.doc rootGroup];   // creato in fondo se manca
    RTDocGroup *group = target;
    [self commit:[self.doc moveStation:s toGroup:group atIndex:group.stations.count] select:s];
}

- (void)chooseLogo:(id)sender
{
    RTDocStation *s = [self selectedItem];
    if (![s isKindOfClass:[RTDocStation class]]) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Logo per «%@»", s.name];
    alert.informativeText = @"Incolla l'indirizzo web di un'immagine (in Safari: clic destro sul logo ▸ Copia indirizzo immagine), "
                            @"oppure scegli un file sul Mac. Il logo si vede nel menu e quando non c'è la copertina del brano.";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 380, 24)];
    field.placeholderString = @"https://…/logo.png";
    NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    clip = [clip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([clip.lowercaseString hasPrefix:@"http://"] || [clip.lowercaseString hasPrefix:@"https://"]) field.stringValue = clip;
    alert.accessoryView = field;
    [alert addButtonWithTitle:@"Usa l'indirizzo"];      // 1000
    [alert addButtonWithTitle:@"Scegli un file…"];      // 1001
    [alert addButtonWithTitle:@"Annulla"];              // 1002
    if (s.image) [alert addButtonWithTitle:@"Togli il logo"];   // 1003
    alert.window.initialFirstResponder = field;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSAlertFirstButtonReturn) {
            [self downloadLogo:field.stringValue forStation:s];
        } else if (result == NSAlertSecondButtonReturn) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self chooseLogoFileForStation:s]; });
        } else if (result == NSAlertThirdButtonReturn + 1) {
            [self.doc setImage:nil forStation:s];
            [self commit:nil select:s];
        }
    }];
}

/// Cartella dei loghi scelti, accanto al file delle stazioni: il logo resta anche se l'originale sparisce.
- (NSString *)newLogoPathWithExtension:(NSString *)ext
{
    NSString *dir = [[self.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"loghi"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [NSUUID UUID].UUIDString, ext]];
}

- (void)chooseLogoFileForStation:(RTDocStation *)s
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"png", @"jpg", @"jpeg", @"gif", @"tif", @"tiff", @"ico", @"icns", @"bmp"];
    panel.message = [NSString stringWithFormat:@"Logo per «%@»", s.name];
    panel.prompt = @"Usa come logo";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSString *dest = [self newLogoPathWithExtension:panel.URL.pathExtension.lowercaseString];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] copyItemAtPath:panel.URL.path toPath:dest error:&error]) {
            [self commit:error.localizedDescription ?: @"Impossibile copiare l'immagine" select:s];
            return;
        }
        [self.doc setImage:dest forStation:s];
        [self commit:nil select:s];
    }];
}

- (void)downloadLogo:(NSString *)address forStation:(RTDocStation *)s
{
    address = [address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = [NSURL URLWithString:address];
    if (!url || !([url.scheme.lowercaseString isEqualToString:@"http"] || [url.scheme.lowercaseString isEqualToString:@"https"])) {
        [self commit:@"Scrivi un indirizzo che comincia con http:// o https://" select:s];
        return;
    }
    self.statusLabel.stringValue = @"Scaricamento del logo…";
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 15;
    [req setValue:@"RadioTray-Mac/1.5 (https://github.com/paselsoft/radiotray-mac)" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
        NSImage *image = data.length ? [[NSImage alloc] initWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showHint];
            NSString *problem = nil;
            if (error) problem = [NSString stringWithFormat:@"Logo non scaricato: %@", error.localizedDescription];
            else if (code >= 400) problem = [NSString stringWithFormat:@"Logo non scaricato: il sito risponde HTTP %ld", (long)code];
            else if (!image || image.size.width < 8)
                problem = @"L'indirizzo non porta a un'immagine che il Mac sa leggere (le pagine web e le immagini SVG non vanno bene: "
                          @"serve l'indirizzo di un file PNG, JPG, GIF o ICO).";
            if (problem) {
                [self commit:problem select:s];
                return;
            }
            NSString *ext = url.pathExtension.lowercaseString;
            if (![@[@"png", @"jpg", @"jpeg", @"gif", @"ico", @"bmp", @"tif", @"tiff", @"webp"] containsObject:ext]) ext = @"img";
            NSString *dest = [self newLogoPathWithExtension:ext];
            NSError *writeError = nil;
            if (![data writeToFile:dest options:NSDataWritingAtomic error:&writeError]) {
                [self commit:writeError.localizedDescription ?: @"Impossibile salvare il logo" select:s];
                return;
            }
            [self.doc setImage:dest forStation:s];
            [self commit:nil select:s];
        });
    }] resume];
}

#pragma mark - Importazione di playlist

- (NSArray<NSURL *> *)playlistFilesIn:(id<NSDraggingInfo>)info
{
    NSMutableArray *out = [NSMutableArray array];
    NSArray<NSURL *> *urls = [info.draggingPasteboard readObjectsForClasses:@[[NSURL class]]
                                                                     options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *u in urls) {
        if ([@[@"pls", @"m3u", @"asx", @"xspf"] containsObject:u.pathExtension.lowercaseString]) [out addObject:u];
    }
    return out;
}

- (void)importPlaylist:(id)sender
{
    if (!self.doc) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"pls", @"m3u", @"asx", @"xspf"];
    panel.allowsMultipleSelection = YES;
    panel.message = @"Scegli i file .pls o .m3u scaricati dai siti delle radio (di solito nella cartella Download)";
    panel.prompt = @"Importa";
    panel.directoryURL = [[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    id selected = [self selectedItem];
    RTDocGroup *group = [selected isKindOfClass:[RTDocStation class]] ? [(RTDocStation *)selected group] : selected;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URLs.count) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [self importFiles:panel.URLs intoGroup:group]; });
    }];
}

/// Legge i file, mostra le stazioni trovate e chiede il gruppo; poi le aggiunge (senza doppioni).
- (void)importFiles:(NSArray<NSURL *> *)files intoGroup:(nullable RTDocGroup *)preferred
{
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *found = [NSMutableArray array];
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    NSMutableSet<NSString *> *known = [NSMutableSet set];
    for (RTDocGroup *g in self.doc.groups) for (RTDocStation *st in g.stations) [known addObject:st.url];
    NSUInteger duplicates = 0;
    for (NSURL *file in files) {
        NSData *data = [NSData dataWithContentsOfURL:file];
        NSString *problem = nil;
        NSArray *stations = data ? [RTPlaylistParser stationsFromPlaylistData:data fileName:file.lastPathComponent problem:&problem] : nil;
        if (!stations) {
            [problems addObject:[NSString stringWithFormat:@"%@: %@", file.lastPathComponent, problem ?: @"file non leggibile"]];
            continue;
        }
        for (NSDictionary *st in stations) {
            if ([known containsObject:st[@"url"]]) {
                duplicates++;
                continue;
            }
            [known addObject:st[@"url"]];
            [found addObject:st];
        }
    }
    if (found.count == 0) {
        NSMutableArray *lines = [problems mutableCopy];
        if (duplicates) [lines addObject:duplicates == 1 ? @"La stazione è già nell'elenco." :
                         [NSString stringWithFormat:@"Le %lu stazioni sono già nell'elenco.", (unsigned long)duplicates]];
        [self commit:[lines componentsJoinedByString:@"\n"] select:nil];
        return;
    }

    NSAlert *alert = [NSAlert new];
    alert.messageText = found.count == 1 ? @"Importa la stazione"
                                         : [NSString stringWithFormat:@"Importa %lu stazioni", (unsigned long)found.count];
    NSMutableString *info = [NSMutableString string];
    if (found.count > 1) {
        NSUInteger shown = 0;
        for (NSDictionary *st in found) {
            if (shown++ == 8) {
                [info appendFormat:@"… e altre %lu\n", (unsigned long)(found.count - 8)];
                break;
            }
            [info appendFormat:@"• %@\n", st[@"name"]];
        }
    } else {
        [info appendFormat:@"%@\n", found[0][@"url"]];
    }
    if (duplicates) [info appendFormat:@"(%lu già nell'elenco: saltate)\n", (unsigned long)duplicates];
    for (NSString *p in problems) [info appendFormat:@"%@\n", p];
    alert.informativeText = info;

    CGFloat width = 380;
    BOOL single = found.count == 1;
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, single ? 60 : 28)];
    NSTextField *nameField = nil;
    if (single) {
        NSTextField *label = [NSTextField labelWithString:@"Nome:"];
        label.alignment = NSTextAlignmentRight;
        label.frame = NSMakeRect(0, 36, 70, 18);
        [view addSubview:label];
        nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(76, 32, width - 76, 24)];
        nameField.stringValue = found[0][@"name"];
        [view addSubview:nameField];
    }
    NSTextField *groupLabel = [NSTextField labelWithString:@"Gruppo:"];
    groupLabel.alignment = NSTextAlignmentRight;
    groupLabel.frame = NSMakeRect(0, 4, 70, 18);
    [view addSubview:groupLabel];
    NSPopUpButton *groups = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(74, 0, width - 74, 26) pullsDown:NO];
    for (RTDocGroup *g in self.doc.groups) {
        [groups addItemWithTitle:[RTBookmarksDocument displayNameForGroup:g]];
        groups.lastItem.representedObject = g;
    }
    NSString *newGroupName = @"Importate";
    for (NSUInteger n = 2; [self.doc groupNamed:newGroupName]; n++) newGroupName = [NSString stringWithFormat:@"Importate %lu", (unsigned long)n];
    [groups addItemWithTitle:[NSString stringWithFormat:@"Nuovo gruppo «%@»", newGroupName]];
    if (preferred && [self.doc.groups containsObject:preferred]) [groups selectItemAtIndex:(NSInteger)[self.doc.groups indexOfObject:preferred]];
    else if (!single) [groups selectItem:groups.lastItem];
    [view addSubview:groups];
    alert.accessoryView = view;
    [alert addButtonWithTitle:@"Importa"];
    [alert addButtonWithTitle:@"Annulla"];
    if (nameField) alert.window.initialFirstResponder = nameField;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertFirstButtonReturn) return;
        RTDocGroup *group = groups.selectedItem.representedObject;
        if (!group) {
            NSUInteger index = self.doc.groups.count;
            if (index > 0 && self.doc.groups.lastObject.isRoot) index--;
            NSString *problem = [self.doc addGroupNamed:newGroupName atIndex:index group:&group];
            if (problem) {
                [self commit:problem select:nil];
                return;
            }
        }
        RTDocStation *last = nil;
        NSMutableArray<NSString *> *refused = [NSMutableArray array];
        for (NSDictionary *st in found) {
            NSString *name = nameField ? [nameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : st[@"name"];
            // nomi doppi nello stesso gruppo: "Nome (2)"
            NSString *unique = name.length ? name : @"Stazione importata";
            for (NSUInteger n = 2; ; n++) {
                BOOL taken = NO;
                for (RTDocStation *x in group.stations) if ([x.name caseInsensitiveCompare:unique] == NSOrderedSame) taken = YES;
                if (!taken) break;
                unique = [NSString stringWithFormat:@"%@ (%lu)", name, (unsigned long)n];
            }
            RTDocStation *created = nil;
            NSString *problem = [self.doc addStationNamed:unique url:st[@"url"] toGroup:group atIndex:group.stations.count station:&created];
            if (problem) [refused addObject:[NSString stringWithFormat:@"%@: %@", unique, problem]];
            else last = created;
        }
        // la ricerca potrebbe nascondere le stazioni appena aggiunte
        self.searchField.stringValue = @"";
        self.filter = @"";
        if ([self commit:nil select:last] && refused.count) {
            [self commit:[refused componentsJoinedByString:@"\n"] select:last];
        }
    }];
}

#pragma mark - Loghi nella tabella

- (nullable NSImage *)logoForStation:(RTDocStation *)s
{
    NSString *key = [NSString stringWithFormat:@"%@\n%@", s.url, s.image ?: @""];
    NSImage *cached = [self.logos objectForKey:key];
    if (cached) return cached;
    RTStationLogo *store = [RTStationLogo shared];
    NSData *data = [store cachedLogoForStationURL:s.url image:s.image];
    NSImage *image = data ? [[NSImage alloc] initWithData:data] : nil;
    if (image && image.size.width >= 8) {
        NSImage *small = [RTTableCell thumbnail:image side:16];
        [self.logos setObject:small forKey:key];
        return small;
    }
    if ((!s.image.length && [store knownMissingForStationURL:s.url]) || [self.loadingLogos containsObject:key]) return nil;
    [self.loadingLogos addObject:key];
    __weak typeof(self) weakSelf = self;
    [store logoForStation:s.name url:s.url image:s.image completion:^(NSData *d) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSImage *img = d ? [[NSImage alloc] initWithData:d] : nil;
        if (!img || img.size.width < 8) return;   // resta in loadingLogos: non si riprova a ogni ridisegno
        [strongSelf.loadingLogos removeObject:key];
        [strongSelf.logos setObject:[RTTableCell thumbnail:img side:16] forKey:key];
        NSInteger row = [strongSelf.outline rowForItem:s];
        if (row >= 0) {
            [strongSelf.outline reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                                          columnIndexes:[NSIndexSet indexSetWithIndex:0]];
        }
    }];
    return nil;
}

- (void)play:(id)sender
{
    RTDocStation *s = [self selectedItem];
    if ([s isKindOfClass:[RTDocStation class]]) [self.delegate stationEditorPlayStation:s.name group:s.group.name];
}

- (void)openJSON:(id)sender
{
    [self.delegate stationEditorOpenJSON];
}

- (void)editClicked:(id)sender
{
    NSInteger row = self.outline.clickedRow, column = self.outline.clickedColumn;
    if (row < 0) return;
    id item = [self.outline itemAtRow:row];
    if (column < 0) column = 0;
    NSString *identifier = self.outline.tableColumns[(NSUInteger)column].identifier;
    if ([item isKindOfClass:[RTDocGroup class]] && ([identifier isEqualToString:kColURL] || [(RTDocGroup *)item isRoot])) return;
    [self.outline editColumn:column row:row withEvent:nil select:YES];
}

#pragma mark - NSOutlineViewDataSource

static BOOL RTMatchesFilter(NSString *text, NSString *filter)
{
    return [text rangeOfString:filter options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
}

- (BOOL)filtering
{
    return self.filter.length > 0;
}

/// Stazioni del gruppo da mostrare: tutte se il nome del gruppo corrisponde alla ricerca.
- (NSArray<RTDocStation *> *)visibleStationsOf:(RTDocGroup *)group
{
    if (![self filtering] || RTMatchesFilter([RTBookmarksDocument displayNameForGroup:group], self.filter)) return group.stations;
    NSMutableArray *out = [NSMutableArray array];
    for (RTDocStation *st in group.stations) {
        if (RTMatchesFilter(st.name, self.filter) || RTMatchesFilter(st.url, self.filter)) [out addObject:st];
    }
    return out;
}

- (NSArray<RTDocGroup *> *)visibleGroups
{
    if (![self filtering]) return self.doc.groups;
    NSMutableArray *out = [NSMutableArray array];
    for (RTDocGroup *g in self.doc.groups) if ([self visibleStationsOf:g].count) [out addObject:g];
    return out;
}

- (void)searchChanged:(id)sender
{
    self.filter = [self.searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    id selected = [self selectedItem];
    [self.outline reloadData];
    [self.outline expandItem:nil expandChildren:YES];
    if (selected && [self.outline rowForItem:selected] >= 0) [self selectItem:selected];
    else if ([self filtering]) {
        // si seleziona la prima stazione trovata: "Ascolta" la fa partire
        for (NSInteger row = 0; row < self.outline.numberOfRows; row++) {
            if ([[self.outline itemAtRow:row] isKindOfClass:[RTDocStation class]]) {
                [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
                [self.outline scrollRowToVisible:row];
                break;
            }
        }
    }
    [self showHint];
    [self updateControls];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (!item) return (NSInteger)[self visibleGroups].count;
    if ([item isKindOfClass:[RTDocGroup class]]) return (NSInteger)[self visibleStationsOf:item].count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (!item) return [self visibleGroups][(NSUInteger)index];
    return [self visibleStationsOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return [item isKindOfClass:[RTDocGroup class]];
}

#pragma mark - Celle e modifica

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)column item:(id)item
{
    BOOL isGroup = [item isKindOfClass:[RTDocGroup class]];
    BOOL nameColumn = [column.identifier isEqualToString:kColName];
    RTTableCell *view = !isGroup && nameColumn
        ? [RTTableCell imageCellInTable:outlineView identifier:@"nameLogo" owner:self]
        : [RTTableCell cellInTable:outlineView identifier:column.identifier owner:self];
    if (!isGroup && nameColumn) view.imageView.image = [self logoForStation:item];
    NSTextField *cell = view.textField;
    cell.delegate = self;
    NSString *value;
    if (isGroup) {
        RTDocGroup *g = item;
        if (nameColumn) {
            value = [RTBookmarksDocument displayNameForGroup:g];
        } else {
            value = g.stations.count == 1 ? @"1 stazione" : [NSString stringWithFormat:@"%lu stazioni", (unsigned long)g.stations.count];
        }
        cell.editable = nameColumn && !g.isRoot;
        cell.font = nameColumn ? [NSFont boldSystemFontOfSize:[NSFont systemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        view.normalColor = nameColumn ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    } else {
        RTDocStation *s = item;
        value = nameColumn ? s.name : s.url;
        cell.editable = YES;
        cell.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        view.normalColor = nameColumn ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    }
    cell.stringValue = value ?: @"";
    view.toolTip = cell.editable ? @"Doppio clic per modificare" : nil;
    return view;
}

- (void)controlTextDidEndEditing:(NSNotification *)note
{
    NSTextField *field = note.object;
    NSInteger row = [self.outline rowForView:field], column = [self.outline columnForView:field];
    if (row < 0 || column < 0) return;
    id item = [self.outline itemAtRow:row];
    NSString *identifier = self.outline.tableColumns[(NSUInteger)column].identifier;
    NSString *text = field.stringValue;
    NSString *problem = nil;
    if ([item isKindOfClass:[RTDocGroup class]]) {
        if ([text isEqualToString:[RTBookmarksDocument displayNameForGroup:item]]) return;
        problem = [self.doc renameGroup:item to:text];
    } else if ([identifier isEqualToString:kColName]) {
        if ([text isEqualToString:[(RTDocStation *)item name]]) return;
        problem = [self.doc renameStation:item to:text];
    } else {
        if ([text isEqualToString:[(RTDocStation *)item url]]) return;
        problem = [self.doc setURL:text forStation:item];
    }
    [self commit:problem select:item];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    [self updateControls];
}

#pragma mark - Trascinamento

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item
{
    NSPasteboardItem *pb = [NSPasteboardItem new];
    [pb setString:@"x" forType:RTDragType];
    return pb;
}

- (void)outlineView:(NSOutlineView *)outlineView draggingSession:(NSDraggingSession *)session
   willBeginAtPoint:(NSPoint)screenPoint forItems:(NSArray *)draggedItems
{
    self.draggedItem = draggedItems.firstObject;
}

- (void)outlineView:(NSOutlineView *)outlineView draggingSession:(NSDraggingSession *)session
       endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation
{
    self.draggedItem = nil;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id<NSDraggingInfo>)info
                  proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    id dragged = self.draggedItem;
    if (!dragged) {
        if (![self playlistFilesIn:info].count || !self.doc) return NSDragOperationNone;
        // si importa nel gruppo su cui si lascia il file (o in quello della stazione)
        id target = [item isKindOfClass:[RTDocStation class]] ? [(RTDocStation *)item group] : item;
        [outlineView setDropItem:target dropChildIndex:NSOutlineViewDropOnItemIndex];
        return NSDragOperationCopy;
    }
    if ([self filtering]) return NSDragOperationNone;
    if ([dragged isKindOfClass:[RTDocGroup class]]) {
        // i gruppi si riordinano solo al primo livello
        if (item != nil || index == NSOutlineViewDropOnItemIndex) return NSDragOperationNone;
        return NSDragOperationMove;
    }
    // una stazione va dentro un gruppo (in una posizione, o in fondo se lasciata sul gruppo)
    if (![item isKindOfClass:[RTDocGroup class]]) return NSDragOperationNone;
    return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
    id dragged = self.draggedItem;
    if (!dragged) {
        NSArray<NSURL *> *files = [self playlistFilesIn:info];
        if (!files.count) return NO;
        RTDocGroup *group = [item isKindOfClass:[RTDocGroup class]] ? item : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ [self importFiles:files intoGroup:group]; });
        return YES;
    }
    if ([dragged isKindOfClass:[RTDocGroup class]]) {
        NSUInteger from = [self.doc.groups indexOfObject:dragged];
        NSUInteger to = (NSUInteger)MAX(0, index);
        if (from < to) to--;   // la rimozione sposta indietro le posizioni successive
        return [self commit:[self.doc moveGroup:dragged toIndex:to] select:dragged];
    }
    if ([dragged isKindOfClass:[RTDocStation class]] && [item isKindOfClass:[RTDocGroup class]]) {
        RTDocStation *s = dragged;
        RTDocGroup *g = item;
        NSUInteger to = index == NSOutlineViewDropOnItemIndex ? g.stations.count : (NSUInteger)index;
        if (s.group == g) {
            NSUInteger from = [g.stations indexOfObject:s];
            if (from < to) to--;
        }
        return [self commit:[self.doc moveStation:s toGroup:g atIndex:to] select:s];
    }
    return NO;
}

@end
