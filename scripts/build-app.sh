#!/bin/bash
# Builds build/UnifiedBuds.app. Set SIGN_IDENTITY to a "Developer ID Application"
# identity for distribution; defaults to ad-hoc signing for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/UnifiedBuds.app"

swift build -c "$CONFIG" --arch arm64 --arch x86_64
BIN="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)/UnifiedBuds"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/UnifiedBuds"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --timestamp=none \
    --entitlements Resources/UnifiedBuds.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP"
