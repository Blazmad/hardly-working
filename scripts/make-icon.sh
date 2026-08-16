#!/usr/bin/env bash
set -euo pipefail

# Fabrique le jeu d'icônes de l'app à partir de assets/icon.svg.
# N'utilise que des outils livrés avec macOS : qlmanage (rendu SVG),
# sips (redimensionnement). Aucune dépendance à installer.
#
# À relancer après toute modification de assets/icon.svg, puis reconstruire.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$PROJECT_DIR/assets/icon.svg"
ICONSET="$PROJECT_DIR/Sources/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -f "$SVG" ]] || { echo "Introuvable : $SVG" >&2; exit 1; }

echo "==> Rendu du SVG en 1024×1024"
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
MASTER="$TMP/$(basename "$SVG").png"
[[ -f "$MASTER" ]] || { echo "Le rendu du SVG a échoué." >&2; exit 1; }

echo "==> Restitution des coins transparents"
# qlmanage aplatit le rendu sur un fond BLANC OPAQUE : sans cette étape, les
# coins arrondis du rx="232" sortent en blanc plein. Invisible dans le Dock de
# macOS 26 (qui remasque les icônes), bien visible sur macOS 14/15 et dans le
# README GitHub, qui affichent le PNG tel quel.
swift "$PROJECT_DIR/scripts/round-corners.swift" "$MASTER" "$TMP/master-rounded.png"
MASTER="$TMP/master-rounded.png"

echo "==> Génération des déclinaisons"
mkdir -p "$ICONSET"
# macOS attend ces dix tailles : 16/32/128/256/512 points, chacune en 1x et 2x.
for size in 16 32 64 128 256 512 1024; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}.png" >/dev/null
done

# Image du README. Produite ici pour qu'elle ne diverge plus de l'icône :
# elle avait été fabriquée à la main, donc gardait les coins blancs.
cp "$ICONSET/icon_256.png" "$PROJECT_DIR/assets/icon-256.png"

echo "==> Écriture du catalogue"
cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16",     "scale" : "1x", "filename" : "icon_16.png" },
    { "idiom" : "mac", "size" : "16x16",     "scale" : "2x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",     "scale" : "1x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",     "scale" : "2x", "filename" : "icon_64.png" },
    { "idiom" : "mac", "size" : "128x128",   "scale" : "1x", "filename" : "icon_128.png" },
    { "idiom" : "mac", "size" : "128x128",   "scale" : "2x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256",   "scale" : "1x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256",   "scale" : "2x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512",   "scale" : "1x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512",   "scale" : "2x", "filename" : "icon_1024.png" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
JSON

cat > "$PROJECT_DIR/Sources/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "version" : 1, "author" : "xcode" } }
JSON

echo ""
echo "Jeu d'icônes prêt : $ICONSET"
ls -1 "$ICONSET" | sed 's/^/  /'
