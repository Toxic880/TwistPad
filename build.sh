#!/bin/bash
# Builds TwistPad.app. SwiftPM only emits a bare binary, but the app needs a real
# bundle for LSUIElement, a bundle identifier, and a signature for SMAppService.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TwistPad"
CONFIG="${1:-release}"
APP="$APP_NAME.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BINARY" ]]; then
	echo "error: expected binary at $BINARY" >&2
	exit 1
fi

echo "==> Assembling $APP"
pkill -x "$APP_NAME" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Built $(pwd)/$APP"
echo "    Run it with:  open $APP"
