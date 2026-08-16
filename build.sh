#!/bin/bash
# Builds TwistPad.app. SwiftPM only emits a bare binary, but the app needs a real
# bundle for LSUIElement, a bundle identifier, and a signature for SMAppService.
#
# Signs with a Developer ID if one is available, otherwise ad-hoc so that anyone
# can still build from source. Release builds need the real identity, since
# notarization will not accept an ad-hoc signature.
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

ALL_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
DETECTED="$(printf '%s\n' "$ALL_IDENTITIES" | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)"
IDENTITY="${CODESIGN_IDENTITY:-$DETECTED}"

if [[ -n "$IDENTITY" ]]; then
	echo "==> Signing: $IDENTITY"
	# Hardened runtime is required for notarization. TwistPad dlopens
	# MultitouchSupport, which is Apple-signed, so library validation permits it
	# without needing an exemption entitlement.
	codesign --force --options runtime --timestamp \
		--sign "$IDENTITY" "$APP"
	codesign --verify --strict --verbose=1 "$APP"
else
	echo "==> Signing (ad-hoc, no Developer ID found)"
	codesign --force --sign - "$APP"
fi

echo "==> Built $(pwd)/$APP"
echo "    Run it with:  open $APP"
