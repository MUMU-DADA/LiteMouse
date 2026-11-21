#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$PROJECT_DIR/scripts/build-app.sh" release

if pgrep -x LiteMouse >/dev/null 2>&1; then
    pkill -x LiteMouse || true
    sleep 0.5
fi

rm -rf /Applications/LiteMouse.app
ditto "$PROJECT_DIR/build/LiteMouse.app" /Applications/LiteMouse.app
codesign --verify --deep --strict /Applications/LiteMouse.app
printf 'Installed: /Applications/LiteMouse.app\n'
