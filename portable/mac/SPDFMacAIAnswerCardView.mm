#import "SPDFMacAIAnswerCardView.h"
#import "SPDFMacGroupActionButton.h"
@interface SPDFAnswerEvidenceButton : SPDFGroupActionButton @end
@implementation SPDFAnswerEvidenceButton
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    NSBezierPath* shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:6 yRadius:6];
    [[NSColor colorWithSRGBRed:.12 green:.29 blue:.24 alpha:self.highlighted ? .23 : .10] setFill]; [shape fill];
    [[NSColor colorWithSRGBRed:.12 green:.29 blue:.24 alpha:.22] setStroke]; [shape stroke];
    NSDictionary* attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName:[NSColor colorWithSRGBRed:.10 green:.24 blue:.19 alpha:1]};
    NSSize size=[self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint(round((NSWidth(self.bounds)-size.width)/2),round((NSHeight(self.bounds)-size.height)/2)) withAttributes:attributes];
    if (self.window.firstResponder==self) {
        [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill]; [NSGraphicsContext restoreGraphicsState];
    }
}
@end
@implementation SPDFMacAIAnswerCardView {
    NSButton* _evidence; NSLayoutConstraint* _height; BOOL _measurementPending;
    void (^_openLink)(NSURL*); NSURL* _citation;
}
- (instancetype)initWithCard:(NSDictionary*)card width:(CGFloat)width openLink:(void (^)(NSURL*))openLink {
    if (!(self=[super initWithFrame:NSMakeRect(0,0,MAX(180,width),150)])) return nil;
    self.identifier=@"answerCard"; self.editable=NO; self.selectable=YES; self.drawsBackground=NO;
    self.verticallyResizable=NO; self.horizontallyResizable=NO;
    self.textContainerInset=NSMakeSize(16,14); self.textContainer.lineFragmentPadding=0;
    self.textContainer.widthTracksTextView=YES;
    NSColor* ink=[NSColor colorWithSRGBRed:.10 green:.24 blue:.19 alpha:1];
    NSMutableParagraphStyle* labelStyle=[NSMutableParagraphStyle new]; labelStyle.paragraphSpacing=5;
    NSMutableAttributedString* text=[[NSMutableAttributedString alloc] initWithString:[card[@"label"] stringByAppendingString:@"\n"]
        attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium],NSForegroundColorAttributeName:ink,NSParagraphStyleAttributeName:labelStyle}];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:card[@"value"]
        attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:32 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:ink}]];
    [self.textStorage setAttributedString:text];
    self.accessibilityLabel=[NSString stringWithFormat:@"Answer: %@, %@",card[@"label"],card[@"value"]];
    _citation=[NSURL URLWithString:card[@"citation"]]; _openLink=[openLink copy];
    _evidence=[[SPDFAnswerEvidenceButton alloc] initWithFrame:NSMakeRect(16,106,120,28)];
    _evidence.identifier=@"answerEvidence"; _evidence.title=@"View evidence"; _evidence.bordered=NO;
    _evidence.target=self; _evidence.action=@selector(openEvidence:); _evidence.accessibilityLabel=@"View evidence for this answer";
    _evidence.toolTip=@"Open the cited document passage"; [self addSubview:_evidence];
    self.translatesAutoresizingMaskIntoConstraints=NO;
    _height=[self.heightAnchor constraintEqualToConstant:150]; _height.active=YES;
    [self measure]; return self;
}
- (void)openEvidence:(id)sender { (void)sender; if (_openLink && _citation) _openLink(_citation); }
- (void)drawRect:(NSRect)dirty {
    BOOL dark=[[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
    [(dark ? [NSColor colorWithSRGBRed:.72 green:.85 blue:.79 alpha:1] :
        [NSColor colorWithSRGBRed:.86 green:.94 blue:.89 alpha:1]) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10] fill];
    [super drawRect:dirty];
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay=YES; }
- (void)measure {
    CGFloat width=NSWidth(self.bounds)-32; if (width<=0 || !_height) return;
    self.textContainer.containerSize=NSMakeSize(width,CGFLOAT_MAX);
    [self.layoutManager ensureLayoutForTextContainer:self.textContainer];
    CGFloat height=MAX(138,ceil(NSMaxY([self.layoutManager usedRectForTextContainer:self.textContainer]))+14+12+28+14);
    if (fabs(_height.constant-height)>.5) _height.constant=height;
}
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size]; _evidence.frame=NSMakeRect(16,size.height-42,120,28);
    if (_measurementPending || !_height || self.hiddenOrHasHiddenAncestor) return;
    _measurementPending=YES;
    __weak SPDFMacAIAnswerCardView* weakSelf=self;
    dispatch_async(dispatch_get_main_queue(),^{ SPDFMacAIAnswerCardView* view=weakSelf;
        if (!view) return; view->_measurementPending=NO; [view measure];
    });
}
@end
