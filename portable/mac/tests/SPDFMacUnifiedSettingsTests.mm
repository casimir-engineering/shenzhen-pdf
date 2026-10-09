#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "../SPDFMacUnifiedSettings.h"
static int failures;
static NSEvent* pendingMouseUp;
@interface NSWindow (SettingsProbe)
@end
@implementation NSWindow (SettingsProbe)
- (NSEvent*)settingsProbeNextEventMatchingMask:(NSEventMask)mask {
    (void)mask; NSEvent* event=pendingMouseUp; pendingMouseUp=nil; return event;
}
@end
static void Check(BOOL ok,NSString* name) { if(!ok) { failures++; fprintf(stderr,"FAIL %s\n",name.UTF8String); } }
static NSView* Find(NSView* view,NSString* identifier) {
    if([view.identifier isEqual:identifier]) return view;
    for(NSView* child in view.subviews) { NSView* found=Find(child,identifier); if(found) return found; }
    return nil;
}
static void Inspect(NSView* view) {
    if([view isKindOfClass:NSButton.class] && !view.hidden) {
        Check(NSWidth(view.frame)>15 && NSHeight(view.frame)>15,[@"button has a real target " stringByAppendingString:view.identifier ?: @""]);
        if([view.identifier isEqual:@"done"] || [view.identifier isEqual:@"connect"]) {
            for(NSValue* point in @[[NSValue valueWithPoint:NSMakePoint(2,2)],
                [NSValue valueWithPoint:NSMakePoint(NSWidth(view.bounds)-2,NSHeight(view.bounds)-2)]])
                Check([view hitTest:[view convertPoint:point.pointValue toView:view.superview]]==view,@"action hit target covers corners");
        }
    }
    for(NSView* child in view.subviews) Inspect(child);
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    Check(SPDFUnifiedSettingsShouldPresent(@{},YES,NO),@"existing readers get discovery once");
    Check(!SPDFUnifiedSettingsShouldPresent(@{},NO,NO),@"restored process skips setup");
    Check(!SPDFUnifiedSettingsShouldPresent(@{},YES,YES),@"detached process skips setup");
    NSDictionary* complete=@{@"settingsExperienceVersion":@(SPDFUnifiedSettingsExperienceVersion)};
    Check(!SPDFUnifiedSettingsShouldPresent(complete,YES,NO),@"complete experience does not repeat");
    Check(SPDFUnifiedSettingsShouldPresent(@{@"settingsExperienceVersion":@1,@"showSettingsOnLaunch":@YES},YES,NO),@"explicit launch preference respected");
    SPDFMacUnifiedSettingsController* controller=[[SPDFMacUnifiedSettingsController alloc]
        initWithState:@{@"collectionEnabled":@YES,@"aiEnabled":@NO,@"autoAnalyze":@NO}];
    __block NSDictionary* change; __block NSString* action; __block NSString* credential;
    controller.settingsChanged=^(NSDictionary* value){change=value;};
    controller.actionHandler=^(NSString* value){action=value;};
    controller.credentialHandler=^(NSString* value){credential=value;};
    for(NSValue* size in @[[NSValue valueWithSize:NSMakeSize(760,612)],[NSValue valueWithSize:NSMakeSize(680,520)]]) {
        [controller.window setContentSize:size.sizeValue];
        for(NSString* section in @[@"overview",@"ai",@"collection",@"reading"]) {
            [controller selectSection:section]; [controller.window.contentView layoutSubtreeIfNeeded];
            Inspect(controller.window.contentView);
            NSView* content=[controller valueForKey:@"content"];
            Check(NSWidth(content.bounds)>500,@"scroll content uses available width");
            for(NSView* child in [(NSStackView*)content arrangedSubviews]) {
                NSRect alignment=[child alignmentRectForFrame:child.frame];
                Check(NSMaxX(alignment)<=NSWidth(content.bounds)+1,@"content does not overflow horizontally");
            }
            if(size.sizeValue.width==760) {
                for(NSString* appearance in @[NSAppearanceNameDarkAqua,NSAppearanceNameAqua]) {
                    controller.window.appearance=[NSAppearance appearanceNamed:appearance];
                    NSBitmapImageRep* rep=[controller.window.contentView bitmapImageRepForCachingDisplayInRect:controller.window.contentView.bounds];
                    [controller.window.contentView cacheDisplayInRect:controller.window.contentView.bounds toBitmapImageRep:rep];
                    NSString* path=[NSString stringWithFormat:@"/tmp/sz-settings-%@-%@.png",section,appearance];
                    Check([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"native settings preview renders");
                }
            }
        }
    }
    [controller selectSection:@"ai"];
    NSButton* connect=(NSButton*)Find(controller.window.contentView,@"connect");
    Method original=class_getInstanceMethod(NSWindow.class,@selector(nextEventMatchingMask:));
    Method injected=class_getInstanceMethod(NSWindow.class,@selector(settingsProbeNextEventMatchingMask:));
    method_exchangeImplementations(original,injected);
    for(NSValue* value in @[[NSValue valueWithPoint:NSMakePoint(2,2)],
        [NSValue valueWithPoint:NSMakePoint(NSWidth(connect.bounds)-2,NSHeight(connect.bounds)-2)],
        [NSValue valueWithPoint:NSMakePoint(NSMidX(connect.bounds),NSMidY(connect.bounds))]]) {
        NSPoint point=[connect convertPoint:value.pointValue toView:nil];
        NSView* root=controller.window.contentView;
        NSView* hit=[root hitTest:[root.superview convertPoint:point fromView:nil]];
        Check(hit==connect,@"production Settings hierarchy preserves every action target");
        NSTimeInterval stamp=NSProcessInfo.processInfo.systemUptime;
        NSEvent* down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0
            timestamp:stamp windowNumber:controller.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
        NSEvent* up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0
            timestamp:stamp+.01 windowNumber:controller.window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
        action=nil; pendingMouseUp=up; [hit mouseDown:down];
        Check([action isEqual:@"connect"],@"full-bounds native click reaches connect on first press");
    }
    method_exchangeImplementations(original,injected);
    Check([action isEqual:@"connect"],@"browser connect routes to host");
    NSButton* autoAnalyze=(NSButton*)Find(controller.window.contentView,@"autoAnalyze"); [autoAnalyze performClick:nil];
    Check([change[@"autoAnalyze"] boolValue],@"automatic analysis is separate explicit preference");
    NSSecureTextField* secret=[controller valueForKey:@"secret"]; secret.stringValue=@"test-only-not-a-key";
    [(NSButton*)Find(controller.window.contentView,@"saveCredential") performClick:nil];
    Check([credential isEqual:@"test-only-not-a-key"] && !secret.stringValue.length,@"key delivered separately and immediately cleared");
    Check(![change.allValues containsObject:credential],@"credential never enters preference changes");
    [controller updateState:@{@"connecting":@YES}];
    Check(![(NSButton*)Find(controller.window.contentView,@"connect") isEnabled],@"connection cannot be started twice");
    [controller updateState:@{@"connecting":@NO,@"connected":@YES}];
    Check(Find(controller.window.contentView,@"disconnect")!=nil,@"connected account exposes disconnect");
    Check(!controller.window.visible,@"verification never shows a window");
    fprintf(stderr,"Unified settings: %d failures\n",failures); return failures?1:0;
} }
