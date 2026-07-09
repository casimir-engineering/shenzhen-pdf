BUILD := build
DIST := ../dist
MUPDF_DIR := ../mupdf
MUPDF_BUILD := $(MUPDF_DIR)/build/release
MUPDF_LIBS := $(MUPDF_BUILD)/libmupdf.a $(MUPDF_BUILD)/libmupdf-third.a $(MUPDF_BUILD)/libmupdf-pkcs7.a
CPU := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

CORE_SRC := core/shenzhen_pdf_core.c
CORE_HDR := core/shenzhen_pdf_core.h
CORE_OBJ := $(BUILD)/shenzhen_pdf_core.o
MAC_APP := $(DIST)/ShenzhenPDF.app
MAC_BIN := $(MAC_APP)/Contents/MacOS/ShenzhenPDF
MAC_DMG := $(DIST)/ShenzhenPDF-mac-arm64.dmg
MAC_WINDOW_SHORTCUT_TEST := $(BUILD)/SPDFMacWindowShortcutsTests
MAC_MINIMAP_WINDOW_TEST := $(BUILD)/SPDFMacMinimapWindowTests
MAC_TAB_STRIP_GEOMETRY_TEST := $(BUILD)/SPDFMacTabStripGeometryTests
MAC_PALETTE_RESULTS_TEST := $(BUILD)/SPDFMacPaletteResultsTests
MAC_FIND_NEAREST_TEST := $(BUILD)/SPDFMacFindNearestTests
MAC_UPDATER_TEST := $(BUILD)/SPDFUpdaterTests
MAC_PROPERTIES_FORMAT_TEST := $(BUILD)/SPDFMacPropertiesFormatTests
MAC_TRANSLATION_FILTER_TEST := $(BUILD)/SPDFTranslationChineseFilterTests
MAC_TRANSLATION_COPY_TEST := $(BUILD)/SPDFTranslationCopyTests
# Exclude standalone test translation units (each defines its own main()).
MAC_SRCS := $(filter-out mac/SPDFUpdaterTests.mm,$(sort $(wildcard mac/*.mm)))
MAC_HDRS := $(sort $(wildcard mac/*.h))
MAC_BUNDLE_ID ?= com.intuition.shenzhenpdf
MAC_VERSION ?= 26.6.27
MAC_BUILD ?= 2
MAC_TESTFLIGHT_PKG = $(DIST)/ShenzhenPDF-testflight-$(MAC_VERSION)-$(MAC_BUILD).pkg
OPENSSL_LIBDIR ?= $(shell pkg-config --variable=libdir openssl 2>/dev/null || echo /opt/homebrew/opt/openssl@3/lib)
OPENSSL_LIBCRYPTO ?= $(OPENSSL_LIBDIR)/libcrypto.3.dylib
MAC_SIGN_IDENTITY ?= -
MAC_APPSTORE_IDENTITY ?=
MAC_INSTALLER_IDENTITY ?=
MAC_CODESIGN_EXTRA ?=
MAC_PROVISIONING_PROFILE ?=
NOTARY_PROFILE ?=
PORTABLE_OPTFLAGS ?= -O2 -DNDEBUG
LINUX_SRCS := linux/ShenzhenPDFGtk.c linux/ShenzhenPDFGtkDisplay.c

ifeq ($(MAC_SIGN_IDENTITY),-)
MAC_CODESIGN_NESTED = if [ -f "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib" ]; then codesign --force --sign - "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib"; fi
MAC_CODESIGN_APP = $(MAC_CODESIGN_NESTED); codesign --force --sign - "$(MAC_APP)"
MAC_CODESIGN_DMG = true
else
MAC_CODESIGN_NESTED = if [ -f "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib" ]; then codesign --force --timestamp --options runtime --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib"; fi
MAC_CODESIGN_APP = $(MAC_CODESIGN_NESTED); codesign --force --timestamp --options runtime $(MAC_CODESIGN_EXTRA) --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_APP)"
MAC_CODESIGN_DMG = codesign --force --timestamp --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_DMG)"
endif

.PHONY: all mac-app mac-window-shortcut-tests mac-minimap-window-tests mac-tab-strip-geometry-tests mac-palette-results-tests mac-find-nearest-tests mac-updater-tests mac-properties-format-tests mac-translation-filter-tests mac-translation-copy-tests dmg notarize staple release-dmg verify-mac-release testflight-app testflight-pkg open-transporter print-mac-signing-identities install clean mupdf-libs linux

all: mac-app

mupdf-libs:
	@test -f "$(MUPDF_BUILD)/libmupdf.a" || $(MAKE) -C "$(MUPDF_DIR)" -j$(CPU) build=release USE_SYSTEM_GLUT=yes brotli=no libs
	@test -f "$(MUPDF_BUILD)/libmupdf-pkcs7.a" || $(MAKE) -C "$(MUPDF_DIR)" -j$(CPU) build=release USE_SYSTEM_GLUT=yes brotli=no "build/release/libmupdf-pkcs7.a"

$(BUILD):
	mkdir -p "$(BUILD)"

$(CORE_OBJ): $(CORE_SRC) $(CORE_HDR) Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) -Icore -I$(MUPDF_DIR)/include -c "$(CORE_SRC)" -o "$(CORE_OBJ)"

mac-app: $(MAC_BIN)

$(MAC_WINDOW_SHORTCUT_TEST): mac/tests/SPDFMacWindowShortcutsTests.mm mac/SPDFMacWindowShortcuts.mm mac/SPDFMacWindowShortcuts.h | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacWindowShortcutsTests.mm mac/SPDFMacWindowShortcuts.mm -framework Cocoa -o "$(MAC_WINDOW_SHORTCUT_TEST)"

mac-window-shortcut-tests: $(MAC_WINDOW_SHORTCUT_TEST)
	"$(MAC_WINDOW_SHORTCUT_TEST)"

$(MAC_MINIMAP_WINDOW_TEST): mac/tests/SPDFMacMinimapWindowTests.mm mac/SPDFMacMinimapWindow.mm mac/SPDFMacMinimapWindow.h | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacMinimapWindowTests.mm mac/SPDFMacMinimapWindow.mm -framework Cocoa -o "$(MAC_MINIMAP_WINDOW_TEST)"

mac-minimap-window-tests: $(MAC_MINIMAP_WINDOW_TEST)
	"$(MAC_MINIMAP_WINDOW_TEST)"

$(MAC_TAB_STRIP_GEOMETRY_TEST): mac/tests/SPDFMacTabStripGeometryTests.mm mac/SPDFMacTabStripGeometry.mm mac/SPDFMacTabStripGeometry.h | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacTabStripGeometryTests.mm mac/SPDFMacTabStripGeometry.mm -framework Foundation -o "$(MAC_TAB_STRIP_GEOMETRY_TEST)"

mac-tab-strip-geometry-tests: $(MAC_TAB_STRIP_GEOMETRY_TEST)
	"$(MAC_TAB_STRIP_GEOMETRY_TEST)"

$(MAC_PALETTE_RESULTS_TEST): mac/tests/SPDFMacPaletteResultsTests.mm mac/SPDFMacPaletteResults.mm mac/SPDFMacPaletteResults.h | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacPaletteResultsTests.mm mac/SPDFMacPaletteResults.mm -framework Cocoa -o "$(MAC_PALETTE_RESULTS_TEST)"

mac-palette-results-tests: $(MAC_PALETTE_RESULTS_TEST)
	"$(MAC_PALETTE_RESULTS_TEST)"

$(MAC_FIND_NEAREST_TEST): mac/tests/SPDFMacFindNearestTests.mm mac/SPDFMacFindNearest.mm mac/SPDFMacFindNearest.h | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacFindNearestTests.mm mac/SPDFMacFindNearest.mm -framework Cocoa -o "$(MAC_FIND_NEAREST_TEST)"

mac-find-nearest-tests: $(MAC_FIND_NEAREST_TEST)
	"$(MAC_FIND_NEAREST_TEST)"

$(MAC_UPDATER_TEST): mac/SPDFUpdaterTests.mm mac/SPDFUpdater.mm mac/SPDFUpdater.h | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Imac mac/SPDFUpdaterTests.mm mac/SPDFUpdater.mm -framework Cocoa -framework Security -o "$(MAC_UPDATER_TEST)"

mac-updater-tests: $(MAC_UPDATER_TEST)
	"$(MAC_UPDATER_TEST)"

$(MAC_PROPERTIES_FORMAT_TEST): mac/tests/SPDFMacPropertiesFormatTests.mm mac/SPDFMacPropertiesFormat.mm mac/SPDFMacPropertiesFormat.h | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Imac mac/tests/SPDFMacPropertiesFormatTests.mm mac/SPDFMacPropertiesFormat.mm -framework Foundation -o "$(MAC_PROPERTIES_FORMAT_TEST)"

mac-properties-format-tests: $(MAC_PROPERTIES_FORMAT_TEST)
	"$(MAC_PROPERTIES_FORMAT_TEST)"

$(MAC_TRANSLATION_FILTER_TEST): mac/tests/SPDFTranslationChineseFilterTests.mm $(CORE_OBJ) | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Icore -I$(MUPDF_DIR)/include mac/tests/SPDFTranslationChineseFilterTests.mm "$(CORE_OBJ)" $(MUPDF_LIBS) -framework Foundation -lm -o "$(MAC_TRANSLATION_FILTER_TEST)"

mac-translation-filter-tests: $(MAC_TRANSLATION_FILTER_TEST)
	"$(MAC_TRANSLATION_FILTER_TEST)"

$(MAC_TRANSLATION_COPY_TEST): mac/tests/SPDFTranslationCopyTests.mm $(CORE_OBJ) | $(BUILD)
	clang++ -std=c++17 -fobjc-arc -Icore -I$(MUPDF_DIR)/include mac/tests/SPDFTranslationCopyTests.mm "$(CORE_OBJ)" $(MUPDF_LIBS) -framework Foundation -lm -o "$(MAC_TRANSLATION_COPY_TEST)"

mac-translation-copy-tests: $(MAC_TRANSLATION_COPY_TEST)
	"$(MAC_TRANSLATION_COPY_TEST)"

$(MAC_BIN): mupdf-libs $(CORE_OBJ) $(MAC_SRCS) $(MAC_HDRS) mac/Info.plist mac/Assets.xcassets/Contents.json mac/Assets.xcassets/AppIcon.appiconset/Contents.json
	rm -rf "$(MAC_APP)"
	mkdir -p "$(MAC_APP)/Contents/MacOS" "$(MAC_APP)/Contents/Resources" "$(MAC_APP)/Contents/Frameworks" "$(DIST)"
	cp "mac/Info.plist" "$(MAC_APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(MAC_BUNDLE_ID)" "$(MAC_APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(MAC_VERSION)" "$(MAC_APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(MAC_BUILD)" "$(MAC_APP)/Contents/Info.plist"
	rm -rf "$(BUILD)/ShenzhenPDF.iconset"
	mkdir -p "$(BUILD)/ShenzhenPDF.iconset"
	cp ../gfx/ShenzhenPDF-16x16x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_16x16.png"
	cp ../gfx/ShenzhenPDF-32x32x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_16x16@2x.png"
	cp ../gfx/ShenzhenPDF-32x32x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_32x32.png"
	cp ../gfx/ShenzhenPDF-48x48x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_32x32@2x.png"
	cp ../gfx/ShenzhenPDF-128x128x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_128x128.png"
	cp ../gfx/ShenzhenPDF-256x256x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_128x128@2x.png"
	cp ../gfx/ShenzhenPDF-256x256x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_256x256.png"
	cp ../gfx/ShenzhenPDF-256x256x32.png "$(BUILD)/ShenzhenPDF.iconset/icon_256x256@2x.png"
	sips -z 512 512 ../gfx/ShenzhenPDF-256x256x32.png --out "$(BUILD)/ShenzhenPDF.iconset/icon_512x512.png" >/dev/null
	sips -z 1024 1024 ../gfx/ShenzhenPDF-256x256x32.png --out "$(BUILD)/ShenzhenPDF.iconset/icon_512x512@2x.png" >/dev/null
	rm -rf "$(BUILD)/Assets.xcassets"
	mkdir -p "$(BUILD)/Assets.xcassets/AppIcon.appiconset"
	cp mac/Assets.xcassets/Contents.json "$(BUILD)/Assets.xcassets/"
	cp mac/Assets.xcassets/AppIcon.appiconset/Contents.json "$(BUILD)/Assets.xcassets/AppIcon.appiconset/"
	cp "$(BUILD)/ShenzhenPDF.iconset"/*.png "$(BUILD)/Assets.xcassets/AppIcon.appiconset/"
	if xcrun --find actool >/dev/null 2>&1; then \
		xcrun actool "$(BUILD)/Assets.xcassets" --compile "$(MAC_APP)/Contents/Resources" --platform macosx --minimum-deployment-target 12.0 --app-icon AppIcon --output-partial-info-plist "$(BUILD)/actool-partial.plist"; \
	else \
		echo "warning: actool not found; using .icns app icon fallback"; \
	fi
	iconutil -c icns "$(BUILD)/ShenzhenPDF.iconset" -o "$(MAC_APP)/Contents/Resources/AppIcon.icns"
	cp "$(MAC_APP)/Contents/Resources/AppIcon.icns" "$(MAC_APP)/Contents/Resources/ShenzhenPDF.icns"
	clang++ $(PORTABLE_OPTFLAGS) -std=c++17 -fobjc-arc -Icore -I$(MUPDF_DIR)/include $(MAC_SRCS) "$(CORE_OBJ)" $(MUPDF_LIBS) -framework Cocoa -framework PDFKit -framework UniformTypeIdentifiers -framework CoreServices -framework Security -L"$(OPENSSL_LIBDIR)" -lcrypto -lm -Wl,-dead_strip -Wl,-x -o "$(MAC_BIN)"
	@if otool -L "$(MAC_BIN)" | grep -q 'libcrypto.3.dylib'; then \
		cp "$(OPENSSL_LIBCRYPTO)" "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib"; \
		crypto_path=$$(otool -L "$(MAC_BIN)" | awk '/libcrypto.3.dylib/ { print $$1; exit }'); \
		install_name_tool -change "$$crypto_path" "@executable_path/../Frameworks/libcrypto.3.dylib" "$(MAC_BIN)"; \
	fi
	@if [ -n "$(MAC_PROVISIONING_PROFILE)" ]; then \
		cp "$(MAC_PROVISIONING_PROFILE)" "$(MAC_APP)/Contents/embedded.provisionprofile"; \
		chmod u+w "$(MAC_APP)/Contents/embedded.provisionprofile"; \
		xattr -c "$(MAC_APP)/Contents/embedded.provisionprofile"; \
	fi
	@if [ -n "$(MAC_PROVISIONING_PROFILE)" ] && echo "$(MAC_CODESIGN_EXTRA)" | grep -q "TestFlight.entitlements"; then \
		mkdir -p "$(BUILD)"; \
		cp mac/TestFlight.entitlements "$(BUILD)/TestFlight-signing.entitlements"; \
		security cms -D -i "$(MAC_PROVISIONING_PROFILE)" -o "$(BUILD)/provision.plist"; \
		/usr/libexec/PlistBuddy -x -c "Print Entitlements" "$(BUILD)/provision.plist" > "$(BUILD)/profile-entitlements.plist"; \
		/usr/libexec/PlistBuddy -c "Merge $(BUILD)/profile-entitlements.plist" "$(BUILD)/TestFlight-signing.entitlements"; \
		if [ -f "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib" ]; then \
			codesign --force --timestamp --options runtime --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib"; \
		fi; \
		codesign --force --timestamp --options runtime --entitlements "$(BUILD)/TestFlight-signing.entitlements" --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_APP)"; \
	else \
		$(MAC_CODESIGN_APP); \
	fi

dmg: mac-app
	hdiutil create -volname "Shenzhen PDF" -srcfolder "$(MAC_APP)" -ov -format UDZO "$(MAC_DMG)"
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
	xcrun notarytool submit "$(MAC_DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait

staple: notarize
	xcrun stapler staple "$(MAC_DMG)"
	xcrun stapler validate "$(MAC_DMG)"

release-dmg: staple verify-mac-release

verify-mac-release:
	codesign --verify --deep --strict --verbose=2 "$(MAC_APP)"
	spctl -a -vv -t execute "$(MAC_APP)"
	spctl -a -vv -t open --context context:primary-signature "$(MAC_DMG)"

testflight-app:
	@if [ -z "$(MAC_APPSTORE_IDENTITY)" ]; then \
		echo "MAC_APPSTORE_IDENTITY must be an Apple Distribution certificate, e.g. Apple Distribution: Friend Name (TEAMID1234)." >&2; \
		exit 2; \
	fi
	@if [ -z "$(MAC_PROVISIONING_PROFILE)" ]; then \
		echo "MAC_PROVISIONING_PROFILE must point to the App Store Connect distribution provisioning profile for $(MAC_BUNDLE_ID)." >&2; \
		exit 2; \
	fi
	$(MAKE) mac-app \
		MAC_SIGN_IDENTITY="$(MAC_APPSTORE_IDENTITY)" \
		MAC_CODESIGN_EXTRA="--entitlements mac/TestFlight.entitlements" \
		MAC_PROVISIONING_PROFILE="$(MAC_PROVISIONING_PROFILE)" \
		MAC_BUNDLE_ID="$(MAC_BUNDLE_ID)" \
		MAC_VERSION="$(MAC_VERSION)" \
		MAC_BUILD="$(MAC_BUILD)"

testflight-pkg: testflight-app
	@if [ -z "$(MAC_INSTALLER_IDENTITY)" ]; then \
		echo "MAC_INSTALLER_IDENTITY must be a 3rd Party Mac Developer Installer certificate." >&2; \
		exit 2; \
	fi
	rm -f "$(MAC_TESTFLIGHT_PKG)"
	productbuild --component "$(MAC_APP)" /Applications --sign "$(MAC_INSTALLER_IDENTITY)" "$(MAC_TESTFLIGHT_PKG)"
	pkgutil --check-signature "$(MAC_TESTFLIGHT_PKG)"
	@echo "Created TestFlight upload package: $(MAC_TESTFLIGHT_PKG)"

open-transporter: testflight-pkg
	@if ! open -Ra Transporter >/dev/null 2>&1; then \
		echo "Install Apple's Transporter app from the Mac App Store, then rerun this target or drag $(MAC_TESTFLIGHT_PKG) into Transporter." >&2; \
		exit 2; \
	fi
	open -a Transporter "$(MAC_TESTFLIGHT_PKG)"

print-mac-signing-identities:
	@security find-identity -v | grep -E "Apple Distribution|Developer ID Application|3rd Party Mac Developer" || true

install: mac-app
	rm -rf "/Applications/ShenzhenPDF.app"
	ditto "$(MAC_APP)" "/Applications/ShenzhenPDF.app"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/ShenzhenPDF.app"

linux: mupdf-libs | $(BUILD)
	$(CC) $(PORTABLE_OPTFLAGS) -Icore -I$(MUPDF_DIR)/include $$(pkg-config --cflags gtk+-3.0) "$(CORE_SRC)" $(LINUX_SRCS) $(MUPDF_LIBS) $$(pkg-config --libs gtk+-3.0 openssl) -lm -o "$(BUILD)/ShenzhenPDF-gtk"

clean:
	rm -rf "$(BUILD)" "$(MAC_APP)" "$(MAC_DMG)" "$(MAC_TESTFLIGHT_PKG)"
