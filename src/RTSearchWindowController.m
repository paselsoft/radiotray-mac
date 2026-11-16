#import "RTSearchWindowController.h"
#import "RTRadioBrowser.h"
#import "RTTableCell.h"

static NSString *const kColName = @"name";
static NSString *const kColCountry = @"country";
static NSString *const kColFormat = @"format";
static NSString *const kColTags = @"tags";

@interface RTSearchWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSPopUpButton *countryPopup;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) RTRadioBrowser *browser;
@property (nonatomic, copy) NSArray<RTFoundStation *> *results;
@end

@implementation RTSearchWindowController

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 460)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = @"Cerca stazioni";
    window.minSize = NSMakeSize(560, 300);
    window.releasedWhenClosed = NO;
    window.frameAutosaveName = @"RadioTraySearchWindow";
    if ((self = [super initWithWindow:window])) {
        _browser = [RTRadioBrowser new];
        _results = @[];
        window.delegate = self;
        [self buildContent];
        [window center];
    }
    return self;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    return b;
}

- (void)buildContent
{
    NSView *content = self.window.contentView;
    CGFloat w = content.bounds.size.width, h = content.bounds.size.height;

    // riga di ricerca
    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, h - 44, w - 210, 24)];
    self.searchField.placeholderString = @"Nome della stazione (per esempio: Radio 24, RTL, jazz)";
    self.searchField.target = self;
    self.searchField.action = @selector(search:);
    self.searchField.sendsWholeSearchString = YES;
    self.searchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:self.searchField];

    self.countryPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(w - 182, h - 46, 162, 26) pullsDown:NO];
    NSArray *countries = @[@[@"Italia", @"IT"], @[@"Tutti i paesi", @""], @[@"Svizzera", @"CH"], @[@"Regno Unito", @"GB"],
                           @[@"Stati Uniti", @"US"], @[@"Francia", @"FR"], @[@"Germania", @"DE"], @[@"Spagna", @"ES"]];
    for (NSArray *c in countries) {
        [self.countryPopup addItemWithTitle:c[0]];
        self.countryPopup.lastItem.representedObject = c[1];
    }
    self.countryPopup.target = self;
    self.countryPopup.action = @selector(search:);
    self.countryPopup.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:self.countryPopup];

    // tabella dei risultati
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 56, w - 40, h - 112)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.allowsMultipleSelection = NO;
    self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NSArray *cols = @[@[kColName, @"Stazione", @260], @[kColCountry, @"Paese", @50], @[kColFormat, @"Formato", @110],
                      @[kColTags, @"Generi", @220]];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        col.editable = NO;
        [self.table addTableColumn:col];
    }
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.target = self;
    self.table.doubleAction = @selector(play:);
    scroll.documentView = self.table;
    [content addSubview:scroll];

    // riga in basso
    self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 20, 16, 16)];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    [content addSubview:self.spinner];

    self.statusLabel = [NSTextField labelWithString:@"Scrivi il nome e premi Invio. Doppio clic per ascoltare."];
    self.statusLabel.frame = NSMakeRect(42, 19, w - 330, 18);
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:self.statusLabel];

    self.playButton = [self buttonWithTitle:@"Ascolta" action:@selector(play:)];
    self.playButton.frame = NSMakeRect(w - 280, 12, 110, 32);
    self.playButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:self.playButton];

    self.addButton = [self buttonWithTitle:@"Aggiungi…" action:@selector(add:)];
    self.addButton.frame = NSMakeRect(w - 166, 12, 146, 32);
    self.addButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.addButton.keyEquivalent = @"\r";
    [content addSubview:self.addButton];

    [self updateButtons];
}

- (void)showAndFocus
{
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.searchField];
}

#pragma mark - Ricerca

- (void)search:(id)sender
{
    NSString *text = [self.searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length < 2) {
        self.statusLabel.stringValue = @"Scrivi almeno due lettere del nome.";
        return;
    }
    NSString *country = self.countryPopup.selectedItem.representedObject;
    [self.spinner startAnimation:nil];
    self.statusLabel.stringValue = @"Ricerca in corso…";
    [self searchText:text original:text alternatives:[RTRadioBrowser alternativeNamesFor:text] country:country];
}

/// Se il nome non dà risultati si riprova con i nomi alternativi (sigle, senza "Radio"…), uno alla volta.
- (void)searchText:(NSString *)text original:(NSString *)original alternatives:(NSArray<NSString *> *)alternatives
           country:(NSString *)country
{
    __weak typeof(self) weakSelf = self;
    [self.browser searchName:text country:country completion:^(NSArray<RTFoundStation *> *stations, NSString *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (stations.count == 0 && alternatives.count) {
            strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"Nessun risultato per «%@», provo «%@»…", original, alternatives[0]];
            [strongSelf searchText:alternatives[0] original:original
                      alternatives:[alternatives subarrayWithRange:NSMakeRange(1, alternatives.count - 1)] country:country];
            return;
        }
        [strongSelf.spinner stopAnimation:nil];
        if (!stations) {
            strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"Ricerca non riuscita: %@", error];
            return;
        }
        strongSelf.results = stations;
        [strongSelf.table reloadData];
        [strongSelf.table scrollRowToVisible:0];
        if (stations.count) [strongSelf.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        NSUInteger unplayable = 0;
        for (RTFoundStation *s in stations) if (!s.playable) unplayable++;
        NSString *how = [text isEqualToString:original] ? @"" : [NSString stringWithFormat:@" per «%@»", text];
        if (stations.count == 0) {
            strongSelf.statusLabel.stringValue = @"Nessuna stazione trovata. Prova con un nome più corto o con \"Tutti i paesi\".";
        } else if (unplayable) {
            strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"%lu %@%@ (%lu in grigio: formato non supportato da macOS)",
                                                  (unsigned long)stations.count, stations.count == 1 ? @"stazione" : @"stazioni", how, (unsigned long)unplayable];
        } else {
            strongSelf.statusLabel.stringValue = [NSString stringWithFormat:@"%lu %@%@", (unsigned long)stations.count,
                                                  stations.count == 1 ? @"stazione" : @"stazioni", how];
        }
        [strongSelf updateButtons];
    }];
}

- (RTFoundStation *)selected
{
    NSInteger row = self.table.selectedRow;
    return row >= 0 && row < (NSInteger)self.results.count ? self.results[(NSUInteger)row] : nil;
}

- (void)updateButtons
{
    RTFoundStation *s = [self selected];
    self.playButton.enabled = s.playable;
    self.addButton.enabled = s.playable;
}

- (void)play:(id)sender
{
    RTFoundStation *s = [self selected];
    if (!s.playable) return;
    [self.delegate searchWindowPlayStation:s.name url:s.url];
}

- (void)add:(id)sender
{
    RTFoundStation *s = [self selected];
    if (!s.playable) return;
    [self.delegate searchWindowAddStation:s.name url:s.url];
}

#pragma mark - Tabella

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.results.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    RTTableCell *cell = [RTTableCell cellInTable:tableView identifier:column.identifier owner:self];
    RTFoundStation *s = self.results[(NSUInteger)row];
    NSString *value = @"";
    if ([column.identifier isEqualToString:kColName]) value = s.name;
    else if ([column.identifier isEqualToString:kColCountry]) value = s.country;
    else if ([column.identifier isEqualToString:kColFormat]) value = s.formatDescription;
    else if ([column.identifier isEqualToString:kColTags]) value = s.tags;
    cell.textField.stringValue = value ?: @"";
    cell.normalColor = s.playable ? [NSColor labelColor] : [NSColor tertiaryLabelColor];
    cell.toolTip = s.url;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButtons];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self.browser cancel];
}

@end
