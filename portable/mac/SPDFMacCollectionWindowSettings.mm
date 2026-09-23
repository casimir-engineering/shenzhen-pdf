#import "SPDFMacCollectionWindowPrivate.h"
@interface SPDFCollectionSettingsStack : NSStackView
@end
@implementation SPDFCollectionSettingsStack
- (BOOL)isFlipped { return YES; }
@end
@implementation SPDFMacCollectionWindow (Settings)
- (void)buildSettingsPane {
    NSView* pane = [NSView new]; self.settingsPane = pane;
    pane.translatesAutoresizingMaskIntoConstraints = NO; [self.contentHost addSubview:pane];
    [NSLayoutConstraint activateConstraints:@[
        [pane.leadingAnchor constraintEqualToAnchor:self.contentHost.leadingAnchor],
        [pane.trailingAnchor constraintEqualToAnchor:self.contentHost.trailingAnchor],
        [pane.topAnchor constraintEqualToAnchor:self.contentHost.topAnchor],
        [pane.bottomAnchor constraintEqualToAnchor:self.contentHost.bottomAnchor]]];
    NSScrollView* scroll = [NSScrollView new]; scroll.hasVerticalScroller = YES; scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO; [pane addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-16],
        [scroll.topAnchor constraintEqualToAnchor:pane.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor]]];
    NSStackView* stack = [SPDFCollectionSettingsStack stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 14; stack.edgeInsets = NSEdgeInsetsMake(8,0,16,0);
    stack.frame = NSMakeRect(0,0,680,660); scroll.documentView = stack;
    [stack.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;
    [stack.heightAnchor constraintGreaterThanOrEqualToConstant:640].active = YES;
    void (^label)(NSString*,CGFloat) = ^(NSString* text,CGFloat size) {
        NSTextField* field = [NSTextField wrappingLabelWithString:text];
        field.font = [NSFont systemFontOfSize:size]; [stack addArrangedSubview:field];
        [field.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    };
    label(@"Collection Settings",22);
    self.enabled = [NSButton checkboxWithTitle:@"Keep local copies and history" target:self action:@selector(changeEnabled:)];
    self.enabled.state = self.store.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:self.enabled];
    label(@"Turning this off stops new copies and indexing. Existing history remains searchable.",12);
    label(@"Location",16);
    self.locationField = [NSTextField wrappingLabelWithString:self.store.rootURL.path];
    self.locationField.selectable = YES; [stack addArrangedSubview:self.locationField];
    [self.locationField.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    NSStackView* location = [NSStackView stackViewWithViews:@[
        [NSButton buttonWithTitle:@"Set location" target:self action:@selector(changeLocation:)],
        [NSButton buttonWithTitle:@"Open location" target:self action:@selector(openLocation:)]]];
    [stack addArrangedSubview:location];
    label(@"Storage",16);
    self.storage = [NSTextField wrappingLabelWithString:@"Storage is calculated when Collection is opened."];
    [stack addArrangedSubview:self.storage]; [self.storage.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    NSStackView* cap = [NSStackView stackViewWithViews:@[]]; cap.spacing = 8;
    self.limitField = [NSTextField new]; self.limitField.placeholderString = @"0";
    self.limitField.doubleValue = [self.store.settings[@"storageLimitBytes"] doubleValue]/1e9;
    self.limitField.accessibilityLabel = @"Storage limit in GB; zero means unlimited";
    self.limitField.target = self; self.limitField.action = @selector(changeLimit:);
    [self.limitField.widthAnchor constraintEqualToConstant:100].active = YES; [cap addArrangedSubview:self.limitField];
    [cap addArrangedSubview:[NSTextField labelWithString:@"GB · 0 = Unlimited"]];
    [cap addArrangedSubview:[NSButton buttonWithTitle:@"Apply" target:self action:@selector(changeLimit:)]];
    [stack addArrangedSubview:cap];
    label(@"Unlimited by default. With a limit, Collection starts with the least-opened documents and removes their oldest versions first, keeping their latest copy. If more space is needed, it removes the remaining Collection documents in the same order.",12);
    label(@"A Keep mark on any version protects the whole history. Originals are never removed. If protected history prevents cleanup, new captures pause until space is available.",12);
}
- (void)openLocation:(id)sender {
    (void)sender;
    if (![NSWorkspace.sharedWorkspace openURL:self.store.rootURL])
        [self showError:[NSError errorWithDomain:@"ShenzhenPDF.Collection" code:1 userInfo:@{
            NSLocalizedDescriptionKey:@"The Collection folder is not available yet. It is created when the first copy is saved."}]];
}
@end
