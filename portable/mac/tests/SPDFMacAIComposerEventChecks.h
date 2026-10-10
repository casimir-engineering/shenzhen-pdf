// Event-dispatch coverage: no direct composer keyDown or palette activation calls.
// NSApplication runs the real search monitor; NSWindow dispatches chat keys. A
// never-ordered panel is not the application key window, so it cannot receive
// NSApplication native forwarding without activating a user-visible app.
#import "SPDFMacPalettePresentation.h"
#import "SPDFMacAIChatWindow.h"
#import "SPDFMacUnsavedImageClose.h"
@interface ShenzhenMacDelegate (ChatWindowMenuProbe)
- (void)closeDocument:(id)sender;
@end
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
// Preserve the production window responder/Escape implementation; suppress only ordering.
@interface SPDFChatDocumentWindow : NSWindow @end
@interface ComposerInvisibleChatWindow : SPDFChatDocumentWindow
@property(nonatomic) BOOL fixtureVisible;
@end
@implementation ComposerInvisibleChatWindow
- (BOOL)isKeyWindow { return self.fixtureVisible; }
- (void)makeKeyAndOrderFront:(id)sender { (void)sender;self.fixtureVisible=YES; }
- (void)orderOut:(id)sender { (void)sender;self.fixtureVisible=NO; }
- (BOOL)isVisible { return self.fixtureVisible; }
@end
@interface SPDFMacAIChatWindow (WindowTestSeam)
+ (NSWindow*)newChatWindow;
- (void)applicationBecameActive:(NSNotification*)note;
- (void)applicationResignedActive:(NSNotification*)note;
- (BOOL)isReaderApplication:(NSRunningApplication*)application;
@end
@interface ComposerApplicationIdentity : NSObject
@property(nonatomic) pid_t processIdentifier;
@property(nonatomic) NSString* bundleIdentifier;
@end
@implementation ComposerApplicationIdentity @end
@interface ComposerChatWindowController : SPDFMacAIChatWindow @end
@implementation ComposerChatWindowController
+ (NSWindow*)newChatWindow {
    return [[ComposerInvisibleChatWindow alloc] initWithContentRect:NSMakeRect(0,0,650,600)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
}
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
- (SPDFMacAIChatWindow*)aiCreateChatWindowForView:(NSView*)view {
    return [[ComposerChatWindowController alloc] initWithContentView:view preferencesURL:SPDFMacAIChatWindow.defaultPreferencesURL];
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
    Check(!reader.aiChatWindow && ![NSFileManager.defaultManager fileExistsAtPath:SPDFMacAIChatWindow.defaultPreferencesURL.path],
        "reader and search setup do not create chat window preferences eagerly");
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
    NSWindow* chat=reader.aiChatWindow;SPDFMacAIChatWindow* controller=[state valueForKey:@"chatWindow"];
    Check(chat && chat!=panel && ![chat isKindOfClass:NSPanel.class] && chat.contentView==view && chat.firstResponder==view.composer,
        "chat is an independent native window with composer first responder");
    Check((chat.styleMask & NSWindowStyleMaskTitled) && (chat.styleMask & NSWindowStyleMaskClosable) &&
        (chat.styleMask & NSWindowStyleMaskMiniaturizable) && (chat.styleMask & NSWindowStyleMaskResizable) &&
        !chat.excludedFromWindowsMenu && !chat.hidesOnDeactivate && !chat.parentWindow,
        "chat supports native close minimize resize window switching and independent ordering");
    Check(!panel.visible && panel.contentView!=view && controller.pinMode==SPDFMacAIChatPinNormal && chat.level==NSNormalWindowLevel,
        "search remains a search panel and ordinary chat starts unpinned");
    view.composer.string=@"Send through application event dispatch";
    [chat sendEvent:ComposerReturn(NO,chat.windowNumber)];
    Check(ComposerWait(^BOOL{return [session.chat[@"messages"] count]==2 && !session.running;}),
        "NSWindow Return sends through actual chat lifecycle");
    Check(ComposerRequestCount()==before+1 && reader.chatOpens==1 && !reader.settingsOpens && !view.composer.string.length,
        "search monitor is removed and chat responder dispatch sends exactly once");
    view.composer.string=@"New line";[view.composer setSelectedRange:NSMakeRange(view.composer.string.length,0)];
    before=ComposerRequestCount();
    [chat sendEvent:ComposerReturn(YES,chat.windowNumber)];
    Check([view.composer.string isEqual:@"New line\n"] && ComposerRequestCount()==before,
        "NSWindow Shift Return inserts a newline without sending");
    view.composer.string=@"Window dispatch";
    [chat sendEvent:ComposerReturn(NO,chat.windowNumber)];
    Check(ComposerWait(^BOOL{return [session.chat[@"messages"] count]==4 && !session.running;}),
        "NSWindow Return dispatch also sends through first responder");
    Check(chat.firstResponder==view.composer && reader.chatOpens==1 && !reader.settingsOpens,
        "composer focus survives request completion");
    ComposerApplicationIdentity* identity=[ComposerApplicationIdentity new];identity.processIdentifier=-1;
    identity.bundleIdentifier=@"org.shenzhenpdf.reader.collection";
    Check([controller isReaderApplication:(NSRunningApplication*)identity],"Collection companion counts as a reader application for app-only pin");
    identity.bundleIdentifier=@"com.example.unrelated";
    Check(![controller isReaderApplication:(NSRunningApplication*)identity],"unrelated application cannot retain app-only pin");
    [controller applicationBecameActive:nil];[controller togglePinMode:SPDFMacAIChatPinApplication];
    Check(controller.pinMode==SPDFMacAIChatPinApplication && chat.level>NSNormalWindowLevel,"app-only pin elevates while reader is active");
    [controller applicationResignedActive:nil];Check(chat.level==NSNormalWindowLevel,"app-only pin never floats above foreign applications");
    [controller applicationBecameActive:nil];Check(chat.level>NSNormalWindowLevel,"app-only pin resumes on reader activation");
    [controller togglePinMode:SPDFMacAIChatPinAllApplications];[controller applicationResignedActive:nil];
    Check(controller.pinMode==SPDFMacAIChatPinAllApplications && chat.level==NSFloatingWindowLevel,"all-applications pin remains floating while inactive");
    ComposerChatWindowController* restored=[[ComposerChatWindowController alloc] initWithContentView:[NSView new]
        preferencesURL:SPDFMacAIChatWindow.defaultPreferencesURL];
    Check(restored.pinMode==SPDFMacAIChatPinAllApplications,"pin preference restores from YAML");
    [controller togglePinMode:SPDFMacAIChatPinAllApplications];Check(chat.level==NSNormalWindowLevel && controller.pinMode==0,"selected pin toggle returns to ordinary mode");
    NSString* chatID=session.chat[@"id"];view.composer.string=@"Draft survives close";
    [chat performClose:nil];
    Check(!chat.visible && [session.chat[@"id"] isEqual:chatID] && [view.composer.string isEqual:@"Draft survives close"],"native close keeps conversation and unsent draft");
    [reader showAIChat:nil];Check(reader.aiChatWindow==chat && chat.visible && [session.chat[@"id"] isEqual:chatID] &&
        [view.composer.string isEqual:@"Draft survives close"],"reopen reuses independent window and preserves conversation");
    NSMenuItem* closeItem=[[NSMenuItem alloc] initWithTitle:@"Close" action:@selector(closeDocument:) keyEquivalent:@"w"];
    Check([reader validateMenuItem:closeItem],"File Close remains available when chat is key and no document is open");
    [reader closeDocument:nil];Check(!chat.visible && [view.composer.string isEqual:@"Draft survives close"],
        "File Close targets chat rather than closing an underlying document");
    [reader showAIChat:nil];
    [reader showPaletteWithTitle:@"Search"];
    Check(chat.visible && panel.visible && panel.contentView!=view,"opening search does not replace or hide chat");
    [reader closePalette:nil];
    NSEvent* escape=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:chat.windowNumber context:nil characters:@"\x1b" charactersIgnoringModifiers:@"\x1b" isARepeat:NO keyCode:53];
    [chat sendEvent:escape];Check(!chat.visible && [view.composer.string isEqual:@"Draft survives close"],"Escape closes only chat and preserves draft");
    [reader closeAIChat];[reader closePalette:nil];[panel close];
}
