#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hardly Working"
SCHEME="HardlyWorking"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

cd "$PROJECT_DIR"

echo "==> Génération du projet Xcode"
xcodegen generate

echo "==> Construction en Release"
xcodebuild -project HardlyWorking.xcodeproj \
           -scheme "$SCHEME" \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           build

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { echo "App introuvable : $APP_PATH" >&2; exit 1; }

echo "==> Vérification de la signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# Étape future, quand le certificat Developer ID sera disponible :
#   codesign --force --deep --options runtime \
#            --sign "Developer ID Application: ..." "$APP_PATH"
#   xcrun notarytool submit "$DMG_PATH" --keychain-profile "..." --wait
#   xcrun stapler staple "$DMG_PATH"
# Rien d'autre ne change dans ce script.

echo "==> Préparation du contenu du DMG"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Création du DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo ""
echo "DMG prêt : $DMG_PATH"
ls -lh "$DMG_PATH"
