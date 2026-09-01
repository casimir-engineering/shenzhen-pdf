#import "SPDFMacTranslationEnablement.h"

#import "SPDFMacMarkdownDelegatePrivate.h"

// Defined in ShenzhenPDFMac.mm.
@interface ShenzhenMacDelegate (SPDFMacTranslationEnablementPrivate)
- (NSString*)trimmedSelectedTextForCommand;
@end

@implementation ShenzhenMacDelegate (SPDFMacTranslationEnablement)

// One description of the tab for every Translate entry point (toolbar button,
// File menu, overflow menu, context menu). See SPDFMacTranslationPolicy.h for
// what each entry point does with it — in short, selection translation works
// anywhere there is a selection (Markdown included), whole-document
// translation stays on the PDF render path.
- (spdf_translation_context)translationContext {
    spdf_translation_context context = {};
    context.markdownActive = [self isMarkdownActive];
    context.pdfDocumentOpen = _doc != NULL;
    context.hasSelection = [self trimmedSelectedTextForCommand].length > 0;
    context.translationRunning = _translationRunning;
    context.translationInstallRunning = _translationInstallRunning;
    return context;
}

- (void)updateTranslateCommandEnablement {
    _translateButton.enabled = spdf_translation_command_enabled([self translationContext]);
}

- (BOOL)beginTranslateCommandForSender:(id)sender {
    spdf_translation_context context = [self translationContext];
    if (spdf_translation_selection_enabled(context)) {
        [self showSelectionTranslationPanel:sender];
        return NO;
    }
    // Whole-document translation rewrites a rendered PDF's own lines in place,
    // so it has nothing to write into on a Markdown tab. Say that plainly
    // instead of leaving the command inert.
    if (spdf_translation_whole_document_available(context) && _path.length) return YES;
    if (context.markdownActive) {
        [self showError:@"Translate a selection"
                 detail:@"Whole-document translation writes translated lines back into a PDF's own pages. "
                        @"For a Markdown document, select the text you want and translate that."];
        return NO;
    }
    NSBeep();
    return NO;
}

@end
