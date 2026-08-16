#!/bin/bash
# Cuts a release:  ./release.sh 1.2
#
# Bumps the version, builds and signs, notarizes, staples, publishes to GitHub,
# and updates the Homebrew cask. The in-app update check compares against the
# release tag, so the version in Info.plist and the tag have to move together.
# That is the whole reason this is a script and not a checklist.
#
# Notarization needs credentials stored once:
#   xcrun notarytool store-credentials "twistpad" \
#       --apple-id "<your-apple-id>" --team-id J4C774VXXC
set -euo pipefail

cd "$(dirname "$0")"

APP="TwistPad.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-twistpad}"
TAP_REPO="https://github.com/Toxic880/homebrew-tap.git"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
	echo "usage: ./release.sh <version>      e.g. ./release.sh 1.2" >&2
	exit 1
fi
VERSION="${VERSION#v}"

if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
	echo "error: version should look like 1.1 or 1.2.3, got '$VERSION'" >&2
	exit 1
fi

PLIST="Resources/Info.plist"
CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"

if [[ "$CURRENT" == "$VERSION" ]]; then
	echo "error: Info.plist is already $VERSION. Pick a higher version." >&2
	exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
	echo "error: not logged in. Run: gh auth login" >&2
	exit 1
fi

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
	echo "error: tag v$VERSION already exists." >&2
	exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
	cat >&2 <<-EOF
	error: no notarization credentials for profile '$NOTARY_PROFILE'.

	Store them once with:
	  xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
	      --apple-id "<your-apple-id>" --team-id J4C774VXXC

	It asks for an app-specific password, which you create at
	appleid.apple.com under Sign-In and Security. Not your Apple password.
	EOF
	exit 1
fi

echo "==> $CURRENT -> $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"

./build.sh

if ! codesign -dv --verbose=4 "$APP" 2>&1 | grep -q "Developer ID Application"; then
	echo "error: $APP is not signed with a Developer ID. Notarization will fail." >&2
	exit 1
fi

ZIP="TwistPad-$VERSION.zip"
rm -f "$ZIP"
# ditto, not zip: it preserves the bundle structure and the signature.
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notarizing (a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

# Staple the ticket into the bundle so it validates offline, then re-zip. The
# submitted archive does not contain the ticket; only the stapled app does.
echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "==> packaged $ZIP ($(du -h "$ZIP" | cut -f1), sha256 ${SHA:0:16}…)"

# Prove Gatekeeper accepts it before anyone downloads it.
echo "==> Gatekeeper check"
spctl --assess --type execute --verbose=2 "$APP"

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
{
	echo "Download \`$ZIP\`, unzip it, and drag TwistPad to Applications."
	echo
	echo "Or with Homebrew:"
	echo
	echo '```bash'
	echo "brew install --cask Toxic880/tap/twistpad"
	echo '```'
	echo
	echo "Signed and notarized by Apple, so it opens without any warnings."
	echo
	echo "## Changes"
	echo
	PREV_TAG="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
	if [[ -n "$PREV_TAG" ]]; then
		git log --no-merges --pretty="- %s" "$PREV_TAG"..HEAD
	else
		git log --no-merges --pretty="- %s" -20
	fi | grep -v "^- Release " || true
} >"$NOTES"

git add -A
git commit -q -m "Release $VERSION"
git push -q origin main

gh release create "v$VERSION" "$ZIP" \
	--title "TwistPad $VERSION" \
	--notes-file "$NOTES"

echo "==> Updating Homebrew cask"
TAP_DIR="$(mktemp -d)"
if git clone -q "$TAP_REPO" "$TAP_DIR" 2>/dev/null; then
	CASK="$TAP_DIR/Casks/twistpad.rb"
	sed -i '' "s|^  version \".*\"|  version \"$VERSION\"|" "$CASK"
	sed -i '' "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" "$CASK"
	git -C "$TAP_DIR" config user.name "Toxic880"
	git -C "$TAP_DIR" config user.email "cooledtechbusiness@gmail.com"
	git -C "$TAP_DIR" commit -qam "twistpad $VERSION"
	git -C "$TAP_DIR" push -q
	echo "    cask now points at $VERSION"
else
	echo "    warning: could not update the tap. Bump Casks/twistpad.rb by hand." >&2
fi
rm -rf "$TAP_DIR"

echo "==> published https://github.com/Toxic880/TwistPad/releases/tag/v$VERSION"
echo "    Existing installs will notice within 24 hours."
