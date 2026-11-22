#!/bin/bash
# Installs (or updates) UnifiedBuds from the latest GitHub release.
#
#   Install: curl -fsSL https://raw.githubusercontent.com/amitdeb9/unifiedbuds-macos/main/install.sh | bash
#   Update:  curl -fsSL https://raw.githubusercontent.com/amitdeb9/unifiedbuds-macos/main/install.sh | bash -s -- --update
#
# --update skips the download when the installed version is already the latest.
set -euo pipefail

REPO="amitdeb9/unifiedbuds-macos"
APP="UnifiedBuds.app"
DEST="/Applications"

update_only=false
[ "${1:-}" = "--update" ] && update_only=true

[ "$(uname)" = "Darwin" ] || { echo "UnifiedBuds runs on macOS only." >&2; exit 1; }

echo "==> Checking the latest UnifiedBuds release..."
release=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
latest=$(printf '%s' "$release" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"v\{0,1\}\([^"]*\)"$/\1/')
url=$(printf '%s' "$release" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/')
[ -n "$url" ] || { echo "No release download found for $REPO." >&2; exit 1; }

installed=""
if [ -d "$DEST/$APP" ]; then
    installed=$(defaults read "$DEST/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
fi
if $update_only && [ -n "${installed}" ] && [ "${installed}" = "${latest}" ]; then
    echo "UnifiedBuds ${installed} is already up to date."
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "==> Downloading UnifiedBuds ${latest}..."
curl -fL --progress-bar "$url" -o "$tmp/UnifiedBuds.zip"
ditto -x -k "$tmp/UnifiedBuds.zip" "$tmp"
[ -d "$tmp/$APP" ] || { echo "The download didn't contain $APP." >&2; exit 1; }

# Quit a running copy so it can be replaced.
if pgrep -x UnifiedBuds >/dev/null; then
    osascript -e 'quit app "UnifiedBuds"' >/dev/null 2>&1 || true
    sleep 1
    pkill -x UnifiedBuds 2>/dev/null || true
fi

sudo_cmd=""
[ -w "$DEST" ] || sudo_cmd="sudo"
echo "==> Installing to $DEST..."
$sudo_cmd rm -rf "$DEST/$APP"
$sudo_cmd ditto "$tmp/$APP" "$DEST/$APP"
$sudo_cmd xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

open "$DEST/$APP"
if [ -n "${installed}" ] && [ "${installed}" != "${latest}" ]; then
    echo "UnifiedBuds updated from ${installed} to ${latest}."
else
    echo "UnifiedBuds ${latest} installed. Allow Bluetooth access when macOS asks."
fi
