#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../../../.." && pwd)
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/spdf-markdown-tests.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT INT TERM

CC=$(xcrun --find clang)
CXX=$(xcrun --find clang++)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SANITIZER_FLAGS=${SPDF_MARKDOWN_SANITIZER_FLAGS:-}

# Intentional word splitting: SANITIZER_FLAGS is a caller-supplied compiler flag list.
# shellcheck disable=SC2086
"$CC" -isysroot "$SDKROOT" -std=c11 -O0 -g -Wall -Wextra -Werror \
    $SANITIZER_FLAGS \
    -I"$ROOT/ext/md4c" \
    -c "$ROOT/ext/md4c/md4c.c" \
    -o "$BUILD_DIR/md4c.o"

SOURCES="
$ROOT/portable/mac/markdown/SPDFMarkdownModel.mm
$ROOT/portable/mac/markdown/SPDFMarkdownParser.mm
$ROOT/portable/mac/markdown/SPDFMarkdownResources.mm
$ROOT/portable/mac/markdown/SPDFMarkdownLanguage.mm
$ROOT/portable/mac/markdown/SPDFMarkdownHighlighter.mm
$ROOT/portable/mac/markdown/SPDFMarkdownRenderer.mm
$ROOT/portable/mac/markdown/SPDFMarkdownBlockRenderer.mm
$ROOT/portable/mac/markdown/SPDFMarkdownPaginator.mm
$ROOT/portable/mac/markdown/SPDFMarkdownAsync.mm
$ROOT/portable/mac/markdown/SPDFMarkdownDocument.mm
"

for TEST in \
    SPDFMarkdownParserTests \
    SPDFMarkdownLanguageTests \
    SPDFMarkdownRendererTests \
    SPDFMarkdownPaginatorTests \
    SPDFMarkdownAsyncTests \
    SPDFMarkdownPDFAdapterTests \
    SPDFMarkdownPerformanceTests
do
    # Intentional word splitting: SOURCES contains one shell-safe repository path per line.
    # SANITIZER_FLAGS is also an intentional caller-supplied compiler flag list.
    # shellcheck disable=SC2086
    "$CXX" -isysroot "$SDKROOT" -std=c++17 -fobjc-arc -O0 -g -Wall -Wextra -Werror \
        $SANITIZER_FLAGS \
        -I"$ROOT/portable/mac/markdown" \
        $SOURCES "$SCRIPT_DIR/$TEST.mm" "$BUILD_DIR/md4c.o" \
        -framework Foundation -framework AppKit -framework CoreText -framework PDFKit \
        -o "$BUILD_DIR/$TEST"
    "$BUILD_DIR/$TEST"
done
