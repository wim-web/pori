#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${PORI_ENGINE_DIR:-/Applications/OpenMTP.app/Contents/Resources/bin/arm64}"
CACHE="$ROOT/.build"
REV=5da350b69c6d0d4aed67a063498ee89c7448400a
ARCHIVE="$CACHE/openmtp-$REV.tar.gz"
mkdir -p "$CACHE/kalam" "$CACHE/usb/include" "$CACHE/usb/lib" "$CACHE/go-cache"
if [ ! -f "$ARCHIVE" ]; then
    curl --fail --location "https://codeload.github.com/ganeshrvel/openmtp/tar.gz/$REV" -o "$ARCHIVE"
fi
printf '%s  %s\n' '6fd0f7ed722cf81aed1a4df305407ef91d8bfca3f48fec491cb2960fce958ae6' "$ARCHIVE" | shasum -a 256 -c -
tar -xzf "$ARCHIVE" -C "$CACHE/kalam" --strip-components=4 "openmtp-$REV/ffi/kalam/native"
tar -xjf "$ROOT/Licenses/libusb-1.0.26-source.tar.bz2" -C "$CACHE/usb/include" --strip-components=2 libusb-1.0.26/libusb/libusb.h
cp "$ENGINE/libusb.dylib" "$CACHE/usb/lib/libusb-1.0.dylib"
install_name_tool -id "$CACHE/usb/lib/libusb-1.0.dylib" "$CACHE/usb/lib/libusb-1.0.dylib"
codesign --force --sign - "$CACHE/usb/lib/libusb-1.0.dylib"
cp "$ROOT/Native/Move/"*.go "$CACHE/kalam/"
export PORI_LIBUSB_DIR="$CACHE/usb"
export PKG_CONFIG="$ROOT/Tools/libusb-pkg-config"
export GOCACHE="$CACHE/go-cache"
export CGO_ENABLED=1 GOOS=darwin GOARCH=arm64
export MACOSX_DEPLOYMENT_TARGET=14.0
export CGO_CFLAGS='-Wno-deprecated-declarations -mmacosx-version-min=14.0'
export CGO_LDFLAGS='-mmacosx-version-min=14.0'
cd "$CACHE/kalam"
go test -mod=readonly .
go build -mod=readonly -trimpath -buildmode=c-shared -o "$ROOT/.build/kalam.dylib" .
install_name_tool -change "$CACHE/usb/lib/libusb-1.0.dylib" @loader_path/libusb.dylib "$ROOT/.build/kalam.dylib"
