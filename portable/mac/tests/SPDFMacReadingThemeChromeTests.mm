// Reading-theme chrome: the gutter role both frontends read and the PDF
// page's border-instead-of-shadow decision.
#import <AppKit/AppKit.h>

#import "SPDFMacDocumentView.h"
#import "markdown/SPDFMarkdownDecorations.h"

#include <assert.h>
#include <stdio.h>

static void Expect(const char* label, BOOL condition) {
    if (condition) return;
    fprintf(stderr, "FAIL %s\n", label);
    exit(1);
}

static BOOL ColorMatchesHex(NSColor* color, unsigned int hex) {
    NSColor* rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return NO;
    unsigned int red = (unsigned int)lround(rgb.redComponent * 255.0);
    unsigned int green = (unsigned int)lround(rgb.greenComponent * 255.0);
    unsigned int blue = (unsigned int)lround(rgb.blueComponent * 255.0);
    return ((red << 16) | (green << 8) | blue) == hex;
}

static CGFloat Luminance(NSColor* color) {
    NSColor* rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return -1.0;
    return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent;
}

static SPDFRenderedPage* MakePage(void) {
    SPDFRenderedPage* page = [[SPDFRenderedPage alloc] init];
    page.pageIndex = 0;
    page.pageWidth = 200.0;
    page.pageHeight = 260.0;
    return page;
}

static NSBitmapImageRep* RasterizeView(NSView* view) {
    NSBitmapImageRep* rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    assert(rep);
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}

// Samples a VIEW-SPACE point. The cached rep is backing-scaled (2x on this
// hardware), and the document view is flipped, so a row is scale * y.
static NSColor* SampleAt(NSBitmapImageRep* rep, NSView* view, CGFloat x, CGFloat y) {
    CGFloat scale = (CGFloat)rep.pixelsWide / MAX((CGFloat)1, NSWidth(view.bounds));
    NSInteger column = (NSInteger)MIN((CGFloat)rep.pixelsWide - 1, MAX((CGFloat)0, floor(x * scale)));
    NSInteger row = (NSInteger)MIN((CGFloat)rep.pixelsHigh - 1, MAX((CGFloat)0, floor(y * scale)));
    return [rep colorAtX:column y:row];
}

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;

        // --- The gutter role, per variant --------------------------------
        SPDFMarkdownTheme* light = [SPDFMarkdownTheme themeForVariant:SPDFMarkdownThemeVariantLight];
        SPDFMarkdownTheme* dark = [SPDFMarkdownTheme themeForVariant:SPDFMarkdownThemeVariantDark];
        // Light names no gutter: every surface keeps the system background it
        // already used, unchanged by the theme work.
        Expect("light gutter role is unset", light.viewportBackgroundColor == nil);
        Expect("light keeps the paper drop shadow", light.drawsPaperShadow);
        Expect("dark gutter is #121212", ColorMatchesHex(dark.viewportBackgroundColor, 0x121212));
        Expect("dark drops the paper shadow", !dark.drawsPaperShadow);
        // The whole point: the gutter must read as clearly darker than the
        // paper, or a page edge disappears into it.
        Expect("dark gutter is darker than dark paper",
               Luminance(dark.viewportBackgroundColor) < Luminance(dark.paperColor) - 0.01);
        Expect("dark paper border is #333333", ColorMatchesHex(dark.paperBorderColor, 0x333333));

        // --- The document view's page-separation seam --------------------
        SPDFDocumentView* view = [[SPDFDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 320, 380)];
        view.zoom = 1.0;
        view.backingScale = 1.0;
        view.pages = @[ MakePage() ];

        Expect("light document view defaults to the shadow", view.drawsPageShadow);
        Expect("light document view draws no page border", view.pageBorderColor == nil);
        Expect("light gutter keeps the system canvas background",
               view.viewportBackgroundColor != nil &&
                   !ColorMatchesHex(view.viewportBackgroundColor, 0x121212));

        view.themeVariant = SPDFMarkdownThemeVariantDark;
        Expect("dark document view drops the shadow", !view.drawsPageShadow);
        Expect("dark document view draws the theme page border",
               ColorMatchesHex(view.pageBorderColor, 0x333333));
        Expect("dark document view takes the theme gutter",
               ColorMatchesHex(view.viewportBackgroundColor, 0x121212));

        // --- The border actually lands on all four sides -----------------
        NSRect pageRect = [view rectForPageAtIndex:0];
        Expect("page rect is real", NSWidth(pageRect) > 10 && NSHeight(pageRect) > 10);
        NSBitmapImageRep* darkRaster = RasterizeView(view);
        struct {
            const char* label;
            NSPoint point;
        } edges[] = {
            // The stroke is inset by half a point, so its centerline — and the
            // pixel it covers at 1x and 2x alike — sits half a point inside the
            // page rect on each of the four sides.
            {"top border", NSMakePoint(NSMidX(pageRect), NSMinY(pageRect) + 0.5)},
            {"bottom border", NSMakePoint(NSMidX(pageRect), NSMaxY(pageRect) - 0.5)},
            {"left border", NSMakePoint(NSMinX(pageRect) + 0.5, NSMidY(pageRect))},
            {"right border", NSMakePoint(NSMaxX(pageRect) - 0.5, NSMidY(pageRect))},
        };
        for (size_t i = 0; i < sizeof(edges) / sizeof(edges[0]); ++i) {
            NSColor* sample = SampleAt(darkRaster, view, edges[i].point.x, edges[i].point.y);
            // #333333 on white paper: every edge must be visibly darker than
            // the sheet it frames, on all four sides.
            Expect(edges[i].label, Luminance(sample) < 0.5);
        }
        // ...and only the edge: one point in, the sheet is untouched.
        Expect("the border does not eat page content",
               Luminance(SampleAt(darkRaster, view, NSMidX(pageRect), NSMinY(pageRect) + 2.0)) > 0.9);
        NSColor* gutter = SampleAt(darkRaster, view, 2, 2);
        Expect("dark gutter is painted around the page", ColorMatchesHex(gutter, 0x121212));

        // Light keeps the sheet edge-to-edge white: no border stroke on it.
        view.themeVariant = SPDFMarkdownThemeVariantLight;
        NSBitmapImageRep* lightRaster = RasterizeView(view);
        for (size_t i = 0; i < sizeof(edges) / sizeof(edges[0]); ++i) {
            NSColor* sample = SampleAt(lightRaster, view, edges[i].point.x, edges[i].point.y);
            Expect("light page edge stays white", Luminance(sample) > 0.9);
        }

        // Presentation mode is pure black in both, with no border frame.
        view.presentationMode = YES;
        view.themeVariant = SPDFMarkdownThemeVariantDark;
        NSBitmapImageRep* presentationRaster = RasterizeView(view);
        NSRect presentationRect = [view rectForPageAtIndex:0];
        Expect("presentation gutter is black", Luminance(SampleAt(presentationRaster, view, 1, 1)) < 0.02);
        Expect("presentation draws no page border",
               Luminance(SampleAt(presentationRaster, view, NSMidX(presentationRect),
                                  NSMinY(presentationRect) + 0.5)) > 0.9);
        view.presentationMode = NO;

        printf("SPDFMacReadingThemeChromeTests passed\n");
    }
    return 0;
}
