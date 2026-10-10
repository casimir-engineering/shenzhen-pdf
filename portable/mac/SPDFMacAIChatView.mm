#import "SPDFMacAIChatView.h"
#import "SPDFMacAIChatSession.h"
#import "SPDFMacCollectionStyle.h"
#import "SPDFMacAIChatMarkdown.h"
#import "SPDFMacGroupActionButton.h"
#import "SPDFMacAIChatStore.h"
#import "SPDFMacAIChatSearch.h"
#import "SPDFMacPanelSearchField.h"
@interface SPDFChatButton : SPDFGroupActionButton
@end
@implementation SPDFChatButton
- (NSSize)intrinsicContentSize { return self.image ? NSMakeSize(28,28) : NSMakeSize(ceil([self.title sizeWithAttributes:@{NSFontAttributeName:self.font}].width)+20,28); }
- (NSRect)rectForSymbol:(NSImage*)icon {
    NSRect available=NSInsetRect(self.bounds,6,6); NSSize size=icon.size;
    if(size.width<=0 || size.height<=0) return NSZeroRect;
    CGFloat scale=MIN(NSWidth(available)/size.width,NSHeight(available)/size.height);
    return NSMakeRect(NSMidX(available)-size.width*scale/2,NSMidY(available)-size.height*scale/2,size.width*scale,size.height*scale);
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty; NSBezierPath* shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:5 yRadius:5];
    if(self.highlighted || self.state==NSControlStateValueOn || [self.identifier isEqual:@"send"] || [self.identifier isEqual:@"authorize"]) {
        [SPDFCollectionColor(self.highlighted || self.state==NSControlStateValueOn ? @"selected" : @"control") setFill]; [shape fill];
    }
    if(self.image) {
        NSImageSymbolConfiguration* configuration=[[NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightMedium]
            configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[SPDFCollectionColor(self.enabled ? @"text" : @"secondary")]]];
        NSImage* icon=[self.image imageWithSymbolConfiguration:configuration];
        [icon drawInRect:[self rectForSymbol:icon] fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.enabled ? 1 : .65 respectFlipped:YES hints:nil];
        if(self.state==NSControlStateValueOn) { [NSColor.controlAccentColor setStroke]; [shape stroke]; }
    } else {
    NSMutableParagraphStyle* p=[NSMutableParagraphStyle new]; p.alignment=self.alignment; p.lineBreakMode=NSLineBreakByTruncatingTail;
    NSDictionary* a=@{NSFontAttributeName:self.font,NSForegroundColorAttributeName:SPDFCollectionColor(self.enabled ? @"text" : @"secondary"),NSParagraphStyleAttributeName:p};
    CGFloat h=[self.title sizeWithAttributes:a].height;
    [self.title drawInRect:NSMakeRect(10,floor((self.bounds.size.height-h)/2),self.bounds.size.width-20,h) withAttributes:a];
    }
    if(self.window.firstResponder==self) { [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill]; [NSGraphicsContext restoreGraphicsState]; }
}
@end
@interface SPDFChatMessageView : NSTextView
@property(nonatomic) NSLayoutConstraint* contentHeight;
@property(nonatomic) BOOL measurementScheduled;
@property(nonatomic) CGFloat measuredWidth;
@end
@implementation SPDFChatMessageView
- (void)drawRect:(NSRect)dirty {
    [self.backgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:7 yRadius:7] fill];
    [super drawRect:dirty];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    if(!self.contentHeight || self.measurementScheduled || size.width<=2*self.textContainerInset.width || self.hiddenOrHasHiddenAncestor) return;
    // NSStackView is assigning its cached frames here. Changing constraints in
    // that callback leaves child frames one layout behind their new heights.
    // Measure after the current layout transaction, never at a hidden dock's
    // zero width; that otherwise expands one line into hundreds of points.
    self.measurementScheduled=YES;
    __weak SPDFChatMessageView* weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SPDFChatMessageView* view=weakSelf; if(!view)return;
        view.measurementScheduled=NO;
        CGFloat width=NSWidth(view.bounds)-2*view.textContainerInset.width;
        if(width<=0 || view.hiddenOrHasHiddenAncestor || fabs(width-view.measuredWidth)<.5)return;
        view.measuredWidth=width;
        view.textContainer.containerSize=NSMakeSize(width,CGFLOAT_MAX);
        [view.layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0,view.string.length) actualCharacterRange:nil];
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
        CGFloat height=MAX(18,ceil(NSMaxY([view.layoutManager usedRectForTextContainer:view.textContainer])))+2*view.textContainerInset.height;
        if(fabs(height-view.contentHeight.constant)>.5) {view.contentHeight.constant=height;view.superview.needsLayout=YES;}
        view.needsDisplay=YES;
    });
}
@end
@interface SPDFChatInputScrollView : NSScrollView
- (void)updateBorder;
- (BOOL)composerFocused;
@end
@implementation SPDFChatInputScrollView
- (BOOL)composerFocused { return [self.window.firstResponder isKindOfClass:NSTextView.class] && [(NSView*)self.window.firstResponder isDescendantOf:self]; }
- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    NSBezierPath* outline=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:7 yRadius:7];
    outline.lineWidth=[self composerFocused] ? 2 : 1;
    [([self composerFocused] ? NSColor.keyboardFocusIndicatorColor : SPDFCollectionColor(@"line")) setStroke]; [outline stroke];
}
- (void)updateBorder {
    self.needsDisplay=YES;
    BOOL focused=[self.window.firstResponder isKindOfClass:NSTextView.class] &&
        [(NSView*)self.window.firstResponder isDescendantOf:self];
    self.layer.borderWidth=focused ? 2 : 1;
    self.layer.borderColor=(focused ? NSColor.keyboardFocusIndicatorColor : SPDFCollectionColor(@"line")).CGColor;
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self updateBorder]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self updateBorder]; }
- (void)layout { [super layout]; [self updateBorder]; }
@end
@interface SPDFChatComposer : NSTextView
@property(nonatomic, copy) void (^submit)(void);
@property(nonatomic, copy) void (^undoAction)(void);
@property(nonatomic, copy) void (^redoAction)(void);
@property(nonatomic, copy) void (^closeAction)(void);
@end
@implementation SPDFChatComposer
- (BOOL)becomeFirstResponder { BOOL ok=[super becomeFirstResponder]; [(SPDFChatInputScrollView*)self.enclosingScrollView updateBorder]; return ok; }
- (BOOL)resignFirstResponder { BOOL ok=[super resignFirstResponder]; dispatch_async(dispatch_get_main_queue(), ^{ [(SPDFChatInputScrollView*)self.enclosingScrollView updateBorder]; }); return ok; }
- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    if(!self.string.length) [@"Ask about your documents…" drawAtPoint:NSMakePoint(13,8)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13],NSForegroundColorAttributeName:SPDFCollectionColor(@"secondary")}];
}
- (BOOL)performKeyEquivalent:(NSEvent*)event {
    if(self.window.firstResponder==self && !self.hiddenOrHasHiddenAncestor && !self.hasMarkedText && !self.string.length && (event.modifierFlags & NSEventModifierFlagCommand) &&
       [event.charactersIgnoringModifiers.lowercaseString isEqual:@"z"]) {[self keyDown:event];return YES;}
    return [super performKeyEquivalent:event];
}
- (void)keyDown:(NSEvent*)event {
    if(self.hasMarkedText) {[super keyDown:event];return;}
    if(event.keyCode==53 && !self.hasMarkedText) { if(self.closeAction)self.closeAction();return; }
    if ((event.keyCode==36 || event.keyCode==76) && !(event.modifierFlags & NSEventModifierFlagShift)) {
        if (self.submit) self.submit(); return;
    }
    if ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers.lowercaseString isEqual:@"z"] && !self.string.length) {
        if(event.modifierFlags & NSEventModifierFlagShift) {if(self.redoAction)self.redoAction();}
        else if (self.undoAction) self.undoAction(); return;
    }
    [super keyDown:event];
}
@end
@interface SPDFChatFlippedView : NSView @end
@implementation SPDFChatFlippedView
- (BOOL)isFlipped { return YES; }
@end
@interface SPDFMacAIChatView () <NSTextViewDelegate,NSSearchFieldDelegate>
@end
@implementation SPDFMacAIChatView {
    SPDFChatComposer* _composer; NSTextField* _status; NSTextField* _inputHelp; NSScrollView* _scroll; NSScrollView* _input; NSStackView* _messages;
    SPDFMacAIChatSearch* _chatFind;
    NSLayoutConstraint* _inputHeight; NSLayoutConstraint* _stopTrailing; NSLayoutConstraint* _stopHistoryTrailing;
    NSStackView* _issue; NSTextField* _issueText; NSButton* _recovery; NSLayoutConstraint* _issueHeight;
    NSButton* _redo; NSSearchField* _chatSearch; NSTextField* _activityDetail; NSProgressIndicator* _progress;
    NSTextField* _prompt; NSLayoutConstraint* _promptHeight; NSArray* _displayedMessages;
    NSString* _submissionError; NSButton* _send; NSButton* _stop; NSButton* _undo; NSUInteger _visibleLimit; NSString* _chatID; BOOL _history; BOOL _running; BOOL _preserveScroll; __weak SPDFMacAIChatSession* _displayedSession;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty; [SPDFCollectionColor(@"window") setFill]; NSRectFill(self.bounds);
    [SPDFCollectionColor(@"line") setFill]; NSRectFill(NSMakeRect(0,35.5,NSWidth(self.bounds),.5));
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES;
    if(_displayedSession && !_history) { _displayedMessages=nil; [self displaySession:_displayedSession]; }
}
- (void)setFrameSize:(NSSize)size {
    BOOL atBottom=_scroll && NSMaxY(_scroll.contentView.bounds)>=NSHeight(_scroll.documentView.bounds)-24;
    BOOL widthChanged=fabs(size.width-self.bounds.size.width)>.5;
    [super setFrameSize:size];
    if(widthChanged && _displayedSession) [self refreshActivityFromSession:_displayedSession];
    if(atBottom && widthChanged && !_chatSearch.stringValue.length) dispatch_async(dispatch_get_main_queue(), ^{ [self scrollToNewest]; });
}
- (NSTextView*)composer { return _composer; }
- (void)setChatSearchQuery:(NSString*)query {
    _chatSearch.stringValue=query ?: @""; _displayedMessages=nil;
    if(_displayedSession) [self displaySession:_displayedSession];
}
- (NSButton*)button:(NSString*)title action:(NSString*)action {
    SPDFChatButton* b=[[SPDFChatButton alloc] initWithFrame:NSZeroRect];
    b.title=title ?: @"Untitled chat"; b.font=[NSFont systemFontOfSize:13]; b.bordered=NO;
    b.alignment=NSTextAlignmentCenter; b.target=self; b.action=@selector(clicked:); b.identifier=action;
    b.accessibilityLabel=title; b.toolTip=title; b.translatesAutoresizingMaskIntoConstraints=NO;
    [b.heightAnchor constraintEqualToConstant:28].active=YES; return b;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    _visibleLimit=40; _undo=[self button:@"Undo" action:@"undo"]; _undo.enabled=NO; _undo.toolTip=@"Undo the assistant’s last action";
    _redo=[self button:@"Redo" action:@"redo"];_redo.enabled=NO;
    NSArray* buttons=@[[self button:@"Hide chat panel" action:@"close"],[self button:@"New chat" action:@"new"],_undo,_redo,
        [self button:@"AI settings" action:@"settings"]];
    NSArray* symbols=@[@"sidebar.left",@"square.and.pencil",@"arrow.uturn.backward",@"arrow.uturn.forward",@"gearshape"];
    for(NSUInteger i=0;i<buttons.count;i++){NSButton* button=buttons[i];button.image=[NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:nil];button.title=@"";[button.widthAnchor constraintEqualToConstant:28].active=YES;}
    NSStackView* header=[NSStackView stackViewWithViews:buttons];header.spacing=8;header.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:header];
    _chatSearch=[NSSearchField new];SPDFConfigurePanelSearchField(_chatSearch);_chatSearch.placeholderString=@"Search this chat";
    _chatSearch.toolTip=@"Search this chat · Return: next match · Shift-Return: previous match";
    _chatSearch.accessibilityLabel=_chatSearch.placeholderString;_chatSearch.delegate=self;_chatSearch.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:_chatSearch];
    [NSLayoutConstraint activateConstraints:@[[_chatSearch.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_chatSearch.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],[_chatSearch.topAnchor constraintEqualToAnchor:self.topAnchor constant:44],
        [_chatSearch.heightAnchor constraintEqualToConstant:30]]];
    _status=SPDFCollectionText(@"Ready for your question",13,NSFontWeightSemibold,NO);
    _status.identifier=@"chatStatus"; _status.translatesAutoresizingMaskIntoConstraints=NO; _status.maximumNumberOfLines=2; [self addSubview:_status];
    _progress=[NSProgressIndicator new]; _progress.style=NSProgressIndicatorStyleSpinning; _progress.controlSize=NSControlSizeSmall;
    _progress.displayedWhenStopped=NO; _progress.translatesAutoresizingMaskIntoConstraints=NO; [self addSubview:_progress];
    _activityDetail=SPDFCollectionText(@"Sources link to highlighted passages",12,NSFontWeightRegular,YES);
    _activityDetail.identifier=@"chatActivityDetail"; _activityDetail.maximumNumberOfLines=2;
    _activityDetail.translatesAutoresizingMaskIntoConstraints=NO; [self addSubview:_activityDetail];
    _prompt=SPDFCollectionText(@"",13,NSFontWeightMedium,NO); _prompt.identifier=@"latestUserPrompt";
    _prompt.maximumNumberOfLines=3; _prompt.selectable=YES; _prompt.translatesAutoresizingMaskIntoConstraints=NO;
    _promptHeight=[_prompt.heightAnchor constraintEqualToConstant:0]; [self addSubview:_prompt];
    _scroll=[NSScrollView new]; _scroll.translatesAutoresizingMaskIntoConstraints=NO;
    _scroll.automaticallyAdjustsContentInsets=NO; _scroll.contentInsets=NSEdgeInsetsZero;
    _scroll.drawsBackground=NO; _scroll.hasVerticalScroller=YES; _scroll.autohidesScrollers=YES;
    _messages=[NSStackView new]; _messages.orientation=NSUserInterfaceLayoutOrientationVertical;
    _messages.alignment=NSLayoutAttributeLeading; _messages.spacing=8; _messages.translatesAutoresizingMaskIntoConstraints=NO;
    NSView* doc=[SPDFChatFlippedView new]; doc.translatesAutoresizingMaskIntoConstraints=NO;
    [doc addSubview:_messages]; _scroll.documentView=doc; [self addSubview:_scroll];
    _chatFind=[[SPDFMacAIChatSearch alloc] initWithScrollView:_scroll messages:_messages];
    SPDFChatInputScrollView* input=[SPDFChatInputScrollView new]; _input=input; input.translatesAutoresizingMaskIntoConstraints=NO;
    input.borderType=NSNoBorder; input.contentInsets=NSEdgeInsetsMake(2,2,2,2); input.drawsBackground=YES; input.backgroundColor=NSColor.textBackgroundColor;
    input.wantsLayer=YES; input.layer.cornerRadius=8; input.hasVerticalScroller=YES; [input updateBorder];
    _composer=[[SPDFChatComposer alloc] initWithFrame:NSMakeRect(0,0,500,64)];
    _composer.font=[NSFont systemFontOfSize:13]; _composer.textColor=NSColor.labelColor;
    _composer.backgroundColor=NSColor.textBackgroundColor; _composer.richText=NO; _composer.allowsUndo=YES;
    _composer.textContainerInset=NSMakeSize(8,8); _composer.autoresizingMask=NSViewWidthSizable;
    _composer.textContainer.widthTracksTextView=YES; _composer.horizontallyResizable=NO;
    _composer.accessibilityLabel=@"Message your document assistant. Enter sends; Shift Enter adds a line.";
    input.documentView=_composer; [self addSubview:input];
    _send=[self button:@"Send ↵" action:@"send"]; _stop=[self button:@"Stop" action:@"stop"];
    [self addSubview:_send]; [self addSubview:_stop];
    NSTextField* inputHelp=SPDFCollectionText(@"↵ Send · ⇧↵ New line",11,NSFontWeightRegular,YES);
    _inputHelp=inputHelp; inputHelp.translatesAutoresizingMaskIntoConstraints=NO; [self addSubview:inputHelp];
    [inputHelp.leadingAnchor constraintEqualToAnchor:input.leadingAnchor].active=YES;
    [inputHelp.centerYAnchor constraintEqualToAnchor:_send.centerYAnchor].active=YES;
    [inputHelp.trailingAnchor constraintLessThanOrEqualToAnchor:_stop.leadingAnchor constant:-12].active=YES;
    __weak __typeof__(self) weakSelf=self;
    _composer.submit=^{ [weakSelf submit]; }; _composer.undoAction=^{ if (weakSelf.action) weakSelf.action(@"undo"); };
    _composer.redoAction=^{if(weakSelf.action)weakSelf.action(@"redo");};
    _composer.closeAction=^{if(weakSelf.action)weakSelf.action(@"close");};
    _issueText=SPDFCollectionText(@"",12,NSFontWeightMedium,NO); _issueText.maximumNumberOfLines=3;
    _issueText.identifier=@"chatSubmissionError";
    _recovery=[self button:@"AI settings…" action:@"settings"];
    [_recovery setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_recovery setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    _issue=[NSStackView stackViewWithViews:@[_issueText,_recovery]]; _issue.spacing=12;
    _issue.identifier=@"chatSubmissionIssue"; _issue.translatesAutoresizingMaskIntoConstraints=NO; _issue.hidden=YES;
    _issueHeight=[_issue.heightAnchor constraintEqualToConstant:0]; [self addSubview:_issue];
    _inputHeight=[input.heightAnchor constraintEqualToConstant:68];
    _stopTrailing=[_stop.trailingAnchor constraintEqualToAnchor:_send.leadingAnchor constant:-8];
    _stopHistoryTrailing=[_stop.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [header.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [header.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],
        [_status.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [_status.trailingAnchor constraintEqualToAnchor:_progress.leadingAnchor constant:-8],
        [_status.topAnchor constraintEqualToAnchor:_chatSearch.bottomAnchor constant:12],
        [_progress.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_progress.centerYAnchor constraintEqualToAnchor:_status.centerYAnchor],
        [_progress.widthAnchor constraintEqualToConstant:16], [_progress.heightAnchor constraintEqualToConstant:16],
        [_activityDetail.leadingAnchor constraintEqualToAnchor:_status.leadingAnchor],
        [_activityDetail.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_activityDetail.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:4],
        [_prompt.topAnchor constraintEqualToAnchor:_activityDetail.bottomAnchor constant:10],
        [_prompt.leadingAnchor constraintEqualToAnchor:_status.leadingAnchor],
        [_prompt.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16], _promptHeight,
        [_scroll.topAnchor constraintEqualToAnchor:_prompt.bottomAnchor constant:8],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_scroll.bottomAnchor constraintEqualToAnchor:_issue.topAnchor constant:-8],
        [_issue.leadingAnchor constraintEqualToAnchor:input.leadingAnchor],
        [_issue.trailingAnchor constraintEqualToAnchor:input.trailingAnchor],
        [_issue.bottomAnchor constraintEqualToAnchor:input.topAnchor constant:-4], _issueHeight,
        [doc.widthAnchor constraintEqualToAnchor:_scroll.contentView.widthAnchor],
        [_messages.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor],
        [_messages.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-8],
        [_messages.topAnchor constraintEqualToAnchor:doc.topAnchor constant:10],
        [_messages.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-12],
        [input.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [input.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        _inputHeight,
        [input.bottomAnchor constraintEqualToAnchor:_send.topAnchor constant:-8],
        [_send.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_send.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        _stopTrailing,
        [_stop.centerYAnchor constraintEqualToAnchor:_send.centerYAnchor]
    ]];
    return self;
}
- (void)controlTextDidChange:(NSNotification*)note { (void)note; [self setChatSearchQuery:_chatSearch.stringValue]; }
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)command {
    if (control!=_chatSearch || textView.hasMarkedText || (command!=@selector(insertNewline:) && command!=@selector(insertLineBreak:) && command!=@selector(insertNewlineIgnoringFieldEditor:))) return NO;
    [_chatFind moveBy:(NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift) ? -1 : 1]; return YES;
}
- (void)submit {
    NSString* text=[_composer.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || !_send.enabled) return;
    if (self.sendText && self.sendText(text)) _composer.string=@"";
}
- (void)clicked:(NSButton*)sender {
    if ([sender.identifier isEqual:@"send"]) [self submit];
    else if ([sender.identifier isEqual:@"older"]) {
        NSPoint origin=_scroll.contentView.bounds.origin; CGFloat height=NSHeight(_scroll.documentView.bounds); _visibleLimit+=40; _displayedMessages=nil;
        _preserveScroll=YES; [self displaySession:_displayedSession]; _preserveScroll=NO; [self layoutSubtreeIfNeeded];
        origin.y+=NSHeight(_scroll.documentView.bounds)-height;
        [_scroll.contentView scrollToPoint:origin]; [_scroll reflectScrolledClipView:_scroll.contentView];
    } else if ([sender.identifier isEqual:@"current"]) {
        if(self.action) self.action(@"current");
    } else if ([sender.identifier hasPrefix:@"citation:"]) {
        NSURL* URL=[NSURL URLWithString:[sender.identifier substringFromIndex:9]];
        if (self.openLink && SPDFMacAIChatLinkAllowed(URL)) self.openLink(URL);
    } else if (self.action) self.action(sender.identifier);
}
- (void)clearRows { for (NSView* v in [_messages.arrangedSubviews copy]) { [_messages removeArrangedSubview:v]; [v removeFromSuperview]; } }
- (void)addText:(NSString*)text role:(NSString*)role {
    NSTextField* label=SPDFCollectionText(role,11,NSFontWeightSemibold,YES); [_messages addArrangedSubview:label];
    BOOL dark=[[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
    NSMutableAttributedString* safe=[SPDFMacAIChatMarkdown(text,MAX(100,self.bounds.size.width-68),dark) mutableCopy];
    // The document renderer terminates blocks with newlines. A chat row already
    // owns its inter-message spacing, so a final blank paragraph must not add it again.
    while(safe.length && [NSCharacterSet.newlineCharacterSet characterIsMember:[safe.string characterAtIndex:safe.length-1]])
        [safe deleteCharactersInRange:NSMakeRange(safe.length-1,1)];
    SPDFChatMessageView* view=[[SPDFChatMessageView alloc] initWithFrame:NSMakeRect(0,0,MAX(120,self.bounds.size.width-48),40)];
    view.verticallyResizable=NO; view.horizontallyResizable=NO;
    view.editable=NO; view.selectable=YES; view.drawsBackground=NO; view.delegate=self;
    view.backgroundColor=SPDFCollectionColor([role isEqual:@"You"] ? @"selected" : @"control");
    view.accessibilityLabel=role;
    view.textContainerInset=NSMakeSize(10,8); view.textContainer.lineFragmentPadding=0;
    view.textContainer.widthTracksTextView=YES; [view.textStorage setAttributedString:safe];
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    CGFloat height=ceil(NSMaxY([view.layoutManager usedRectForTextContainer:view.textContainer]));
    view.translatesAutoresizingMaskIntoConstraints=NO; [_messages addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:_messages.widthAnchor].active=YES;
    view.contentHeight=[view.heightAnchor constraintEqualToConstant:MAX(18,height)+2*view.textContainerInset.height]; view.contentHeight.active=YES;
    [_messages setCustomSpacing:16 afterView:view];
}
- (void)addPreview:(NSDictionary*)preview {
    if(![preview isKindOfClass:NSDictionary.class]) return;
    NSString* path=[preview[@"path"] isKindOfClass:NSString.class] ? preview[@"path"] : nil;
    NSString* caption=[preview[@"caption"] isKindOfClass:NSString.class] ? preview[@"caption"] : @"Document page";
    NSString* root=SPDFMacAIChatStore.defaultDirectory.path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    NSString* resolved=path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    if(![resolved hasPrefix:[root stringByAppendingString:@"/"]] || ![resolved.pathExtension.lowercaseString isEqual:@"png"]) path=nil;
    NSDictionary* attributes=path ? [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] : nil;
    NSImage* image=[attributes fileSize]<=8*1024*1024 && [attributes fileSize]>0 ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
    if(!image || image.size.width<=0 || image.size.height<=0) {
        [self addText:@"This page preview is no longer available. Ask to show the page again." role:caption]; return;
    }
    NSTextField* label=SPDFCollectionText(caption,11,NSFontWeightSemibold,YES); [_messages addArrangedSubview:label];
    NSImageView* view=[NSImageView new]; view.image=image; view.imageScaling=NSImageScaleProportionallyUpOrDown;
    view.accessibilityLabel=caption; view.translatesAutoresizingMaskIntoConstraints=NO; [_messages addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:_messages.widthAnchor].active=YES;
    [view.heightAnchor constraintEqualToConstant:MIN(280,280*image.size.height/image.size.width)].active=YES;
    NSDictionary* citation=preview[@"citation"];
    if([citation isKindOfClass:NSDictionary.class]) {
        NSMutableArray* items=[NSMutableArray array];
        for(NSString* key in @[@"path",@"page",@"revision",@"layoutIdentity"]) if(citation[key])
            [items addObject:[NSURLQueryItem queryItemWithName:key value:[citation[key] description]]];
        NSURLComponents* URL=[NSURLComponents new]; URL.scheme=@"spdf-ai"; URL.host=@"document"; URL.queryItems=items;
        NSButton* open=[self button:@"Open this page" action:[@"citation:" stringByAppendingString:URL.string]];
        [_messages addArrangedSubview:open]; [_messages setCustomSpacing:20 afterView:open];
    }
}
- (BOOL)textView:(NSTextView*)textView clickedOnLink:(id)link atIndex:(NSUInteger)index {
    (void)textView; (void)index; NSURL* URL=[link isKindOfClass:NSURL.class] ? link : [NSURL URLWithString:[link description]];
    if (self.openLink && SPDFMacAIChatLinkAllowed(URL)) self.openLink(URL); return YES;
}
- (void)showSubmissionError:(NSString*)message { [self showSubmissionError:message recoveryAction:@"settings"]; }
- (void)showSubmissionError:(NSString*)message recoveryAction:(NSString*)action {
    _submissionError=[message copy]; _issueText.stringValue=message ?: @"";
    _recovery.identifier=action ?: @"settings";
    _recovery.title=[action isEqual:@"authorize"] ? @"Authorize & send…" : @"AI settings…";
    _recovery.accessibilityLabel=_recovery.title; _recovery.toolTip=_recovery.title;
    [_recovery invalidateIntrinsicContentSize]; [self refreshActivityFromSession:_displayedSession];
    if(message.length)NSAccessibilityPostNotification(_issueText,NSAccessibilityValueChangedNotification);
}
- (void)refreshActivityFromSession:(SPDFMacAIChatSession*)session {
    _displayedSession=session; _running=session.running;
    BOOL issueVisible=!_history && _submissionError.length>0;
    _issue.hidden=!issueVisible; _issueHeight.constant=issueVisible ? 60 : 0;
    NSString* fallback=_history ? @"Chats are saved on this Mac" : @"Sources link to highlighted passages";
    SPDFMacAIChatActivityState state=session.activityState;
    NSString* title=_history ? @"Your chats" : @"Ready for your question";
    if(state==SPDFMacAIChatActivityThinking) title=@"Thinking…";
    else if(state==SPDFMacAIChatActivityWorking) title=@"Working on your documents";
    else if(state==SPDFMacAIChatActivityCompleted) title=@"Complete · Ready for your reply";
    else if(state==SPDFMacAIChatActivityError) title=@"Error · Review the details";
    else if(state==SPDFMacAIChatActivityPaused) title=@"Paused · Ready to continue";
    else if(state==SPDFMacAIChatActivityStopped) title=@"Stopped · Ready for your next message";
    _status.stringValue=issueVisible ? @"Message not sent" : title;
    _activityDetail.stringValue=issueVisible ? _submissionError : session.activityDetail.length ? session.activityDetail : fallback;
    if(_chatSearch.stringValue.length && !issueVisible && !session.running) {
        NSUInteger matches=0;
        for(NSDictionary* message in session.chat[@"messages"]) {
            NSString* role=message[@"role"], *content=message[@"content"];
            if(([role isEqual:@"user"] || [role isEqual:@"assistant"]) && [content isKindOfClass:NSString.class] &&
               [content rangeOfString:_chatSearch.stringValue options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound) matches++;
        }
        _activityDetail.stringValue=matches ? [NSString stringWithFormat:@"%lu matching message%@",(unsigned long)matches,matches==1 ? @"" : @"s"] : @"No matches in this chat";
    }
    _activityDetail.toolTip=_activityDetail.stringValue;
    if(session.running) [_progress startAnimation:nil]; else [_progress stopAnimation:nil];
    NSString* latest=@"";
    for(NSDictionary* message in [session.chat[@"messages"] reverseObjectEnumerator])
        if([message[@"role"] isEqual:@"user"] && [message[@"content"] isKindOfClass:NSString.class]) { latest=message[@"content"]; break; }
    _prompt.hidden=_history || !latest.length || _chatSearch.stringValue.length;
    _prompt.stringValue=latest.length ? [@"You: " stringByAppendingString:latest] : @"";
    CGFloat promptHeight=[_prompt.stringValue boundingRectWithSize:NSMakeSize(MAX(240,self.bounds.size.width-36),CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:_prompt.font}].size.height;
    _promptHeight.constant=_prompt.hidden ? 0 : MIN(50,MAX(18,ceil(promptHeight)));
    _prompt.toolTip=latest; _prompt.accessibilityLabel=_prompt.stringValue;
    _status.accessibilityLabel=_status.stringValue;
    _send.enabled=!session.running && !_history; _stop.enabled=session.running; _composer.editable=!_history;
    _input.hidden=_history; _send.hidden=_history; _inputHeight.constant=_history ? 0 : 68;
    _stopTrailing.active=NO; _stopHistoryTrailing.active=NO;
    (_history ? _stopHistoryTrailing : _stopTrailing).active=YES;
    _inputHelp.stringValue=_history ? @"Select a chat above, or start a new one." : @"↵ Send · ⇧↵ New line";
    _redo.enabled=[session respondsToSelector:@selector(canRedo)] && session.canRedo && !session.running;
    _undo.enabled=!session.running && [session respondsToSelector:@selector(canUndo)] && [[session valueForKey:@"canUndo"] boolValue];
    _status.textColor=NSColor.labelColor;
    NSAccessibilityPostNotification(_status,NSAccessibilityValueChangedNotification);
}
- (void)scrollToNewest {
    if (_chatSearch.stringValue.length) return;
    // Rebuilt rich rows change document height. Resolve their layout before
    // clamping the scroll origin, otherwise the first label can be half hidden.
    [self layoutSubtreeIfNeeded]; [_scroll.documentView layoutSubtreeIfNeeded];
    [_scroll.contentView scrollToPoint:NSMakePoint(0,MAX(0,NSHeight(_scroll.documentView.bounds)-NSHeight(_scroll.contentView.bounds)))]; [_scroll reflectScrolledClipView:_scroll.contentView];
}
- (void)displaySession:(SPDFMacAIChatSession*)session {
    NSPoint previousOrigin=_scroll.contentView.bounds.origin;
    BOOL differentChat=![_chatID isEqual:session.chat[@"id"]];
    BOOL followBottom=differentChat || !_displayedMessages || NSMaxY(_scroll.contentView.bounds)>=NSHeight(_scroll.documentView.bounds)-24;
    if(differentChat) { _visibleLimit=40; _submissionError=nil; _chatSearch.stringValue=@""; }
    [self refreshActivityFromSession:session];
    NSArray* messages=session.chat[@"messages"];
    if(messages.count>_displayedMessages.count && [messages.lastObject[@"role"] isEqual:@"user"])followBottom=YES;
    if(!differentChat && _displayedMessages && !followBottom)
        for(NSUInteger i=_displayedMessages.count;i<messages.count;i++) {
            NSDictionary* item=messages[i];NSString* role=item[@"role"];
            if(([role isEqual:@"preview"] && [item[@"local"] boolValue]) ||
                ([@[@"user",@"assistant"] containsObject:role] && [item[@"content"] isKindOfClass:NSString.class] && [item[@"content"] length]))_visibleLimit++;
        }
    if (!_history && [_chatID isEqual:session.chat[@"id"]] && [_displayedMessages isEqual:messages]) return;
    _history=NO; [self refreshActivityFromSession:session]; _chatID=session.chat[@"id"];
    _displayedMessages=[[NSArray alloc] initWithArray:messages ?: @[] copyItems:YES]; [self clearRows];
    if (!messages.count) {
        NSTextField* empty=SPDFCollectionText(@"Ask about this document, find an answer across groups, or organize your tabs.",13,NSFontWeightRegular,YES);
        empty.maximumNumberOfLines=0; empty.identifier=@"chatEmptyState";
        empty.translatesAutoresizingMaskIntoConstraints=NO; [_messages addArrangedSubview:empty];
        [empty.widthAnchor constraintEqualToAnchor:_messages.widthAnchor].active=YES;
    } else {
        NSMutableArray* visibleMessages=[NSMutableArray array]; NSString* query=_chatSearch.stringValue;
        for(NSDictionary* message in messages) {
            if([message[@"role"] isEqual:@"preview"] && [message[@"local"] boolValue] && !query.length) {
                [visibleMessages addObject:message];continue;
            }
            if(![@[@"user",@"assistant"] containsObject:message[@"role"]])continue;
            NSString* content=message[@"content"];if(![content isKindOfClass:NSString.class] || !content.length)continue;
            if(query.length && [content rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location==NSNotFound)continue;
            [visibleMessages addObject:message];
        }
        NSUInteger first=!query.length && visibleMessages.count>_visibleLimit ? visibleMessages.count-_visibleLimit : 0;
        if(first)[_messages addArrangedSubview:[self button:@"Show older messages" action:@"older"]];
        for(NSUInteger i=first;i<visibleMessages.count;i++) {
            NSDictionary* message=visibleMessages[i];
            if([message[@"role"] isEqual:@"preview"])[self addPreview:message[@"preview"]];
            else [self addText:message[@"content"] role:[message[@"role"] isEqual:@"user"] ? @"You" : @"Assistant"];
        }
    }
    [_chatFind updateQuery:_chatSearch.stringValue];
    if (_chatSearch.stringValue.length) return;
    if(!_preserveScroll && followBottom) {
        [self scrollToNewest];
        dispatch_async(dispatch_get_main_queue(), ^{ [self scrollToNewest]; });
    } else if(!_preserveScroll) {
        [self layoutSubtreeIfNeeded];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self layoutSubtreeIfNeeded];
            if (self->_chatSearch.stringValue.length) return;
            [self->_scroll.contentView scrollToPoint:previousOrigin];
            [self->_scroll reflectScrolledClipView:self->_scroll.contentView];
        });
    }
}
- (void)displayChats:(NSArray<NSDictionary*>*)chats {
    [_chatFind updateQuery:@""];
    if(self.window.firstResponder==_composer) [self.window makeFirstResponder:nil];
    _history=YES; _send.enabled=NO; _stop.enabled=_running; _composer.editable=NO; [self clearRows]; _status.stringValue=@"Chats are saved on this Mac";
    if(_displayedSession) [self refreshActivityFromSession:_displayedSession];
    [_messages addArrangedSubview:[self button:@"Return to current chat" action:@"current"]];
    NSButton* deleteAll=[self button:@"Delete all chats…" action:@"deleteAll"]; deleteAll.enabled=chats.count>0;
    [_messages addArrangedSubview:deleteAll];
    if (!chats.count) [self addText:@"No conversations yet. Start a new chat to ask about your documents." role:@"Chats"];
    for (NSDictionary* chat in chats) {
        NSButton* open=[self button:chat[@"title"] action:[@"load:" stringByAppendingString:chat[@"id"]]];
        open.lineBreakMode=NSLineBreakByTruncatingTail; open.alignment=NSTextAlignmentLeft;
        NSButton* remove=[self button:@"Delete" action:[@"delete:" stringByAppendingString:chat[@"id"]]];
        NSStackView* row=[NSStackView stackViewWithViews:@[open,remove]]; row.spacing=8; [_messages addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:_messages.widthAnchor].active=YES;
        [open.widthAnchor constraintEqualToAnchor:row.widthAnchor constant:-76].active=YES;
    }
    [self scrollToNewest];
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollToNewest]; });
}
@end
