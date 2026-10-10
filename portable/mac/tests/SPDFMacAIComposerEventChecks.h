// Event-dispatch coverage: no direct composer keyDown or palette activation calls.
// NSApplication runs the real search monitor; NSWindow dispatches chat keys. A
// never-ordered panel is not the application key window, so it cannot receive
// NSApplication native forwarding without activating a user-visible app.
#import "SPDFMacPalettePresentation.h"
@interface ComposerInvisiblePanel : NSPanel
@property(nonatomic) BOOL fixtureVisible;
@property(nonatomic) NSUInteger dispatchedKeys;
@end
@implementation ComposerInvisiblePanel
- (void)makeKeyAndOrderFront:(id)sender { (void)sender;self.fixtureVisible=YES; }
- (void)orderOut:(id)sender { (void)sender;self.fixtureVisible=NO; }
- (BOOL)isVisible { return self.fixtureVisible; }
- (void)sendEvent:(NSEvent*)event { if(event.type==NSEventTypeKeyDown)self.dispatchedKeys++;[super sendEvent:event]; }
@end
@interface ComposerEventReader : ComposerReaderProbe
@property(nonatomic) NSUInteger chatOpens;
- (void)seedPalette;
- (NSPanel*)fixturePanel;
- (BOOL)searchMonitorInstalled;
@end
@implementation ComposerEventReader
- (void)seedPalette {
    _window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,700) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    _window.releasedWhenClosed=NO;
    _palettePanel=[[ComposerInvisiblePanel alloc] initWithContentRect:NSMakeRect(-20000,-20000,650,390)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
    _palettePanel.releasedWhenClosed=NO;_palettePanel.alphaValue=0;
    _paletteMode=1;_paletteSearchField=[[SPDFPaletteSearchField alloc] initWithFrame:NSMakeRect(10,10,400,30)];
    ((SPDFPaletteSearchField*)_paletteSearchField).reader=self;_paletteSearchField.delegate=self;
    _paletteTable=[NSTableView new];_paletteResults=[NSMutableArray array];
    [_palettePanel.contentView addSubview:_paletteSearchField];
}
- (NSPanel*)fixturePanel { return _palettePanel; }
- (BOOL)searchMonitorInstalled { return _paletteEventMonitor!=nil; }
- (void)refreshPaletteResults {}
- (NSArray*)paletteMenuCommandCandidates { return @[]; }
- (void)showAIChat:(id)sender { self.chatOpens++;[super showAIChat:sender]; }
@end
static void CheckComposerEventDispatch(void) {
    SaveComposerSettings(YES,YES,YES);
    ComposerEventReader* reader=[ComposerEventReader new];reader.testKey=@"sk-or-v1-offline-acceptance-only";[reader seedPalette];
    [reader showPaletteWithTitle:@"Search"];
    NSPanel* panel=[reader fixturePanel];
    Check([reader searchMonitorInstalled] && [panel.firstResponder isKindOfClass:NSTextView.class],
        "search lifecycle installs monitor and focuses search editor");
    NSUInteger before=ComposerRequestCount();
    [NSApp sendEvent:ComposerReturn(NO,panel.windowNumber)];
    Check(reader.chatOpens==1 && ![reader searchMonitorInstalled] && !reader.settingsOpens,
        "NSApplication Return transitions search to chat once and removes search monitor");
    id state=[reader readerAIState];SPDFMacAIChatView* view=[state valueForKey:@"view"];
    SPDFMacAIChatSession* session=[state valueForKey:@"session"];
    Check(panel.contentView==view && panel.firstResponder==view.composer,"chat lifecycle leaves the composer first responder");
    view.composer.string=@"Send through application event dispatch";
    [panel sendEvent:ComposerReturn(NO,panel.windowNumber)];
    Check(ComposerWait(^BOOL{return [session.chat[@"messages"] count]==2 && !session.running;}),
        "NSWindow Return sends through actual chat lifecycle");
    Check(ComposerRequestCount()==before+1 && reader.chatOpens==1 && !reader.settingsOpens && !view.composer.string.length,
        "search monitor is removed and chat responder dispatch sends exactly once");
    view.composer.string=@"New line";[view.composer setSelectedRange:NSMakeRange(view.composer.string.length,0)];
    before=ComposerRequestCount();
    [panel sendEvent:ComposerReturn(YES,panel.windowNumber)];
    Check([view.composer.string isEqual:@"New line\n"] && ComposerRequestCount()==before,
        "NSWindow Shift Return inserts a newline without sending");
    view.composer.string=@"Window dispatch";
    [panel sendEvent:ComposerReturn(NO,panel.windowNumber)];
    Check(ComposerWait(^BOOL{return [session.chat[@"messages"] count]==4 && !session.running;}),
        "NSWindow Return dispatch also sends through first responder");
    Check(panel.firstResponder==view.composer && reader.chatOpens==1 && !reader.settingsOpens,
        "composer focus survives request completion");
    [reader closeAIChat];[reader closePalette:nil];[panel close];
}
