#!/bin/bash
set -euo pipefail
PORI_ROOT="$(cd "$(dirname "$0")" && pwd)"
PORI_APP="$PORI_ROOT/Pori.app"
PORI_ENGINE="${PORI_ENGINE_DIR:-/Applications/OpenMTP.app/Contents/Resources/bin/arm64}"
PORI_CACHE="$PORI_ROOT/.build/module-cache"
mkdir -p "$PORI_APP/Contents/MacOS" "$PORI_APP/Contents/Frameworks" "$PORI_APP/Contents/Resources/Licenses" "$PORI_CACHE"
for name in kalam.dylib libusb.dylib; do
    if [ ! -f "$PORI_ENGINE/$name" ]; then
        printf 'Missing engine: %s\nSet PORI_ENGINE_DIR to the OpenMTP arm64 engine directory.\n' "$PORI_ENGINE/$name" >&2
        exit 1
    fi
    cp "$PORI_ENGINE/$name" "$PORI_APP/Contents/Frameworks/$name"
done
cp "$PORI_ROOT/Licenses/"* "$PORI_APP/Contents/Resources/Licenses/"
cp "$PORI_ROOT/Info.plist" "$PORI_APP/Contents/Info.plist"
xcrun clang -fobjc-arc -O2 -mmacosx-version-min=14.0 "$PORI_ROOT/Native/mtp-helper.m" -framework Foundation -o "$PORI_APP/Contents/MacOS/mtp-helper"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path "$PORI_CACHE" "$PORI_ROOT/Sources/"*.swift -o "$PORI_APP/Contents/MacOS/Pori" -framework AppKit -framework SwiftUI -framework UniformTypeIdentifiers
if [ -f "$PORI_ROOT/Icon.icns" ]; then cp "$PORI_ROOT/Icon.icns" "$PORI_APP/Contents/Resources/Icon.icns"; fi
codesign --force --sign - "$PORI_APP/Contents/Frameworks/libusb.dylib"
codesign --force --sign - "$PORI_APP/Contents/Frameworks/kalam.dylib"
codesign --force --sign - "$PORI_APP/Contents/MacOS/mtp-helper"
codesign --force --sign - "$PORI_APP"
codesign --verify --deep --strict "$PORI_APP"
"$PORI_APP/Contents/MacOS/Pori" --self-test
printf 'Built: %s\n' "$PORI_APP"
