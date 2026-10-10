#pragma once
#import "SPDFMacDelegatePrivate.h"
@interface ShenzhenMacDelegate (SPDFMacAIIntegration)
- (void)showAIChat:(id)sender;
- (void)showAIChats:(id)sender;
- (void)closeAIChat;
- (void)cancelAIChat;
- (BOOL)isAIChatVisible;
- (NSWindow*)aiChatWindow;
- (void)preparePaletteForSearch;
- (void)showAIChatForQuery:(NSString*)query;
@end
@interface ShenzhenMacDelegate (SPDFMacAISettingsIntegration)
- (void)showUnifiedSettings:(id)sender;
- (void)showAIConnectionSettingsWithReason:(NSString*)reason;
- (void)showUnifiedSettingsAfterFirstPaint;
@end
@interface ShenzhenMacDelegate (SPDFMacAIAnalysisIntegration)
- (void)aiDocumentDidOpen:(NSString*)path;
- (void)configureAIAnalysis:(id)settings;
- (void)configureAIAnalysisForMarkdownSession:(id)session path:(NSString*)path;
- (NSDictionary*)aiAnalysisForPath:(NSString*)path;
- (NSArray<NSDictionary*>*)aiGeneratedChapterRows;
- (void)appendAIGeneratedChaptersMatchingFilter:(NSString*)filter;
@end
