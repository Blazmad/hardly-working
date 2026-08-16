#!/usr/bin/env bash
set -euo pipefail

# Fabrique le favicon du site à partir de assets/favicon.svg.
# Mêmes outils que make-icon.sh, livrés avec macOS : qlmanage, sips.
#
# Pourquoi un SVG distinct de assets/icon.svg : l'icône de l'app est illisible
# en 16 px. Le détail est expliqué en tête de assets/favicon.svg.
#
# Les fichiers produits vont dans site/ et sont versionnés, pour que le site
# reste déployable sans relancer ce script.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$PROJECT_DIR/assets/favicon.svg"
SITE="$PROJECT_DIR/site"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -f "$SVG" ]] || { echo "Introuvable : $SVG" >&2; exit 1; }

echo "==> Rendu du SVG en 1024×1024"
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
MASTER="$TMP/$(basename "$SVG").png"
[[ -f "$MASTER" ]] || { echo "Le rendu du SVG a échoué." >&2; exit 1; }

echo "==> Génération des déclinaisons"
# 16/32 : onglet de navigateur (32 = le même onglet sur écran Retina).
# 180    : « ajouter à l'écran d'accueil » sur iOS.
sips -z 16  16  "$MASTER" --out "$SITE/favicon-16.png"       >/dev/null
sips -z 32  32  "$MASTER" --out "$SITE/favicon-32.png"       >/dev/null
sips -z 180 180 "$MASTER" --out "$SITE/apple-touch-icon.png" >/dev/null

# Le SVG est servi tel quel : les navigateurs qui le gèrent (Chrome, Firefox)
# l'affichent net à n'importe quelle taille. Safari l'ignore et prend le PNG.
cp "$SVG" "$SITE/favicon.svg"

echo ""
echo "Favicon prêt dans $SITE"
ls -l "$SITE"/favicon-16.png "$SITE"/favicon-32.png \
      "$SITE"/apple-touch-icon.png "$SITE"/favicon.svg | sed 's/^/  /'
