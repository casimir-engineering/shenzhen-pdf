#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Keeps right- and middle-button hand panning independent from the Markdown
// canvas' left-button text-selection state.
@interface SPDFMacMarkdownPanController : NSObject
@property(nonatomic, readonly, getter=isPanning) BOOL panning;
@property(nonatomic, readonly) BOOL moved;
- (instancetype)initWithDocumentView:(NSView*)documentView NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)beginAtWindowPoint:(NSPoint)windowPoint timestamp:(NSTimeInterval)timestamp;
- (void)continueAtWindowPoint:(NSPoint)windowPoint timestamp:(NSTimeInterval)timestamp;
- (void)end;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
