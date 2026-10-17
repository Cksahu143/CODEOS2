#!/bin/bash
# Builds CodeOS.app in ./build. Requires the Xcode Command Line Tools on macOS 13+.
# The result is ad-hoc signed for local use only. It is not notarized for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/CodeOS.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/CodeOS" "$APP/Contents/MacOS/CodeOS"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it with: open build/CodeOS.app"
