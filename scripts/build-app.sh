#!/bin/bash
# Builds a universal (Intel + Apple Silicon) CodeOS.app in ./build, including the fan helper.
# Ad-hoc signed for local use. Not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --product CodeOS
  swift build -c release --arch "$arch" --product codeos-fanctl
done

APP="build/CodeOS.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/CodeOS .build/x86_64-apple-macosx/release/CodeOS \
    -output "$APP/Contents/MacOS/CodeOS"
lipo -create .build/arm64-apple-macosx/release/codeos-fanctl .build/x86_64-apple-macosx/release/codeos-fanctl \
    -output "$APP/Contents/MacOS/codeos-fanctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/MacOS/codeos-fanctl"
codesign --force --sign - "$APP"

lipo -info "$APP/Contents/MacOS/CodeOS"
echo "Built $APP"
