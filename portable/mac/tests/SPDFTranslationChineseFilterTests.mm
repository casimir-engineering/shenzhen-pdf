#import <Foundation/Foundation.h>

#import "shenzhen_pdf_core.h"

static int gFailureCount = 0;

static void expect_han(NSString* label, const char* text, int expected) {
    int actual = spdf_text_contains_han(text);
    if (actual != expected) {
        fprintf(stderr, "FAIL %s: expected %d, got %d\n", label.UTF8String, expected, actual);
        ++gFailureCount;
    }
}

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        expect_han(@"NULL input", NULL, 0);
        expect_han(@"empty string", "", 0);

        expect_han(@"pure Latin", "Purely Latin caption that must be skipped", 0);
        expect_han(@"Latin with accents",
                   "Coordonn\xC3\xA9"
                   "es pr\xC3\xA9"
                   "cises \xC3\xA0 v\xC3\xA9"
                   "rifier",
                   0);
        expect_han(@"punctuation and digits only", "3.3V / 100mA (numbers & units only)", 0);
        expect_han(@"fullwidth punctuation only", "\xEF\xBC\x8C\xE3\x80\x82\xEF\xBC\x9A\xE3\x80\x81", 0);

        expect_han(@"pure Han simplified", "\xE7\xA1\xAC\xE4\xBB\xB6\xE8\xAE\xBE\xE8\xAE\xA1\xE6\x89\x8B\xE5\x86\x8C",
                   1);
        expect_han(@"pure Han traditional", "\xE7\xA1\xAC\xE9\xAB\x94\xE8\xA8\xAD\xE8\xA8\x88", 1);
        expect_han(@"mixed Han and Latin", "\xE7\x94\xB5\xE6\xBA\x90\xE7\xAE\xA1\xE7\x90\x86 Power Management", 1);
        expect_han(@"single Han among digits", "PCB:1\xC2\xB1"
                                               "0.1 \xE6\xBF\x80\xE5\x85\x89",
                   1);

        // Boundary code points of the detected ranges.
        expect_han(@"U+4E00 first unified ideograph", "\xE4\xB8\x80", 1);
        expect_han(@"U+9FFF last unified ideograph", "\xE9\xBF\xBF", 1);
        expect_han(@"U+3400 first Extension A", "\xE3\x90\x80", 1);
        expect_han(@"U+4DBF last Extension A", "\xE4\xB6\xBF", 1);
        expect_han(@"U+F900 compatibility ideograph", "\xEF\xA4\x80", 1);
        expect_han(@"U+20000 Extension B (4-byte UTF-8)", "\xF0\xA0\x80\x80", 1);

        // Neighbouring non-Han CJK scripts must not count as Chinese.
        expect_han(@"U+33FF just below Extension A", "\xE3\x8F\xBF", 0);
        expect_han(@"U+A000 just above unified ideographs", "\xEA\x80\x80", 0);
        expect_han(@"hiragana only", "\xE3\x81\xB2\xE3\x82\x89\xE3\x81\x8C\xE3\x81\xAA", 0);
        expect_han(@"katakana only", "\xE3\x82\xAB\xE3\x82\xBF\xE3\x82\xAB\xE3\x83\x8A", 0);
        expect_han(@"hangul only", "\xED\x95\x9C\xEA\xB5\xAD\xEC\x96\xB4", 0);
        expect_han(@"emoji only", "\xF0\x9F\x98\x80\xF0\x9F\x8E\x89", 0);

        // Malformed UTF-8 must be skipped without crashing or matching.
        expect_han(@"stray continuation byte", "\x80\x80 abc", 0);
        expect_han(@"truncated 3-byte sequence at end", "abc\xE7\xA1", 0);
        expect_han(@"truncated 4-byte sequence at end", "abc\xF0\xA0\x80", 0);
        expect_han(@"invalid lead byte 0xFF", "\xFF\xFE abc", 0);
        expect_han(@"Han after malformed bytes", "\x80\xE7\xA1\xAC", 1);
        expect_han(@"lone lead byte then Latin", "\xE7 hardware", 0);
    }
    if (gFailureCount > 0) return 1;
    printf("SPDFTranslationChineseFilterTests passed\n");
    return 0;
}
