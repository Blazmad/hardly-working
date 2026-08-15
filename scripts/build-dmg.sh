#!/usr/bin/env bash
set -euo pipefail

# Construit l'app, la signe, la notarise chez Apple et produit le DMG.
#
# Signature et notarisation sont automatiques SI le certificat Developer ID et
# les identifiants de notarisation sont présents sur la machine. Sinon, le script
# se rabat sur la signature de développement et le dit clairement — ainsi il reste
# utilisable par quiconque clone ce dépôt sans compte développeur Apple.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hardly Working"
SCHEME="HardlyWorking"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

# Identité de distribution et profil de notarisation (voir README pour les créer).
DEV_ID="$(security find-identity -v -p codesigning \
          | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
NOTARY_PROFILE="hardly-working"

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

if [[ -n "$DEV_ID" ]]; then
    echo "==> Signature de distribution"
    echo "    $DEV_ID"
    # --options runtime active le « hardened runtime », exigé par la notarisation.
    # --timestamp horodate la signature : sans lui, elle expirerait avec le certificat.
    codesign --force --options runtime --timestamp \
             --sign "$DEV_ID" "$APP_PATH"
else
    echo "==> Aucun certificat Developer ID : on garde la signature de développement"
fi

echo "==> Vérification de la signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# L'app est notarisée et agrafée AVANT d'entrer dans le DMG. Sans cela, le DMG
# contiendrait une app non agrafée : une fois copiée dans /Applications, macOS
# aurait besoin du réseau pour vérifier la notarisation au premier lancement.
if [[ -n "$DEV_ID" ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "==> Notarisation de l'app"
    ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/app-to-notarize.zip"
    xcrun notarytool submit "$BUILD_DIR/app-to-notarize.zip" \
          --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$BUILD_DIR/app-to-notarize.zip"
    xcrun stapler staple "$APP_PATH"
fi

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

if [[ -n "$DEV_ID" ]]; then
    echo "==> Signature du DMG"
    codesign --force --timestamp --sign "$DEV_ID" "$DMG_PATH"

    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "==> Notarisation du DMG"
        xcrun notarytool submit "$DMG_PATH" \
              --keychain-profile "$NOTARY_PROFILE" --wait

        echo "==> Agrafage du ticket"
        # L'agrafage colle le verdict d'Apple dans le fichier lui-même :
        # macOS peut alors le vérifier même sans connexion réseau.
        xcrun stapler staple "$DMG_PATH"

        echo "==> Verdict de Gatekeeper"
        spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
    else
        echo "==> Identifiants de notarisation absents (profil « $NOTARY_PROFILE ») :"
        echo "    DMG signé mais NON notarisé — macOS affichera un avertissement."
    fi
fi

echo ""
echo "DMG prêt : $DMG_PATH"
ls -lh "$DMG_PATH"
