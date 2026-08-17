#!/usr/bin/env bash
set -euo pipefail

# Builds the app, signs it, has Apple notarize it and produces the DMG.
#
# Signing and notarization happen automatically IF the Developer ID certificate
# and the notarization credentials are present on the machine. Otherwise the
# script falls back to the development signature and says so clearly, so it
# stays usable by anyone cloning this repository without an Apple developer
# account.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hardly Working"
SCHEME="HardlyWorking"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

# Distribution identity and notarization profile (see README to create them).
DEV_ID="$(security find-identity -v -p codesigning \
          | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
NOTARY_PROFILE="hardly-working"

cd "$PROJECT_DIR"

# Checked BEFORE the build so a broken credential costs a second, not a build.
# A Developer ID signature without notarization is the worst outcome: macOS
# shows a dialog with no Open button, so refuse to produce one by accident.
# One probe only - it authenticates against Apple, so it is not free.
NOTARIZE=0
if [[ -n "$DEV_ID" ]]; then
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        NOTARIZE=1
    elif [[ "${SKIP_NOTARIZATION:-}" == "1" ]]; then
        echo "==> SKIP_NOTARIZATION=1: the DMG will be signed but NOT notarized"
    else
        echo "Notarization profile \"$NOTARY_PROFILE\" is missing or rejected." >&2
        echo "Recreate it with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\"" >&2
        echo "Or re-run with SKIP_NOTARIZATION=1 to build without notarizing." >&2
        exit 1
    fi
fi

echo "==> Generating the Xcode project"
xcodegen generate

echo "==> Building in Release"
xcodebuild -project HardlyWorking.xcodeproj \
           -scheme "$SCHEME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           build

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { echo "App not found: $APP_PATH" >&2; exit 1; }

if [[ -n "$DEV_ID" ]]; then
    echo "==> Distribution signature"
    echo "    $DEV_ID"
    # --options runtime enables the hardened runtime, which notarization requires.
    # --timestamp timestamps the signature: without it, it would expire with the
    # certificate.
    codesign --force --options runtime --timestamp \
             --sign "$DEV_ID" "$APP_PATH"
else
    echo "==> No Developer ID certificate: keeping the development signature"
fi

echo "==> Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# The app is notarized and stapled BEFORE it goes into the DMG. Otherwise the
# DMG would hold an unstapled app, and once copied to /Applications macOS would
# need network access to verify the notarization on first launch.
if [[ "$NOTARIZE" == 1 ]]; then
    echo "==> Notarizing the app"
    ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/app-to-notarize.zip"
    xcrun notarytool submit "$BUILD_DIR/app-to-notarize.zip" \
          --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$BUILD_DIR/app-to-notarize.zip"
    xcrun stapler staple "$APP_PATH"
fi

echo "==> Preparing the DMG contents"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating the DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

if [[ -n "$DEV_ID" ]]; then
    echo "==> Signing the DMG"
    codesign --force --timestamp --sign "$DEV_ID" "$DMG_PATH"

    if [[ "$NOTARIZE" == 1 ]]; then
        echo "==> Notarizing the DMG"
        xcrun notarytool submit "$DMG_PATH" \
              --keychain-profile "$NOTARY_PROFILE" --wait

        echo "==> Stapling the ticket"
        # Stapling glues Apple's verdict into the file itself, so macOS can check
        # it even without a network connection.
        xcrun stapler staple "$DMG_PATH"

        echo "==> Gatekeeper verdict"
        spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
    else
        echo "==> DMG signed but NOT notarized - macOS will show a warning."
    fi
fi

echo ""
echo "DMG ready: $DMG_PATH"
ls -lh "$DMG_PATH"
# Paste this line into the release notes: GitHub release assets are mutable,
# a published SHA-256 is the only out-of-band integrity reference users get.
# Bare filename on purpose - an absolute path would leak the local username.
(cd "$DIST_DIR" && shasum -a 256 "${DMG_PATH##*/}")
