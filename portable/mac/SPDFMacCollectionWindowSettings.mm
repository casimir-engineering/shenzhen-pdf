#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionStyle.h"
@interface SPDFCollectionSettingsStack : NSStackView
@end
@implementation SPDFCollectionSettingsStack
- (BOOL)isFlipped { return YES; }
@end
@implementation SPDFMacCollectionWindow (Settings)
- (void)buildSettingsPane {
    NSView* pane = SPDFCollectionSurface(@"window"); self.settingsPane = pane;
    pane.translatesAutoresizingMaskIntoConstraints = NO; [self.contentHost addSubview:pane];
    [NSLayoutConstraint activateConstraints:@[[pane.leadingAnchor constraintEqualToAnchor:self.contentHost.leadingAnchor],
        [pane.trailingAnchor constraintEqualToAnchor:self.contentHost.trailingAnchor],
        [pane.topAnchor constraintEqualToAnchor:self.contentHost.topAnchor],[pane.bottomAnchor constraintEqualToAnchor:self.contentHost.bottomAnchor]]];
    NSScrollView* scroll = [NSScrollView new]; scroll.hasVerticalScroller = YES; scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO; [pane addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:14],
        [scroll.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-14],
        [scroll.topAnchor constraintEqualToAnchor:pane.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor]]];
    NSStackView* stack = [SPDFCollectionSettingsStack stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 11; stack.edgeInsets = NSEdgeInsetsMake(14,0,14,0);
    stack.frame = NSMakeRect(0,0,710,660); scroll.documentView = stack;
    NSLayoutConstraint* width = [stack.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor]; width.priority = NSLayoutPriorityDefaultHigh; width.active = YES;
    [stack.widthAnchor constraintLessThanOrEqualToConstant:710].active = YES;
    [stack.heightAnchor constraintGreaterThanOrEqualToConstant:640].active = YES;
    void (^add)(NSView*) = ^(NSView* view) { [stack addArrangedSubview:view]; [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES; };
    void (^section)(NSString*) = ^(NSString* title) { add(SPDFCollectionText(title,13,NSFontWeightSemibold,NO)); };
    void (^divider)(void) = ^{ NSView* line = SPDFCollectionDivider(); add(line); [stack setCustomSpacing:19 afterView:line]; };
    NSTextField* title = SPDFCollectionText(@"Local copies and history",13,NSFontWeightSemibold,NO); add(title); [stack setCustomSpacing:20 afterView:title];
    self.enabled = [NSButton checkboxWithTitle:@"Keep Collection enabled" target:self action:@selector(changeEnabled:)];
    self.enabled.font = [NSFont systemFontOfSize:13]; self.enabled.state = self.store.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:self.enabled];
    NSTextField* captureHelp = SPDFCollectionText(@"You continue using the originals. Turning this off stops new copies; existing history remains available.",12,NSFontWeightRegular,YES);
    add(captureHelp); [stack setCustomSpacing:19 afterView:captureHelp]; divider();
    section(@"Storage");
    NSStackView* cap = [NSStackView stackViewWithViews:@[]]; cap.spacing = 6; cap.distribution = NSStackViewDistributionFill;
    [cap addArrangedSubview:SPDFCollectionText(@"Storage cap",12,NSFontWeightRegular,NO)];
    [cap addArrangedSubview:[NSView new]];
    self.limitPicker = SPDFCollectionPopUp(); [self.limitPicker addItemsWithTitles:@[@"Unlimited (default)",@"Custom limit"]];
    [self.limitPicker selectItemAtIndex:[self.store.settings[@"storageLimitBytes"] unsignedLongLongValue] ? 1 : 0];
    self.limitPicker.target = self; self.limitPicker.action = @selector(changeLimitMode:); [cap addArrangedSubview:self.limitPicker];
    self.limitField = [NSTextField new]; self.limitField.placeholderString = @"0";
    self.limitField.doubleValue = [self.store.settings[@"storageLimitBytes"] doubleValue]/1e9;
    self.limitField.font = [NSFont systemFontOfSize:13]; self.limitField.textColor = SPDFCollectionColor(@"text");
    self.limitField.backgroundColor = SPDFCollectionColor(@"pane");
    self.limitField.accessibilityLabel = @"Storage limit in GB; zero means unlimited";
    self.limitField.target = self; self.limitField.action = @selector(changeLimit:); self.limitField.delegate = (id)self;
    [self.limitField.widthAnchor constraintEqualToConstant:70].active = YES; [cap addArrangedSubview:self.limitField];
    self.limitUnit = SPDFCollectionText(@"GB",13,NSFontWeightRegular,NO); [cap addArrangedSubview:self.limitUnit]; add(cap);
    self.limitField.hidden = self.limitPicker.indexOfSelectedItem == 0; self.limitUnit.hidden = self.limitField.hidden;
    add(SPDFCollectionText(@"Unlimited by default. Set 0 to keep all saved copies.",12,NSFontWeightRegular,YES));
    self.storage = SPDFCollectionText(@"Storage is calculated when Collection is opened.",12,NSFontWeightRegular,YES); add(self.storage);
    NSStackView* policy = [NSStackView stackViewWithViews:@[]]; policy.spacing = 12; policy.distribution = NSStackViewDistributionFill;
    [policy addArrangedSubview:SPDFCollectionText(@"When full",13,NSFontWeightRegular,NO)]; [policy addArrangedSubview:[NSView new]];
    self.storagePolicy = SPDFCollectionText(@"No automatic deletion while unlimited",12,NSFontWeightRegular,YES);
    self.storagePolicy.alignment = NSTextAlignmentRight; [policy addArrangedSubview:self.storagePolicy]; add(policy);
    NSTextField* protection = SPDFCollectionText(@"Kept histories and original files are never removed.",12,NSFontWeightRegular,YES);
    add(protection); [stack setCustomSpacing:19 afterView:protection]; divider();
    section(@"Location");
    self.locationField = SPDFCollectionText(self.store.rootURL.path,12,NSFontWeightRegular,NO);
    self.locationField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]; self.locationField.selectable = YES; add(self.locationField);
    NSStackView* location = [NSStackView stackViewWithViews:@[
        SPDFCollectionButton(@"Set location",self,@selector(changeLocation:),@"normal"),
        SPDFCollectionButton(@"Open location",self,@selector(openLocation:),@"normal")]];
    location.spacing = 8; [stack addArrangedSubview:location];
    NSTextField* locationHelp = SPDFCollectionText(@"Set location moves the Collection after verifying the copies.",12,NSFontWeightRegular,YES);
    add(locationHelp); [stack setCustomSpacing:19 afterView:locationHelp]; divider();
    NSStackView* footer = [NSStackView stackViewWithViews:@[]]; footer.distribution = NSStackViewDistributionFill;
    self.settingsStatus = SPDFCollectionText(@"",12,NSFontWeightRegular,YES); [footer addArrangedSubview:self.settingsStatus];
    [footer addArrangedSubview:[NSView new]];
    [footer addArrangedSubview:SPDFCollectionButton(@"Apply",self,@selector(changeLimit:),@"normal")]; add(footer);
    [self updateStoragePolicy];
}
- (void)changeLimitMode:(id)sender {
    (void)sender; BOOL unlimited = self.limitPicker.indexOfSelectedItem == 0;
    self.limitField.hidden = unlimited; self.limitUnit.hidden = unlimited;
    if (!unlimited && self.limitField.doubleValue == 0) self.limitField.doubleValue = 10;
    [self updateStoragePolicy]; [self.window.contentView layoutSubtreeIfNeeded];
    NSAccessibilityPostNotification(self.settingsPane,NSAccessibilityLayoutChangedNotification);
    if (!unlimited) { [self.window makeFirstResponder:self.limitField]; [self.limitField selectText:nil]; }
}
- (void)controlTextDidChange:(NSNotification*)notification {
    if (notification.object == self.limitField) [self updateStoragePolicy];
}
- (void)updateStoragePolicy {
    double amount = 0; BOOL unlimited = self.limitPicker.indexOfSelectedItem == 0;
    NSScanner* scanner = [NSScanner scannerWithString:self.limitField.stringValue];
    BOOL valid = unlimited || ([scanner scanDouble:&amount] && scanner.isAtEnd && isfinite(amount) && amount>=0 && amount<=1e8);
    unsigned long long proposed = valid ? (unsigned long long)(amount*1e9) : 0;
    unsigned long long applied = [self.store.settings[@"storageLimitBytes"] unsignedLongLongValue];
    self.storagePolicy.stringValue = !valid ? @"Enter a valid storage limit" : proposed == 0 ?
        @"No automatic deletion while unlimited" : @"Least opened first · older versions, then documents";
    NSString* appliedLabel = applied ? [NSByteCountFormatter stringFromByteCount:(long long)applied countStyle:NSByteCountFormatterCountStyleFile] : @"Unlimited";
    self.settingsStatus.stringValue = !valid ? @"Enter a valid limit before applying." : proposed != applied ?
        [NSString stringWithFormat:@"Pending change · Apply to review. Applied limit: %@.",appliedLabel] :
        [NSString stringWithFormat:@"Applied limit: %@.",appliedLabel];
}
- (void)openLocation:(id)sender {
    (void)sender;
    if (![NSWorkspace.sharedWorkspace openURL:self.store.rootURL])
        [self showError:[NSError errorWithDomain:@"ShenzhenPDF.Collection" code:1 userInfo:@{
            NSLocalizedDescriptionKey:@"The Collection folder is not available yet. It is created when the first copy is saved."}]];
}
@end
