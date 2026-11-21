#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

CONFIGURATION="${1:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
UNIVERSAL="${UNIVERSAL:-0}"

BUILD_ARGS=(-c "$CONFIGURATION")
if [[ "$UNIVERSAL" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_ARGS[@]}"
BINARY_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$PROJECT_DIR/build/LiteMouse.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_DIR/LiteMouse" "$APP_DIR/Contents/MacOS/LiteMouse"

swift scripts/make-icon.swift "$PROJECT_DIR/build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/LiteMouseIcon.icns"
rm -rf "$PROJECT_DIR/build/AppIcon.iconset"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>LiteMouse</string>
<key>CFBundleDisplayName</key><string>LiteMouse</string>
<key>CFBundleIdentifier</key><string>local.litemouse.app</string>
<key>CFBundleExecutable</key><string>LiteMouse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
<key>CFBundleIconFile</key><string>LiteMouseIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf 'Built: %s (v%s, arch: %s)\n' "$APP_DIR" "$VERSION" "$(lipo -archs "$APP_DIR/Contents/MacOS/LiteMouse")"
