#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-0.1.0}"
UNIVERSAL="${UNIVERSAL:-1}"

VERSION="$VERSION" UNIVERSAL="$UNIVERSAL" "$PROJECT_DIR/scripts/build-app.sh" release

APP_DIR="$PROJECT_DIR/build/LiteMouse.app"
ARCH_LABEL="universal"
if [[ "$UNIVERSAL" != "1" ]]; then
    ARCH_LABEL="$(uname -m)"
fi
DMG_PATH="$PROJECT_DIR/build/LiteMouse-${VERSION}-macos-${ARCH_LABEL}.dmg"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/litemouse-dmg.XXXXXX")"
MNT="$STAGE/mnt"
cleanup() {
    if [[ -d "$MNT" ]] && mount | grep -q " on $MNT "; then
        hdiutil detach "$MNT" -force -quiet || true
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$STAGE/image" "$MNT"
ditto --norsrc --noextattr --noqtn "$APP_DIR" "$STAGE/image/LiteMouse.app"
ln -s /Applications "$STAGE/image/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "LiteMouse ${VERSION}" -srcfolder "$STAGE/image" -fs HFS+ -format UDZO \
    -imagekey zlib-level=9 -quiet "$DMG_PATH"
hdiutil verify -quiet "$DMG_PATH"

# Verify mounted image structure, version, and code signature
hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen -mountpoint "$MNT" -quiet
[[ "$(readlink "$MNT/Applications")" == "/Applications" ]] || { echo "Missing /Applications symlink" >&2; exit 1; }
codesign --verify --deep --strict "$MNT/LiteMouse.app"
GOT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MNT/LiteMouse.app/Contents/Info.plist")"
[[ "$GOT_VER" == "$VERSION" ]] || { echo "Version mismatch: got $GOT_VER, expected $VERSION" >&2; exit 1; }
hdiutil detach "$MNT" -quiet

printf 'Packaged: %s (%s)\n' "$DMG_PATH" "$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
