#import "SPDFMacAIIntegration.h"
#import "SPDFMacAIChatSession.h"
#import "SPDFMacAICitations.h"
#import "SPDFMacAIChatStore.h"
#import "SPDFMacAIChatView.h"
#import "SPDFMacAITransport.h"
#import "SPDFMacAICredentials.h"
#import "SPDFMacAISettings.h"
#import "SPDFMacAITools.h"
#import "SPDFMacPalettePresentation.h"
#import "SPDFMacUnifiedSettings.h"
#import <objc/runtime.h>
@interface SPDFReaderAIState : NSObject
@property SPDFMacAIChatSession* session;
@property SPDFMacAIChatStore* store;
@property SPDFMacAITools* tools;
@property SPDFMacAIChatView* view;
@property NSView* searchContent;
@property id monitor;
@property BOOL history;
@end
@implementation SPDFReaderAIState
- (void)dealloc { if (_monitor) [NSEvent removeMonitor:_monitor]; [_session cancel]; }
@end
static char stateKey;
@implementation ShenzhenMacDelegate (SPDFMacAIIntegration)
- (SPDFReaderAIState*)readerAIState {
    SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);
    if (!state) {
        state=[SPDFReaderAIState new];
        state.store=[[SPDFMacAIChatStore alloc] initWithDirectory:SPDFMacAIChatStore.defaultDirectory];
        SPDFMacAITools* tools=[[SPDFMacAITools alloc] initWithReader:self]; state.tools=tools;
        state.session=[[SPDFMacAIChatSession alloc] initWithTransport:[[SPDFMacAITransport alloc] initWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration]
            tools:(id<SPDFMacAIChatTools>)tools definitions:SPDFMacAITools.toolDefinitions store:state.store];
        state.view=[[SPDFMacAIChatView alloc] initWithFrame:NSMakeRect(0,0,650,520)];
        objc_setAssociatedObject(self,&stateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak ShenzhenMacDelegate* owner=self; __weak SPDFReaderAIState* weakState=state;
        state.session.changed=^{
            [weakState.view refreshActivityFromSession:weakState.session];
            if (!weakState.history) [weakState.view displaySession:weakState.session];
        };
        state.view.sendText=^BOOL(NSString* text) { return [owner aiSendText:text]; };
        state.view.action=^(NSString* action) { [owner aiChatAction:action]; };
        state.view.openLink=^(NSURL* URL) { [owner aiOpenCitation:URL]; };
    }
    return state;
}
- (BOOL)isAIChatVisible {
    SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);
    return state && _palettePanel.visible && _palettePanel.contentView==state.view;
}
- (void)preparePaletteForSearch {
    SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);
    if (!state) return;
    if (state.monitor) { [NSEvent removeMonitor:state.monitor]; state.monitor=nil; }
    if (state.searchContent && _palettePanel.contentView==state.view) _palettePanel.contentView=state.searchContent;
}
- (void)showAIChat:(id)sender { (void)sender; SPDFReaderAIState* state=[self readerAIState]; [state.session newChat]; state.view.composer.string=@""; [self showAIChatForQuery:nil]; }
- (void)showAIChatForQuery:(NSString*)query {
    if (!_palettePanel) [self showPaletteWithTitle:@"Search"];
    SPDFReaderAIState* state=[self readerAIState];
    if (_palettePanel.contentView!=state.view) state.searchContent=_palettePanel.contentView;
    [self closePalette:nil]; state.history=NO;
    _palettePanel.contentView=state.view; _palettePanel.title=@"Document assistant";
    NSRect frame=[_palettePanel frameRectForContentRect:NSMakeRect(0,0,650,540)];
    NSRect screen=(_window.screen ?: NSScreen.mainScreen).visibleFrame;
    frame.size.width=MIN(frame.size.width,NSWidth(screen)-32); frame.size.height=MIN(frame.size.height,NSHeight(screen)-48);
    frame.origin=NSMakePoint(MAX(NSMinX(screen)+16,MIN(NSMidX(_window.frame)-NSWidth(frame)/2,NSMaxX(screen)-NSWidth(frame)-16)),
        MAX(NSMinY(screen)+24,MIN(NSMaxY(_window.frame)-88-NSHeight(frame),NSMaxY(screen)-NSHeight(frame)-24)));
    [_palettePanel setFrame:frame display:NO]; [state.view displaySession:state.session];
    [_palettePanel makeKeyAndOrderFront:nil]; [_palettePanel makeFirstResponder:state.view.composer];
    __weak __typeof__(self) weakSelf=self;
    state.monitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent*(NSEvent* event) {
        __typeof__(self) reader=weakSelf; if (reader && [reader isAIChatVisible] && event.window==reader->_palettePanel && event.keyCode==53) {
            [reader closeAIChat]; return nil;
        } return event;
    }];
    if (query.length) { [state.session newChat]; state.view.composer.string=query; }
}
- (void)cancelAIChat { [((SPDFReaderAIState*)objc_getAssociatedObject(self,&stateKey)).session cancel]; }
- (void)closeAIChat {
    SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);
    if (state.monitor) { [NSEvent removeMonitor:state.monitor]; state.monitor=nil; }
    [_palettePanel orderOut:nil]; [_window makeFirstResponder:_pageScrollView];
}
- (void)showAIChats:(id)sender {
    (void)sender; [self showAIChatForQuery:nil]; SPDFReaderAIState* state=[self readerAIState];
    state.history=YES; [state.view displayChats:[state.store chats]];
}
- (BOOL)aiSendText:(NSString*)text {
    SPDFMacAISettings* settings=[[SPDFMacAISettings alloc] initWithURL:SPDFMacAISettings.defaultURL];
    NSError* error=nil; [settings load:&error];
    if (!settings.enabled) { [self showAIConnectionSettingsWithReason:@"Enable document chat to send your message. Your draft is waiting in the chat."]; return NO; }
    NSString* key=[SPDFMacAICredentials APIKeyWithError:&error];
    if (!key.length) { [self showAIConnectionSettingsWithReason:@"Connect OpenRouter to send your message. Your draft is waiting in the chat."]; return NO; }
    SPDFReaderAIState* state=[self readerAIState]; state.history=NO;
    NSUInteger before=[state.session.chat[@"messages"] count];
    [state.session send:text model:settings.model apiKey:key]; return [state.session.chat[@"messages"] count]>before;
}
- (void)aiChatAction:(NSString*)action {
    SPDFReaderAIState* state=[self readerAIState];
    if ([action isEqual:@"close"]) { [self closeAIChat]; return; }
    if ([action isEqual:@"settings"]) { [self showUnifiedSettings:nil]; return; }
    if ([action isEqual:@"current"]) { state.history=NO; [state.view displaySession:state.session]; [_palettePanel makeFirstResponder:state.view.composer]; return; }
    if ([action isEqual:@"new"]) { state.history=NO; state.view.composer.string=@""; [state.session newChat]; [_palettePanel makeFirstResponder:state.view.composer]; return; }
    if ([action isEqual:@"stop"]) { [state.session cancel]; return; }
    if ([action isEqual:@"undo"]) { NSError* error=nil; [state.session undo:&error]; if (error) [self->_palettePanel presentError:error]; return; }
    if ([action isEqual:@"history"]) { state.history=YES; [state.view displayChats:[state.store chats]]; return; }
    if ([action hasPrefix:@"load:"]) {
        NSDictionary* chat=[state.store chatWithID:[action substringFromIndex:5]];
        if (chat) { state.history=NO; state.view.composer.string=@""; [state.session loadChat:chat]; [_palettePanel makeFirstResponder:state.view.composer]; } return;
    }
    if ([action isEqual:@"deleteAll"] || [action hasPrefix:@"delete:"]) {
        NSAlert* alert=[NSAlert new]; alert.messageText=[action isEqual:@"deleteAll"] ? @"Delete all chats?" : @"Delete this chat?";
        alert.informativeText=@"This removes saved conversations from this Mac. Documents and document history are unchanged.";
        [alert addButtonWithTitle:@"Delete"]; [alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:_palettePanel completionHandler:^(NSModalResponse result) {
            if (result!=NSAlertFirstButtonReturn) return;
            NSString* identifier=[action hasPrefix:@"delete:"] ? [action substringFromIndex:7] : nil;
            BOOL current=!identifier || [state.session.chat[@"id"] isEqual:identifier];
            if (current) [state.session cancel];
            NSError* error=nil; BOOL ok=identifier ? [state.store deleteChatWithID:identifier error:&error] : [state.store deleteAll:&error];
            if (ok && current) [state.session newChat];
            if (error) [self->_palettePanel presentError:error];
            state.history=YES; [state.view displayChats:[state.store chats]];
        }];
    }
}
- (void)aiOpenCitation:(NSURL*)URL {
    if ([URL.scheme.lowercaseString isEqual:@"https"]) { [NSWorkspace.sharedWorkspace openURL:URL]; return; }
    SPDFReaderAIState* state=[self readerAIState];
    NSDictionary* args=SPDFMacAICitationArguments(URL);
    if (!SPDFMacAIChatContainsCitation(state.session.chat,args)) {
        NSAlert* alert=[NSAlert new]; alert.messageText=@"This link has no retrieved evidence";
        alert.informativeText=@"Ask the assistant to retrieve the passage again before opening its citation.";
        [alert addButtonWithTitle:@"OK"]; [alert beginSheetModalForWindow:_palettePanel completionHandler:nil]; return;
    }
    [state.tools performTool:@"show_document" arguments:args completion:^(NSDictionary* result) {
        if (result[@"error"]) {
            NSAlert* alert=[NSAlert new]; alert.messageText=@"This citation is unavailable";
            alert.informativeText=[result[@"error"] description]; [alert addButtonWithTitle:@"OK"];
            [alert beginSheetModalForWindow:self->_palettePanel completionHandler:nil];
        }
        [state.view refreshActivityFromSession:state.session];
        if (!result[@"error"]) [self closeAIChat];
    }];
}
@end
