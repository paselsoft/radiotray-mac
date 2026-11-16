#import "RTProgramsWindowController.h"
#import "RTAlarm.h"
#import "RTBookmarks.h"
#import "RTTableCell.h"

static NSString *const kColOn = @"on";
static NSString *const kColWhen = @"when";
static NSString *const kColStation = @"station";
static NSString *const kColName = @"name";

@interface RTProgramsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *programs;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSButton *editButton;
@property (nonatomic, strong) NSButton *removeButton;
@end

@implementation RTProgramsWindowController

+ (NSString *)describeProgram:(NSDictionary *)p
{
    NSString *when = [NSString stringWithFormat:@"%@ %@", [RTAlarm describeMinutes:[p[@"minutes"] integerValue]],
                      [RTAlarm describeDays:(RTAlarmDays)[p[@"days"] unsignedIntegerValue]]];
    NSInteger duration = [p[@"duration"] integerValue];
    NSString *station = p[@"station"] ?: @"?";
    return duration > 0 ? [NSString stringWithFormat:@"%@ · %@ · %ld min", when, station, (long)duration]
                        : [NSString stringWithFormat:@"%@ · %@", when, station];
}

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 320)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.title = @"Programmi";
    window.minSize = NSMakeSize(560, 240);
    window.releasedWhenClosed = NO;
    window.frameAutosaveName = @"RadioTrayPrograms";
    if ((self = [super initWithWindow:window])) {
        _programs = [NSMutableArray array];
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
        @"La radio si accende da sola all'ora scelta sulla stazione indicata e, se vuoi, si spegne dopo qualche minuto "
        @"(per esempio il giornale radio). Il Mac deve essere acceso. La radiosveglia resta nel menu a parte."];
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
    table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NSArray *cols = @[@[kColOn, @"Attivo", @50], @[kColWhen, @"Quando", @170], @[kColStation, @"Stazione", @200], @[kColName, @"Nome", @150]];
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
    [self updateButtons];
}

- (void)showPrograms:(NSArray<NSDictionary *> *)programs
{
    [self.programs removeAllObjects];
    for (NSDictionary *p in programs) [self.programs addObject:[p mutableCopy]];
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
    [self.delegate programsDidChange:[self.programs copy]];
}

- (void)updateButtons
{
    BOOL selected = self.table.selectedRow >= 0;
    self.editButton.enabled = selected;
    self.removeButton.enabled = selected;
}

#pragma mark - Modifica

/// Finestra di modifica; YES se l'utente ha salvato (il programma è aggiornato).
- (BOOL)editProgram:(NSMutableDictionary *)p title:(NSString *)title
{
    RTBookmarks *bookmarks = [self.delegate programsBookmarks];
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    [alert addButtonWithTitle:@"Salva"];
    [alert addButtonWithTitle:@"Annulla"];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 186)];

    NSTextField *(^label)(NSString *, CGFloat) = ^NSTextField *(NSString *text, CGFloat y) {
        NSTextField *l = [NSTextField labelWithString:text];
        l.frame = NSMakeRect(0, y, 78, 20);
        [view addSubview:l];
        return l;
    };
    label(@"Nome:", 162);
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(84, 160, 316, 24)];
    name.stringValue = p[@"name"] ?: @"";
    name.placeholderString = @"per esempio: Giornale radio";
    [view addSubview:name];

    label(@"Ora:", 130);
    NSDatePicker *picker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(84, 127, 90, 26)];
    picker.datePickerStyle = NSTextFieldAndStepperDatePickerStyle;
    picker.datePickerElements = NSHourMinuteDatePickerElementFlag;
    picker.locale = [NSLocale localeWithLocaleIdentifier:@"it_IT"];
    NSInteger minutes = [p[@"minutes"] integerValue];
    NSCalendar *cal = [NSCalendar currentCalendar];
    picker.dateValue = [cal dateBySettingHour:minutes / 60 minute:minutes % 60 second:0 ofDate:[NSDate date] options:0];
    [view addSubview:picker];

    label(@"Giorni:", 98);
    NSArray *dayNames = @[@"Lu", @"Ma", @"Me", @"Gi", @"Ve", @"Sa", @"Do"];
    NSMutableArray<NSButton *> *dayBoxes = [NSMutableArray array];
    NSUInteger days = [p[@"days"] unsignedIntegerValue];
    for (NSUInteger i = 0; i < 7; i++) {
        NSButton *b = [NSButton checkboxWithTitle:dayNames[i] target:nil action:NULL];
        b.frame = NSMakeRect(84 + i * 44, 98, 44, 20);
        b.state = (days & (1u << i)) ? NSControlStateValueOn : NSControlStateValueOff;
        [view addSubview:b];
        [dayBoxes addObject:b];
    }

    label(@"Stazione:", 66);
    NSPopUpButton *stations = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(80, 61, 320, 26) pullsDown:NO];
    for (RTGroup *g in bookmarks.groups) {
        for (RTStation *st in g.stations) {
            [stations addItemWithTitle:g.isRoot ? st.name : [NSString stringWithFormat:@"%@ ▸ %@", g.name, st.name]];
            stations.lastItem.representedObject = @[g.name, st.name];
            if ([g.name isEqualToString:p[@"group"] ?: @""] && [st.name isEqualToString:p[@"station"] ?: @""]) [stations selectItem:stations.lastItem];
        }
    }
    [view addSubview:stations];

    label(@"Spegni dopo:", 34);
    NSPopUpButton *duration = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(80, 29, 200, 26) pullsDown:NO];
    NSArray *durations = @[@0, @5, @10, @15, @20, @30, @45, @60, @90, @120];
    for (NSNumber *d in durations) {
        [duration addItemWithTitle:d.integerValue == 0 ? @"non spegnere" : [NSString stringWithFormat:@"%@ minuti", d]];
        duration.lastItem.representedObject = d;
        if ([d isEqual:p[@"duration"] ?: @0]) [duration selectItem:duration.lastItem];
    }
    [view addSubview:duration];

    NSButton *enabled = [NSButton checkboxWithTitle:@"Attivo" target:nil action:NULL];
    enabled.frame = NSMakeRect(84, 2, 200, 20);
    enabled.state = [p[@"enabled"] ?: @YES boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:enabled];

    alert.accessoryView = view;
    alert.window.initialFirstResponder = name;
    if (stations.numberOfItems == 0) {
        NSAlert *none = [NSAlert new];
        none.messageText = @"Nessuna stazione";
        none.informativeText = @"Aggiungi prima almeno una stazione.";
        [none runModal];
        return NO;
    }
    while (YES) {
        if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
        NSUInteger chosen = 0;
        for (NSUInteger i = 0; i < 7; i++) if (dayBoxes[i].state == NSControlStateValueOn) chosen |= (1u << i);
        if (chosen) {
            NSDateComponents *c = [cal components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:picker.dateValue];
            NSArray *key = stations.selectedItem.representedObject;
            NSString *n = [name.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            p[@"name"] = n.length ? n : key[1];
            p[@"minutes"] = @(c.hour * 60 + c.minute);
            p[@"days"] = @(chosen);
            p[@"group"] = key[0];
            p[@"station"] = key[1];
            p[@"duration"] = duration.selectedItem.representedObject ?: @0;
            p[@"enabled"] = @(enabled.state == NSControlStateValueOn);
            // se l'ora è appena passata non deve partire subito
            NSDate *now = [NSDate date];
            if ([RTAlarm shouldFireAt:now minutes:c.hour * 60 + c.minute days:chosen lastFired:nil calendar:cal]) p[@"lastFired"] = now;
            else [p removeObjectForKey:@"lastFired"];
            return YES;
        }
        NSAlert *noDays = [NSAlert new];
        noDays.messageText = @"Scegli almeno un giorno della settimana.";
        [noDays runModal];
    }
}

- (void)add:(id)sender
{
    NSMutableDictionary *p = [@{ @"minutes": @(18 * 60), @"days": @(RTAlarmWeekdays), @"duration": @0, @"enabled": @YES } mutableCopy];
    if (![self editProgram:p title:@"Nuovo programma"]) return;
    [self.programs addObject:p];
    [self save];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:self.programs.count - 1] byExtendingSelection:NO];
}

- (void)edit:(id)sender
{
    NSInteger row = self.table.clickedRow >= 0 ? self.table.clickedRow : self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.programs.count) return;
    NSMutableDictionary *copy = [self.programs[(NSUInteger)row] mutableCopy];
    if (![self editProgram:copy title:@"Modifica programma"]) return;
    self.programs[(NSUInteger)row] = copy;
    [self save];
}

- (void)remove:(id)sender
{
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.programs.count) return;
    [self.programs removeObjectAtIndex:(NSUInteger)row];
    [self save];
}

- (void)toggleEnabled:(NSButton *)sender
{
    NSInteger row = [self.table rowForView:sender];
    if (row < 0 || row >= (NSInteger)self.programs.count) return;
    self.programs[(NSUInteger)row][@"enabled"] = @(sender.state == NSControlStateValueOn);
    [self save];
}

#pragma mark - Tabella

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.programs.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSDictionary *p = self.programs[(NSUInteger)row];
    if ([column.identifier isEqualToString:kColOn]) {
        NSButton *box = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleEnabled:)];
        box.state = [p[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        return box;
    }
    RTTableCell *cell = [RTTableCell cellInTable:tableView identifier:column.identifier owner:self];
    NSString *text = @"";
    if ([column.identifier isEqualToString:kColWhen]) {
        text = [NSString stringWithFormat:@"%@ %@", [RTAlarm describeMinutes:[p[@"minutes"] integerValue]],
                [RTAlarm describeDays:(RTAlarmDays)[p[@"days"] unsignedIntegerValue]]];
        NSInteger d = [p[@"duration"] integerValue];
        if (d > 0) text = [text stringByAppendingFormat:@" · %ld min", (long)d];
    } else if ([column.identifier isEqualToString:kColStation]) {
        text = p[@"station"] ?: @"";
    } else {
        text = p[@"name"] ?: @"";
    }
    cell.textField.stringValue = text;
    cell.normalColor = [p[@"enabled"] boolValue] ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButtons];
}

@end
