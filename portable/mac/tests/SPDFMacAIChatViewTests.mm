#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "../SPDFMacAIChatView.h"
#import "../SPDFMacAIChatMarkdown.h"
#import "../SPDFMacAIChatSession.h"
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
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
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
    NSTextView* answer=(id)messages.arrangedSubviews[1]; CGFloat wide=NSHeight(answer.frame);
    Check([answer.string hasPrefix:@"Power requirements"],@"latest assistant response appears first");
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
    NSView* label=messages.arrangedSubviews.firstObject;
    NSRect labelRect=[label.superview convertRect:[label alignmentRectForFrame:label.frame] toView:transcript.contentView];
    NSDate* layoutDeadline=[NSDate dateWithTimeIntervalSinceNow:.2];
    while(!NSContainsRect(transcript.contentView.bounds,labelRect) && layoutDeadline.timeIntervalSinceNow>0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]]; [view layoutSubtreeIfNeeded];
        labelRect=[label.superview convertRect:[label alignmentRectForFrame:label.frame] toView:transcript.contentView];
    }
    Check(NSContainsRect(transcript.contentView.bounds,labelRect),@"first message label fully visible after narrow reflow");
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
    __block NSInteger pinMode=0; __block NSUInteger pinActions=0;
    __weak SPDFMacAIChatView* weakView=view;
    view.action=^(NSString* action){
        if([action isEqual:@"pinApp"] || [action isEqual:@"pinAll"]) {
            NSInteger next=[action isEqual:@"pinApp"] ? 1 : 2; pinMode=pinMode==next ? 0 : next;
            [weakView setPinMode:pinMode]; pinActions++;
        }
    };
    NSButton* pinApp=(id)Find(view,@"pinApp"); NSButton* pinAll=(id)Find(view,@"pinAll");
    Check(pinApp.image && pinAll.image && pinApp.toolTip.length && pinAll.toolTip.length,@"both pin modes have native symbols and hover explanations");
    for(NSButton* pin in @[pinApp,pinAll]) {
        NSRect icon=[pin rectForSymbol:pin.image];
        Check(NSContainsRect(NSInsetRect(pin.bounds,6,6),icon) &&
            fabs(NSWidth(icon)/NSHeight(icon)-pin.image.size.width/pin.image.size.height)<.0001,@"pin symbol fits its target without changing aspect ratio");
    }
    Click(window,pinApp,NSMakePoint(2,2));
    Check(pinMode==1 && pinApp.state==NSControlStateValueOn && pinAll.state==NSControlStateValueOff,@"app pin selects only its own mode");
    Capture(view,@"pin-app");
    Click(window,pinAll,NSMakePoint(NSWidth(pinAll.bounds)-2,NSHeight(pinAll.bounds)-2));
    Check(pinMode==2 && pinApp.state==NSControlStateValueOff && pinAll.state==NSControlStateValueOn,@"all-windows pin replaces app pin");
    Capture(view,@"pin-all"); [pinAll performClick:nil];
    Check(pinMode==0 && pinActions==3 && pinAll.state==NSControlStateValueOff,@"selected pin toggles back to normal");
    fixture.running=YES; fixture.activityState=SPDFMacAIChatActivityWorking;
    fixture.status=@"Reading · Schematic, page 2"; fixture.activityDetail=fixture.status; [view displaySession:(id)fixture];
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] containsString:@"Working"] &&
        [[(NSTextField*)Find(view,@"chatActivityDetail") stringValue] containsString:@"Schematic"],@"active work shows an explicit heading and current tool detail");
    Check(!send.enabled && [(NSButton*)Find(view,@"stop") isEnabled],@"active task has explicit stop action");
    [window setContentSize:NSMakeSize(760,580)];
    for(NSString* appearance in @[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]) {
        window.appearance=[NSAppearance appearanceNamed:appearance];
        [view displayChats:@[]]; [view displaySession:(id)fixture]; [view layoutSubtreeIfNeeded];
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
    NSTextView* compact=(id)messages.arrangedSubviews[1];
    NSView* nextRole=messages.arrangedSubviews[2];
    NSRect bodyRect=[compact convertRect:compact.bounds toView:transcript.documentView];
    NSRect nextRect=[nextRole.superview convertRect:[nextRole alignmentRectForFrame:nextRole.frame] toView:transcript.documentView];
    Check(NSHeight(compact.frame)<=24 && NSMinY(nextRect)-NSMaxY(bodyRect)>=15 && NSMinY(nextRect)-NSMaxY(bodyRect)<=20,
        @"short messages use compact measured rows and consistent16–20point separation");
    Check([compact.string hasSuffix:@"Board layout?"] && ![compact.string hasSuffix:@"\n"],@"only renderer-added terminal blank lines are removed");
    Check(InspectTargets(view)>=14,@"minimum-height chat keeps every header and footer action reachable");
    Check(NSHeight(transcript.frame)>80 && NSContainsRect(view.bounds,view.composer.enclosingScrollView.frame),@"minimum-height chat keeps transcript and composer usable");
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] containsString:@"Ready for your reply"] && send.enabled,@"finished question explicitly invites the user’s reply");
    fixture.activityState=SPDFMacAIChatActivityThinking; fixture.activityDetail=@"Waiting for the model…"; fixture.running=YES;
    [view displaySession:(id)fixture]; Capture(view,@"thinking");
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] isEqual:@"Thinking…"],@"thinking is a prominent explicit state");
    fixture.activityState=SPDFMacAIChatActivityError; fixture.activityDetail=@"Chat changed in another window. Reopen the latest conversation to continue."; fixture.running=NO;
    [view displaySession:(id)fixture]; Capture(view,@"error");
    Check([[(NSTextField*)Find(view,@"chatStatus") stringValue] containsString:@"Error"] &&
        [[(NSTextField*)Find(view,@"chatActivityDetail") stringValue] containsString:@"another window"],@"error heading and recovery detail remain visible");
    view.composer.string=@"Please summarize this document.";
    [view showSubmissionError:@"macOS blocked the saved OpenRouter key. Authorize access to send this message." recoveryAction:@"authorize"];
    Capture(view,@"authorize-minimum");
    NSView* issue=Find(view,@"chatSubmissionIssue");
    Check(NSContainsRect(view.bounds,issue.frame) && NSContainsRect(view.bounds,view.composer.enclosingScrollView.frame) &&
        NSHeight(transcript.frame)>20 && InspectTargets(view)>=16,@"authorization recovery and preserved draft fit at520×400");
    [view showSubmissionError:nil]; view.composer.string=@"";
    fixture.chat=@{@"id":@"question",@"messages":@[
        @{@"role":@"user",@"content":@"Use the board layout."},
        @{@"role":@"assistant",@"content":@"Updated answer with the requested document."}]};
    [view displaySession:(id)fixture];
    Check([[(NSTextView*)messages.arrangedSubviews[1] string] hasPrefix:@"Updated answer"] &&
        [[(NSTextField*)Find(view,@"latestUserPrompt") stringValue] containsString:@"Use the board layout"],@"same-count transcript changes refresh both question context and answer");
    NSMutableArray* longMessages=[NSMutableArray array];
    for(NSUInteger i=0;i<45;i++) [longMessages addObject:@{@"role":@"user",@"content":[NSString stringWithFormat:@"Message %lu",(unsigned long)i]}];
    fixture.chat=@{@"id":@"long",@"messages":longMessages}; [view displaySession:(id)fixture];
    NSButton* older=(id)Find(view,@"older"); Check(older!=nil,@"long conversations reveal older-message affordance");
    Capture(view,@"older-messages");
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
    [NSFileManager.defaultManager removeItemAtPath:scratch error:nil];
        Check(!window.visible,@"probe never shows an app window");
    fprintf(stderr,"AI chat view: %d failures\n",failures); return failures?1:0;
} }
