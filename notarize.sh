#!/bin/bash
# Signs CodeOS.app with a Developer ID certificate, notarizes it with Apple, and staples
# the ticket. Requires a paid Apple Developer account. Run build-app.sh first.
#
#   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   export NOTARY_PROFILE="codeos-notary"   # created once with: xcrun notarytool store-credentials
#   bash scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

APP="build/CodeOS.app"
ZIP="build/CodeOS.zip"

codesign --force --options runtime --timestamp \
    --entitlements Resources/CodeOS.entitlements \
    --sign "$DEVELOPER_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "Notarized and stapled: $APP"
