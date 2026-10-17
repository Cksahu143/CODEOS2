#!/bin/bash
# Builds a universal (Intel + Apple Silicon) CodeOS.app in ./build.
# Ad-hoc signed for local use. Not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
swift build -c release --arch x86_64

APP="build/CodeOS.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
    ".build/arm64-apple-macosx/release/CodeOS" \
    ".build/x86_64-apple-macosx/release/CodeOS" \
    -output "$APP/Contents/MacOS/CodeOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

lipo -info "$APP/Contents/MacOS/CodeOS"
echo "Built $APP"
