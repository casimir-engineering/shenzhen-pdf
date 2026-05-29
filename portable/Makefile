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
MAC_SRCS := $(sort $(wildcard mac/*.mm))
MAC_HDRS := $(sort $(wildcard mac/*.h))
MAC_BUNDLE_ID ?= org.shenzhenpdf.ShenzhenPDF
MAC_VERSION ?= 0.5.0
MAC_BUILD ?= 5
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

ifeq ($(MAC_SIGN_IDENTITY),-)
MAC_CODESIGN_NESTED = if [ -f "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib" ]; then codesign --force --sign - "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib"; fi
MAC_CODESIGN_APP = $(MAC_CODESIGN_NESTED); codesign --force --sign - "$(MAC_APP)"
MAC_CODESIGN_DMG = true
else
MAC_CODESIGN_NESTED = if [ -f "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib" ]; then codesign --force --timestamp --options runtime --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib"; fi
MAC_CODESIGN_APP = $(MAC_CODESIGN_NESTED); codesign --force --timestamp --options runtime $(MAC_CODESIGN_EXTRA) --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_APP)"
MAC_CODESIGN_DMG = codesign --force --timestamp --sign "$(MAC_SIGN_IDENTITY)" "$(MAC_DMG)"
endif

.PHONY: all mac-app dmg notarize staple release-dmg verify-mac-release testflight-app testflight-pkg open-transporter print-mac-signing-identities install clean mupdf-libs linux

all: mac-app

mupdf-libs:
	@test -f "$(MUPDF_BUILD)/libmupdf.a" || $(MAKE) -C "$(MUPDF_DIR)" -j$(CPU) build=release USE_SYSTEM_GLUT=yes brotli=no

$(BUILD):
	mkdir -p "$(BUILD)"

$(CORE_OBJ): $(CORE_SRC) $(CORE_HDR) Makefile | $(BUILD)
	clang $(PORTABLE_OPTFLAGS) -Icore -I$(MUPDF_DIR)/include -c "$(CORE_SRC)" -o "$(CORE_OBJ)"

mac-app: $(MAC_BIN)

$(MAC_BIN): mupdf-libs $(CORE_OBJ) $(MAC_SRCS) $(MAC_HDRS) mac/Info.plist
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
	iconutil -c icns "$(BUILD)/ShenzhenPDF.iconset" -o "$(MAC_APP)/Contents/Resources/ShenzhenPDF.icns"
	clang++ $(PORTABLE_OPTFLAGS) -std=c++17 -fobjc-arc -Icore -I$(MUPDF_DIR)/include $(MAC_SRCS) "$(CORE_OBJ)" $(MUPDF_LIBS) -framework Cocoa -framework UniformTypeIdentifiers -L"$(OPENSSL_LIBDIR)" -lcrypto -lm -o "$(MAC_BIN)"
	@if otool -L "$(MAC_BIN)" | grep -q 'libcrypto.3.dylib'; then \
		cp "$(OPENSSL_LIBCRYPTO)" "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib"; \
		crypto_path=$$(otool -L "$(MAC_BIN)" | awk '/libcrypto.3.dylib/ { print $$1; exit }'); \
		install_name_tool -change "$$crypto_path" "@executable_path/../Frameworks/libcrypto.3.dylib" "$(MAC_BIN)"; \
	fi
	@if [ -n "$(MAC_PROVISIONING_PROFILE)" ]; then \
		cp "$(MAC_PROVISIONING_PROFILE)" "$(MAC_APP)/Contents/embedded.provisionprofile"; \
	fi
	$(MAC_CODESIGN_APP)

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
	$(CC) $(PORTABLE_OPTFLAGS) -Icore -I$(MUPDF_DIR)/include $$(pkg-config --cflags gtk+-3.0) "$(CORE_SRC)" linux/ShenzhenPDFGtk.c $(MUPDF_LIBS) $$(pkg-config --libs gtk+-3.0 openssl) -lm -o "$(BUILD)/ShenzhenPDF-gtk"

clean:
	rm -rf "$(BUILD)" "$(MAC_APP)" "$(MAC_DMG)" "$(MAC_TESTFLIGHT_PKG)"
