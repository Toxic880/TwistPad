#!/bin/bash
# Cuts a release:  ./release.sh 1.1
#
# Bumps the version, builds, zips the bundle, tags, and publishes to GitHub.
# The in-app update check compares against the release tag, so the version in
# Info.plist and the tag have to move together. That is the whole reason this
# is a script and not a checklist.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
	echo "usage: ./release.sh <version>      e.g. ./release.sh 1.1" >&2
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

echo "==> $CURRENT -> $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"

./build.sh

ZIP="TwistPad-$VERSION.zip"
rm -f "$ZIP"
# ditto, not zip: it preserves the bundle structure and the signature.
ditto -c -k --keepParent TwistPad.app "$ZIP"
echo "==> packaged $ZIP ($(du -h "$ZIP" | cut -f1))"

git add -A
git commit -q -m "Release $VERSION"
git push -q origin main

# Notes are built here rather than with --generate-notes, which conflicts with
# --notes on some gh versions. A half-created release is painful to recover.
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
{
	echo "Download \`$ZIP\`, unzip it, and drag TwistPad to Applications."
	echo
	echo "### macOS will block it on first launch"
	echo
	echo "TwistPad is not notarized, so you will see *\"Apple could not verify"
	echo "TwistPad.app is free of malware\"*. Click **Done**, not Move to Bin, then:"
	echo
	echo "**System Settings > Privacy & Security**, scroll to Security, and click"
	echo "**Open Anyway** next to TwistPad. Open the app again and confirm."
	echo
	echo "Or in Terminal:"
	echo
	echo '```bash'
	echo "xattr -dr com.apple.quarantine /Applications/TwistPad.app"
	echo '```'
	echo
	echo "Right click then Open no longer works on macOS 15 and later."
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

gh release create "v$VERSION" "$ZIP" \
	--title "TwistPad $VERSION" \
	--notes-file "$NOTES"

echo "==> published https://github.com/Toxic880/TwistPad/releases/tag/v$VERSION"
echo "    Existing installs will notice within 24 hours."
