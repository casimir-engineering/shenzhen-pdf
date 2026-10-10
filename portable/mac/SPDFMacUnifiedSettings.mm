#import "SPDFMacUnifiedSettings.h"
#import "SPDFMacCollectionStyle.h"
#import "SPDFMacGroupActionButton.h"
#import "SPDFMacSearchablePicker.h"

const NSInteger SPDFUnifiedSettingsExperienceVersion = 2;
BOOL SPDFUnifiedSettingsShouldPresent(NSDictionary* settings, BOOL primaryLaunch, BOOL detached) {
    return primaryLaunch && !detached && ([settings[@"settingsExperienceVersion"] integerValue] <
        SPDFUnifiedSettingsExperienceVersion);
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
@property(nonatomic) BOOL setupWizard;
@property(nonatomic) NSInteger wizardStep;
@property(nonatomic) NSButton* back;
@property(nonatomic) NSButton* done;
@property(nonatomic) NSButton* showAtLaunch;
@property(nonatomic) BOOL usesAPIKey;
@property(nonatomic) NSTextField* progress;
@property(nonatomic) NSStackView* defaultRows;
@property(nonatomic) NSSearchField* formatSearch;
@end

@implementation SPDFMacUnifiedSettingsController
- (instancetype)initWithState:(NSDictionary*)state {
    NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,612)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self=[super initWithWindow:window])) return nil;
    self.state=[state copy] ?: @{}; self.setupWizard=[state[@"setupWizard"] boolValue]; self.wizardStep=MAX(0,MIN(3,[state[@"wizardStep"] integerValue])); self.controls=[NSMutableDictionary dictionary];
    window.title=@"ShenzhenPDF Settings"; window.releasedWhenClosed=NO;
    window.minSize=NSMakeSize(650,540); window.delegate=self;
    NSView* root=SPDFCollectionSurface(@"window"); window.contentView=root;
    NSStackView* nav=[NSStackView stackViewWithViews:@[]]; self.navigation=nav;
    nav.spacing=8; nav.translatesAutoresizingMaskIntoConstraints=NO;
    NSArray* keys=@[@"overview",@"ai",@"collection",@"reading"];
    NSArray* labels=@[@"General",@"AI settings",@"Collection",@"Reading & access"];
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
    NSButton* done=[self button:@"Done" action:@selector(finish:) key:@"done"];
    self.done=done; done.keyEquivalent=@"\r";
    NSButton* show=[NSButton checkboxWithTitle:@"Show Settings when ShenzhenPDF starts" target:self action:@selector(toggle:)];
    show.identifier=@"showSettingsOnLaunch"; show.state=[state[@"showSettingsOnLaunch"] boolValue];
    self.showAtLaunch=show; self.controls[@"showSettingsOnLaunch"]=show; show.font=[NSFont systemFontOfSize:12];
    self.back=[self button:@"Back" action:@selector(previousStep:) key:@"wizardBack"];
    self.progress=SPDFCollectionText(@"",12,NSFontWeightMedium,YES);
    NSStackView* footer=[NSStackView stackViewWithViews:@[show,self.back,self.progress,[NSView new],done]];
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
        [content.heightAnchor constraintGreaterThanOrEqualToAnchor:scroll.contentView.heightAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20]
    ]];
    [self refreshMode]; return self;
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
    else if([section isEqual:@"access"]) [self buildAccess];
    else if([section isEqual:@"defaults"]) [self buildDefaults];
    else [self buildOverview];
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.content scrollPoint:NSZeroPoint];
}
- (void)buildOverview {
    [self heading:@"General settings" subtitle:@"Configure reading, Collection and AI. Changes are saved automatically."];
    [self divider];
    [self actionRow:@"AI" detail:@"Press ⌘K, then Return to chat. Find evidence across groups, follow page links, and undo the assistant’s changes."
        label:@"AI settings" action:@"showAI"];
    [self row:@"Keep a local copy and history" detail:@"You continue using the originals. Copies stay on this Mac; change this here at any time."
        control:[self toggle:@"collectionEnabled" label:@"Keep enabled"]];
    [self actionRow:@"Default reader" detail:@"PDFs, Markdown, text, code, images, EPUB and more. Open files here by default if you prefer."
        label:@"Choose file types…" action:@"showDefaults"];
    [self divider];
    [self text:@"⌘O  Open a document     ⌘K  Find or ask     ⌘G  Your groups" size:13 bold:NO secondary:NO];
    [self text:@"You can always return here with Settings… in the ShenzhenPDF menu." size:12 bold:NO secondary:YES];
}
- (void)buildAI {
    [self heading:@"AI settings" subtitle:@"Connect OpenRouter and choose a model. Usage is charged to your OpenRouter account."];
    BOOL connected=[self.state[@"connected"] boolValue], connecting=[self.state[@"connecting"] boolValue];
    NSButton* connect=[self button:connected ? @"Disconnect" : connecting ? @"Connecting…" : @"Connect OpenRouter"
        action:@selector(performAction:) key:connected ? @"disconnect" : @"connect"];
    connect.enabled=!connecting; self.controls[@"connection"]=connect;
    NSStackView* connectionRow=[self row:connected ? @"Connected to OpenRouter" : @"OpenRouter account"
        detail:self.state[@"connectionStatus"] ?: @"Sign in in your browser. Your credential stays in macOS Keychain." control:connect];
    NSStackView* connectionWords=connectionRow.arrangedSubviews.firstObject;
    self.connectionTitle=connectionWords.arrangedSubviews.firstObject; self.connectionDetail=connectionWords.arrangedSubviews.lastObject;
    [self buildKeyAlternative];
    [self divider];
    SPDFMacSearchablePicker* model=[[SPDFMacSearchablePicker alloc] initWithFrame:NSZeroRect];
    model.identifier=@"model"; model.emptyMessage=[self.state[@"modelsLoading"] boolValue] ? @"Loading models…" : @"Open the list to load models"; model.choices=self.state[@"models"] ?: @[];
    model.selectedID=self.state[@"model"] ?: @"deepseek/deepseek-v4.1-flash";
    __weak SPDFMacUnifiedSettingsController* weakSelf=self;
    model.opened=^{ if(weakSelf.actionHandler) weakSelf.actionHandler(@"requestModels"); };
    model.selected=^(NSString* value){ [weakSelf emit:@{@"model":value}]; };
    [model.widthAnchor constraintEqualToConstant:300].active=YES;
    [model.heightAnchor constraintEqualToConstant:28].active=YES; self.controls[@"model"]=model;
    NSStackView* modelRow=[self row:@"Model" detail:self.state[@"modelStatus"] ?: @"Search available OpenRouter models." control:model];
    self.modelDetail=[(NSStackView*)modelRow.arrangedSubviews.firstObject arrangedSubviews].lastObject;
    if(self.setupWizard) {
        [self text:@"After setup, opened documents are sent to OpenRouter for summaries and missing chapters. This uses account credits. Change this in AI settings." size:12 bold:NO secondary:YES];
        self.content.arrangedSubviews.lastObject.identifier=@"aiUploadDisclosure";
        return;
    }
    [self add:[self toggle:@"aiEnabled" label:@"Enable document chat"]];
    [self add:[self toggle:@"autoAnalyze" label:@"Prepare summaries, keywords and missing chapters automatically"]];
    [self text:@"Automatic preparation sends document text to OpenRouter and its provider after opening, in the background. It uses paid tokens. Existing chapters stay intact; generated information is cached for unchanged documents." size:12 bold:NO secondary:YES];
    [self text:@"Requests require providers that do not train on your content and retain no request data. If no eligible provider is available, the request stops. You can stop a task at any time." size:12 bold:NO secondary:YES];
}
- (void)buildKeyAlternative {
    if([self.state[@"connected"] boolValue]) return;
    if(!self.usesAPIKey) {
        [self row:@"" detail:@"" control:[self button:@"Connect with API key" action:@selector(revealKey:) key:@"revealKey"]]; return;
    }
    self.secret=[NSSecureTextField new]; self.secret.placeholderString=@"OpenRouter API key";
    self.secret.accessibilityLabel=@"OpenRouter API key"; self.secret.font=[NSFont systemFontOfSize:13];
    self.secret.target=self; self.secret.action=@selector(saveCredential:);
    NSButton* save=[self button:@"Use key" action:@selector(saveCredential:) key:@"saveCredential"];
    NSStackView* keys=[NSStackView stackViewWithViews:@[self.secret,save]]; keys.spacing=8;
    [self add:keys];
    [self add:[self button:@"Connect in browser instead" action:@selector(revealKey:) key:@"hideKey"]];
    [(NSButton*)self.controls[@"connection"] setHidden:YES];
}
- (void)revealKey:(NSButton*)sender { self.usesAPIKey=[sender.identifier isEqual:@"revealKey"]; [self selectSection:@"ai"]; if(self.secret) [self.window makeFirstResponder:self.secret]; }
- (void)buildCollection {
    [self heading:@"Collection" subtitle:@"Keep local copies and version history while continuing to work with the original files."];
    [self add:[self toggle:@"collectionEnabled" label:@"Keep a local copy and history of documents I open"]];
    [self buildStorage];
    if(self.setupWizard) return;
    [self divider];
    [self actionRow:@"Storage and location" detail:@"Choose where copies live and how much space to use. Originals are never deleted by Collection cleanup."
        label:@"Manage storage…" action:@"collectionSettings"];
    [self actionRow:@"Browse your Collection" detail:@"Search saved documents, open a copy, or explore a document’s version history."
        label:@"Open Collection" action:@"collection"];
}
- (void)buildReading {
    [self heading:@"Reading & access" subtitle:@"These choices are optional. Grant only the permissions you need."];
    [self add:[self toggle:@"keepImageColors" label:@"Keep original image colors by default"]];
    [self actionRow:@"Default reader" detail:@"Open PDF files with ShenzhenPDF from Finder and other apps."
        label:@"Choose file types…" action:@"showDefaults"];
    [self divider];
    [self actionRow:@"Full Disk Access" detail:@"For documents stored inside other apps’ protected folders. macOS may require reopening ShenzhenPDF after granting access."
        label:@"Open Settings…" action:@"fullDiskAccess"];
    [self divider];
    [self actionRow:@"Keyboard shortcuts" detail:@"Explore document navigation, search, groups and the new AI chat controls."
        label:@"View shortcuts" action:@"shortcuts"];
}
- (void)emit:(NSDictionary*)change {
    NSMutableDictionary* state=[self.state mutableCopy]; [state addEntriesFromDictionary:change]; self.state=state;
    if(self.settingsChanged) self.settingsChanged(change);
}
- (void)showSetupWizard { self.setupWizard=YES; [self refreshMode]; }
- (void)showSettings { self.setupWizard=NO; [self refreshMode]; }
- (void)refreshMode {
    self.navigation.hidden=self.setupWizard; self.showAtLaunch.hidden=YES;
    self.back.hidden=!self.setupWizard; self.back.enabled=self.wizardStep>0;
    self.progress.hidden=!self.setupWizard;
    self.progress.stringValue=[NSString stringWithFormat:@"Step %ld of 4",(long)self.wizardStep+1];
    self.done.title=self.setupWizard && self.wizardStep<3 ? @"Continue" : @"Done";
    [self.done invalidateIntrinsicContentSize];
    self.window.title=self.setupWizard ? @"Set up ShenzhenPDF" : @"ShenzhenPDF Settings";
    [self selectSection:self.setupWizard ? @[@"access",@"collection",@"ai",@"defaults"][(NSUInteger)self.wizardStep] : @"overview"];
}
- (void)previousStep:(id)sender {
    (void)sender; self.wizardStep=MAX(0,self.wizardStep-1); [self emit:@{@"wizardStep":@(self.wizardStep)}]; [self refreshMode];
}
- (void)buildAccess {
    [self heading:@"Full Disk Access" subtitle:@"Allow ShenzhenPDF to open documents in protected folders, including downloads from Mail and Safari."];
    [self actionRow:@"Grant access in macOS" detail:@"Open System Settings, enable ShenzhenPDF under Full Disk Access, then return here. macOS may require reopening the app."
        label:@"Open System Settings" action:@"fullDiskAccess"];
    [self divider];
    [self text:@"You can continue without this permission. macOS will ask for access when needed." size:13 bold:NO secondary:YES];
}
- (void)buildStorage {
    NSString* mode=self.state[@"collectionStorageMode"] ?: @"dynamic";
    NSPopUpButton* modes=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [modes addItemsWithTitles:@[@"Dynamic",@"Static limit",@"Unlimited"]];
    [modes selectItemAtIndex:[mode isEqual:@"static"] ? 1 : [mode isEqual:@"unlimited"] ? 2 : 0];
    modes.target=self; modes.action=@selector(storageModeChanged:); modes.identifier=@"collectionStorageMode";
    [self row:@"Storage limit" detail:@"Automatic cleanup never deletes originals." control:modes];
    if([mode isEqual:@"dynamic"]) {
        NSTextField* amount=SPDFCollectionText(@"80%",13,NSFontWeightSemibold,NO);
        amount.identifier=@"collectionDynamicPercent";
        [self row:@"Available storage" detail:@"Uses up to 80% of free space plus existing Collection storage. The limit adjusts as disk usage changes." control:amount];
    } else if([mode isEqual:@"static"]) {
        NSTextField* amount=[NSTextField new]; amount.font=[NSFont systemFontOfSize:13];
        amount.identifier=@"collectionStorageGiB";
        double value=[self.state[@"collectionStorageGiB"] doubleValue];
        amount.stringValue=[NSString stringWithFormat:@"%g",value>0 ? value : 10];
        amount.target=self; amount.action=@selector(storageAmountChanged:); amount.delegate=self;
        amount.accessibilityLabel=@"Storage limit in GiB";
        [amount.widthAnchor constraintEqualToConstant:80].active=YES;
        [self row:@"Limit (GiB)" detail:@"Keep Collection within a fixed storage budget." control:amount];
    }
    NSString* budget=self.state[@"collectionBudgetText"];
    if(budget.length) [self text:budget size:12 bold:NO secondary:YES];
    [self actionRow:@"Collection location" detail:self.state[@"collectionLocation"] ?: @"The default location is inside ShenzhenPDF’s application support folder."
        label:@"Set location…" action:@"setCollectionLocation"];
}
- (void)storageModeChanged:(NSPopUpButton*)sender {
    NSString* mode=@[@"dynamic",@"static",@"unlimited"][(NSUInteger)sender.indexOfSelectedItem];
    NSMutableDictionary* changes=[@{@"collectionStorageMode":mode} mutableCopy];
    if([mode isEqual:@"static"]) {
        double amount=[self.state[@"collectionStorageGiB"] doubleValue];
        if(amount<=0) amount=[self.state[@"collectionEffectiveStorageGiB"] doubleValue];
        changes[@"collectionStorageGiB"]=@(amount>0 ? amount : 10);
    }
    [self emit:changes];
    [self selectSection:@"collection"];
}
- (void)storageAmountChanged:(NSTextField*)sender {
    double value=MAX(.1,sender.doubleValue);
    sender.stringValue=[NSString stringWithFormat:@"%g",value]; [self emit:@{sender.identifier:@(value)}];
}
- (void)buildDefaults {
    [self heading:@"Default reader" subtitle:@"Choose which file types open in ShenzhenPDF. Each choice is independent."];
    self.formatSearch=[NSSearchField new]; self.formatSearch.placeholderString=@"Search file types";
    self.formatSearch.identifier=@"formatSearch"; self.formatSearch.delegate=self;
    self.formatSearch.accessibilityLabel=@"Search file types";
    [self.formatSearch.heightAnchor constraintEqualToConstant:28].active=YES;
    [self add:self.formatSearch];
    self.defaultRows=[NSStackView stackViewWithViews:@[]]; self.defaultRows.orientation=NSUserInterfaceLayoutOrientationVertical;
    self.defaultRows.alignment=NSLayoutAttributeLeading; self.defaultRows.spacing=16;
    [self add:self.defaultRows]; [self refreshDefaultRows];
}
- (void)refreshDefaultRows {
    for(NSView* view in [self.defaultRows.arrangedSubviews copy]) { [self.defaultRows removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSStackView* pageContent=self.content; self.content=self.defaultRows;
    NSArray* formats=self.state[@"defaultFormats"] ?: @[@{@"extension":@"pdf",@"name":@"PDF"},@{@"extension":@"epub",@"name":@"EPUB"},@{@"extension":@"md",@"name":@"Markdown"}];
    for(NSDictionary* format in formats) {
        NSString* ext=format[@"extension"]; if(!ext.length) continue;
        NSString* searchable=[NSString stringWithFormat:@"%@ %@",ext,format[@"name"]];
        if(self.formatSearch.stringValue.length && ![searchable localizedCaseInsensitiveContainsString:self.formatSearch.stringValue]) continue;
        BOOL current=[format[@"isDefault"] boolValue];
        NSString* action=[@"defaultReader:" stringByAppendingString:ext];
        [self actionRow:format[@"name"] ?: ext detail:[@"." stringByAppendingString:ext]
            label:current ? @"Default reader" : @"Make default" action:action];
        self.controls[action].enabled=!current;
    }
    self.content=pageContent;
}
- (void)controlTextDidChange:(NSNotification*)note { if(note.object==self.formatSearch) [self refreshDefaultRows]; }
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
    if ([[(NSControl*)note.object identifier] hasPrefix:@"collection"]) [self storageAmountChanged:note.object];
}
- (void)performAction:(NSButton*)sender {
    if ([sender.identifier isEqual:@"showDefaults"]) { [self selectSection:@"defaults"]; return; }
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
    if(overview) overview.title=@"AI settings";
    if([self.section isEqual:@"ai"]) {
        BOOL connected=[merged[@"connected"] boolValue], connecting=[merged[@"connecting"] boolValue];
        NSButton* button=(NSButton*)self.controls[@"connection"];
        button.title=connected ? @"Disconnect" : connecting ? @"Connecting…" : @"Connect OpenRouter";
        button.identifier=connected ? @"disconnect" : @"connect"; button.accessibilityLabel=button.title;
        button.enabled=!connecting; [button invalidateIntrinsicContentSize];
        self.connectionTitle.stringValue=connected ? @"Connected to OpenRouter" : @"OpenRouter account";
        self.connectionDetail.stringValue=merged[@"connectionStatus"] ?: @"Sign in in your browser. Your credential stays in macOS Keychain.";
        self.modelDetail.stringValue=[merged[@"modelsLoading"] boolValue] ? @"Loading models…" : ([merged[@"modelStatus"] length] ? merged[@"modelStatus"] : @"Search available OpenRouter models.");
        SPDFMacSearchablePicker* model=(id)self.controls[@"model"];
        model.emptyMessage=[merged[@"modelsLoading"] boolValue] ? @"Loading models…" : ([merged[@"modelStatus"] length] ? merged[@"modelStatus"] : @"No models available");
        if(state[@"modelsLoading"]) [model refreshChoices];
        if(state[@"models"]) { model.choices=merged[@"models"]; [model refreshChoices]; }
        if(state[@"model"]) model.selectedID=merged[@"model"];
        button.hidden=self.usesAPIKey && !connected;
    }
    if([self.section isEqual:@"defaults"] && state[@"defaultFormats"]) [self refreshDefaultRows];
    [self.window.contentView layoutSubtreeIfNeeded];
}
- (void)finish:(id)sender {
    (void)sender; [self.window makeFirstResponder:nil];
    if(self.setupWizard && self.wizardStep<3) { self.wizardStep++; [self emit:@{@"wizardStep":@(self.wizardStep)}]; [self refreshMode]; return; }
    self.completing=YES; [self.window close]; self.completing=NO;
}
- (void)windowWillClose:(NSNotification*)note {
    (void)note; self.secret.stringValue=@"";
    if (self.actionHandler) self.actionHandler(self.completing ? (self.setupWizard ? @"wizardDone" : @"done") : @"dismissed");
}
- (void)showForWindow:(NSWindow*)parent {
    (void)parent; [self.window center]; [self showWindow:nil];
}
@end
