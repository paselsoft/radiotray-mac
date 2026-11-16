#import "RTStationCheckWindowController.h"
#import "RTBookmarksDocument.h"
#import "RTRadioBrowser.h"
#import "RTStationChecker.h"
#import "RTTableCell.h"

static NSString *const kColStation = @"station";
static NSString *const kColResult = @"result";
static NSString *const kColProposal = @"proposal";
static const NSUInteger RTParallelChecks = 3;

typedef NS_ENUM(NSInteger, RTCheckState) { RTCheckWaiting, RTCheckRunning, RTCheckOK, RTCheckFailed };

@interface RTCheckRow : NSObject
@property (nonatomic, copy) NSString *group;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;
@property (nonatomic) BOOL direct;
@property (nonatomic) RTCheckState state;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, strong, nullable) RTFoundStation *proposal;
@property (nonatomic) BOOL searchingProposal;
@end
@implementation RTCheckRow
@end

@interface RTStationCheckWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) NSMutableArray<RTCheckRow *> *rows;
@property (nonatomic, strong) NSMutableArray<RTStationChecker *> *checkers;
@property (nonatomic, strong) RTRadioBrowser *browser;
@property (nonatomic, strong) NSMutableArray<RTCheckRow *> *searchQueue;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSProgressIndicator *progress;
@property (nonatomic, strong) NSButton *onlyProblems;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSButton *replaceButton;
@property (nonatomic, strong) NSButton *againButton;
@end

@implementation RTStationCheckWindowController

- (instancetype)initWithBookmarksPath:(NSString *)path
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 480)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = @"Verifica le stazioni";
    window.minSize = NSMakeSize(680, 300);
    window.releasedWhenClosed = NO;
    window.frameAutosaveName = @"RadioTrayStationCheck";
    if ((self = [super initWithWindow:window])) {
        _path = [path copy];
        _rows = [NSMutableArray array];
        _checkers = [NSMutableArray array];
        _searchQueue = [NSMutableArray array];
        _browser = [RTRadioBrowser new];
        window.delegate = self;
        [self buildContent];
        [window center];
    }
    return self;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.frame = frame;
    [self.window.contentView addSubview:b];
    return b;
}

- (void)buildContent
{
    NSView *content = self.window.contentView;
    CGFloat w = content.bounds.size.width, h = content.bounds.size.height;

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, h - 36, 200, 16)];
    self.progress.indeterminate = NO;
    self.progress.style = NSProgressIndicatorStyleBar;
    self.progress.autoresizingMask = NSViewMinYMargin;
    [content addSubview:self.progress];

    self.onlyProblems = [NSButton checkboxWithTitle:@"Mostra solo le stazioni con problemi" target:self action:@selector(filterChanged:)];
    self.onlyProblems.frame = NSMakeRect(236, h - 38, 300, 20);
    self.onlyProblems.autoresizingMask = NSViewMinYMargin;
    [content addSubview:self.onlyProblems];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 84, w - 40, h - 132)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTableView *table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    table.usesAlternatingRowBackgroundColors = YES;
    table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    NSArray *cols = @[@[kColStation, @"Stazione", @240], @[kColResult, @"Esito", @220], @[kColProposal, @"Proposta dall'archivio", @300]];
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        col.editable = NO;
        [table addTableColumn:col];
    }
    table.dataSource = self;
    table.delegate = self;
    scroll.documentView = table;
    [content addSubview:scroll];
    self.table = table;

    self.againButton = [self button:@"Verifica di nuovo" action:@selector(again:) frame:NSMakeRect(14, 44, 150, 32)];
    self.playButton = [self button:@"Ascolta la proposta" action:@selector(playProposal:) frame:NSMakeRect(w - 404, 44, 180, 32)];
    self.playButton.autoresizingMask = NSViewMinXMargin;
    self.replaceButton = [self button:@"Usa l'indirizzo proposto" action:@selector(replace:) frame:NSMakeRect(w - 224, 44, 210, 32)];
    self.replaceButton.autoresizingMask = NSViewMinXMargin;

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.frame = NSMakeRect(20, 16, w - 40, 18);
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.statusLabel.autoresizingMask = NSViewWidthSizable;
    [content addSubview:self.statusLabel];
}

- (void)showAndStart
{
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self start];
}

#pragma mark - Verifica

- (void)start
{
    for (RTStationChecker *c in self.checkers) [c cancel];
    [self.checkers removeAllObjects];
    [self.browser cancel];
    [self.searchQueue removeAllObjects];
    self.generation++;
    [self.rows removeAllObjects];

    NSString *error = nil;
    RTBookmarksDocument *doc = [RTBookmarksDocument documentWithData:[NSData dataWithContentsOfFile:self.path] ?: [NSData data] error:&error];
    for (RTDocGroup *g in doc.groups) {
        for (RTDocStation *s in g.stations) {
            RTCheckRow *row = [RTCheckRow new];
            row.group = g.name;
            row.name = s.name;
            row.url = s.url;
            row.state = RTCheckWaiting;
            row.detail = @"in attesa…";
            [self.rows addObject:row];
        }
    }
    self.progress.maxValue = MAX(1, self.rows.count);
    self.progress.doubleValue = 0;
    [self.table reloadData];
    if (!doc) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Il file delle stazioni ha un errore: %@", error];
        return;
    }
    for (NSUInteger i = 0; i < RTParallelChecks; i++) {
        RTStationChecker *checker = [RTStationChecker new];
        [self.checkers addObject:checker];
        [self runNextWith:checker generation:self.generation];
    }
    [self updateStatus];
}

- (void)runNextWith:(RTStationChecker *)checker generation:(NSUInteger)generation
{
    RTCheckRow *row = nil;
    for (RTCheckRow *r in self.rows) if (r.state == RTCheckWaiting) { row = r; break; }
    if (!row) {
        [self updateStatus];
        return;
    }
    row.state = RTCheckRunning;
    row.detail = @"prova in corso…";
    [self reloadRow:row];
    __weak typeof(self) weakSelf = self;
    [checker checkURL:row.url direct:row.direct completion:^(BOOL ok, NSString *detail) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.generation != generation) return;
        row.state = ok ? RTCheckOK : RTCheckFailed;
        row.detail = detail;
        strongSelf.progress.doubleValue += 1;
        if (!ok) [strongSelf queueProposalSearch:row];
        [strongSelf reloadRow:row];
        [strongSelf updateStatus];
        [strongSelf runNextWith:checker generation:generation];
    }];
}

/// Le ricerche nell'archivio una alla volta (l'archivio è gratuito: niente raffiche di richieste).
- (void)queueProposalSearch:(RTCheckRow *)row
{
    row.searchingProposal = YES;
    [self.searchQueue addObject:row];
    if (self.searchQueue.count == 1) [self searchNextProposal];
}

- (void)searchNextProposal
{
    RTCheckRow *row = self.searchQueue.firstObject;
    if (!row) return;
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    [self.browser searchName:row.name country:nil completion:^(NSArray<RTFoundStation *> *stations, NSString *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.generation != generation) return;
        row.searchingProposal = NO;
        for (RTFoundStation *s in stations) {
            if (s.playable && ![s.url isEqualToString:row.url]) {
                row.proposal = s;
                break;
            }
        }
        [strongSelf reloadRow:row];
        [strongSelf updateButtons];
        [strongSelf.searchQueue removeObject:row];
        [strongSelf searchNextProposal];
    }];
}

- (NSArray<RTCheckRow *> *)shownRows
{
    if (self.onlyProblems.state != NSControlStateValueOn) return self.rows;
    NSMutableArray *out = [NSMutableArray array];
    for (RTCheckRow *r in self.rows) if (r.state == RTCheckFailed) [out addObject:r];
    return out;
}

- (void)reloadRow:(RTCheckRow *)row
{
    NSUInteger i = [[self shownRows] indexOfObjectIdenticalTo:row];
    if (i == NSNotFound) {
        [self.table reloadData];
        return;
    }
    [self.table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:i]
                          columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.table.numberOfColumns)]];
}

- (void)updateStatus
{
    NSUInteger ok = 0, bad = 0, done = 0;
    for (RTCheckRow *r in self.rows) {
        if (r.state == RTCheckOK) ok++;
        if (r.state == RTCheckFailed) bad++;
    }
    done = ok + bad;
    if (done < self.rows.count) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Verifica in corso: %lu di %lu…", (unsigned long)done, (unsigned long)self.rows.count];
    } else if (bad == 0) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Tutte le %lu stazioni rispondono.", (unsigned long)ok];
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:
            @"%lu stazioni funzionano, %lu non rispondono. Seleziona una stazione con una proposta: \"Ascolta\" per provarla, \"Usa l'indirizzo proposto\" per sostituirla.",
            (unsigned long)ok, (unsigned long)bad];
    }
    [self updateButtons];
}

- (RTCheckRow *)selectedRow
{
    NSInteger i = self.table.selectedRow;
    NSArray *rows = [self shownRows];
    return i >= 0 && i < (NSInteger)rows.count ? rows[(NSUInteger)i] : nil;
}

- (void)updateButtons
{
    RTCheckRow *row = [self selectedRow];
    BOOL hasProposal = row.state == RTCheckFailed && row.proposal != nil;
    self.playButton.enabled = hasProposal;
    self.replaceButton.enabled = hasProposal;
}

#pragma mark - Azioni

- (void)again:(id)sender { [self start]; }

- (void)filterChanged:(id)sender
{
    [self.table reloadData];
    [self updateButtons];
}

- (void)playProposal:(id)sender
{
    RTCheckRow *row = [self selectedRow];
    if (row.proposal) [self.delegate stationCheckPlayName:row.name url:row.proposal.url];
}

- (void)replace:(id)sender
{
    RTCheckRow *row = [self selectedRow];
    if (!row.proposal) return;
    NSString *error = nil;
    RTBookmarksDocument *doc = [RTBookmarksDocument documentWithData:[NSData dataWithContentsOfFile:self.path] ?: [NSData data] error:&error];
    RTDocStation *target = nil;
    for (RTDocStation *s in [doc groupNamed:row.group].stations) if ([s.name isEqualToString:row.name]) target = s;
    NSString *problem = doc ? (target ? [doc setURL:row.proposal.url forStation:target] : @"Stazione non trovata nel file") : error;
    if (!problem) {
        NSError *writeError = nil;
        if (![[doc dataRepresentation] writeToFile:self.path options:NSDataWritingAtomic error:&writeError]) {
            problem = writeError.localizedDescription ?: @"Impossibile salvare";
        }
    }
    if (problem) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Indirizzo non sostituito";
        alert.informativeText = problem;
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    [self.delegate stationCheckDidSaveBookmarks];
    // si riprova subito la stazione con il nuovo indirizzo
    row.url = row.proposal.url;
    row.proposal = nil;
    row.state = RTCheckRunning;
    row.detail = @"prova del nuovo indirizzo…";
    [self reloadRow:row];
    RTStationChecker *checker = [RTStationChecker new];
    [self.checkers addObject:checker];
    __weak typeof(self) weakSelf = self;
    [checker checkURL:row.url direct:NO completion:^(BOOL ok, NSString *detail) {
        row.state = ok ? RTCheckOK : RTCheckFailed;
        row.detail = ok ? [@"sostituito · " stringByAppendingString:detail] : detail;
        [weakSelf reloadRow:row];
        [weakSelf updateStatus];
    }];
}

#pragma mark - Tabella

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[self shownRows].count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)rowIndex
{
    RTTableCell *cell = [RTTableCell cellInTable:tableView identifier:column.identifier owner:self];
    RTCheckRow *row = [self shownRows][(NSUInteger)rowIndex];
    NSString *text = @"";
    NSColor *color = [NSColor labelColor];
    if ([column.identifier isEqualToString:kColStation]) {
        text = [row.group isEqualToString:@"root"] ? row.name : [NSString stringWithFormat:@"%@ ▸ %@", row.group, row.name];
    } else if ([column.identifier isEqualToString:kColResult]) {
        switch (row.state) {
            case RTCheckWaiting:
            case RTCheckRunning: text = row.detail; color = [NSColor secondaryLabelColor]; break;
            case RTCheckOK:      text = [@"✅ " stringByAppendingString:row.detail]; break;
            case RTCheckFailed:  text = [@"❌ " stringByAppendingString:row.detail]; color = [NSColor systemRedColor]; break;
        }
    } else {
        if (row.state == RTCheckFailed) {
            if (row.proposal) text = [NSString stringWithFormat:@"%@ · %@", row.proposal.name, row.proposal.formatDescription];
            else text = row.searchingProposal ? @"ricerca nell'archivio…" : @"nessuna alternativa trovata";
            if (!row.proposal) color = [NSColor secondaryLabelColor];
        }
    }
    cell.textField.stringValue = text ?: @"";
    cell.normalColor = color;
    cell.toolTip = [column.identifier isEqualToString:kColProposal] ? row.proposal.url : row.url;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButtons];
}

- (void)windowWillClose:(NSNotification *)notification
{
    for (RTStationChecker *c in self.checkers) [c cancel];
    [self.browser cancel];
    self.generation++;
}

@end
