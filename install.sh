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
# Query GitHub API with cache-busting to always get the freshest release tag
release=$(curl -fsSL -H "Cache-Control: no-cache" "https://api.github.com/repos/$REPO/releases/latest?t=$(date +%s)" 2>/dev/null || true)
latest=$(printf '%s' "$release" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"v\{0,1\}\([^"]*\)"$/\1/' || true)
url=$(printf '%s' "$release" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/' || true)

# If GitHub API is rate-limited or unavailable, fall back to the release redirect URL
if [ -z "$latest" ] || [ -z "$url" ]; then
    loc=$(curl -sIL "https://github.com/$REPO/releases/latest" 2>/dev/null | grep -i "^location:" | head -1 | tr -d '\r\n' | awk '{print $2}' || true)
    if [ -n "$loc" ]; then
        latest=$(basename "$loc" | sed 's/^v//')
        url="https://github.com/$REPO/releases/download/v${latest}/UnifiedBuds.zip"
    fi
fi

[ -n "$latest" ] && [ -n "$url" ] || { echo "Could not determine the latest release for $REPO. Check internet connection." >&2; exit 1; }

# Semantic version comparison: returns 0 if $1 >= $2
version_ge() {
    [ "$1" = "$2" ] && return 0
    local lowest
    lowest=$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)
    [ "$lowest" != "$1" ]
}

installed=""
if [ -d "$DEST/$APP" ]; then
    installed=$(defaults read "$DEST/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
fi

# Always protect against downgrades: if installed is >= latest, never downgrade
if [ -n "${installed}" ] && version_ge "${installed}" "${latest}"; then
    echo "UnifiedBuds ${installed} is already up to date (latest release is ${latest})."
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
