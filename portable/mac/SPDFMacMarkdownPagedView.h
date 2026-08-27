#pragma once

#import "SPDFMacUIHelpers.h"

@class SPDFMarkdownPaginationPlan;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPDFMacMarkdownPageFitMode) {
    SPDFMacMarkdownPageFitCustom = 0,
    SPDFMacMarkdownPageFitActual = 1,
    SPDFMacMarkdownPageFitWidth = 2,
    SPDFMacMarkdownPageFitHeight = 3,
    SPDFMacMarkdownPageFitPage = 4,
};

@interface SPDFMacMarkdownPagedView : SPDFScrollView
@property(nonatomic, readonly) NSUInteger pageCount;
@property(nonatomic, readonly) NSInteger currentPageIndex;
@property(nonatomic, readonly) NSUInteger visibleAttributedLocation;
@property(nonatomic, readonly, copy) NSArray<NSValue*>* documentPageRects;
@property(nonatomic, readonly) NSSize documentCanvasSize;
@property(nonatomic) SPDFMacMarkdownPageFitMode fitMode;
@property(nonatomic) BOOL presentationMode;
@property(nonatomic) NSRange selectedRange;
@property(nonatomic, readonly, copy) NSString* selectedText;
@property(nonatomic, copy) NSArray<NSValue*>* searchRanges;
@property(nonatomic, copy, nullable) void (^viewportChangedHandler)(NSInteger pageIndex, CGFloat zoom);
@property(nonatomic, copy, nullable) void (^activateDestinationHandler)(NSString* destination, BOOL wikiLink);
@property(nonatomic, copy, nullable) void (^chooseCodeLanguageHandler)(NSUInteger blockIndex);

- (instancetype)initWithPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                      attributedString:(NSAttributedString*)attributedString NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;
- (void)setZoom:(CGFloat)zoom centeredAtPoint:(NSPoint)point;
- (void)zoomByFactor:(CGFloat)factor;
- (void)applyFitMode:(SPDFMacMarkdownPageFitMode)fitMode;
- (void)goToPageAtIndex:(NSInteger)pageIndex alignTop:(BOOL)alignTop;
- (BOOL)revealRange:(NSRange)range;
- (NSUInteger)pageIndexForRange:(NSRange)range;
- (void)centerAtDocumentPoint:(NSPoint)point;
- (void)centerOnPageAtIndex:(NSInteger)pageIndex xFraction:(CGFloat)xFraction yFraction:(CGFloat)yFraction;
- (void)scrollByDocumentDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY;
- (void)forwardScrollWheelEvent:(NSEvent*)event;
- (void)magnifyByDelta:(CGFloat)delta;
- (BOOL)zoomWithScrollWheelEvent:(NSEvent*)event centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)magnifyByDelta:(CGFloat)delta centeredAtWindowPoint:(NSPoint)windowPoint;
- (void)magnifyByDelta:(CGFloat)delta centeredAtDocumentPoint:(NSPoint)documentPoint;
- (void)noteExternalScrollPositionChanged;
@end

NS_ASSUME_NONNULL_END
