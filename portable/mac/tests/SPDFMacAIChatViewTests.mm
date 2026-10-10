#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "../SPDFMacAIChatView.h"
#import "../SPDFMacAIChatMarkdown.h"
#import "../SPDFMacAIChatSession.h"
#import "../SPDFMacAIChatSearch.h"
static int failures;
static NSEvent* pendingUp;
@interface NSButton (AIChatSymbolProbe)
- (NSRect)rectForSymbol:(NSImage*)image;
@end
@interface NSWindow (AIChatProbe)
- (NSEvent*)chatProbeEvent:(NSEventMask)mask;
@end
@implementation NSWindow (AIChatProbe)
- (NSEvent*)chatProbeEvent:(NSEventMask)mask { (void)mask; NSEvent* event=pendingUp; pendingUp=nil; return event; }
@end
@interface ChatFixture : NSObject
@property(nonatomic) NSDictionary* chat;
@property(nonatomic) NSString* status;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL canUndo;
@property(nonatomic) BOOL canRedo;
@property(nonatomic) SPDFMacAIChatActivityState activityState;
@property(nonatomic) NSString* activityDetail;
@end
@implementation ChatFixture @end
static void Check(BOOL yes,NSString* message) { if(!yes) { failures++; fprintf(stderr,"FAIL %s\n",message.UTF8String); } }
static NSView* Find(NSView* root,NSString* key) {
    if([root.identifier isEqual:key]) return root;
    for(NSView* child in root.subviews) { NSView* found=Find(child,key); if(found) return found; } return nil;
}
static NSUInteger InspectTargets(NSView* view) {
    NSUInteger count=0;
    if([NSStringFromClass(view.class) isEqual:@"SPDFChatButton"] && !view.hidden) {
        NSView* root=view.window.contentView;
        for(NSValue* p in @[[NSValue valueWithPoint:NSMakePoint(2,2)],
            [NSValue valueWithPoint:NSMakePoint(NSWidth(view.bounds)-2,NSHeight(view.bounds)-2)]]) {
            if(!NSPointInRect(p.pointValue,view.visibleRect)) continue;
            NSPoint point=[view convertPoint:p.pointValue toView:nil];
            Check([root hitTest:[root.superview convertPoint:point fromView:nil]]==view,
                [@"chat action visible corners unobstructed: " stringByAppendingString:view.identifier]); count++;
        }
    }
    for(NSView* child in view.subviews) count+=InspectTargets(child); return count;
}
static NSUInteger ImageCount(NSView* view) {
    NSUInteger count=[view isKindOfClass:NSImageView.class] ? 1 : 0;
    for(NSView* child in view.subviews) count+=ImageCount(child); return count;
}
static void Capture(NSView* view,NSString* name) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.03]];
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep* rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    Check([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@"/tmp/sz-ai-chat-" stringByAppendingFormat:@"%@.png",name] atomically:YES],@"native state evidence saved");
}
static void Click(NSWindow* window,NSButton* button,NSPoint local) {
    NSPoint point=[button convertPoint:local toView:nil];
    NSView* root=window.contentView; NSView* hit=[root hitTest:[root.superview convertPoint:point fromView:nil]];
    Check(hit==button,@"native hierarchy owns full button bounds");
    NSTimeInterval stamp=NSProcessInfo.processInfo.systemUptime;
    NSEvent* down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:stamp
        windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    pendingUp=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:stamp+.01
        windowNumber:window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
    Method original=class_getInstanceMethod(NSWindow.class,@selector(nextEventMatchingMask:));
    Method injected=class_getInstanceMethod(NSWindow.class,@selector(chatProbeEvent:));
    method_exchangeImplementations(original,injected); [hit mouseDown:down]; method_exchangeImplementations(original,injected);
}
#import "SPDFMacAIChatDockChecks.h"
#import "SPDFMacAIChatReopenChecks.h"
#import "SPDFMacAIChatOrderChecks.h"
#import "SPDFMacAIChatBlankRowsChecks.h"
#import "SPDFMacAIAnswerCardViewChecks.h"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    RunChatReopenChecks();
    RunChatOrderChecks();
    RunBlankChatRowsChecks();
    RunAnswerCardViewChecks();
    NSAttributedString* safe=SPDFMacAIChatMarkdown(@"**Evidence** [page](spdf-ai://document?path=test&page=2) [site](https://example.com) [unsafe](file:///tmp/private) ![hidden](file:///tmp/private.png) ![remote](https://example.com/tracker.png)",500,YES);
    __block NSUInteger links=0,attachments=0;
    [safe enumerateAttributesInRange:NSMakeRange(0,safe.length) options:0 usingBlock:^(NSDictionary* a,NSRange r,BOOL* stop){
        (void)r;(void)stop; if(a[NSLinkAttributeName]) { links++; Check(SPDFMacAIChatLinkAllowed(a[NSLinkAttributeName]),@"rendered link is allowed"); }
        if(a[NSAttachmentAttributeName]) attachments++;
    }];
    Check(links==2,@"rich Markdown retains document and HTTPS links"); Check(!attachments,@"model images cannot resolve any resource");
    Check(!SPDFMacAIChatLinkAllowed([NSURL URLWithString:@"https://user:secret@example.com"]),@"credential URL is not clickable");
    NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,580) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    SPDFMacAIChatView* view=[[SPDFMacAIChatView alloc] initWithFrame:window.contentView.bounds]; window.contentView=view;
    ChatFixture* fixture=[ChatFixture new]; fixture.chat=@{@"id":@"test",@"messages":@[
        @{@"role":@"user",@"content":@"What is the board’s power requirement?"},
        @{@"role":@"assistant",@"content":@"## Power requirements\nThe board uses **5 V input**. See [the schematic, page 2](spdf-ai://document?path=board.pdf&page=2).\n\n- Peak current: **2 A**\n- Check connector polarity before connecting.\n\n```c\nconst float voltage = 5.0f;\n```\n\nI checked the schematic and assembly notes. The values agree; the assembly guide also recommends a regulated supply. The test fixture intentionally includes a longer paragraph describing evidence quality, connector assumptions, polarity and voltage tolerance. These words must wrap over additional lines in a narrow chat panel while remaining fully selectable and never covering the next message."}
    ]};
    [view displaySession:(id)fixture]; [window.contentView layoutSubtreeIfNeeded];
    NSStackView* messages=[view valueForKey:@"messages"];
    NSTextView* answer=(id)messages.arrangedSubviews[3]; CGFloat wide=NSHeight(answer.frame);
    Check([answer.string hasPrefix:@"Power requirements"],@"assistant response follows the user in chronological order");
    Check([[(NSTextField*)Find(view,@"latestUserPrompt") stringValue] containsString:@"What is the board’s power requirement?"],@"latest user question stays visible above a long answer");
    [window setContentSize:NSMakeSize(520,580)]; [window.contentView layoutSubtreeIfNeeded];
    [window.contentView layoutSubtreeIfNeeded];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]]; [window.contentView layoutSubtreeIfNeeded];
    Check(NSHeight(answer.frame)>wide,@"message height reflows at narrower width");
    NSRange finalGlyph=NSMakeRange(answer.layoutManager.numberOfGlyphs-1,1);
    NSRect finalLine=[answer.layoutManager boundingRectForGlyphRange:finalGlyph inTextContainer:answer.textContainer];
    Check([answer.string hasSuffix:@"next message."] && NSMaxY(finalLine)<=NSHeight(answer.bounds)+.5,
        @"compact measurement preserves the final line of long wrapped prose");
    Check(InspectTargets(view)>=10,@"all narrow chat header controls tested at visible corners");
    NSScrollView* transcript=[view valueForKey:@"scroll"];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]]; [view layoutSubtreeIfNeeded];
    Check(fabs(NSMaxY(transcript.contentView.bounds)-NSHeight(transcript.documentView.bounds))<2,
        @"newest message bottom stays visible after narrow reflow");
    NSTextField* question=(id)Find(view,@"latestUserPrompt");
    Check(NSContainsRect(view.bounds,[question convertRect:question.bounds toView:view]) &&
        NSMaxY([question convertRect:question.bounds toView:view])<=NSMinY(transcript.frame),@"question context fits above the transcript without overlap at minimum width");
    __block NSURL* citation; __block NSRange citationRange=NSMakeRange(NSNotFound,0);
    [answer.textStorage enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,answer.string.length) options:0
        usingBlock:^(id value,NSRange range,BOOL* stop) {
            if([[value description] hasPrefix:@"spdf-ai://"]) { citation=value; citationRange=range; *stop=YES; }
        }];
    Check([citation.absoluteString isEqual:@"spdf-ai://document?path=board.pdf&page=2"],@"rendered citation preserves the exact custom URL");
    if(citationRange.location!=NSNotFound) {
        NSRange glyph=[answer.layoutManager glyphRangeForCharacterRange:NSMakeRange(citationRange.location,1) actualCharacterRange:nil];
        NSRect rect=[answer.layoutManager boundingRectForGlyphRange:glyph inTextContainer:answer.textContainer];
        [answer scrollRangeToVisible:citationRange];[view layoutSubtreeIfNeeded];
        NSPoint point=[answer convertPoint:NSMakePoint(NSMidX(rect)+answer.textContainerOrigin.x,NSMidY(rect)+answer.textContainerOrigin.y) toView:nil];
        Check([view hitTest:[view.superview convertPoint:point fromView:nil]]==answer,@"native citation glyph hit reaches its message view");
        __block NSURL* opened; view.openLink=^(NSURL* URL){ opened=URL; };
        [answer.delegate textView:answer clickedOnLink:citation atIndex:citationRange.location];
        Check([opened.absoluteString isEqual:citation.absoluteString],@"native text link delegate routes the exact document citation");
    }
    Check([NSStringFromClass(view.composer.enclosingScrollView.class) isEqual:@"SPDFChatInputScrollView"],@"composer uses explicit appearance-aware border drawing");
    Check(![(NSButton*)Find(view,@"undo") isEnabled],@"Undo is disabled without a reversible action");
    __block NSUInteger accepted=0; view.sendText=^BOOL(NSString* text){(void)text;return NO;};
    view.composer.string=@"Keep this draft"; NSButton* send=(id)Find(view,@"send"); [send performClick:nil];
    Check([view.composer.string isEqual:@"Keep this draft"],@"unconfigured account preserves composer text");
    view.sendText=^BOOL(NSString* text){(void)text;accepted++;return YES;};
    for(NSValue* p in @[[NSValue valueWithPoint:NSMakePoint(2,2)],[NSValue valueWithPoint:NSMakePoint(NSWidth(send.bounds)-2,NSHeight(send.bounds)-2)]]) {
        view.composer.string=@"A question"; Click(window,send,p.pointValue);
        Check(!view.composer.string.length,@"accepted native click clears submitted text");
    }
    Check(accepted==2,@"each full-bounds click submits exactly once");
    [window makeFirstResponder:view.composer];
    [view.composer setMarkedText:@"中文" selectedRange:NSMakeRange(2,0) replacementRange:NSMakeRange(NSNotFound,0)];
    [view.composer keyDown:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36]];
    Check(accepted==2,@"IME Return confirms composition without sending unfinished text");
    [view.composer unmarkText];view.composer.string=@"";

    __block NSMutableArray* actions=[NSMutableArray array];
    view.action=^(NSString* action){[actions addObject:action];};
    fixture.canUndo=YES;fixture.canRedo=YES;[view refreshActivityFromSession:(id)fixture];
    [window setContentSize:NSMakeSize(360,600)];[view layoutSubtreeIfNeeded];
    for(NSString* key in @[@"close",@"new",@"undo",@"redo",@"settings"]) {
        NSButton* button=(id)Find(view,key);
        Check(button.image && button.toolTip.length,@"panel actions have vector symbols and hover help");
        NSRect icon=[button rectForSymbol:button.image];
        Check(NSContainsRect(NSInsetRect(button.bounds,6,6),icon) &&
            fabs(NSWidth(icon)/NSHeight(icon)-button.image.size.width/button.image.size.height)<.0001,@"symbols keep fixed aspect ratio");
        Click(window,button,NSMakePoint(2,2));
        Click(window,button,NSMakePoint(NSWidth(button.bounds)-2,NSHeight(button.bounds)-2));
    }
    Check(actions.count==10,@"each header action responds at both corners at narrow width");
    NSEvent* redoKey=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand|NSEventModifierFlagShift timestamp:0 windowNumber:window.windowNumber context:nil characters:@"Z" charactersIgnoringModifiers:@"Z" isARepeat:NO keyCode:6];
    [window makeFirstResponder:nil];[view.composer performKeyEquivalent:redoKey];
    Check(actions.count==10,@"composer cannot steal Undo or Redo from another focused control");
    [window makeFirstResponder:view.composer];
    Check([view.composer performKeyEquivalent:redoKey] && [actions.lastObject isEqual:@"redo"] && actions.count==11,@"uppercase Cmd Shift Z reaches agent Redo from empty composer");
    NSSearchField* chatSearch=[view valueForKey:@"chatSearch"]; chatSearch.stringValue=@"polarity";
    [(id<NSSearchFieldDelegate>)view controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:chatSearch]];
    Check([chatSearch.placeholderString isEqual:@"Search this chat"] && messages.arrangedSubviews.count==2,@"chat search filters only matching messages in this conversation");
    NSTextView* match=(id)messages.arrangedSubviews[1];
    NSRange hit=[match.string rangeOfString:@"polarity"];
    Check(hit.location!=NSNotFound && [match.layoutManager temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:hit.location effectiveRange:nil],@"matching term is highlighted in rendered message");
    NSDictionary* originalChat=fixture.chat;
    NSString* padding=[@"Context line with enough text to wrap at narrow widths.\n\n" stringByPaddingToLength:3500 withString:@"Context line with enough text to wrap at narrow widths.\n\n" startingAtIndex:0];
    fixture.chat=@{@"id":@"search-deep",@"messages":@[@{@"role":@"assistant",@"content":[NSString stringWithFormat:@"%@First needle passage.\n\n%@Second needle passage.\n\n%@",padding,padding,padding]}]};
    Check(SPDFMacAIChatHasTextMatch(fixture.chat,@"NEEDLE") && !SPDFMacAIChatHasTextMatch(fixture.chat,@"search-deep") &&
        !SPDFMacAIChatHasTextMatch(@{@"messages":@[@{@"role":@"tool",@"content":@"needle"}]},@"needle"),
        @"history content search finds visible speaker messages, excluding titles and internal tool results");
    [view displaySession:(id)fixture];[view setChatSearchQuery:@"needle"];
    void (^checkVisibleHit)(NSUInteger)=^(NSUInteger occurrence) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.08]];[view layoutSubtreeIfNeeded];
        NSTextView* text=(id)messages.arrangedSubviews[1];NSRange hit=[text.string rangeOfString:@"needle"];
        if(occurrence)hit=[text.string rangeOfString:@"needle" options:0 range:NSMakeRange(NSMaxRange(hit),text.string.length-NSMaxRange(hit))];
        NSRange glyph=[text.layoutManager glyphRangeForCharacterRange:NSMakeRange(hit.location,1) actualCharacterRange:nil];
        NSRect rect=[text.layoutManager boundingRectForGlyphRange:glyph inTextContainer:text.textContainer];
        rect.origin.x+=text.textContainerOrigin.x;rect.origin.y+=text.textContainerOrigin.y;
        rect=[text convertRect:rect toView:transcript.documentView];
        Check(NSContainsRect(transcript.contentView.bounds,rect),@"chat search reveals exact glyph deep inside a long message");
        Check([text.layoutManager temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:hit.location effectiveRange:nil]!=nil,
            @"revealed search occurrence stays highlighted while field has focus");
    };
    checkVisibleHit(0);Capture(view,@"search-exact-passage");
    Check([(id<NSSearchFieldDelegate>)view control:chatSearch textView:(id)chatSearch.currentEditor doCommandBySelector:@selector(insertNewline:)],@"Return in chat search navigates matches instead of submitting a message");
    checkVisibleHit(1);
    [(SPDFMacAIChatSearch*)[view valueForKey:@"chatFind"] moveBy:-1];checkVisibleHit(0);
    fixture.chat=originalChat;[view displaySession:(id)fixture];
    [view setChatSearchQuery:@"nonexistent"];
    Check(!messages.arrangedSubviews.count && [[(NSTextField*)Find(view,@"chatActivityDetail") stringValue] isEqual:@"No matches in this chat"],@"no-match feedback remains local to current chat");
    [view setChatSearchQuery:@""];
    Check(messages.arrangedSubviews.count==4 && !Find(view,@"history"),@"clearing local search restores both speakers; duplicate history action removed");
    NSRect hideRect=[Find(view,@"close") convertRect:Find(view,@"close").bounds toView:view];
    Check(NSMinY(hideRect)==4 && NSHeight(hideRect)==28 && NSMinX(hideRect)<NSMinX([Find(view,@"new") convertRect:Find(view,@"new").bounds toView:view]),@"Hide is first in the aligned36point toolbar");
    Capture(view,@"docked-compact");
    fixture.running=YES; fixture.activityState=SPDFMacAIChatActivityWorking;
    fixture.status=@"Reading · Schematic, page 2"; fixture.activityDetail=fixture.status; [view displaySession:(id)fixture];
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] containsString:@"Working"] &&
        [[(NSTextField*)Find(view,@"chatActivityDetail") stringValue] containsString:@"Schematic"],@"active work shows an explicit heading and current tool detail");
    Check(!send.enabled && [(NSButton*)Find(view,@"stop") isEnabled],@"active task has explicit stop action");
    [window setContentSize:NSMakeSize(760,580)];
    for(NSString* appearance in @[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]) {
        window.appearance=[NSAppearance appearanceNamed:appearance];
        [view displayChats:@[]]; [view displaySession:(id)fixture]; [view layoutSubtreeIfNeeded];
        NSTextView* assistant=(id)messages.arrangedSubviews[3];
        NSTextView* user=(id)messages.arrangedSubviews[1];
        [window.effectiveAppearance performAsCurrentDrawingAppearance:^{
            Check(![[assistant.backgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace]
                isEqual:[user.backgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace]],@"user and assistant have distinct shades in each theme");
        }];
        NSBitmapImageRep* rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        Check([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"/tmp/sz-ai-chat-%@.png",appearance] atomically:YES],@"chat native preview saved");
    }
    [view displayChats:@[]];
    Check([(NSButton*)Find(view,@"stop") isEnabled],@"history keeps cancellation available for active tasks");
    fixture.running=NO; fixture.activityState=SPDFMacAIChatActivityStopped;
    fixture.status=@"Stopped. Completed changes can still be undone."; fixture.activityDetail=fixture.status; fixture.canUndo=YES;
    [view refreshActivityFromSession:(id)fixture];
    Check(![(NSButton*)Find(view,@"stop") isEnabled] && [(NSButton*)Find(view,@"undo") isEnabled],@"history refreshes task completion and undo state");
    Check([[(NSTextField*)[view valueForKey:@"status"] stringValue] hasPrefix:@"Stopped"],@"history shows current task status");
    Check(Find(view,@"current")!=nil,@"history offers return to current conversation");
    Check(view.composer.enclosingScrollView.hidden && Find(view,@"send").hidden,@"history hides the noneditable composer and Send");
    Check(![(NSButton*)Find(view,@"deleteAll") isEnabled],@"empty history cannot delete nonexistent chats");
    Check(InspectTargets(view)>=10,@"history controls remain reachable without composer");
    Capture(view,@"history-stopped");
    [window setContentSize:NSMakeSize(520,400)];
    fixture.chat=@{@"id":@"question",@"messages":@[
        @{@"role":@"user",@"content":@"Summarize the design notes."},
        @{@"role":@"assistant",@"content":@"Which document should I use: **Power supply** or **Board layout**?"}]};
    fixture.activityState=SPDFMacAIChatActivityCompleted; fixture.activityDetail=@"Waiting for your next message.";
    [view displaySession:(id)fixture]; Capture(view,@"question");
    window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [view displaySession:(id)fixture]; Capture(view,@"question-dark");
    NSTextView* compact=(id)messages.arrangedSubviews[1];
    NSView* nextRole=messages.arrangedSubviews[2];
    NSRect bodyRect=[compact convertRect:compact.bounds toView:transcript.documentView];
    NSRect nextRect=[nextRole.superview convertRect:[nextRole alignmentRectForFrame:nextRole.frame] toView:transcript.documentView];
    Check(NSHeight(compact.frame)<=40 && NSMinY(nextRect)-NSMaxY(bodyRect)>=15 && NSMinY(nextRect)-NSMaxY(bodyRect)<=20,
        @"short messages include comfortable padding and consistent16–20point separation");
    Check([compact.string hasSuffix:@"design notes."] && ![compact.string hasSuffix:@"\n"],@"only renderer-added terminal blank lines are removed");
    Check(InspectTargets(view)>=12,@"minimum-height chat keeps every header and footer action reachable");
    Check(NSHeight(transcript.frame)>80 && NSContainsRect(view.bounds,view.composer.enclosingScrollView.frame),@"minimum-height chat keeps transcript and composer usable");
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] containsString:@"Ready for your reply"] && send.enabled,@"finished question explicitly invites the user’s reply");
    fixture.activityState=SPDFMacAIChatActivityThinking; fixture.activityDetail=@"Waiting for the model…"; fixture.running=YES;
    [view displaySession:(id)fixture]; Capture(view,@"thinking");
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] isEqual:@"Thinking…"],@"thinking is a prominent explicit state");
    fixture.activityState=SPDFMacAIChatActivityPaused; fixture.activityDetail=@"Changes saved. Ask a follow-up to continue."; fixture.running=NO;
    [view displaySession:(id)fixture];
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] hasPrefix:@"Paused"] && ![[(NSTextField*)Find(view,@"chatStatus") stringValue] containsString:@"Error"],@"step limit shows paused instead of incorrectly labelling successful changes an error");
    fixture.activityState=SPDFMacAIChatActivityError; fixture.activityDetail=@"Chat changed in another window. Reopen the latest conversation to continue."; fixture.running=NO;
    [view displaySession:(id)fixture]; Capture(view,@"error");
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] containsString:@"Error"] &&
        [[(NSTextField*)Find(view,@"chatActivityDetail") stringValue] containsString:@"another window"],@"error heading and recovery detail remain visible");
    view.composer.string=@"Please summarize this document.";
    [view showSubmissionError:@"macOS blocked the saved OpenRouter key. Authorize access to send this message." recoveryAction:@"authorize"];
    Capture(view,@"authorize-minimum");
    NSView* issue=Find(view,@"chatSubmissionIssue");
    Check(NSContainsRect(view.bounds,issue.frame) && NSContainsRect(view.bounds,view.composer.enclosingScrollView.frame) &&
        NSHeight(transcript.frame)>20 && InspectTargets(view)>=14,@"authorization recovery and preserved draft fit at520×400");
    [view showSubmissionError:nil]; view.composer.string=@"";
    fixture.chat=@{@"id":@"question",@"messages":@[
        @{@"role":@"user",@"content":@"Use the board layout."},
        @{@"role":@"assistant",@"content":@"Updated answer with the requested document."}]};
    [view displaySession:(id)fixture];
    Check([[(NSTextView*)messages.arrangedSubviews[3] string] hasPrefix:@"Updated answer"] &&
        [[(NSTextField*)Find(view,@"latestUserPrompt") stringValue] containsString:@"Use the board layout"],@"same-count transcript changes refresh both question context and answer");
    NSMutableArray* longMessages=[NSMutableArray array];
    for(NSUInteger i=0;i<45;i++) [longMessages addObject:@{@"role":@"user",@"content":[NSString stringWithFormat:@"Message %lu",(unsigned long)i]}];
    fixture.chat=@{@"id":@"long",@"messages":longMessages}; [view displaySession:(id)fixture];
    NSButton* older=(id)Find(view,@"older"); Check(older!=nil,@"long conversations reveal older-message affordance");
    Capture(view,@"older-messages");
    [view setChatSearchQuery:@"Message 0"];
    Check(messages.arrangedSubviews.count==2 && [[(NSTextView*)messages.arrangedSubviews[1] string] isEqual:@"Message 0"],@"search includes older messages beyond the initial40message viewport");
    [view setChatSearchQuery:@""]; older=(id)Find(view,@"older");
    [older performClick:nil]; Check(Find(view,@"older")==nil && messages.arrangedSubviews.count==90,@"older messages remain available on demand");
    NSString* scratch=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    setenv("SPDF_STATE_DIR",scratch.UTF8String,1);
    NSString* assets=[scratch stringByAppendingPathComponent:@"Chats/test-assets"];
    [NSFileManager.defaultManager createDirectoryAtPath:assets withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* imagePath=[assets stringByAppendingPathComponent:@"page.png"];
    NSBitmapImageRep* tiny=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil pixelsWide:2 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:8 bitsPerPixel:32];
    memset(tiny.bitmapData,255,16);
    [[tiny representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:imagePath atomically:YES];
    fixture.chat=@{@"id":@"preview",@"messages":@[@{@"role":@"preview",@"local":@YES,
        @"preview":@{@"path":imagePath,@"caption":@"Schematic · Page 2",@"citation":@{@"path":@"board.pdf",@"page":@2}}}]};
    [view displaySession:(id)fixture]; [view layoutSubtreeIfNeeded];
    Check(ImageCount(view)==1,@"trusted tool page preview is displayed from chat assets");
    fixture.chat=@{@"id":@"blocked-preview",@"messages":@[@{@"role":@"preview",@"local":@YES,
        @"preview":@{@"path":@"/tmp/private.png",@"caption":@"Untrusted path"}}]};
    [view displaySession:(id)fixture];
    Check(ImageCount(view)==0,@"preview outside chat assets cannot load a local file");
    fixture.chat=@{@"id":@"empty",@"messages":@[]}; fixture.status=@""; fixture.activityState=SPDFMacAIChatActivityIdle; fixture.activityDetail=@"";
    [view displaySession:(id)fixture]; Capture(view,@"empty");
    Check(messages.arrangedSubviews.count==1 && [messages.arrangedSubviews.firstObject isKindOfClass:NSTextField.class],@"empty chat uses plain helper text without an empty message bubble");
    [NSFileManager.defaultManager removeItemAtPath:scratch error:nil];
        Check(!window.visible,@"probe never shows an app window");
    CheckChatDock();
    fprintf(stderr,"AI chat view: %d failures\n",failures); return failures?1:0;
} }
