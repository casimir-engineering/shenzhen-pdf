#import "SPDFMacAIIntegration.h"
#import "SPDFMacAIChatSession.h"
#import "SPDFMacAICitations.h"
#import "SPDFMacAIChatStore.h"
#import "SPDFMacAIChatView.h"
#import "SPDFMacAIChatDock.h"
#import "SPDFMacAIChatHistoryView.h"
#import "SPDFMacSidebarWorkspace.h"
#import "SPDFMacWorkspacePanels.h"
#import "SPDFMacAITransport.h"
#import "SPDFMacAICredentials.h"
#import "SPDFMacAISettings.h"
#import "SPDFMacAITools.h"
#import "SPDFMacPalettePresentation.h"
#import "SPDFMacUnifiedSettings.h"
#import <objc/runtime.h>
@interface ShenzhenMacDelegate (AISetupHost)
- (void)showUnifiedSettingsMode:(BOOL)wizard;
- (void)persistActiveState;
- (void)rebuildSidebar;
@end
@interface SPDFReaderAIState : NSObject
@property SPDFMacAIChatSession* session;
@property SPDFMacAIChatStore* store;
@property SPDFMacAITools* tools;
@property SPDFMacAIChatView* view;
@property SPDFMacAIChatDock* dock;
@property SPDFMacAIChatHistoryView* historyView;
@property NSUInteger searchGeneration;
@property NSMutableDictionary* drafts;
@property BOOL history;
@property NSString* submissionIssue;
@property BOOL setupRequired;
@end
@implementation SPDFReaderAIState
- (void)dealloc { [_session cancel]; }
@end
static char stateKey;
@implementation ShenzhenMacDelegate (SPDFMacAIIntegration)
- (SPDFMacAITransport*)aiChatTransport {
    return [[SPDFMacAITransport alloc] initWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
}
- (NSString*)aiAPIKeyForSending:(NSError**)error { return [SPDFMacAICredentials APIKeyWithError:error]; }
- (SPDFReaderAIState*)readerAIHistoryState {
    SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);
    if(!state) {
        state=[SPDFReaderAIState new];state.drafts=[NSMutableDictionary dictionary];
        state.store=[[SPDFMacAIChatStore alloc] initWithDirectory:SPDFMacAIChatStore.defaultDirectory];
        objc_setAssociatedObject(self,&stateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
- (SPDFReaderAIState*)readerAIState {
    SPDFReaderAIState* state=[self readerAIHistoryState];
    if(!state.session) {
        SPDFMacAITools* tools=[[SPDFMacAITools alloc] initWithReader:self]; state.tools=tools;
        state.session=[[SPDFMacAIChatSession alloc] initWithTransport:[self aiChatTransport]
            tools:(id<SPDFMacAIChatTools>)tools definitions:SPDFMacAITools.toolDefinitions store:state.store];
        state.view=[[SPDFMacAIChatView alloc] initWithFrame:NSMakeRect(0,0,650,520)];
        objc_setAssociatedObject(self,&stateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak ShenzhenMacDelegate* owner=self; __weak SPDFReaderAIState* weakState=state;
        state.session.changed=^{
            [owner searchAIChats:weakState.historyView.search.stringValue ?: @""];
            [weakState.view refreshActivityFromSession:weakState.session];
            [weakState.view displaySession:weakState.session];
        };
        state.view.sendText=^BOOL(NSString* text) { return [owner aiSendText:text]; };
        state.view.action=^(NSString* action) { [owner aiChatAction:action]; };
        state.view.searchChats=^(NSString* query){ query=[query copy];[owner showAIChats:nil];weakState.historyView.search.stringValue=query;[owner searchAIChats:query]; };
        state.view.openLink=^(NSURL* URL) { [owner aiOpenCitation:URL]; };
    }
    return state;
}
- (BOOL)isAIChatVisible { return ((SPDFReaderAIState*)objc_getAssociatedObject(self,&stateKey)).dock.visible; }
- (CGFloat)aiChatReservedWidth {SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);return state.dock.visible ? MAX(320,NSWidth(state.view.frame))+1 : 0;}
- (NSWindow*)aiChatWindow { return nil; } // Chat is part of the reader; Cmd+W still closes a document.
- (void)preparePaletteForSearch {}
- (void)showAIChat:(id)sender { (void)sender;[self showAIChatForQuery:nil]; }
- (void)showAIChatForQuery:(NSString*)query {
    SPDFReaderAIState* state=[self readerAIState];[self closePalette:nil];
    if(!state.dock && _documentContainer.superview) {
        state.dock=[[SPDFMacAIChatDock alloc] initWithReaderView:_documentContainer chatView:state.view
            width:[[self sidebarWorkspaceState][@"chatWidth"] doubleValue]];
        __weak ShenzhenMacDelegate* owner=self;
        state.dock.resized=^(CGFloat width){ [owner sidebarWorkspaceState][@"chatWidth"]=@(width);[owner persistActiveState];[owner applyWorkspacePanelPolicy];[owner relayoutDocumentForViewportChange]; };
    }
    if(query.length) {
        state.drafts[state.session.chat[@"id"]]=[state.view.composer.string copy] ?: @"";
        [state.session newChat];state.view.composer.string=query;
    }
    [state.view setHistorySearchQuery:state.historyView.search.stringValue];
    [state.dock setVisible:YES];[self applyWorkspacePanelPolicy];[state.view displaySession:state.session];
    [self relayoutDocumentForViewportChange];[_window makeFirstResponder:state.view.composer];
}
- (void)cancelAIChat { [((SPDFReaderAIState*)objc_getAssociatedObject(self,&stateKey)).session cancel]; }
- (void)closeAIChat {
    SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);
    [state.dock setVisible:NO];[self applyWorkspacePanelPolicy];[self relayoutDocumentForViewportChange];[_window makeFirstResponder:_pageScrollView];
}
- (void)showAIChats:(id)sender {
    (void)sender;[self readerAIHistoryState];_sidebarModeControl.spdf_selectedSidebarMode=SPDFSidebarModeChats;
    _sidebarPreferredVisible=YES;[self prioritizeWorkspaceSidebar];[self rememberSidebarWorkspaceMode];[self rebuildSidebar];
}
- (BOOL)showAIChatSidebarIfSelected {
    SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);
    BOOL selected=_sidebarModeControl.spdf_selectedSidebarMode==SPDFSidebarModeChats;
    state.historyView.hidden=!selected;if(!selected)return NO;
    if(!_sidebarPreferredVisible) {state.historyView.hidden=YES;return YES;}
    state=[self readerAIHistoryState];
    if(!state.historyView) {
        state.historyView=[SPDFMacAIChatHistoryView new];state.historyView.translatesAutoresizingMaskIntoConstraints=NO;
        [_sidebarContainer addSubview:state.historyView];
        [NSLayoutConstraint activateConstraints:@[[state.historyView.leadingAnchor constraintEqualToAnchor:_sidebarContainer.leadingAnchor],
            [state.historyView.trailingAnchor constraintEqualToAnchor:_sidebarContainer.trailingAnchor],
            [state.historyView.topAnchor constraintEqualToAnchor:_sidebarModeControl.bottomAnchor],
            [state.historyView.bottomAnchor constraintEqualToAnchor:_sidebarContainer.bottomAnchor]]];
        __weak ShenzhenMacDelegate* owner=self;
        state.historyView.action=^(NSString* action){ [owner aiChatAction:action]; };
        state.historyView.searchChanged=^(NSString* query){ [owner searchAIChats:query]; };
    }
    state.historyView.hidden=NO;[self searchAIChats:state.historyView.search.stringValue];return YES;
}
- (void)searchAIChats:(NSString*)query {
    SPDFReaderAIState* state=objc_getAssociatedObject(self,&stateKey);if(!state.historyView || state.historyView.hidden || !_sidebarPreferredVisible)return;
    [state.view setHistorySearchQuery:query];
    NSUInteger generation=++state.searchGeneration;query=[query copy] ?: @"";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(generation!=state.searchGeneration || state.historyView.hidden || !self->_sidebarPreferredVisible)return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            NSArray* chats=[state.store chatsMatchingQuery:query];
            dispatch_async(dispatch_get_main_queue(),^{if(generation==state.searchGeneration)[state.historyView displayChats:chats selectedID:state.session.chat[@"id"]];});
        });
    });
}
- (NSString*)aiAuthorizeAPIKeyForSending:(NSError**)error { return [SPDFMacAICredentials authorizeAPIKeyAccessWithError:error]; }
- (BOOL)aiSendText:(NSString*)text { return [self aiSendText:text authorizedKey:nil]; }
- (BOOL)aiSendText:(NSString*)text authorizedKey:(NSString*)authorizedKey {
    if(![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)return NO;
    SPDFReaderAIState* state=[self readerAIState];
    if(state.session.running)return NO;
    state.setupRequired=NO;
    BOOL (^reject)(NSString*)=^BOOL(NSString* reason) {
        state.submissionIssue=reason; [state.view showSubmissionError:reason]; return NO;
    };
    SPDFMacAISettings* settings=[[SPDFMacAISettings alloc] initWithURL:SPDFMacAISettings.defaultURL];
    NSError* error=nil;
    if(![settings load:&error])return reject(@"AI settings could not be read. Your draft is kept; try again.");
    if(settings.onboardingRevision<SPDFUnifiedSettingsExperienceVersion) {
        state.setupRequired=YES;
        return reject(@"Finish setup using Settings above before sending. Your draft is kept.");
    }
    if(!settings.enabled)return reject(@"Document chat is disabled. Enable it in Settings above. Your draft is kept.");
    // An explicit send checks the credential itself. A stale status flag must not
    // redirect an already connected user to Settings before trying their saved key.
    NSString* key=authorizedKey ?: [self aiAPIKeyForSending:&error];
    if(!key.length) {
        BOOL needsAuthorization=error.code==errSecAuthFailed || error.code==errSecInteractionNotAllowed || error.code==errSecNotAvailable;
        NSString* reason=needsAuthorization ? @"macOS blocked the saved OpenRouter key. Authorize access to send this message." :
            @"Connect OpenRouter in AI settings to send. Your draft is kept.";
        state.submissionIssue=reason;
        [state.view showSubmissionError:reason recoveryAction:needsAuthorization ? @"authorize" : @"settings"]; return NO;
    }
    if(!settings.connectionConfigured) {
        settings.connectionConfigured=YES;
        if(![settings save:&error])return reject(@"The connection could not be saved. Your draft is kept; try again.");
        [NSDistributedNotificationCenter.defaultCenter postNotificationName:@"ShenzhenPDFAISettingsChanged" object:nil userInfo:nil deliverImmediately:YES];
    }
    state.submissionIssue=nil; [state.view showSubmissionError:nil]; state.history=NO;
    NSUInteger before=[state.session.chat[@"messages"] count];
    state.session.defaultLanguage=settings.language;
    [state.session send:text model:settings.model apiKey:key]; return [state.session.chat[@"messages"] count]>before;
}
- (void)aiChatAction:(NSString*)action {
    SPDFReaderAIState* state=[self readerAIState];
    if ([action isEqual:@"close"]) { [self closeAIChat]; return; }
    if ([action isEqual:@"authorize"]) {
        NSString* draft=state.view.composer.string;
        if(![draft stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length || state.session.running)return;
        SPDFMacAISettings* settings=[[SPDFMacAISettings alloc] initWithURL:SPDFMacAISettings.defaultURL];
        if(![settings load:nil] || !settings.enabled || settings.onboardingRevision<SPDFUnifiedSettingsExperienceVersion) {
            [self aiSendText:draft]; return;
        }
        NSError* error=nil; NSString* key=[self aiAuthorizeAPIKeyForSending:&error];
        if(key.length) { if([self aiSendText:draft authorizedKey:key])state.view.composer.string=@""; }
        else {
            state.submissionIssue=@"Access was not authorized. Your message is kept; authorize access or reconnect in Settings.";
            [state.view showSubmissionError:state.submissionIssue recoveryAction:@"authorize"];
        }
        return;
    }
    if ([action isEqual:@"settings"]) {
        if(state.setupRequired)[self showUnifiedSettingsMode:YES];
        else if(state.submissionIssue.length)[self showAIConnectionSettingsWithReason:state.submissionIssue];
        else [self showUnifiedSettings:nil];
        return;
    }
    if ([action isEqual:@"current"]) { [self showAIChatForQuery:nil]; return; }
    if ([action isEqual:@"new"]) { state.drafts[state.session.chat[@"id"]]=[state.view.composer.string copy] ?: @"";[state.session newChat];state.view.composer.string=@"";[self showAIChatForQuery:nil]; return; }
    if ([action isEqual:@"stop"]) { [state.session cancel]; return; }
    if ([action isEqual:@"undo"] || [action isEqual:@"redo"]) { [state.session performHistoryAction:[action isEqual:@"redo"]]; return; }
    if ([action isEqual:@"history"]) { [self showAIChats:nil]; return; }
    if ([action hasPrefix:@"load:"]) {
        NSDictionary* chat=[state.store chatWithID:[action substringFromIndex:5]];
        if (chat) { state.drafts[state.session.chat[@"id"]]=[state.view.composer.string copy] ?: @""; [state.session loadChat:chat];state.view.composer.string=state.drafts[chat[@"id"]] ?: @"";[self showAIChatForQuery:nil]; } return;
    }
    if ([action isEqual:@"deleteAll"] || [action hasPrefix:@"delete:"]) {
        NSAlert* alert=[NSAlert new]; alert.messageText=[action isEqual:@"deleteAll"] ? @"Delete all chats?" : @"Delete this chat?";
        alert.informativeText=@"This removes saved conversations from this Mac. Documents and document history are unchanged.";
        [alert addButtonWithTitle:@"Delete"]; [alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:self->_window completionHandler:^(NSModalResponse result) {
            if (result!=NSAlertFirstButtonReturn) return;
            NSString* identifier=[action hasPrefix:@"delete:"] ? [action substringFromIndex:7] : nil;
            BOOL current=!identifier || [state.session.chat[@"id"] isEqual:identifier];
            if (current) [state.session cancel];
            NSError* error=nil; BOOL ok=identifier ? [state.store deleteChatWithID:identifier error:&error] : [state.store deleteAll:&error];
            if (ok && current) [state.session newChat];
            if (error) [self->_window presentError:error];
            [self searchAIChats:state.historyView.search.stringValue];
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
        [alert addButtonWithTitle:@"OK"]; [alert beginSheetModalForWindow:self->_window completionHandler:nil]; return;
    }
    [state.tools performTool:@"show_document" arguments:args completion:^(NSDictionary* result) {
        if (result[@"error"]) {
            NSAlert* alert=[NSAlert new]; alert.messageText=@"This citation is unavailable";
            alert.informativeText=[result[@"error"] description]; [alert addButtonWithTitle:@"OK"];
            [alert beginSheetModalForWindow:self->_window completionHandler:nil];
        }
        [state.view refreshActivityFromSession:state.session];
        if (!result[@"error"]) [self->_window makeKeyAndOrderFront:nil];
    }];
}
@end
