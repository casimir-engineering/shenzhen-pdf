#import "SPDFMarkdownTestSupport.h"

#import "../../markdown/SPDFMarkdownHighlighter.h"

static void SPDFExpectNoOverlap(NSArray<SPDFMarkdownSyntaxToken*>* tokens, NSString* language) {
    for (NSUInteger i = 1; i < tokens.count; ++i)
        SPDFExpect(NSIntersectionRange(tokens[i - 1].range, tokens[i].range).length == 0,
                   [language stringByAppendingString:@" tokens never overlap"]);
}

static SPDFMarkdownSyntaxToken* SPDFTokenCovering(NSArray<SPDFMarkdownSyntaxToken*>* tokens, NSRange range) {
    for (SPDFMarkdownSyntaxToken* token in tokens) {
        if (token.range.location <= range.location && NSMaxRange(token.range) >= NSMaxRange(range)) return token;
    }
    return nil;
}

int main(void) {
    @autoreleasepool {
        SPDFMarkdownLanguageCatalog* catalog = SPDFMarkdownLanguageCatalog.sharedCatalog;
        SPDFExpect(catalog.languages.count == 5, @"only fully highlighted languages are advertised");
        SPDFExpect([[catalog languageForFenceIdentifier:@"  JS extra"].identifier isEqualToString:@"javascript"],
                   @"aliases and fence info suffixes resolve");
        SPDFExpect([catalog languagesMatchingQuery:@"script"].count == 1, @"language search matches display names");
        SPDFExpect([catalog languageForFenceIdentifier:@"made-up"] == nil, @"unknown language remains unknown");

        SPDFMarkdownHighlighter* highlighter = [SPDFMarkdownHighlighter new];
        NSDictionary* samples = @{
            @"swift": @"let value = 42 // swift comment",
            @"python": @"def value():\n    # python comment\n    return 42",
            @"javascript": @"const value = 42; // js comment",
            @"json": @"{\"value\": 42, \"ok\": true}",
            @"markdown": @"## Heading\n**strong** and [link](target)",
        };
        for (SPDFMarkdownLanguage* language in catalog.languages) {
            NSArray* tokens = [highlighter tokensForCode:samples[language.identifier] language:language];
            SPDFExpect(tokens.count >= 2, [language.displayName stringByAppendingString:@" has a dedicated lexer"]);
            SPDFExpectNoOverlap(tokens, language.displayName);
        }
        NSArray<SPDFMarkdownSyntaxToken*>* pythonTokens =
            [highlighter tokensForCode:@"# comment\nvalue = 1"
                              language:[catalog languageForFenceIdentifier:@"python"]];
        NSArray<SPDFMarkdownSyntaxToken*>* jsTokens =
            [highlighter tokensForCode:@"# not-a-js-comment\nvalue = 1"
                              language:[catalog languageForFenceIdentifier:@"javascript"]];
        SPDFExpect(pythonTokens.firstObject.kind == SPDFMarkdownSyntaxTokenComment,
                   @"Python recognizes hash comments");
        SPDFExpect(jsTokens.firstObject.kind != SPDFMarkdownSyntaxTokenComment,
                   @"JavaScript does not borrow Python comment syntax");

        NSDictionary* stringCases = @{
            @"javascript": @"const url = \"https://example.com\";",
            @"swift": @"let url = \"https://example.com\"",
            @"python": @"value = '# not a comment'",
        };
        for (NSString* identifier in stringCases) {
            NSString* source = stringCases[identifier];
            NSRange quote = [source rangeOfString:identifier.length == 6 ? @"'# not a comment'" : @"\"https://example.com\""];
            NSArray* tokens = [highlighter tokensForCode:source language:[catalog languageForFenceIdentifier:identifier]];
            SPDFMarkdownSyntaxToken* token = SPDFTokenCovering(tokens, quote);
            SPDFExpect(token.kind == SPDFMarkdownSyntaxTokenString,
                       [identifier stringByAppendingString:@" keeps comment markers inside strings"]);
        }
        NSString* JSONC = @"{\"a\": 1 // comment\n}";
        NSArray* JSONCTokens = [highlighter tokensForCode:JSONC language:[catalog languageForFenceIdentifier:@"jsonc"]];
        SPDFMarkdownSyntaxToken* JSONCComment = SPDFTokenCovering(JSONCTokens, [JSONC rangeOfString:@"// comment"]);
        SPDFExpect(JSONCComment.kind == SPDFMarkdownSyntaxTokenComment,
                   @"the advertised jsonc alias highlights comments without corrupting strings");
        NSString* arithmetic = @"let value = 1-2";
        NSArray* arithmeticTokens =
            [highlighter tokensForCode:arithmetic language:[catalog languageForFenceIdentifier:@"swift"]];
        NSRange minus = [arithmetic rangeOfString:@"-"];
        BOOL operatorCaptured = NO;
        for (SPDFMarkdownSyntaxToken* token in arithmeticTokens) {
            if (NSLocationInRange(minus.location, token.range)) operatorCaptured = YES;
        }
        SPDFExpect(!operatorCaptured, @"numeric tokens do not swallow arithmetic operators");

        SPDFMarkdownLanguagePickerModel* picker = [SPDFMarkdownLanguagePickerModel new];
        picker.query = @"s";
        SPDFExpect(picker.filteredLanguages.count > 1 && picker.selectedIndex == 0,
                   @"query filters and selects first row");
        [picker moveSelectionBy:1];
        SPDFExpect(picker.selectedIndex == 1, @"arrow navigation advances one row");
        [picker moveSelectionByPage:1 visibleRowCount:5];
        [picker moveSelectionBy:1];
        SPDFExpect(picker.selectedIndex == (NSInteger)picker.filteredLanguages.count - 1,
                   @"navigation clamps at last row");
        picker.query = @"no such language";
        SPDFExpect(picker.selectedLanguage == nil && picker.selectedIndex == -1,
                   @"empty result has no selection");
    }
    return SPDFFinishTests(@"SPDFMarkdownLanguageTests");
}
