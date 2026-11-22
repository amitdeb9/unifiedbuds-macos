#!/bin/bash
# Packages build/UnifiedBuds.app into build/UnifiedBuds.dmg (brew install create-dmg).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d build/UnifiedBuds.app ] || scripts/build-app.sh
rm -f build/UnifiedBuds.dmg
create-dmg \
    --volname "UnifiedBuds" \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "UnifiedBuds.app" 140 170 \
    --app-drop-link 400 170 \
    build/UnifiedBuds.dmg build/UnifiedBuds.app
