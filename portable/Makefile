BUILD := build
DIST := ../dist
MUPDF_DIR := ../mupdf
MUPDF_BUILD := $(MUPDF_DIR)/build/release
MUPDF_LIBS := $(MUPDF_BUILD)/libmupdf.a $(MUPDF_BUILD)/libmupdf-third.a $(MUPDF_BUILD)/libmupdf-pkcs7.a
CPU := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

CORE_SRC := core/sumatra_pdf_core.c
CORE_HDR := core/sumatra_pdf_core.h
CORE_OBJ := $(BUILD)/sumatra_pdf_core.o
MAC_APP := $(DIST)/SumatraPDF.app
MAC_BIN := $(MAC_APP)/Contents/MacOS/SumatraPDF
MAC_DMG := $(DIST)/SumatraPDF-mac-arm64.dmg
OPENSSL_LIBDIR ?= $(shell pkg-config --variable=libdir openssl 2>/dev/null || echo /opt/homebrew/opt/openssl@3/lib)
OPENSSL_LIBCRYPTO ?= $(OPENSSL_LIBDIR)/libcrypto.3.dylib

.PHONY: all mac-app dmg install clean mupdf-libs linux

all: mac-app

mupdf-libs:
	@test -f "$(MUPDF_BUILD)/libmupdf.a" || $(MAKE) -C "$(MUPDF_DIR)" -j$(CPU) build=release USE_SYSTEM_GLUT=yes brotli=no

$(BUILD):
	mkdir -p "$(BUILD)"

$(CORE_OBJ): $(CORE_SRC) $(CORE_HDR) | $(BUILD)
	clang -Icore -I$(MUPDF_DIR)/include -c "$(CORE_SRC)" -o "$(CORE_OBJ)"

mac-app: $(MAC_BIN)

$(MAC_BIN): mupdf-libs $(CORE_OBJ) mac/SumatraPDFMac.mm mac/Info.plist
	rm -rf "$(MAC_APP)"
	mkdir -p "$(MAC_APP)/Contents/MacOS" "$(MAC_APP)/Contents/Resources" "$(MAC_APP)/Contents/Frameworks" "$(DIST)"
	cp "mac/Info.plist" "$(MAC_APP)/Contents/Info.plist"
	rm -rf "$(BUILD)/SumatraPDF.iconset"
	mkdir -p "$(BUILD)/SumatraPDF.iconset"
	cp ../gfx/SumatraPDF-16x16x32.png "$(BUILD)/SumatraPDF.iconset/icon_16x16.png"
	cp ../gfx/SumatraPDF-32x32x32.png "$(BUILD)/SumatraPDF.iconset/icon_16x16@2x.png"
	cp ../gfx/SumatraPDF-32x32x32.png "$(BUILD)/SumatraPDF.iconset/icon_32x32.png"
	cp ../gfx/SumatraPDF-48x48x32.png "$(BUILD)/SumatraPDF.iconset/icon_32x32@2x.png"
	cp ../gfx/SumatraPDF-128x128x32.png "$(BUILD)/SumatraPDF.iconset/icon_128x128.png"
	cp ../gfx/SumatraPDF-256x256x32.png "$(BUILD)/SumatraPDF.iconset/icon_128x128@2x.png"
	cp ../gfx/SumatraPDF-256x256x32.png "$(BUILD)/SumatraPDF.iconset/icon_256x256.png"
	cp ../gfx/SumatraPDF-256x256x32.png "$(BUILD)/SumatraPDF.iconset/icon_256x256@2x.png"
	sips -z 512 512 ../gfx/SumatraPDF-256x256x32.png --out "$(BUILD)/SumatraPDF.iconset/icon_512x512.png" >/dev/null
	sips -z 1024 1024 ../gfx/SumatraPDF-256x256x32.png --out "$(BUILD)/SumatraPDF.iconset/icon_512x512@2x.png" >/dev/null
	iconutil -c icns "$(BUILD)/SumatraPDF.iconset" -o "$(MAC_APP)/Contents/Resources/SumatraPDF.icns"
	clang++ -std=c++17 -fobjc-arc -Icore -I$(MUPDF_DIR)/include "mac/SumatraPDFMac.mm" "$(CORE_OBJ)" $(MUPDF_LIBS) -framework Cocoa -L"$(OPENSSL_LIBDIR)" -lcrypto -lm -o "$(MAC_BIN)"
	@if otool -L "$(MAC_BIN)" | grep -q 'libcrypto.3.dylib'; then \
		cp "$(OPENSSL_LIBCRYPTO)" "$(MAC_APP)/Contents/Frameworks/libcrypto.3.dylib"; \
		crypto_path=$$(otool -L "$(MAC_BIN)" | awk '/libcrypto.3.dylib/ { print $$1; exit }'); \
		install_name_tool -change "$$crypto_path" "@executable_path/../Frameworks/libcrypto.3.dylib" "$(MAC_BIN)"; \
	fi
	codesign --force --deep --sign - "$(MAC_APP)"

dmg: mac-app
	hdiutil create -volname SumatraPDF -srcfolder "$(MAC_APP)" -ov -format UDZO "$(MAC_DMG)"

install: mac-app
	rm -rf "/Applications/SumatraPDF.app"
	ditto "$(MAC_APP)" "/Applications/SumatraPDF.app"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/SumatraPDF.app"

linux: mupdf-libs
	$(CC) -Icore -I$(MUPDF_DIR)/include $$(pkg-config --cflags gtk+-3.0) "$(CORE_SRC)" linux/SumatraPDFGtk.c $(MUPDF_LIBS) $$(pkg-config --libs gtk+-3.0 openssl) -lm -o "$(BUILD)/SumatraPDF-gtk"

clean:
	rm -rf "$(BUILD)" "$(MAC_APP)" "$(MAC_DMG)"
