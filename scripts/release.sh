#!/bin/bash
# Builds UnifiedBuds and publishes it as a GitHub release that install.sh downloads.
# Bump CFBundleShortVersionString (and CFBundleVersion) in Resources/Info.plist first.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
ZIP="build/UnifiedBuds-$VERSION.zip"

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG already exists. Bump the version in Resources/Info.plist." >&2
    exit 1
fi

scripts/build-app.sh
rm -f "$ZIP"
ditto -c -k --keepParent build/UnifiedBuds.app "$ZIP"

gh release create "$TAG" "$ZIP" --title "UnifiedBuds $VERSION" --generate-notes
echo "Published $TAG"
