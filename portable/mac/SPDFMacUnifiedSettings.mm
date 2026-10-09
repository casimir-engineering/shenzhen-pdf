#import "SPDFMacUnifiedSettings.h"
#import "SPDFMacCollectionStyle.h"
#import "SPDFMacGroupActionButton.h"

const NSInteger SPDFUnifiedSettingsExperienceVersion = 1;
BOOL SPDFUnifiedSettingsShouldPresent(NSDictionary* settings, BOOL primaryLaunch, BOOL detached) {
    return primaryLaunch && !detached && ([settings[@"settingsExperienceVersion"] integerValue] <
        SPDFUnifiedSettingsExperienceVersion || [settings[@"showSettingsOnLaunch"] boolValue]);
}

@interface SPDFSettingsStack : NSStackView
@end
@implementation SPDFSettingsStack
- (BOOL)isFlipped { return YES; }
@end

// Reuse the reader's full-bounds, first-click tracking. Native cell drawing is
// intentionally replaced only for appearance, not by another tracking mechanism.
@interface SPDFSettingsButton : SPDFGroupActionButton
@end
@implementation SPDFSettingsButton
- (NSSize)intrinsicContentSize {
    return NSMakeSize(ceil([self.title sizeWithAttributes:@{NSFontAttributeName:self.font}].width)+24,28);
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    NSBezierPath* shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:5 yRadius:5];
    [SPDFCollectionColor(self.highlighted || self.state==NSControlStateValueOn || [self.identifier isEqual:@"done"] ? @"selected" : @"control") setFill];
    [shape fill];
    NSMutableParagraphStyle* style=[NSMutableParagraphStyle new]; style.alignment=NSTextAlignmentCenter;
    NSDictionary* attributes=@{NSFontAttributeName:self.font,NSForegroundColorAttributeName:
        SPDFCollectionColor(self.enabled ? @"text" : @"secondary"),NSParagraphStyleAttributeName:style};
    CGFloat h=[self.title sizeWithAttributes:attributes].height;
    [self.title drawInRect:NSMakeRect(8,floor((self.bounds.size.height-h)/2),self.bounds.size.width-16,h)
        withAttributes:attributes];
    if (self.window.firstResponder==self) {
        [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill];
        [NSGraphicsContext restoreGraphicsState];
    }
}
@end

@interface SPDFMacUnifiedSettingsController ()
@property(nonatomic) NSDictionary* state;
@property(nonatomic) NSStackView* content;
@property(nonatomic) NSStackView* navigation;
@property(nonatomic) NSMutableDictionary<NSString*,NSControl*>* controls;
@property(nonatomic) NSTextField* status;
@property(nonatomic) NSTextField* connectionTitle;
@property(nonatomic) NSTextField* connectionDetail;
@property(nonatomic) NSTextField* modelDetail;
@property(nonatomic) NSSecureTextField* secret;
@property(nonatomic) NSString* section;
@property(nonatomic) BOOL completing;
@end

@implementation SPDFMacUnifiedSettingsController
- (instancetype)initWithState:(NSDictionary*)state {
    NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,612)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self=[super initWithWindow:window])) return nil;
    self.state=[state copy] ?: @{}; self.controls=[NSMutableDictionary dictionary];
    window.title=@"ShenzhenPDF Settings"; window.releasedWhenClosed=NO;
    window.minSize=NSMakeSize(650,540); window.delegate=self;
    NSView* root=SPDFCollectionSurface(@"window"); window.contentView=root;
    NSStackView* nav=[NSStackView stackViewWithViews:@[]]; self.navigation=nav;
    nav.spacing=8; nav.translatesAutoresizingMaskIntoConstraints=NO;
    NSArray* keys=@[@"overview",@"ai",@"collection",@"reading"];
    NSArray* labels=@[@"Start here",@"AI & documents",@"Collection",@"Reading & access"];
    for (NSUInteger i=0;i<keys.count;i++) {
        NSButton* b=[self button:labels[i] action:@selector(changeSection:) key:keys[i]];
        [nav addArrangedSubview:b];
    }
    NSScrollView* scroll=[NSScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.hasVerticalScroller=YES; scroll.drawsBackground=NO; scroll.borderType=NSNoBorder;
    NSStackView* content=[SPDFSettingsStack stackViewWithViews:@[]]; self.content=content;
    content.orientation=NSUserInterfaceLayoutOrientationVertical; content.alignment=NSLayoutAttributeLeading;
    content.spacing=16; content.edgeInsets=NSEdgeInsetsMake(8,0,24,0);
    content.translatesAutoresizingMaskIntoConstraints=NO; scroll.documentView=content;
    NSButton* done=[self button:@"Start reading" action:@selector(finish:) key:@"done"];
    done.keyEquivalent=@"\r";
    NSButton* show=[NSButton checkboxWithTitle:@"Show Settings when ShenzhenPDF starts" target:self action:@selector(toggle:)];
    show.identifier=@"showSettingsOnLaunch"; show.state=[state[@"showSettingsOnLaunch"] boolValue];
    self.controls[@"showSettingsOnLaunch"]=show; show.font=[NSFont systemFontOfSize:12];
    NSStackView* footer=[NSStackView stackViewWithViews:@[show,[NSView new],done]];
    footer.spacing=16; footer.translatesAutoresizingMaskIntoConstraints=NO;
    for (NSView* view in @[nav,scroll,footer]) [root addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [nav.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [nav.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],
        [nav.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [scroll.topAnchor constraintEqualToAnchor:nav.bottomAnchor constant:20],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-12],
        [content.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20]
    ]];
    [self selectSection:@"overview"]; return self;
}
- (NSButton*)button:(NSString*)title action:(SEL)action key:(NSString*)key {
    SPDFSettingsButton* button=[[SPDFSettingsButton alloc] initWithFrame:NSZeroRect];
    button.title=title; button.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    button.target=self; button.action=action; button.bordered=NO;
    button.identifier=key; button.accessibilityLabel=title; button.translatesAutoresizingMaskIntoConstraints=NO;
    [button.heightAnchor constraintEqualToConstant:28].active=YES;
    return button;
}
- (void)add:(NSView*)view {
    [self.content addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:self.content.widthAnchor].active=YES;
}
- (void)text:(NSString*)text size:(CGFloat)size bold:(BOOL)bold secondary:(BOOL)secondary {
    NSTextField* label=SPDFCollectionText(text,size,bold ? NSFontWeightSemibold : NSFontWeightRegular,secondary);
    label.lineBreakMode=NSLineBreakByWordWrapping; label.maximumNumberOfLines=0;
    label.cell.wraps=YES; label.cell.scrollable=NO; [self add:label];
}
- (void)heading:(NSString*)title subtitle:(NSString*)subtitle {
    [self text:title size:24 bold:YES secondary:NO]; [self text:subtitle size:13 bold:NO secondary:YES];
}
- (NSStackView*)row:(NSString*)title detail:(NSString*)detail control:(NSView*)control {
    NSTextField* name=SPDFCollectionText(title,13,NSFontWeightSemibold,NO);
    NSTextField* help=SPDFCollectionText(detail,12,NSFontWeightRegular,YES);
    help.lineBreakMode=NSLineBreakByWordWrapping; help.maximumNumberOfLines=0; help.cell.wraps=YES;
    NSStackView* words=[NSStackView stackViewWithViews:@[name,help]];
    words.orientation=NSUserInterfaceLayoutOrientationVertical; words.alignment=NSLayoutAttributeLeading; words.spacing=4;
    NSStackView* row=[NSStackView stackViewWithViews:@[words,control]]; row.spacing=24;
    row.alignment=NSLayoutAttributeCenterY; row.distribution=NSStackViewDistributionFill;
    [words setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [help.widthAnchor constraintEqualToAnchor:words.widthAnchor].active=YES; [self add:row]; return row;
}
- (NSButton*)toggle:(NSString*)key label:(NSString*)label {
    NSButton* button=[NSButton checkboxWithTitle:label target:self action:@selector(toggle:)];
    button.identifier=key; button.state=[self.state[key] boolValue];
    button.font=[NSFont systemFontOfSize:13]; button.accessibilityLabel=label;
    self.controls[key]=button; return button;
}
- (void)actionRow:(NSString*)title detail:(NSString*)detail label:(NSString*)label action:(NSString*)action {
    NSButton* button=[self button:label action:@selector(performAction:) key:action];
    button.accessibilityLabel=[NSString stringWithFormat:@"%@ — %@",label,title]; self.controls[action]=button;
    [self row:title detail:detail control:button];
}
- (void)divider { [self add:SPDFCollectionDivider()]; }
- (void)selectSection:(NSString*)section {
    self.section=section; self.secret.stringValue=@""; self.secret=nil;
    for (NSView* view in [self.content.arrangedSubviews copy]) { [self.content removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSControl* show=self.controls[@"showSettingsOnLaunch"]; [self.controls removeAllObjects];
    if (show) self.controls[@"showSettingsOnLaunch"]=show;
    for (NSButton* button in self.navigation.arrangedSubviews) button.state=[button.identifier isEqual:section];
    if ([section isEqual:@"ai"]) [self buildAI];
    else if ([section isEqual:@"collection"]) [self buildCollection];
    else if ([section isEqual:@"reading"]) [self buildReading];
    else [self buildOverview];
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.content scrollPoint:NSZeroPoint];
}
- (void)buildOverview {
    [self heading:@"Make room for your documents." subtitle:@"A few choices, all in one place. Reading works straight away; AI is optional."];
    [self divider];
    [self actionRow:@"Ask your documents" detail:@"Press ⌘K, then Return to chat. Find evidence across groups, follow page links, and undo the assistant’s changes."
        label:[self.state[@"connected"] boolValue] ? @"AI settings" : @"Connect OpenRouter" action:@"showAI"];
    [self row:@"Keep a local copy and history" detail:@"You continue using the originals. Copies stay on this Mac; change this here at any time."
        control:[self toggle:@"collectionEnabled" label:@"Keep enabled"]];
    [self actionRow:@"Your everyday reader" detail:@"PDFs, Markdown, text, code, images, EPUB and more. Open files here by default if you prefer."
        label:@"Make default…" action:@"defaultReader"];
    [self divider];
    [self text:@"⌘O  Open a document     ⌘K  Find or ask     ⌘G  Your groups" size:13 bold:NO secondary:NO];
    [self text:@"You can always return here with Settings… in the ShenzhenPDF menu." size:12 bold:NO secondary:YES];
}
- (void)buildAI {
    [self heading:@"A conversation with your documents." subtitle:@"Connect your own OpenRouter account. Your account pays for usage; ShenzhenPDF adds no AI fee."];
    BOOL connected=[self.state[@"connected"] boolValue], connecting=[self.state[@"connecting"] boolValue];
    NSButton* connect=[self button:connected ? @"Disconnect" : connecting ? @"Connecting…" : @"Connect OpenRouter"
        action:@selector(performAction:) key:connected ? @"disconnect" : @"connect"];
    connect.enabled=!connecting; self.controls[@"connection"]=connect;
    NSStackView* connectionRow=[self row:connected ? @"Connected to OpenRouter" : @"OpenRouter account"
        detail:self.state[@"connectionStatus"] ?: @"Sign in in your browser. Your credential stays in macOS Keychain." control:connect];
    NSStackView* connectionWords=connectionRow.arrangedSubviews.firstObject;
    self.connectionTitle=connectionWords.arrangedSubviews.firstObject; self.connectionDetail=connectionWords.arrangedSubviews.lastObject;
    [self divider];
    NSTextField* model=[NSTextField new]; model.identifier=@"model"; model.delegate=self;
    model.stringValue=self.state[@"model"] ?: @"deepseek/deepseek-v4.1-flash";
    model.placeholderString=@"provider/model"; model.font=[NSFont systemFontOfSize:13];
    model.accessibilityLabel=@"OpenRouter model identifier"; model.target=self; model.action=@selector(modelChanged:);
    [model.widthAnchor constraintEqualToConstant:300].active=YES; self.controls[@"model"]=model;
    NSStackView* modelRow=[self row:@"Model" detail:[self.state[@"modelStatus"] length] ? self.state[@"modelStatus"] : @"Choose an OpenRouter model ID. Availability and price depend on the provider." control:model];
    self.modelDetail=[(NSStackView*)modelRow.arrangedSubviews.firstObject arrangedSubviews].lastObject;
    [self add:[self toggle:@"aiEnabled" label:@"Enable document chat"]];
    [self add:[self toggle:@"autoAnalyze" label:@"Prepare summaries, keywords and missing chapters automatically"]];
    [self text:@"Automatic preparation sends document text to OpenRouter and its provider after opening, in the background. It uses paid tokens. Existing chapters stay intact; generated information is cached for unchanged documents." size:12 bold:NO secondary:YES];
    [self text:@"Requests require providers that do not train on your content and retain no request data. If no eligible provider is available, the request stops. You can stop a task at any time." size:12 bold:NO secondary:YES];
    [self divider];
    self.secret=[NSSecureTextField new]; self.secret.placeholderString=@"Paste an API key instead";
    self.secret.accessibilityLabel=@"OpenRouter API key"; self.secret.font=[NSFont systemFontOfSize:13];
    self.secret.target=self; self.secret.action=@selector(saveCredential:);
    NSButton* save=[self button:@"Use key" action:@selector(saveCredential:) key:@"saveCredential"];
    NSStackView* keys=[NSStackView stackViewWithViews:@[self.secret,save]]; keys.spacing=8;
    [self add:keys]; [self text:@"Optional alternative to browser sign-in. The key is never written to settings files or chat history." size:11 bold:NO secondary:YES];
}
- (void)buildCollection {
    [self heading:@"A safety net, on this Mac." subtitle:@"Keep local copies and version history while continuing to work with the original files."];
    [self add:[self toggle:@"collectionEnabled" label:@"Keep a local copy and history of documents I open"]];
    [self text:@"Turning this off stops new copies. Your existing Collection remains available. Storage is unlimited unless you choose a limit." size:13 bold:NO secondary:YES];
    [self divider];
    [self actionRow:@"Storage and location" detail:@"Choose where copies live and how much space to use. Originals are never deleted by Collection cleanup."
        label:@"Manage storage…" action:@"collectionSettings"];
    [self actionRow:@"Browse your Collection" detail:@"Search saved documents, open a copy, or explore a document’s version history."
        label:@"Open Collection" action:@"collection"];
}
- (void)buildReading {
    [self heading:@"Comfortable reading. Fewer interruptions." subtitle:@"These choices are optional. Grant only the permissions you need."];
    [self add:[self toggle:@"keepImageColors" label:@"Keep original image colors by default"]];
    [self actionRow:@"Default reader" detail:@"Open PDF files with ShenzhenPDF from Finder and other apps."
        label:@"Make default…" action:@"defaultReader"];
    [self divider];
    [self actionRow:@"Accessibility" detail:@"Allow trackpad zoom in an unfocused reader window. Normal reading and zoom work without it."
        label:@"Open Settings…" action:@"accessibility"];
    [self actionRow:@"Full Disk Access" detail:@"For documents stored inside other apps’ protected folders. macOS may require reopening ShenzhenPDF after granting access."
        label:@"Open Settings…" action:@"fullDiskAccess"];
    [self divider];
    [self actionRow:@"Keyboard shortcuts" detail:@"Explore document navigation, search, groups and the new AI chat controls."
        label:@"View shortcuts" action:@"shortcuts"];
}
- (void)changeSection:(NSButton*)sender { [self selectSection:sender.identifier]; }
- (void)toggle:(NSButton*)sender {
    NSDictionary* change=@{sender.identifier:@(sender.state==NSControlStateValueOn)};
    NSMutableDictionary* state=[self.state mutableCopy]; [state addEntriesFromDictionary:change]; self.state=state;
    if (self.settingsChanged) self.settingsChanged(change);
}
- (void)modelChanged:(NSTextField*)sender {
    NSString* model=[sender.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!model.length) return;
    NSMutableDictionary* state=[self.state mutableCopy]; state[@"model"]=model; self.state=state;
    if (self.settingsChanged) self.settingsChanged(@{@"model":model});
}
- (void)controlTextDidEndEditing:(NSNotification*)note {
    if ([[(NSControl*)note.object identifier] isEqual:@"model"]) [self modelChanged:note.object];
}
- (void)performAction:(NSButton*)sender {
    if ([sender.identifier isEqual:@"showAI"]) { [self selectSection:@"ai"]; return; }
    if (self.actionHandler) self.actionHandler(sender.identifier);
}
- (void)saveCredential:(id)sender {
    (void)sender; NSString* secret=[self.secret.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.secret.stringValue=@"";
    if (secret.length && self.credentialHandler) self.credentialHandler(secret);
}
- (void)updateState:(NSDictionary*)state {
    NSMutableDictionary* merged=[self.state mutableCopy]; [merged addEntriesFromDictionary:state]; self.state=merged;
    // Status callbacks must not destroy a field editor or erase an in-progress
    // API-key draft. Update the existing controls; rebuild only on section changes.
    for(NSString* key in @[@"showSettingsOnLaunch",@"collectionEnabled",@"keepImageColors",@"aiEnabled",@"autoAnalyze"])
        if(state[key]) [(NSButton*)self.controls[key] setState:[merged[key] boolValue]];
    NSButton* overview=(NSButton*)self.controls[@"showAI"];
    if(overview) overview.title=[merged[@"connected"] boolValue] ? @"AI settings" : @"Connect OpenRouter";
    if([self.section isEqual:@"ai"]) {
        BOOL connected=[merged[@"connected"] boolValue], connecting=[merged[@"connecting"] boolValue];
        NSButton* button=(NSButton*)self.controls[@"connection"];
        button.title=connected ? @"Disconnect" : connecting ? @"Connecting…" : @"Connect OpenRouter";
        button.identifier=connected ? @"disconnect" : @"connect"; button.accessibilityLabel=button.title;
        button.enabled=!connecting; [button invalidateIntrinsicContentSize];
        self.connectionTitle.stringValue=connected ? @"Connected to OpenRouter" : @"OpenRouter account";
        self.connectionDetail.stringValue=merged[@"connectionStatus"] ?: @"Sign in in your browser. Your credential stays in macOS Keychain.";
        self.modelDetail.stringValue=[merged[@"modelStatus"] length] ? merged[@"modelStatus"] : @"Choose an OpenRouter model ID. Availability and price depend on the provider.";
        NSTextField* model=(NSTextField*)self.controls[@"model"];
        if(state[@"model"] && !model.currentEditor) model.stringValue=merged[@"model"];
    }
    [self.window.contentView layoutSubtreeIfNeeded];
}
- (void)finish:(id)sender {
    (void)sender; [self.window makeFirstResponder:nil]; self.completing=YES; [self.window close]; self.completing=NO;
}
- (void)windowWillClose:(NSNotification*)note {
    (void)note; self.secret.stringValue=@"";
    if (self.actionHandler) self.actionHandler(self.completing ? @"done" : @"dismissed");
}
- (void)showForWindow:(NSWindow*)parent {
    (void)parent; [self.window center]; [self showWindow:nil];
}
@end
