#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/../../.." && pwd)
cd "$root"

make core-password-tests >/dev/null

case "$(uname -s)" in
    Darwin)
        arch=${MAC_ARCH:-arm64}
        deployment=${MACOSX_DEPLOYMENT_TARGET:-12.0}
        mupdf_build="../mupdf/build/release-macos-${arch}-${deployment}"
        platform_libs="-framework Foundation"
        ;;
    *)
        mupdf_build=${MUPDF_BUILD:-../mupdf/build/release}
        platform_libs=""
        ;;
esac

binary="build/password_runtime_test"
# pkg-config and platform_libs intentionally expand into compiler arguments.
# shellcheck disable=SC2046,SC2086
${CC:-cc} -O2 -Wall -Wextra -Icore -Ilinux/gtk4 -I../mupdf/include \
    linux/gtk4/tests/password_runtime_case.c linux/gtk4/spdf_password.c linux/gtk4/spdf_password_controller.c \
    linux/gtk4/spdf_password_lifecycle.c build/shenzhen_pdf_core.o build/spdf_recolor.o \
    "$mupdf_build/libmupdf.a" "$mupdf_build/libmupdf-third.a" "$mupdf_build/libmupdf-pkcs7.a" \
    $(pkg-config --cflags --libs glib-2.0 gio-2.0) $platform_libs -lm -o "$binary"

core/tests/run_password_tests.sh "$binary"
