BUILD := build
DIST := ../dist
MUPDF_DIR := ../mupdf
UNAME_S := $(shell uname -s)
SPDF_RELEASE_MODE ?= 0
MAC_ARCH ?= arm64
MACOSX_DEPLOYMENT_TARGET ?= 12.0
MAC_BUNDLE_ID ?= com.intuition.shenzhenpdf
MAC_TEAM_ID ?= 66LJ4BV7Q3
PORTABLE_OPTFLAGS ?= -O2 -DNDEBUG
PORTABLE_TEST_OPTFLAGS := $(filter-out -DNDEBUG,$(PORTABLE_OPTFLAGS))

ifeq ($(SPDF_RELEASE_MODE),1)
override MAC_ARCH := arm64
override MACOSX_DEPLOYMENT_TARGET := 12.0
override MAC_BUNDLE_ID := com.intuition.shenzhenpdf
override MAC_TEAM_ID := 66LJ4BV7Q3
override PORTABLE_OPTFLAGS := -O2 -DNDEBUG
endif

# Where the mupdf static libs live, relative to $(MUPDF_DIR). Overridable so
# builds for another distro's toolchain don't clobber the default output
# (build-rpm.sh uses MUPDF_OUT=build/release-fedora).
ifeq ($(UNAME_S),Darwin)
MAC_TARGET_FLAGS := -arch $(MAC_ARCH) -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
MUPDF_MAC_ARGS := ARCHFLAGS="-arch $(MAC_ARCH)" XCFLAGS="$(MAC_TARGET_FLAGS)"
MUPDF_OUT ?= build/release-macos-$(MAC_ARCH)-$(MACOSX_DEPLOYMENT_TARGET)
export MACOSX_DEPLOYMENT_TARGET
else
MAC_TARGET_FLAGS :=
MUPDF_MAC_ARGS :=
MUPDF_OUT ?= build/release
endif
MUPDF_BUILD := $(MUPDF_DIR)/$(MUPDF_OUT)
MUPDF_LIBS := $(MUPDF_BUILD)/libmupdf.a $(MUPDF_BUILD)/libmupdf-third.a $(MUPDF_BUILD)/libmupdf-pkcs7.a
CPU := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

CORE_SRC := core/shenzhen_pdf_core.c
CORE_HDR := core/shenzhen_pdf_core.h
CORE_OBJ := $(BUILD)/shenzhen_pdf_core.o
CORE_SELECTION_SRC := core/spdf_selection.c
CORE_SELECTION_HDR := core/spdf_selection.h
CORE_SELECTION_OBJ := $(BUILD)/spdf_selection.o
CORE_SELECTION_SUPPORT_SRC := core/spdf_selection_support.c
CORE_SELECTION_SUPPORT_OBJ := $(BUILD)/spdf_selection_support.o
CORE_RECOLOR_SRC := core/spdf_recolor.c
CORE_RECOLOR_HDR := core/spdf_recolor.h
CORE_RECOLOR_OBJ := $(BUILD)/spdf_recolor.o
CORE_OBJS := $(CORE_OBJ) $(CORE_SELECTION_OBJ) $(CORE_SELECTION_SUPPORT_OBJ) $(CORE_RECOLOR_OBJ)
YAML_SRC := core/spdf_yaml.c
YAML_HDR := core/spdf_yaml.h
YAML_OBJ := $(BUILD)/spdf_yaml.o
MAC_MD4C_OBJ := $(BUILD)/md4c.o
# Vendored Gumbo HTML5 parser (pure C, no dependencies) backing the Markdown
# reader's sanitizing HTML-island whitelist (portable/mac/markdown/SPDFMarkdownHTML*.mm).
MAC_GUMBO_SRCS := $(sort $(wildcard ../ext/gumbo-parser/src/*.c))
MAC_GUMBO_OBJS := $(patsubst ../ext/gumbo-parser/src/%.c,$(BUILD)/gumbo-%.o,$(MAC_GUMBO_SRCS))
CORE_OUTLINE_TEST := $(BUILD)/SPDFCoreOutlineTests
CORE_PASSWORD_TEST := $(BUILD)/SPDFCorePasswordTests
CORE_RECOLOR_TEST := $(BUILD)/SPDFCoreRecolorTests
CORE_RENDER_THEME_TEST := $(BUILD)/SPDFCoreRenderThemeTests
CORE_RECOLOR_PROBE := $(BUILD)/SPDFRecolorProbe
CORE_SELECTION_TEST := $(BUILD)/SPDFCoreSelectionTests
CORE_CJK_SELECTION_TEST := $(BUILD)/SPDFCoreCJKSelectionTests
MAC_APP := $(DIST)/ShenzhenPDF.app
MAC_BIN := $(MAC_APP)/Contents/MacOS/ShenzhenPDF
MAC_DMG := $(DIST)/ShenzhenPDF-mac-arm64.dmg
MAC_ICON_SRCS := $(addprefix ../gfx/ShenzhenPDF-,$(addsuffix x32.png,16x16 32x32 64x64 128x128 256x256 512x512 1024x1024))
MAC_WINDOW_SHORTCUT_TEST := $(BUILD)/SPDFMacWindowShortcutsTests
MAC_WINDOW_CHROME_TEST := $(BUILD)/SPDFMacWindowChromeTests
MAC_PASSWORD_TEST := $(BUILD)/SPDFMacPasswordTests
MAC_MINIMAP_WINDOW_TEST := $(BUILD)/SPDFMacMinimapWindowTests
MAC_TAB_STRIP_GEOMETRY_TEST := $(BUILD)/SPDFMacTabStripGeometryTests
MAC_TAB_STRIP_INTERACTION_TEST := $(BUILD)/SPDFMacTabStripInteractionTests
MAC_READING_THEME_CHROME_TEST := $(BUILD)/SPDFMacReadingThemeChromeTests
MAC_PALETTE_RESULTS_TEST := $(BUILD)/SPDFMacPaletteResultsTests
MAC_FIND_NEAREST_TEST := $(BUILD)/SPDFMacFindNearestTests
MAC_UPDATER_TEST := $(BUILD)/SPDFUpdaterTests
MAC_PROPERTIES_FORMAT_TEST := $(BUILD)/SPDFMacPropertiesFormatTests
MAC_TRANSLATION_FILTER_TEST := $(BUILD)/SPDFTranslationChineseFilterTests
MAC_TRANSLATION_COPY_TEST := $(BUILD)/SPDFTranslationCopyTests
MAC_CURSOR_REGION_TEST := $(BUILD)/SPDFMacCursorRegionsTests
MAC_TAB_LIFECYCLE_TEST := $(BUILD)/SPDFMacTabLifecycleTests
MAC_FILE_EXPLORER_TEST := $(BUILD)/SPDFMacFileExplorerPreferenceTests
MAC_SELECTION_CLICK_TEST := $(BUILD)/SPDFMacSelectionClickTests
MAC_SELECTION_ADAPTER_TEST := $(BUILD)/SPDFMacSelectionAdapterTests
MAC_LAUNCH_WORK_POLICY_TEST := $(BUILD)/SPDFMacLaunchWorkPolicyTests
MAC_STATE_YAML_TEST := $(BUILD)/SPDFStateYamlTests
MAC_RELEASE_NOTES_PREVIEW := $(BUILD)/SPDFReleaseNotesPreview
# Exclude standalone test translation units (each defines its own main()).
MAC_MARKDOWN_SRCS := $(sort $(wildcard mac/markdown/*.mm))
MAC_SRCS := $(filter-out mac/SPDFUpdaterTests.mm,$(sort $(wildcard mac/*.mm))) $(MAC_MARKDOWN_SRCS)
MAC_HDRS := $(sort $(wildcard mac/*.h) $(wildcard mac/markdown/*.h))
MAC_VERSION ?= 26.9.1
MAC_BUILD ?= 2
MAC_SIGN_IDENTITY ?= -
NOTARY_PROFILE ?=
NOTARY_RESULT ?= $(DIST)/notarytool-$(MAC_VERSION)-$(MAC_BUILD).json

ifeq ($(MAC_SIGN_IDENTITY),-)
MAC_CODESIGN_APP = codesign --force --sign - "$(MAC_APP)"
MAC_CODESIGN_DMG = true
else
MAC_CODESIGN_APP = codesign --force --timestamp --options runtime --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_APP)"
MAC_CODESIGN_DMG = codesign --force --timestamp --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_DMG)"
endif

.PHONY: all mac-app core-outline-tests core-password-tests core-recolor-tests core-render-theme-tests core-recolor-probe core-selection-tests icon-tests mac-window-shortcut-tests mac-window-chrome-tests mac-password-tests mac-minimap-window-tests mac-tab-strip-geometry-tests mac-tab-strip-interaction-tests mac-reading-theme-chrome-tests mac-palette-results-tests mac-find-nearest-tests mac-updater-tests mac-properties-format-tests mac-translation-filter-tests mac-translation-copy-tests mac-cursor-region-tests mac-state-yaml-tests mac-tab-lifecycle-tests mac-file-explorer-tests mac-selection-click-tests mac-selection-adapter-tests mac-launch-work-policy-tests mac-markdown-tests linux-password-tests file-size-ratchet-tests release-pipeline-tests test-binaries release-notes-preview print-release-config dmg notarize staple release-dmg release-dmg-artifact verify-mac-release verify-mac-unsigned print-mac-signing-identities install clean mupdf-libs linux

all: mac-app

mupdf-libs:
	@test -f "$(MUPDF_BUILD)/libmupdf.a" -a -f "$(MUPDF_BUILD)/libmupdf-third.a" || $(MAKE) -C "$(MUPDF_DIR)" -j$(CPU) build=release OUT="$(MUPDF_OUT)" $(MUPDF_MAC_ARGS) USE_SYSTEM_GLUT=yes brotli=no libs "$(MUPDF_OUT)/libmupdf-third.a"
	@test -f "$(MUPDF_BUILD)/libmupdf-pkcs7.a" || $(MAKE) -C "$(MUPDF_DIR)" -j$(CPU) build=release OUT="$(MUPDF_OUT)" $(MUPDF_MAC_ARGS) USE_SYSTEM_GLUT=yes brotli=no "$(MUPDF_OUT)/libmupdf-pkcs7.a"

$(BUILD):
	mkdir -p "$(BUILD)"

$(CORE_OBJ): $(CORE_SRC) $(CORE_HDR) Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Icore -I$(MUPDF_DIR)/include -c "$(CORE_SRC)" -o "$(CORE_OBJ)"

$(CORE_SELECTION_OBJ): $(CORE_SELECTION_SRC) $(CORE_SELECTION_HDR) $(CORE_HDR) Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Icore -I$(MUPDF_DIR)/include -c "$(CORE_SELECTION_SRC)" -o "$(CORE_SELECTION_OBJ)"

$(CORE_SELECTION_SUPPORT_OBJ): $(CORE_SELECTION_SUPPORT_SRC) $(CORE_SELECTION_HDR) $(CORE_HDR) Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Icore -I$(MUPDF_DIR)/include -c "$(CORE_SELECTION_SUPPORT_SRC)" -o "$(CORE_SELECTION_SUPPORT_OBJ)"

$(CORE_RECOLOR_OBJ): $(CORE_RECOLOR_SRC) $(CORE_RECOLOR_HDR) Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Wall -Wextra -Werror -Icore -c "$(CORE_RECOLOR_SRC)" -o "$(CORE_RECOLOR_OBJ)"

$(MAC_MD4C_OBJ): ../ext/md4c/md4c.c ../ext/md4c/md4c.h Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -std=c11 -I../ext/md4c -c ../ext/md4c/md4c.c -o "$(MAC_MD4C_OBJ)"

$(BUILD)/gumbo-%.o: ../ext/gumbo-parser/src/%.c Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -std=c99 -I../ext/gumbo-parser/src -c $< -o $@

$(YAML_OBJ): $(YAML_SRC) $(YAML_HDR) Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Icore -c "$(YAML_SRC)" -o "$(YAML_OBJ)"

mac-app: $(MAC_BIN)

$(CORE_OUTLINE_TEST): core/tests/SPDFCoreOutlineTests.c $(CORE_OBJ) $(CORE_RECOLOR_OBJ) mupdf-libs | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Wall -Wextra -Icore -I$(MUPDF_DIR)/include $< "$(CORE_OBJ)" "$(CORE_RECOLOR_OBJ)" $(MUPDF_LIBS) $(if $(filter Darwin,$(UNAME_S)),-framework Foundation) -lm -o "$@"

core-outline-tests: $(CORE_OUTLINE_TEST)
	"$(CORE_OUTLINE_TEST)"

$(CORE_PASSWORD_TEST): core/tests/SPDFCorePasswordTests.c $(CORE_OBJ) $(CORE_RECOLOR_OBJ) mupdf-libs | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Wall -Wextra -Icore -I$(MUPDF_DIR)/include $< "$(CORE_OBJ)" "$(CORE_RECOLOR_OBJ)" $(MUPDF_LIBS) $(if $(filter Darwin,$(UNAME_S)),-framework Foundation) -lm -o "$@"

core-password-tests: $(CORE_PASSWORD_TEST)
	core/tests/run_password_tests.sh "$(CORE_PASSWORD_TEST)"

$(CORE_RECOLOR_TEST): core/tests/SPDFCoreRecolorTests.c $(CORE_RECOLOR_OBJ) | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Wall -Wextra -Werror -Icore $< "$(CORE_RECOLOR_OBJ)" -lm -o "$@"

core-recolor-tests: $(CORE_RECOLOR_TEST)
	"$(CORE_RECOLOR_TEST)"

$(CORE_RENDER_THEME_TEST): core/tests/SPDFCoreRenderThemeTests.c $(CORE_OBJS) mupdf-libs | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Wall -Wextra -Werror -Icore -I$(MUPDF_DIR)/include $< $(CORE_OBJS) $(MUPDF_LIBS) $(if $(filter Darwin,$(UNAME_S)),-framework Foundation) -lm -o "$@"

core-render-theme-tests: $(CORE_RENDER_THEME_TEST)
	"$(CORE_RENDER_THEME_TEST)"

# Not part of the test suite: renders a real page with and without the dark
# reading theme, times every transform and writes before/after PNGs, so recolor
# quality and cost can be judged from pixels rather than argued.
$(CORE_RECOLOR_PROBE): core/tests/SPDFRecolorProbe.c $(CORE_OBJS) mupdf-libs | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Wall -Wextra -Icore -I$(MUPDF_DIR)/include $< $(CORE_OBJS) $(MUPDF_LIBS) $(if $(filter Darwin,$(UNAME_S)),-framework Foundation) -lm -o "$@"

core-recolor-probe: $(CORE_RECOLOR_PROBE)

$(CORE_SELECTION_TEST): core/tests/SPDFCoreSelectionTests.c $(CORE_OBJS) mupdf-libs | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Wall -Wextra -Icore -I$(MUPDF_DIR)/include $< $(CORE_OBJS) $(MUPDF_LIBS) $(if $(filter Darwin,$(UNAME_S)),-framework Foundation) -lm -o "$@"

$(CORE_CJK_SELECTION_TEST): core/tests/SPDFCoreCJKSelectionTests.c $(CORE_OBJS) mupdf-libs | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -Wall -Wextra -Icore -I$(MUPDF_DIR)/include $< $(CORE_OBJS) $(MUPDF_LIBS) $(if $(filter Darwin,$(UNAME_S)),-framework Foundation) -lm -o "$@"

core-selection-tests: $(CORE_SELECTION_TEST) $(CORE_CJK_SELECTION_TEST)
	"$(CORE_SELECTION_TEST)"
	"$(CORE_CJK_SELECTION_TEST)"

$(MAC_WINDOW_SHORTCUT_TEST): mac/tests/SPDFMacWindowShortcutsTests.mm mac/SPDFMacWindowShortcuts.mm mac/SPDFMacWindowShortcuts.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacWindowShortcutsTests.mm mac/SPDFMacWindowShortcuts.mm -framework Cocoa -o "$(MAC_WINDOW_SHORTCUT_TEST)"

mac-window-shortcut-tests: $(MAC_WINDOW_SHORTCUT_TEST)
	"$(MAC_WINDOW_SHORTCUT_TEST)"

$(MAC_WINDOW_CHROME_TEST): mac/tests/SPDFMacWindowChromeTests.mm mac/SPDFMacWindowChrome.mm mac/SPDFMacWindowChrome.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacWindowChromeTests.mm mac/SPDFMacWindowChrome.mm -framework Foundation -o "$(MAC_WINDOW_CHROME_TEST)"

mac-window-chrome-tests: $(MAC_WINDOW_CHROME_TEST)
	"$(MAC_WINDOW_CHROME_TEST)"

$(MAC_PASSWORD_TEST): mac/tests/SPDFMacPasswordTests.mm mac/SPDFMacPassword.mm mac/SPDFMacPassword.h $(CORE_OBJ) $(CORE_RECOLOR_OBJ) mupdf-libs | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac -Icore -I$(MUPDF_DIR)/include mac/tests/SPDFMacPasswordTests.mm mac/SPDFMacPassword.mm "$(CORE_OBJ)" "$(CORE_RECOLOR_OBJ)" $(MUPDF_LIBS) -framework Cocoa -lm -o "$(MAC_PASSWORD_TEST)"

mac-password-tests: $(MAC_PASSWORD_TEST)
	"$(MAC_PASSWORD_TEST)"
	mac/tests/SPDFMacPasswordSourceTests.sh

$(MAC_MINIMAP_WINDOW_TEST): mac/tests/SPDFMacMinimapWindowTests.mm mac/SPDFMacMinimapWindow.mm mac/SPDFMacMinimapWindow.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacMinimapWindowTests.mm mac/SPDFMacMinimapWindow.mm -framework Cocoa -o "$(MAC_MINIMAP_WINDOW_TEST)"

mac-minimap-window-tests: $(MAC_MINIMAP_WINDOW_TEST)
	"$(MAC_MINIMAP_WINDOW_TEST)"

$(MAC_TAB_STRIP_GEOMETRY_TEST): mac/tests/SPDFMacTabStripGeometryTests.mm mac/SPDFMacTabStripGeometry.mm mac/SPDFMacTabStripGeometry.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacTabStripGeometryTests.mm mac/SPDFMacTabStripGeometry.mm -framework Foundation -o "$(MAC_TAB_STRIP_GEOMETRY_TEST)"

mac-tab-strip-geometry-tests: $(MAC_TAB_STRIP_GEOMETRY_TEST)
	"$(MAC_TAB_STRIP_GEOMETRY_TEST)"

$(MAC_TAB_STRIP_INTERACTION_TEST): mac/tests/SPDFMacTabStripInteractionTests.mm mac/SPDFMacTabStripView.mm mac/SPDFMacTabStripView.h mac/SPDFMacTabStripGeometry.mm mac/SPDFMacTabStripGeometry.h mac/SPDFMacWindowChrome.mm mac/SPDFMacWindowChrome.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Wall -Wextra -Werror -Imac -Icore -I$(MUPDF_DIR)/include mac/tests/SPDFMacTabStripInteractionTests.mm mac/SPDFMacTabStripView.mm mac/SPDFMacTabStripGeometry.mm mac/SPDFMacWindowChrome.mm -framework Cocoa -o "$(MAC_TAB_STRIP_INTERACTION_TEST)"

mac-tab-strip-interaction-tests: $(MAC_TAB_STRIP_INTERACTION_TEST)
	"$(MAC_TAB_STRIP_INTERACTION_TEST)"

# The reading-theme chrome seams: the gutter and page-border decisions on
# SPDFDocumentView, the single-segment toolbar pill, and the Translate
# enablement policy. Links the AppKit half only - no mupdf, and no markdown
# pipeline beyond the palette itself.
MAC_READING_THEME_CHROME_SRCS := mac/tests/SPDFMacReadingThemeChromeTests.mm mac/SPDFMacDocumentView.mm \
	mac/SPDFMacPageRendering.mm mac/SPDFMacRenderedPage.mm mac/SPDFMacDelayedLinkActivation.mm \
	mac/SPDFMacDocumentViewTheme.mm mac/SPDFMacSupport.mm mac/SPDFMacSelectionClick.mm mac/SPDFMacInactiveZoom.mm mac/SPDFMacUIHelpers.mm \
	mac/SPDFMacCursorRegions.mm mac/SPDFMacWindowChrome.mm mac/SPDFMacTranslationPolicy.mm \
	mac/markdown/SPDFMarkdownTheme.mm

$(MAC_READING_THEME_CHROME_TEST): $(MAC_READING_THEME_CHROME_SRCS) mac/SPDFMacTranslationPolicy.h mac/markdown/SPDFMarkdownDecorations.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Wall -Wextra -Werror -Imac -Icore -Imac/markdown $(MAC_READING_THEME_CHROME_SRCS) -framework Cocoa -framework UniformTypeIdentifiers -o "$(MAC_READING_THEME_CHROME_TEST)"

mac-reading-theme-chrome-tests: $(MAC_READING_THEME_CHROME_TEST)
	"$(MAC_READING_THEME_CHROME_TEST)"

$(MAC_PALETTE_RESULTS_TEST): mac/tests/SPDFMacPaletteResultsTests.mm mac/SPDFMacPaletteResults.mm mac/SPDFMacPaletteResults.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacPaletteResultsTests.mm mac/SPDFMacPaletteResults.mm -framework Cocoa -o "$(MAC_PALETTE_RESULTS_TEST)"

mac-palette-results-tests: $(MAC_PALETTE_RESULTS_TEST)
	"$(MAC_PALETTE_RESULTS_TEST)"

$(MAC_FIND_NEAREST_TEST): mac/tests/SPDFMacFindNearestTests.mm mac/SPDFMacFindNearest.mm mac/SPDFMacFindNearest.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacFindNearestTests.mm mac/SPDFMacFindNearest.mm -framework Cocoa -o "$(MAC_FIND_NEAREST_TEST)"

mac-find-nearest-tests: $(MAC_FIND_NEAREST_TEST)
	"$(MAC_FIND_NEAREST_TEST)"

$(MAC_UPDATER_TEST): mac/SPDFUpdaterTests.mm mac/SPDFUpdater.mm mac/SPDFUpdaterDownloadBounds.mm mac/SPDFUpdaterRelease.mm mac/SPDFMacFileExplorerPreference.mm mac/SPDFUpdater.h mac/SPDFUpdaterDownloadBounds.h mac/SPDFUpdaterRelease.h mac/SPDFMacFileExplorerPreference.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/SPDFUpdaterTests.mm mac/SPDFUpdater.mm mac/SPDFUpdaterDownloadBounds.mm mac/SPDFUpdaterRelease.mm mac/SPDFMacFileExplorerPreference.mm -framework Cocoa -framework Security -o "$(MAC_UPDATER_TEST)"

mac-updater-tests: $(MAC_UPDATER_TEST)
	"$(MAC_UPDATER_TEST)"

release-pipeline-tests:
	release/release-common-tests.sh
	release/release-workflow-tests.sh

print-release-config:
	@printf '%s\n' "$(MAC_TEAM_ID)|$(MAC_BUNDLE_ID)|$(MAC_ARCH)|$(MACOSX_DEPLOYMENT_TARGET)|$(PORTABLE_OPTFLAGS)"

mac-markdown-tests:
	mac/tests/markdown/run-tests.sh
	mac/tests/run-markdown-integration-tests.sh

linux-password-tests:
	linux/gtk4/tests/password_source_test.sh
	linux/gtk4/tests/run_password_runtime_tests.sh

file-size-ratchet-tests:
	../tools/test-file-size-ratchet.sh
	../tools/check-file-sizes.sh --root ..

icon-tests:
	../gfx/verify-shenzhen-pdf-icons.sh

$(MAC_PROPERTIES_FORMAT_TEST): mac/tests/SPDFMacPropertiesFormatTests.mm mac/SPDFMacPropertiesFormat.mm mac/SPDFMacPropertiesFormat.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacPropertiesFormatTests.mm mac/SPDFMacPropertiesFormat.mm -framework Foundation -o "$(MAC_PROPERTIES_FORMAT_TEST)"

mac-properties-format-tests: $(MAC_PROPERTIES_FORMAT_TEST)
	"$(MAC_PROPERTIES_FORMAT_TEST)"

$(MAC_TRANSLATION_FILTER_TEST): mac/tests/SPDFTranslationChineseFilterTests.mm $(CORE_OBJ) $(CORE_RECOLOR_OBJ) mupdf-libs | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Icore -I$(MUPDF_DIR)/include mac/tests/SPDFTranslationChineseFilterTests.mm "$(CORE_OBJ)" "$(CORE_RECOLOR_OBJ)" $(MUPDF_LIBS) -framework Foundation -lm -o "$(MAC_TRANSLATION_FILTER_TEST)"

mac-translation-filter-tests: $(MAC_TRANSLATION_FILTER_TEST)
	"$(MAC_TRANSLATION_FILTER_TEST)"

$(MAC_TRANSLATION_COPY_TEST): mac/tests/SPDFTranslationCopyTests.mm $(CORE_OBJ) $(CORE_RECOLOR_OBJ) mupdf-libs | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Icore -I$(MUPDF_DIR)/include mac/tests/SPDFTranslationCopyTests.mm "$(CORE_OBJ)" "$(CORE_RECOLOR_OBJ)" $(MUPDF_LIBS) -framework Foundation -lm -o "$(MAC_TRANSLATION_COPY_TEST)"

mac-translation-copy-tests: $(MAC_TRANSLATION_COPY_TEST)
	"$(MAC_TRANSLATION_COPY_TEST)"

$(MAC_CURSOR_REGION_TEST): mac/tests/SPDFMacCursorRegionsTests.mm mac/SPDFMacCursorRegions.mm mac/SPDFMacCursorRegions.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacCursorRegionsTests.mm mac/SPDFMacCursorRegions.mm -framework Foundation -o "$(MAC_CURSOR_REGION_TEST)"

mac-cursor-region-tests: $(MAC_CURSOR_REGION_TEST)
	"$(MAC_CURSOR_REGION_TEST)"

$(MAC_TAB_LIFECYCLE_TEST): mac/tests/SPDFMacTabLifecycleTests.mm mac/SPDFMacTabLifecycle.mm mac/SPDFMacTabLifecycle.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Wall -Wextra -Werror -Imac mac/tests/SPDFMacTabLifecycleTests.mm mac/SPDFMacTabLifecycle.mm -framework Foundation -o "$(MAC_TAB_LIFECYCLE_TEST)"

mac-tab-lifecycle-tests: $(MAC_TAB_LIFECYCLE_TEST)
	"$(MAC_TAB_LIFECYCLE_TEST)"

$(MAC_FILE_EXPLORER_TEST): mac/tests/SPDFMacFileExplorerPreferenceTests.mm mac/SPDFMacFileExplorerPreference.mm mac/SPDFMacFileExplorerPreference.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Wall -Wextra -Werror -Imac mac/tests/SPDFMacFileExplorerPreferenceTests.mm mac/SPDFMacFileExplorerPreference.mm -framework Cocoa -o "$(MAC_FILE_EXPLORER_TEST)"

mac-file-explorer-tests: $(MAC_FILE_EXPLORER_TEST)
	"$(MAC_FILE_EXPLORER_TEST)"

$(MAC_SELECTION_CLICK_TEST): mac/tests/SPDFMacSelectionClickTests.mm mac/SPDFMacDocumentView.mm mac/SPDFMacDocumentView.h mac/SPDFMacPageRendering.mm mac/SPDFMacPageRendering.h mac/SPDFMacSelectionClick.mm mac/SPDFMacSelectionClick.h mac/SPDFMacDelayedLinkActivation.mm mac/SPDFMacDelayedLinkActivation.h mac/SPDFMacCursorRegions.mm mac/SPDFMacCursorRegions.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Wall -Wextra -Werror -Imac -Icore -I$(MUPDF_DIR)/include mac/tests/SPDFMacSelectionClickTests.mm mac/SPDFMacDocumentView.mm mac/SPDFMacPageRendering.mm mac/SPDFMacSelectionClick.mm mac/SPDFMacDelayedLinkActivation.mm mac/SPDFMacCursorRegions.mm -framework Cocoa -o "$(MAC_SELECTION_CLICK_TEST)"

mac-selection-click-tests: $(MAC_SELECTION_CLICK_TEST)
	"$(MAC_SELECTION_CLICK_TEST)"

$(MAC_SELECTION_ADAPTER_TEST): mac/tests/SPDFMacSelectionAdapterTests.mm mac/SPDFMacSelectionAdapter.mm mac/SPDFMacSelectionAdapter.h mac/SPDFMacSelectionClick.h core/shenzhen_pdf_core.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Wall -Wextra -Werror -Imac -Icore mac/tests/SPDFMacSelectionAdapterTests.mm mac/SPDFMacSelectionAdapter.mm -framework Cocoa -o "$(MAC_SELECTION_ADAPTER_TEST)"

mac-selection-adapter-tests: $(MAC_SELECTION_ADAPTER_TEST)
	"$(MAC_SELECTION_ADAPTER_TEST)"

$(MAC_LAUNCH_WORK_POLICY_TEST): mac/tests/launch/SPDFMacLaunchWorkPolicyTests.mm mac/SPDFMacInactivePreload.mm mac/SPDFMacInactivePreload.h mac/SPDFMacLaunchWorkPolicy.mm mac/SPDFMacLaunchWorkPolicy.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Wall -Wextra -Werror -Imac mac/tests/launch/SPDFMacLaunchWorkPolicyTests.mm mac/SPDFMacInactivePreload.mm mac/SPDFMacLaunchWorkPolicy.mm -framework Cocoa -o "$(MAC_LAUNCH_WORK_POLICY_TEST)"

mac-launch-work-policy-tests: $(MAC_LAUNCH_WORK_POLICY_TEST)
	"$(MAC_LAUNCH_WORK_POLICY_TEST)"

$(MAC_STATE_YAML_TEST): mac/tests/SPDFStateYamlTests.mm $(YAML_OBJ) | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Icore mac/tests/SPDFStateYamlTests.mm "$(YAML_OBJ)" -framework Foundation -o "$(MAC_STATE_YAML_TEST)"

mac-state-yaml-tests: $(MAC_STATE_YAML_TEST)
	"$(MAC_STATE_YAML_TEST)"

$(MAC_BIN): mupdf-libs $(CORE_OBJS) $(YAML_OBJ) $(MAC_MD4C_OBJ) $(MAC_GUMBO_OBJS) $(MAC_SRCS) $(MAC_HDRS) $(MAC_ICON_SRCS) mac/Info.plist mac/Assets.xcassets/Contents.json mac/Assets.xcassets/AppIcon.appiconset/Contents.json
	rm -rf "$(MAC_APP)"
	mkdir -p "$(MAC_APP)/Contents/MacOS" "$(MAC_APP)/Contents/Resources" "$(DIST)"
	cp "mac/Info.plist" "$(MAC_APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(MAC_BUNDLE_ID)" "$(MAC_APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(MAC_VERSION)" "$(MAC_APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(MAC_BUILD)" "$(MAC_APP)/Contents/Info.plist"
	rm -rf "$(BUILD)/ShenzhenPDF.iconset"
	mkdir -p "$(BUILD)/ShenzhenPDF.iconset"
	cp ../gfx/ShenzhenPDF-16x16x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_16x16.png"
	cp ../gfx/ShenzhenPDF-32x32x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_16x16@2x.png"
	cp ../gfx/ShenzhenPDF-32x32x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_32x32.png"
	cp ../gfx/ShenzhenPDF-64x64x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_32x32@2x.png"
	cp ../gfx/ShenzhenPDF-128x128x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_128x128.png"
	cp ../gfx/ShenzhenPDF-256x256x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_128x128@2x.png"
	cp ../gfx/ShenzhenPDF-256x256x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_256x256.png"
	cp ../gfx/ShenzhenPDF-512x512x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_256x256@2x.png"
	cp ../gfx/ShenzhenPDF-512x512x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_512x512.png"
	cp ../gfx/ShenzhenPDF-1024x1024x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_512x512@2x.png"
	rm -rf "$(BUILD)/Assets.xcassets"
	mkdir -p "$(BUILD)/Assets.xcassets/AppIcon.appiconset"
	cp mac/Assets.xcassets/Contents.json "$(BUILD)/Assets.xcassets/"
	cp mac/Assets.xcassets/AppIcon.appiconset/Contents.json "$(BUILD)/Assets.xcassets/AppIcon.appiconset/"
	cp "$(BUILD)/ShenzhenPDF.iconset"/*.png "$(BUILD)/Assets.xcassets/AppIcon.appiconset/"
	if xcrun --find actool >/dev/null 2>&1; then \
		xcrun actool "$(BUILD)/Assets.xcassets" --compile "$(MAC_APP)/Contents/Resources" --platform macosx --minimum-deployment-target "$(MACOSX_DEPLOYMENT_TARGET)" --app-icon AppIcon --output-partial-info-plist "$(BUILD)/actool-partial.plist"; \
	else \
		echo "warning: actool not found; using .icns app icon fallback"; \
	fi
	iconutil -c icns "$(BUILD)/ShenzhenPDF.iconset" -o "$(MAC_APP)/Contents/Resources/AppIcon.icns"
	cp "$(MAC_APP)/Contents/Resources/AppIcon.icns" "$(MAC_APP)/Contents/Resources/ShenzhenPDF.icns"
	clang++ $(PORTABLE_OPTFLAGS) $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Icore -I$(MUPDF_DIR)/include $(MAC_SRCS) $(CORE_OBJS) "$(YAML_OBJ)" $(MAC_MD4C_OBJ) $(MAC_GUMBO_OBJS) $(MUPDF_LIBS) -framework Cocoa -framework QuartzCore -framework PDFKit -framework UniformTypeIdentifiers -framework CoreServices -framework Security -lm -Wl,-dead_strip -Wl,-x -o "$(MAC_BIN)"
	@if otool -L "$(MAC_BIN)" | grep -Eq 'libcrypto|/opt/homebrew|/usr/local'; then \
		echo "unexpected mutable runtime dependency in $(MAC_BIN)" >&2; \
		otool -L "$(MAC_BIN)" >&2; \
		exit 1; \
	fi
	xattr -cr "$(MAC_APP)"
	$(MAC_CODESIGN_APP)

dmg: mac-app
	mac/make-installer-dmg.sh "$(MAC_APP)" "$(MAC_DMG)" "Shenzhen PDF"
	$(MAC_CODESIGN_DMG)

notarize: dmg
	@if [ "$(MAC_SIGN_IDENTITY)" = "-" ]; then \
		echo "MAC_SIGN_IDENTITY must be a Developer ID Application certificate for public macOS releases." >&2; \
		exit 2; \
	fi
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
		echo "NOTARY_PROFILE must name an xcrun notarytool keychain profile." >&2; \
		echo "Create one with: xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-password>" >&2; \
		exit 2; \
	fi
	release/notarize-mac-dmg.sh "$(MAC_DMG)" "$(NOTARY_PROFILE)" "$(NOTARY_RESULT)"

staple: notarize
	xcrun stapler staple "$(MAC_DMG)"
	xcrun stapler validate "$(MAC_DMG)"

verify-mac-release: staple
	release/verify-mac-artifact.sh --dmg "$(MAC_DMG)" --version "$(MAC_VERSION)" --build "$(MAC_BUILD)" --bundle-id "$(MAC_BUNDLE_ID)" --team-id "$(MAC_TEAM_ID)" --min-os "$(MACOSX_DEPLOYMENT_TARGET)"

release-dmg:
	@test "$(SPDF_RELEASE_MODE)" = "1" || (echo "release-dmg must be invoked through build-mac-release.sh" >&2; exit 2)
	$(MAKE) release-dmg-artifact

ifeq ($(SPDF_RELEASE_MODE),1)
release-dmg-artifact: verify-mac-release
else
release-dmg-artifact:
	@echo "release-dmg-artifact requires SPDF_RELEASE_MODE=1" >&2
	@exit 2
endif

verify-mac-unsigned: dmg
	release/verify-mac-artifact.sh --unsigned --dmg "$(MAC_DMG)" --version "$(MAC_VERSION)" --build "$(MAC_BUILD)" --bundle-id "$(MAC_BUNDLE_ID)" --min-os "$(MACOSX_DEPLOYMENT_TARGET)"

# Every compiled binary the *-tests targets execute. A release sweep builds
# this first with -j, then runs the suites sequentially, so the compiling is
# spread over all cores while the test log stays in a deterministic order.
# Running the *-tests targets themselves under -j would interleave their
# output: the make shipped with macOS is 3.81, which has no --output-sync.
TEST_BINARIES := $(CORE_OUTLINE_TEST) $(CORE_PASSWORD_TEST) $(CORE_RECOLOR_TEST) \
	$(CORE_RENDER_THEME_TEST) $(CORE_SELECTION_TEST) $(CORE_CJK_SELECTION_TEST) \
	$(MAC_WINDOW_SHORTCUT_TEST) $(MAC_WINDOW_CHROME_TEST) $(MAC_PASSWORD_TEST) \
	$(MAC_MINIMAP_WINDOW_TEST) $(MAC_TAB_STRIP_GEOMETRY_TEST) \
	$(MAC_TAB_STRIP_INTERACTION_TEST) $(MAC_READING_THEME_CHROME_TEST) \
	$(MAC_PALETTE_RESULTS_TEST) $(MAC_FIND_NEAREST_TEST) $(MAC_UPDATER_TEST) \
	$(MAC_PROPERTIES_FORMAT_TEST) $(MAC_TRANSLATION_FILTER_TEST) \
	$(MAC_TRANSLATION_COPY_TEST) $(MAC_CURSOR_REGION_TEST) \
	$(MAC_TAB_LIFECYCLE_TEST) $(MAC_FILE_EXPLORER_TEST) \
	$(MAC_SELECTION_CLICK_TEST) $(MAC_SELECTION_ADAPTER_TEST) \
	$(MAC_LAUNCH_WORK_POLICY_TEST) $(MAC_STATE_YAML_TEST)
# The GTK test binaries are appended further down, once their sources are
# globbed; the test-binaries rule itself lives at the end of this file so its
# prerequisite list is expanded after that.

$(MAC_RELEASE_NOTES_PREVIEW): release/SPDFReleaseNotesPreview.mm mac/SPDFUpdaterRelease.mm mac/SPDFUpdater.h mac/SPDFUpdaterRelease.h | $(BUILD)
	clang++ $(MAC_TARGET_FLAGS) -std=c++17 -fobjc-arc -Imac release/SPDFReleaseNotesPreview.mm mac/SPDFUpdaterRelease.mm -framework Cocoa -o "$(MAC_RELEASE_NOTES_PREVIEW)"

release-notes-preview: $(MAC_RELEASE_NOTES_PREVIEW)
	@test -n "$(NOTES_FILE)" || (echo "NOTES_FILE is required" >&2; exit 2)
	"$(MAC_RELEASE_NOTES_PREVIEW)" "$(NOTES_FILE)" "$(MAC_VERSION)-$(MAC_BUILD)"

print-mac-signing-identities:
	@security find-identity -v -p codesigning | grep "Developer ID Application" || true

install: mac-app
	rm -rf "/Applications/ShenzhenPDF.app"
	ditto "$(MAC_APP)" "/Applications/ShenzhenPDF.app"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/ShenzhenPDF.app"

LINUX_GTK4_SRCS := $(sort $(wildcard linux/gtk4/*.c))

linux-gtk4: mupdf-libs | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) -Wall -Icore -Ilinux/gtk4 -I$(MUPDF_DIR)/include $$(pkg-config --cflags gtk4 libadwaita-1) "$(CORE_SRC)" "$(CORE_SELECTION_SRC)" "$(CORE_SELECTION_SUPPORT_SRC)" "$(CORE_RECOLOR_SRC)" "$(YAML_SRC)" $(LINUX_GTK4_SRCS) $(MUPDF_LIBS) $$(pkg-config --libs gtk4 libadwaita-1 openssl) -lm -o "$(BUILD)/ShenzhenPDF-gtk4"

LINUX_GTK4_TEST_SRCS := $(sort $(wildcard linux/gtk4/tests/*_test.c))
LINUX_GTK4_TEST_BINS := $(patsubst linux/gtk4/tests/%.c,$(BUILD)/%,$(LINUX_GTK4_TEST_SRCS))
# The recipe these replaced rebuilt every binary on every invocation, so the
# prerequisite net is deliberately wide: any core/ or linux/gtk4/ header moving
# rebuilds all 26. Correctness first; they are ~0.4s each and now build in
# parallel under `make -j test-binaries`.
LINUX_GTK4_TEST_DEPS := $(YAML_SRC) $(sort $(wildcard core/*.h) $(wildcard linux/gtk4/*.h)) Makefile

$(LINUX_GTK4_TEST_BINS): $(BUILD)/%: linux/gtk4/tests/%.c $(LINUX_GTK4_TEST_DEPS) | $(BUILD)
	$(CC) $(PORTABLE_TEST_OPTFLAGS) -Wall -Icore -Ilinux/gtk4 $$(pkg-config --cflags glib-2.0 openssl) $< "$(YAML_SRC)" $$(pkg-config --libs glib-2.0 openssl) -lm -o "$@"

TEST_BINARIES += $(LINUX_GTK4_TEST_BINS)

linux-gtk4-tests: $(LINUX_GTK4_TEST_BINS)
	@set -e; for bin in $(LINUX_GTK4_TEST_BINS); do "$$bin"; done

# Deliberately not named *-tests: spdf_discover_test_targets() scans this file
# for that suffix, and this target runs nothing.
test-binaries: $(TEST_BINARIES)

clean:
	rm -rf "$(BUILD)" "$(MAC_APP)" "$(MAC_DMG)"
