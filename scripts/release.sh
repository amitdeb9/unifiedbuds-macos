#!/bin/bash
# Builds UnifiedBuds and publishes it as a GitHub release: a zip that install.sh
# downloads and a DMG for direct download.
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

# The release tag must point at the code being built, so require it to be pushed.
if [ -n "$(git status --porcelain)" ]; then
    echo "Commit your changes before releasing." >&2
    exit 1
fi
git fetch -q origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
    echo "Push your commits before releasing." >&2
    exit 1
fi

scripts/build-app.sh
rm -f "$ZIP"
ditto -c -k --keepParent build/UnifiedBuds.app "$ZIP"
# The DMG keeps a fixed name so .../releases/latest/download/UnifiedBuds.dmg always works.
scripts/make-dmg.sh

gh release create "$TAG" "$ZIP" build/UnifiedBuds.dmg --target "$(git rev-parse HEAD)" --title "UnifiedBuds $VERSION" --generate-notes
echo "Published $TAG"
