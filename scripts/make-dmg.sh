#!/bin/bash
# Packages build/UnifiedBuds.noindex/UnifiedBuds.app into build/UnifiedBuds.dmg: the app next to an
# Applications shortcut to drag it onto. Uses only the built-in hdiutil.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d build/UnifiedBuds.noindex/UnifiedBuds.app ] || scripts/build-app.sh
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto build/UnifiedBuds.noindex/UnifiedBuds.app "$staging/UnifiedBuds.app"
ln -s /Applications "$staging/Applications"

rm -f build/UnifiedBuds.dmg
hdiutil create -quiet -volname "UnifiedBuds" -srcfolder "$staging" -fs HFS+ -format UDZO -ov build/UnifiedBuds.dmg
echo "Built build/UnifiedBuds.dmg"
