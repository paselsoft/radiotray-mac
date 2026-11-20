#import "RTShowsWindowController.h"
#import "RTAlarm.h"
#import "RTBookmarks.h"
#import "RTShows.h"
#import "RTTableCell.h"

static NSString *const kColImage = @"image";
static NSString *const kColName = @"name";
static NSString *const kColStation = @"station";
static NSString *const kColWhen = @"when";

@interface RTShowsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *shows;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSButton *editButton;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSTextField *status;
@property (nonatomic, weak, nullable) NSTextField *imageField;   // campo Foto della scheda aperta
@end

@implementation RTShowsWindowController

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 360)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = @"Palinsesto personale";
    window.minSize = NSMakeSize(600, 260);
    window.releasedWhenClosed = NO;
    window.frameAutosaveName = @"RadioTrayShows";
    if ((self = [super initWithWindow:window])) {
        _shows = [NSMutableArray array];
        [self buildContent];
        [window center];
    }
    return self;
}

- (NSButton *)button:(NSString *)title action:(SEL)action x:(CGFloat)x width:(CGFloat)width
{
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.frame = NSMakeRect(x, 12, width, 32);
    b.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [self.window.contentView addSubview:b];
    return b;
}

- (void)buildContent
{
    NSView *content = self.window.contentView;
    CGFloat w = content.bounds.size.width, h = content.bounds.size.height;
    NSTextField *info = [NSTextField wrappingLabelWithString:
        @"I programmi che segui: quando ascolti quella stazione in quell'orario, al posto di \"In riproduzione\" e del logo "
        @"si vedono il nome del programma e la foto. Utile per le radio che non lo mandano, come Radio 24."];
    info.frame = NSMakeRect(20, h - 52, w - 40, 36);
    info.textColor = [NSColor secondaryLabelColor];
    info.font = [NSFont systemFontOfSize:11];
    info.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:info];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 56, w - 40, h - 116)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTableView *table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    table.usesAlternatingRowBackgroundColors = YES;
    table.rowHeight = 34;
    table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NSArray *cols = @[@[kColImage, @"", @36], @[kColName, @"Programma", @220], @[kColStation, @"Stazione", @150], @[kColWhen, @"Quando", @220]];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        [table addTableColumn:col];
    }
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.doubleAction = @selector(edit:);
    scroll.documentView = table;
    [content addSubview:scroll];
    self.table = table;

    [self button:@"Nuovo programma…" action:@selector(add:) x:14 width:170];
    self.editButton = [self button:@"Modifica…" action:@selector(edit:) x:184 width:110];
    self.removeButton = [self button:@"Elimina" action:@selector(remove:) x:294 width:100];
    self.status = [NSTextField labelWithString:@""];
    self.status.frame = NSMakeRect(404, 20, w - 424, 16);
    self.status.textColor = [NSColor secondaryLabelColor];
    self.status.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:self.status];
    [self updateButtons];
}

- (void)showShows:(NSArray<NSDictionary *> *)shows
{
    [self.shows removeAllObjects];
    for (NSDictionary *s in shows) [self.shows addObject:[s mutableCopy]];
    [self.table reloadData];
    [self updateButtons];
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)save
{
    [self.table reloadData];
    [self updateButtons];
    [self.delegate showsDidChange:[self.shows copy]];
}

- (void)updateButtons
{
    BOOL selected = self.table.selectedRow >= 0;
    self.editButton.enabled = selected;
    self.removeButton.enabled = selected;
}

+ (NSString *)describeWhen:(NSDictionary *)s
{
    return [NSString stringWithFormat:@"%@ · %@", [RTAlarm describeDays:(RTAlarmDays)[s[@"days"] unsignedIntegerValue]],
            [s[@"slots"] isKindOfClass:[NSString class]] ? s[@"slots"] : @""];
}

#pragma mark - Foto

- (NSString *)newImagePathWithExtension:(NSString *)ext
{
    NSString *dir = [self.delegate showsImageFolder];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [NSUUID UUID].UUIDString, ext.length ? ext : @"img"]];
}

/// La foto scelta: un file sul Mac (copiato nella cartella di RadioTray) o un indirizzo web (scaricato).
- (void)storeImage:(NSString *)source forShow:(NSMutableDictionary *)show
{
    source = [source stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([source isEqualToString:show[@"image"] ?: @""]) return;
    if (!source.length) {
        [show removeObjectForKey:@"image"];
        return;
    }
    NSString *lower = source.lowercaseString;
    if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) {
        NSString *dest = [self newImagePathWithExtension:source.pathExtension.lowercaseString];
        if ([[NSFileManager defaultManager] copyItemAtPath:source.stringByExpandingTildeInPath toPath:dest error:NULL]) show[@"image"] = dest;
        return;
    }
    self.status.stringValue = @"Scaricamento della foto…";
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:source]];
    req.timeoutInterval = 15;
    [req setValue:@"Mozilla/5.0 (Macintosh) RadioTray-Mac" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        NSImage *image = data.length ? [[NSImage alloc] initWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!image || image.size.width < 8) {
                self.status.stringValue = @"Foto non scaricata: serve l'indirizzo di un'immagine (PNG, JPG…).";
                return;
            }
            NSString *dest = [self newImagePathWithExtension:@"img"];
            if (![data writeToFile:dest atomically:YES]) return;
            show[@"image"] = dest;
            self.status.stringValue = @"Foto salvata.";
            [self save];
        });
    }] resume];
}

#pragma mark - Modifica

- (BOOL)editShow:(NSMutableDictionary *)s title:(NSString *)title
{
    RTBookmarks *bookmarks = [self.delegate showsBookmarks];
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    [alert addButtonWithTitle:@"Salva"];
    [alert addButtonWithTitle:@"Annulla"];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 196)];
    void (^label)(NSString *, CGFloat) = ^(NSString *text, CGFloat y) {
        NSTextField *l = [NSTextField labelWithString:text];
        l.frame = NSMakeRect(0, y, 84, 20);
        [view addSubview:l];
    };
    NSTextField *(^field)(CGFloat, NSString *, NSString *) = ^NSTextField *(CGFloat y, NSString *value, NSString *placeholder) {
        NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(90, y - 2, 330, 24)];
        f.stringValue = value ?: @"";
        f.placeholderString = placeholder;
        [view addSubview:f];
        return f;
    };
    label(@"Programma:", 172);
    NSTextField *name = field(172, s[@"name"], @"per esempio: Melog");
    label(@"Con:", 142);
    NSTextField *host = field(142, s[@"host"], @"per esempio: Gianluca Nicoletti");

    label(@"Stazione:", 112);
    NSPopUpButton *stations = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(86, 107, 334, 26) pullsDown:NO];
    for (RTGroup *g in bookmarks.groups) {
        for (RTStation *st in g.stations) {
            [stations addItemWithTitle:g.isRoot ? st.name : [NSString stringWithFormat:@"%@ ▸ %@", g.name, st.name]];
            stations.lastItem.representedObject = @[g.name, st.name];
            if ([g.name isEqualToString:s[@"group"] ?: @""] && [st.name isEqualToString:s[@"station"] ?: @""]) [stations selectItem:stations.lastItem];
        }
    }
    [view addSubview:stations];

    label(@"Giorni:", 82);
    NSArray *dayNames = @[@"Lu", @"Ma", @"Me", @"Gi", @"Ve", @"Sa", @"Do"];
    NSMutableArray<NSButton *> *dayBoxes = [NSMutableArray array];
    NSUInteger days = [s[@"days"] unsignedIntegerValue];
    for (NSUInteger i = 0; i < 7; i++) {
        NSButton *b = [NSButton checkboxWithTitle:dayNames[i] target:nil action:NULL];
        b.frame = NSMakeRect(90 + i * 46, 82, 46, 20);
        b.state = (days & (1u << i)) ? NSControlStateValueOn : NSControlStateValueOff;
        [view addSubview:b];
        [dayBoxes addObject:b];
    }
    label(@"Orari:", 52);
    NSTextField *slots = field(52, s[@"slots"], @"per esempio: 12:15-13:00, 23:10-24:00");

    label(@"Foto:", 22);
    NSTextField *image = [[NSTextField alloc] initWithFrame:NSMakeRect(90, 20, 240, 24)];
    image.stringValue = s[@"image"] ?: @"";
    image.placeholderString = @"indirizzo dell'immagine o file";
    [view addSubview:image];
    NSButton *choose = [NSButton buttonWithTitle:@"Scegli file…" target:nil action:NULL];
    choose.bezelStyle = NSBezelStyleRounded;
    choose.frame = NSMakeRect(332, 16, 92, 32);
    [view addSubview:choose];
    choose.target = self;
    choose.action = @selector(chooseImageFile:);
    self.imageField = image;

    NSTextField *hint = [NSTextField labelWithString:@"Foto: in Safari clic destro sull'immagine ▸ Copia indirizzo immagine, poi incolla."];
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.frame = NSMakeRect(90, 0, 330, 14);
    [view addSubview:hint];

    alert.accessoryView = view;
    alert.window.initialFirstResponder = name;
    if (stations.numberOfItems == 0) return NO;
    while (YES) {
        if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
        NSUInteger chosen = 0;
        for (NSUInteger i = 0; i < 7; i++) if (dayBoxes[i].state == NSControlStateValueOn) chosen |= (1u << i);
        NSString *n = [name.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *problem = nil;
        if (!n.length) problem = @"Scrivi il nome del programma.";
        else if (!chosen) problem = @"Scegli almeno un giorno della settimana.";
        else if (![RTShows slotsFromString:slots.stringValue]) problem = @"Scrivi gli orari così: 12:15-13:00 (più orari separati da virgole; 24:00 per la mezzanotte).";
        if (!problem) {
            NSArray *key = stations.selectedItem.representedObject;
            s[@"name"] = n;
            s[@"host"] = [host.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            s[@"group"] = key[0];
            s[@"station"] = key[1];
            s[@"days"] = @(chosen);
            s[@"slots"] = [slots.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [self storeImage:image.stringValue forShow:s];
            return YES;
        }
        NSAlert *bad = [NSAlert new];
        bad.messageText = problem;
        [bad runModal];
    }
}

- (void)chooseImageFile:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"png", @"jpg", @"jpeg", @"gif", @"tif", @"tiff", @"bmp", @"heic"];
    panel.prompt = @"Usa come foto";
    if ([panel runModal] == NSModalResponseOK && panel.URL) self.imageField.stringValue = panel.URL.path;
}

- (void)add:(id)sender
{
    NSMutableDictionary *s = [@{ @"days": @(RTAlarmWeekdays) } mutableCopy];
    if (![self editShow:s title:@"Nuovo programma"]) return;
    [self.shows addObject:s];
    [self save];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:self.shows.count - 1] byExtendingSelection:NO];
}

- (void)edit:(id)sender
{
    NSInteger row = self.table.clickedRow >= 0 ? self.table.clickedRow : self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.shows.count) return;
    NSMutableDictionary *s = self.shows[(NSUInteger)row];
    NSMutableDictionary *copy = [s mutableCopy];
    if (![self editShow:copy title:@"Modifica programma"]) return;
    self.shows[(NSUInteger)row] = copy;
    [self save];
}

- (void)remove:(id)sender
{
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.shows.count) return;
    [self.shows removeObjectAtIndex:(NSUInteger)row];
    [self save];
}

#pragma mark - Tabella

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.shows.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSDictionary *s = self.shows[(NSUInteger)row];
    if ([column.identifier isEqualToString:kColImage]) {
        NSImageView *iv = [NSImageView new];
        iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        NSString *path = s[@"image"];
        NSImage *img = path.length ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
        iv.image = img ? [RTTableCell thumbnail:img side:30] : nil;
        return iv;
    }
    RTTableCell *cell = [RTTableCell cellInTable:tableView identifier:column.identifier owner:self];
    NSString *text;
    if ([column.identifier isEqualToString:kColName]) {
        text = [s[@"host"] length] ? [NSString stringWithFormat:@"%@ – con %@", s[@"name"], s[@"host"]] : s[@"name"];
    } else if ([column.identifier isEqualToString:kColStation]) {
        text = s[@"station"];
    } else {
        text = [RTShowsWindowController describeWhen:s];
    }
    cell.textField.stringValue = text ?: @"";
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButtons];
}

@end
