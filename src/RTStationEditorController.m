#import "RTStationEditorController.h"
#import "RTBookmarksDocument.h"
#import "RTTableCell.h"
#import "RTStationLogo.h"

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

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 84, w - 40, h - 104)];
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
    [outline registerForDraggedTypes:@[RTDragType]];
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
    self.upButton.enabled = ok && item && index > 0;
    self.downButton.enabled = ok && item && index + 1 < count;

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

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (!item) return (NSInteger)self.doc.groups.count;
    if ([item isKindOfClass:[RTDocGroup class]]) return (NSInteger)[(RTDocGroup *)item stations].count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (!item) return self.doc.groups[(NSUInteger)index];
    return [(RTDocGroup *)item stations][(NSUInteger)index];
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
    if (!dragged) return NSDragOperationNone;
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
