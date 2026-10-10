#import "SPDFMacAIChatView.h"
#import "SPDFMacAIChatSession.h"
#import "SPDFMacCollectionStyle.h"
#import "SPDFMacAIChatMarkdown.h"
#import "SPDFMacGroupActionButton.h"
#import "SPDFMacAIChatStore.h"
@interface SPDFChatButton : SPDFGroupActionButton
@end
@implementation SPDFChatButton
- (NSSize)intrinsicContentSize { return NSMakeSize(ceil([self.title sizeWithAttributes:@{NSFontAttributeName:self.font}].width)+20,28); }
- (void)drawRect:(NSRect)dirty {
    (void)dirty; NSBezierPath* shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:5 yRadius:5];
    if(self.highlighted || [self.identifier isEqual:@"send"]) {
        [SPDFCollectionColor(self.highlighted ? @"selected" : @"control") setFill]; [shape fill];
    }
    NSMutableParagraphStyle* p=[NSMutableParagraphStyle new]; p.alignment=self.alignment; p.lineBreakMode=NSLineBreakByTruncatingTail;
    NSDictionary* a=@{NSFontAttributeName:self.font,NSForegroundColorAttributeName:SPDFCollectionColor(self.enabled ? @"text" : @"secondary"),NSParagraphStyleAttributeName:p};
    CGFloat h=[self.title sizeWithAttributes:a].height;
    [self.title drawInRect:NSMakeRect(10,floor((self.bounds.size.height-h)/2),self.bounds.size.width-20,h) withAttributes:a];
    if(self.window.firstResponder==self) { [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill]; [NSGraphicsContext restoreGraphicsState]; }
}
@end
@interface SPDFChatMessageView : NSTextView
@property(nonatomic) NSLayoutConstraint* contentHeight;
@property(nonatomic) BOOL measuring;
@end
@implementation SPDFChatMessageView
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    if(!self.contentHeight || self.measuring) return;
    self.measuring=YES;
    self.textContainer.containerSize=NSMakeSize(MAX(1,size.width),CGFLOAT_MAX);
    [self.layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0,self.string.length) actualCharacterRange:nil];
    [self.layoutManager ensureLayoutForTextContainer:self.textContainer];
    CGFloat h=MAX(24,ceil([self.layoutManager usedRectForTextContainer:self.textContainer].size.height)+8);
    if(fabs(h-self.contentHeight.constant)>.5) { self.contentHeight.constant=h; self.superview.needsLayout=YES; }
    self.measuring=NO;
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
@end
@implementation SPDFChatComposer
- (BOOL)becomeFirstResponder { BOOL ok=[super becomeFirstResponder]; [(SPDFChatInputScrollView*)self.enclosingScrollView updateBorder]; return ok; }
- (BOOL)resignFirstResponder { BOOL ok=[super resignFirstResponder]; dispatch_async(dispatch_get_main_queue(), ^{ [(SPDFChatInputScrollView*)self.enclosingScrollView updateBorder]; }); return ok; }
- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    if(!self.string.length) [@"Ask about your documents…" drawAtPoint:NSMakePoint(13,8)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13],NSForegroundColorAttributeName:SPDFCollectionColor(@"secondary")}];
}
- (void)keyDown:(NSEvent*)event {
    if ((event.keyCode==36 || event.keyCode==76) && !(event.modifierFlags & NSEventModifierFlagShift)) {
        if (self.submit) self.submit(); return;
    }
    if ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqual:@"z"] && !self.string.length) {
        if (self.undoAction) self.undoAction(); return;
    }
    [super keyDown:event];
}
@end
@interface SPDFChatFlippedView : NSView @end
@implementation SPDFChatFlippedView
- (BOOL)isFlipped { return YES; }
@end
@interface SPDFMacAIChatView () <NSTextViewDelegate>
@end
@implementation SPDFMacAIChatView {
    SPDFChatComposer* _composer; NSTextField* _status; NSTextField* _inputHelp; NSScrollView* _scroll; NSScrollView* _input; NSStackView* _messages;
    NSLayoutConstraint* _inputHeight; NSLayoutConstraint* _stopTrailing; NSLayoutConstraint* _stopHistoryTrailing;
    NSString* _submissionError; NSButton* _send; NSButton* _stop; NSButton* _undo; NSUInteger _visibleLimit; NSUInteger _messageCount; NSString* _chatID; BOOL _history; BOOL _running; BOOL _preserveScroll; __weak SPDFMacAIChatSession* _displayedSession;
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty { (void)dirty; [SPDFCollectionColor(@"window") setFill]; NSRectFill(self.bounds); }
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES;
    if(_displayedSession && !_history) { _chatID=nil; [self displaySession:_displayedSession]; }
}
- (void)setFrameSize:(NSSize)size {
    BOOL top=_scroll && _scroll.contentView.bounds.origin.y<20;
    BOOL widthChanged=fabs(size.width-self.bounds.size.width)>.5;
    [super setFrameSize:size];
    if(top && widthChanged) dispatch_async(dispatch_get_main_queue(), ^{ [self scrollToNewest]; });
}
- (NSTextView*)composer { return _composer; }
- (NSButton*)button:(NSString*)title action:(NSString*)action {
    SPDFChatButton* b=[[SPDFChatButton alloc] initWithFrame:NSZeroRect];
    b.title=title ?: @"Untitled chat"; b.font=[NSFont systemFontOfSize:13]; b.bordered=NO;
    b.alignment=NSTextAlignmentCenter; b.target=self; b.action=@selector(clicked:); b.identifier=action;
    b.accessibilityLabel=title; b.toolTip=title; b.translatesAutoresizingMaskIntoConstraints=NO;
    [b.heightAnchor constraintEqualToConstant:28].active=YES; return b;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    _visibleLimit=40; _undo=[self button:@"Undo action" action:@"undo"]; _undo.enabled=NO;
    NSStackView* header=[NSStackView stackViewWithViews:@[[self button:@"New chat" action:@"new"],
        [self button:@"Chats" action:@"history"],_undo,
        [self button:@"Settings" action:@"settings"],[self button:@"Close · Esc" action:@"close"]]];
    header.spacing=8; header.translatesAutoresizingMaskIntoConstraints=NO; [self addSubview:header];
    _status=SPDFCollectionText(@"Ask about your documents",11,NSFontWeightRegular,YES);
    _status.identifier=@"chatStatus"; _status.translatesAutoresizingMaskIntoConstraints=NO; _status.maximumNumberOfLines=2; [self addSubview:_status];
    _scroll=[NSScrollView new]; _scroll.translatesAutoresizingMaskIntoConstraints=NO;
    _scroll.automaticallyAdjustsContentInsets=NO; _scroll.contentInsets=NSEdgeInsetsZero;
    _scroll.drawsBackground=NO; _scroll.hasVerticalScroller=YES; _scroll.autohidesScrollers=YES;
    _messages=[NSStackView new]; _messages.orientation=NSUserInterfaceLayoutOrientationVertical;
    _messages.alignment=NSLayoutAttributeLeading; _messages.spacing=8; _messages.translatesAutoresizingMaskIntoConstraints=NO;
    NSView* doc=[SPDFChatFlippedView new]; doc.translatesAutoresizingMaskIntoConstraints=NO;
    [doc addSubview:_messages]; _scroll.documentView=doc; [self addSubview:_scroll];
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
    NSTextField* inputHelp=SPDFCollectionText(@"Return sends · Shift Return adds a line",11,NSFontWeightRegular,YES);
    _inputHelp=inputHelp; inputHelp.translatesAutoresizingMaskIntoConstraints=NO; [self addSubview:inputHelp];
    [inputHelp.leadingAnchor constraintEqualToAnchor:input.leadingAnchor].active=YES;
    [inputHelp.centerYAnchor constraintEqualToAnchor:_send.centerYAnchor].active=YES;
    [inputHelp.trailingAnchor constraintLessThanOrEqualToAnchor:_stop.leadingAnchor constant:-12].active=YES;
    __weak __typeof__(self) weakSelf=self;
    _composer.submit=^{ [weakSelf submit]; }; _composer.undoAction=^{ if (weakSelf.action) weakSelf.action(@"undo"); };
    _inputHeight=[input.heightAnchor constraintEqualToConstant:68];
    _stopTrailing=[_stop.trailingAnchor constraintEqualToAnchor:_send.leadingAnchor constant:-8];
    _stopHistoryTrailing=[_stop.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [header.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [header.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],
        [_status.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [_status.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_status.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [_scroll.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:12],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_scroll.bottomAnchor constraintEqualToAnchor:input.topAnchor constant:-12],
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
- (void)submit {
    NSString* text=[_composer.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || !_send.enabled) return;
    if (self.sendText && self.sendText(text)) _composer.string=@"";
}
- (void)clicked:(NSButton*)sender {
    if ([sender.identifier isEqual:@"send"]) [self submit];
    else if ([sender.identifier isEqual:@"older"]) {
        NSPoint origin=_scroll.contentView.bounds.origin; _visibleLimit+=40; _chatID=nil;
        _preserveScroll=YES; [self displaySession:_displayedSession]; _preserveScroll=NO; [self layoutSubtreeIfNeeded];
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
    NSAttributedString* safe=SPDFMacAIChatMarkdown(text,MAX(240,self.bounds.size.width-48),dark);
    SPDFChatMessageView* view=[[SPDFChatMessageView alloc] initWithFrame:NSMakeRect(0,0,MAX(240,self.bounds.size.width-48),40)];
    view.verticallyResizable=NO; view.horizontallyResizable=NO;
    view.editable=NO; view.selectable=YES; view.drawsBackground=NO; view.delegate=self;
    view.textContainerInset=NSZeroSize; view.textContainer.lineFragmentPadding=0;
    view.textContainer.widthTracksTextView=YES; [view.textStorage setAttributedString:safe];
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    CGFloat height=ceil([view.layoutManager usedRectForTextContainer:view.textContainer].size.height)+8;
    view.translatesAutoresizingMaskIntoConstraints=NO; [_messages addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:_messages.widthAnchor].active=YES;
    view.contentHeight=[view.heightAnchor constraintEqualToConstant:MAX(24,height)]; view.contentHeight.active=YES;
    [_messages setCustomSpacing:20 afterView:view];
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
- (void)showSubmissionError:(NSString*)message {
    _submissionError=[message copy]; [self refreshActivityFromSession:_displayedSession];
}
- (void)refreshActivityFromSession:(SPDFMacAIChatSession*)session {
    _displayedSession=session; _running=session.running;
    NSString* fallback=_history ? @"Chats are saved on this Mac" : @"Answers cite your documents · newest messages first";
    _status.stringValue=!_history && _submissionError.length ? _submissionError : session.status.length ? session.status : fallback;
    _status.accessibilityLabel=_status.stringValue;
    _send.enabled=!session.running && !_history; _stop.enabled=session.running; _composer.editable=!_history;
    _input.hidden=_history; _send.hidden=_history; _inputHeight.constant=_history ? 0 : 68;
    _stopTrailing.active=NO; _stopHistoryTrailing.active=NO;
    (_history ? _stopHistoryTrailing : _stopTrailing).active=YES;
    _inputHelp.stringValue=_history ? @"Select a chat above, or start a new one." : @"Return sends · Shift Return adds a line";
    _undo.enabled=[session respondsToSelector:@selector(canUndo)] && [[session valueForKey:@"canUndo"] boolValue];
    _status.textColor=session.status.length && !session.running ? NSColor.labelColor : SPDFCollectionColor(@"secondary");
    NSAccessibilityPostNotification(_status,NSAccessibilityValueChangedNotification);
}
- (void)scrollToNewest {
    // Rebuilt rich rows change document height. Resolve their layout before
    // clamping the scroll origin, otherwise the first label can be half hidden.
    [self layoutSubtreeIfNeeded]; [_scroll.documentView layoutSubtreeIfNeeded];
    [_scroll.contentView scrollToPoint:NSZeroPoint]; [_scroll reflectScrolledClipView:_scroll.contentView];
}
- (void)displaySession:(SPDFMacAIChatSession*)session {
    BOOL differentChat=_chatID && ![_chatID isEqual:session.chat[@"id"]];
    if(differentChat) { _visibleLimit=40; _submissionError=nil; }
    [self refreshActivityFromSession:session];
    NSArray* messages=session.chat[@"messages"];
    if (!_history && [_chatID isEqual:session.chat[@"id"]] && _messageCount==messages.count) return;
    _history=NO; [self refreshActivityFromSession:session]; _chatID=session.chat[@"id"]; _messageCount=messages.count; [self clearRows];
    if (!messages.count) {
        [self addText:@"# Your documents, in conversation\nFind an answer across groups, explain a page, or organize your workspace.\n\nTry **“Find the power requirements in my open documents”** or **“Summarize this document and suggest chapters.”**\n\nOnly requested context is sent to your model. You can stop a task or undo its changes." role:@"Shenzhen PDF"];
    } else {
        NSUInteger visible=0; BOOL hasOlder=NO;
        for (NSDictionary* message in messages.reverseObjectEnumerator) {
            if ([message[@"role"] isEqual:@"preview"] && [message[@"local"] boolValue]) {
                if(visible>=_visibleLimit) { hasOlder=YES; break; }
                [self addPreview:message[@"preview"]]; ++visible; continue;
            }
            if (![message[@"role"] isEqual:@"user"] && ![message[@"role"] isEqual:@"assistant"]) continue;
            NSString* content=message[@"content"]; if (![content isKindOfClass:NSString.class] || !content.length) continue;
            if(visible>=_visibleLimit) { hasOlder=YES; break; }
            [self addText:content role:[message[@"role"] isEqual:@"user"] ? @"You" : @"Assistant"];
            ++visible;
        }
        if(hasOlder) [_messages addArrangedSubview:[self button:@"Show older messages" action:@"older"]];
    }
    if(!_preserveScroll) {
        [self scrollToNewest];
        dispatch_async(dispatch_get_main_queue(), ^{ [self scrollToNewest]; });
    }
}
- (void)displayChats:(NSArray<NSDictionary*>*)chats {
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
