#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO=$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)
PORTABLE="$REPO/portable"
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/spdf-markdown-ui-tests.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT INT TERM

CC=$(xcrun --find clang)
CXX=$(xcrun --find clang++)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SANITIZER_FLAGS=${SPDF_MARKDOWN_SANITIZER_FLAGS:-}

# shellcheck disable=SC2086
"$CC" -isysroot "$SDKROOT" -std=c11 -O0 -g -Wall -Wextra -Werror \
    $SANITIZER_FLAGS -I"$REPO/ext/md4c" -c "$REPO/ext/md4c/md4c.c" -o "$BUILD_DIR/md4c.o"

# Vendored Gumbo HTML5 parser backing the sanitizing HTML-island whitelist.
# Third-party sources compile without -Werror.
GUMBO_OBJS=""
for GUMBO_SRC in "$REPO/ext/gumbo-parser/src"/*.c; do
    GUMBO_OBJ="$BUILD_DIR/gumbo-$(basename "$GUMBO_SRC" .c).o"
    # shellcheck disable=SC2086
    "$CC" -isysroot "$SDKROOT" -std=c99 -O0 -g $SANITIZER_FLAGS \
        -I"$REPO/ext/gumbo-parser/src" -c "$GUMBO_SRC" -o "$GUMBO_OBJ"
    GUMBO_OBJS="$GUMBO_OBJS $GUMBO_OBJ"
done

FOUNDATION_SOURCES="
$PORTABLE/mac/markdown/SPDFMarkdownModel.mm
$PORTABLE/mac/markdown/SPDFMarkdownMathTypesetter.mm
$PORTABLE/mac/markdown/SPDFMarkdownParser.mm
$PORTABLE/mac/markdown/SPDFMarkdownHTML.mm
$PORTABLE/mac/markdown/SPDFMarkdownHTMLBlocks.mm
$PORTABLE/mac/markdown/SPDFMarkdownResources.mm
$PORTABLE/mac/markdown/SPDFMarkdownLanguage.mm
$PORTABLE/mac/markdown/SPDFMarkdownHighlighter.mm
$PORTABLE/mac/markdown/SPDFMarkdownLexerSupport.mm
$PORTABLE/mac/markdown/SPDFMarkdownLexersCFamily.mm
$PORTABLE/mac/markdown/SPDFMarkdownLexersScripting.mm
$PORTABLE/mac/markdown/SPDFMarkdownLexersMarkup.mm
$PORTABLE/mac/markdown/SPDFMarkdownLexersData.mm
$PORTABLE/mac/markdown/SPDFMarkdownRenderer.mm
$PORTABLE/mac/markdown/SPDFMarkdownBlockRenderer.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagram.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramModel.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramCanvas.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramFlowchartParser.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramSequenceParser.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramStructParsers.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramChartParsers.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramLayout.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramBand.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramGraphShapes.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramSequenceShapes.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramChartShapes.mm
$PORTABLE/mac/markdown/SPDFMarkdownDiagramBlock.mm
$PORTABLE/mac/markdown/SPDFMarkdownInlineRenderer.mm
$PORTABLE/mac/markdown/SPDFMarkdownDecorations.mm
$PORTABLE/mac/markdown/SPDFMarkdownTheme.mm
$PORTABLE/mac/markdown/SPDFMarkdownTableDecorations.mm
$PORTABLE/mac/markdown/SPDFMarkdownTableLayout.mm
$PORTABLE/mac/markdown/SPDFMarkdownImageRowBand.mm
$PORTABLE/mac/markdown/SPDFMarkdownPaginator.mm
$PORTABLE/mac/markdown/SPDFMarkdownPaginatorDrawing.mm
$PORTABLE/mac/markdown/SPDFMarkdownAsync.mm
$PORTABLE/mac/markdown/SPDFMarkdownDocument.mm
"
UI_SOURCES="
$PORTABLE/mac/tests/SPDFMacMarkdownScrollViewTestSupport.mm
$PORTABLE/mac/SPDFMacMarkdownCache.mm
$PORTABLE/mac/SPDFMacMarkdownKeyboardPolicy.mm
$PORTABLE/mac/SPDFMacMarkdownRouting.mm
$PORTABLE/mac/SPDFMacMarkdownView.mm
$PORTABLE/mac/SPDFMacCursorRegions.mm
$PORTABLE/mac/SPDFMacFindNearest.mm
$PORTABLE/mac/SPDFMacMarkdownPanController.mm
$PORTABLE/mac/SPDFMacMarkdownPageCanvas.mm
$PORTABLE/mac/SPDFMacMarkdownPageCanvas+Copy.mm
$PORTABLE/mac/SPDFMacMarkdownPageCanvas+Cursor.mm
$PORTABLE/mac/SPDFMacMarkdownPageCanvas+Decorations.mm
$PORTABLE/mac/SPDFMacMarkdownPageCanvas+Navigation.mm
$PORTABLE/mac/SPDFMacMarkdownPageCanvas+Pan.mm
$PORTABLE/mac/SPDFMacMarkdownPageCanvas+Search.mm
$PORTABLE/mac/SPDFMacMarkdownPagedView.mm
$PORTABLE/mac/SPDFMacRenderedPage.mm
$PORTABLE/mac/SPDFMacMarkdownMinimapModel.mm
$PORTABLE/mac/SPDFMacMarkdownSidebarModel.mm
$PORTABLE/mac/SPDFMacMarkdownLanguagePicker.mm
$PORTABLE/mac/SPDFMacMarkdownPrinting.mm
$PORTABLE/mac/SPDFMacMarkdownSession.mm
$PORTABLE/mac/SPDFMacMarkdownSession+Interaction.mm
$PORTABLE/mac/SPDFMacMarkdownSession+RemoteImages.mm
$PORTABLE/mac/SPDFMacMarkdownSession+Search.mm
$PORTABLE/mac/SPDFMacMarkdownSessionImageLoader.mm
"

for TEST in \
    SPDFMacMarkdownKeyboardPolicyTests \
    SPDFMacMarkdownRoutingTests \
    SPDFMacMarkdownPagedViewTests \
    SPDFMacMarkdownCopySelectionTests \
    SPDFMacMarkdownMinimapModelTests \
    SPDFMacMarkdownSidebarModelTests \
    SPDFMacMarkdownSessionTests \
    SPDFMacMarkdownSessionFindTests \
    SPDFMacMarkdownRemoteImageSessionTests \
    SPDFMacMarkdownLanguagePickerTests \
    SPDFMacMarkdownPrintingTests
do
    # Source lists and sanitizer flags intentionally use shell word splitting.
    # shellcheck disable=SC2086
    "$CXX" -isysroot "$SDKROOT" -std=c++17 -fobjc-arc -O0 -g -Wall -Wextra -Werror \
        $SANITIZER_FLAGS -I"$PORTABLE/core" -I"$PORTABLE/mac" -I"$PORTABLE/mac/markdown" \
        $FOUNDATION_SOURCES $UI_SOURCES "$SCRIPT_DIR/$TEST.mm" "$BUILD_DIR/md4c.o" $GUMBO_OBJS \
        -framework Foundation -framework AppKit -framework CoreText -framework PDFKit \
        -framework UniformTypeIdentifiers -o "$BUILD_DIR/$TEST"
    "$BUILD_DIR/$TEST"
done
