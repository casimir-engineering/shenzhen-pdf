#import "SPDFMacAIChatHistoryView.h"
#import "SPDFMacPanelSearchField.h"
#import "SPDFMacGroupActionButton.h"
#import "SPDFMacCollectionStyle.h"
@interface SPDFChatHistoryTable : NSTableView
@property(copy) void (^openSelection)(NSInteger);
@end
@implementation SPDFChatHistoryTable
- (void)keyDown:(NSEvent*)event {
    if((event.keyCode==36 || event.keyCode==76) && self.selectedRow>=0) {if(self.openSelection)self.openSelection(self.selectedRow);return;}
    [super keyDown:event];
}
@end
@implementation SPDFMacAIChatHistoryView {
    NSSearchField* _search; NSTableView* _table; NSArray* _chats; NSTextField* _empty;
}
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(NSRect)dirty {(void)dirty;[SPDFCollectionColor(@"window") setFill];NSRectFill(self.bounds);}
- (void)viewDidChangeEffectiveAppearance {[super viewDidChangeEffectiveAppearance];self.needsDisplay=YES;}
- (NSSearchField*)search {return _search;}
- (instancetype)initWithFrame:(NSRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    _search=[NSSearchField new];SPDFConfigurePanelSearchField(_search);_search.placeholderString=@"Search chats";
    _search.accessibilityLabel=@"Search previous chats";_search.delegate=self;_search.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:_search];
    NSButton* add=[SPDFGroupActionButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"square.and.pencil" accessibilityDescription:nil] target:self action:@selector(newChat:)];
    add.bordered=NO;add.toolTip=@"New chat";add.accessibilityLabel=add.toolTip;add.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:add];
    NSScrollView* scroll=[NSScrollView new];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;scroll.drawsBackground=NO;
    scroll.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:scroll];
    _table=[SPDFChatHistoryTable new];_table.headerView=nil;_table.rowHeight=36;_table.backgroundColor=NSColor.clearColor;
    NSTableColumn* column=[[NSTableColumn alloc] initWithIdentifier:@"chat"];column.resizingMask=NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];_table.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
    _table.dataSource=self;_table.delegate=self;_table.target=self;_table.action=@selector(openChat:);scroll.documentView=_table;
    __weak SPDFMacAIChatHistoryView* owner=self;
    ((SPDFChatHistoryTable*)_table).openSelection=^(NSInteger row){
        SPDFMacAIChatHistoryView* strong=owner;
        if(strong && row>=0 && row<(NSInteger)strong->_chats.count && strong.action)
            strong.action([@"load:" stringByAppendingString:strong->_chats[(NSUInteger)row][@"id"]]);
    };
    NSMenu* menu=[NSMenu new];[menu addItemWithTitle:@"Delete chat…" action:@selector(deleteChat:) keyEquivalent:@""].target=self;
    [menu addItem:NSMenuItem.separatorItem];[menu addItemWithTitle:@"Delete all chats…" action:@selector(deleteAll:) keyEquivalent:@""].target=self;_table.menu=menu;
    _empty=SPDFCollectionText(@"No chats yet. Start a new chat with + or ⌘K, then Return.",12,NSFontWeightRegular,YES);
    _empty.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:_empty];
    [NSLayoutConstraint activateConstraints:@[
        [_search.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],[_search.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [_search.heightAnchor constraintEqualToConstant:30],[_search.trailingAnchor constraintEqualToAnchor:add.leadingAnchor constant:-6],
        [add.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],[add.centerYAnchor constraintEqualToAnchor:_search.centerYAnchor],
        [add.widthAnchor constraintEqualToConstant:28],[add.heightAnchor constraintEqualToConstant:28],
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],[scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
        [scroll.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:8],[scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_empty.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],[_empty.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_empty.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:24]]];return self;
}
- (void)displayChats:(NSArray*)chats selectedID:(NSString*)identifier {
    _chats=chats;[_table reloadData];[_table deselectAll:nil];_empty.hidden=chats.count>0;
    _empty.stringValue=_search.stringValue.length ? @"No matching chats" : @"No chats yet. Start one with New chat or ⌘K, then Return.";
    for(NSUInteger i=0;i<chats.count;i++)if([chats[i][@"id"] isEqual:identifier])[_table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { (void)table;return _chats.count; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    (void)table;(void)column;NSDictionary* chat=_chats[(NSUInteger)row];
    NSTableCellView* cell=[NSTableCellView new];
    NSTextField* field=[NSTextField labelWithString:chat[@"title"] ?: @"New chat"];field.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    field.lineBreakMode=NSLineBreakByTruncatingTail;field.toolTip=field.stringValue;
    field.translatesAutoresizingMaskIntoConstraints=NO;[cell addSubview:field];cell.textField=field;
    [NSLayoutConstraint activateConstraints:@[[field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
        [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],[field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];return cell;
}
- (void)controlTextDidChange:(NSNotification*)note {(void)note;if(self.searchChanged)self.searchChanged(_search.stringValue);}
- (void)newChat:(id)sender {(void)sender;if(self.action)self.action(@"new");}
- (void)openChat:(id)sender {(void)sender;NSInteger row=_table.clickedRow>=0 ? _table.clickedRow : _table.selectedRow;if(row>=0 && row<(NSInteger)_chats.count && self.action)self.action([@"load:" stringByAppendingString:_chats[(NSUInteger)row][@"id"]]);}
- (void)deleteChat:(id)sender {(void)sender;NSInteger row=_table.clickedRow>=0 ? _table.clickedRow : _table.selectedRow;if(row>=0 && row<(NSInteger)_chats.count && self.action)self.action([@"delete:" stringByAppendingString:_chats[(NSUInteger)row][@"id"]]);}
- (void)deleteAll:(id)sender {(void)sender;if(self.action)self.action(@"deleteAll");}
@end
