#!/usr/bin/env bash
set -euo pipefail

# Fabrique l'image d'aperçu Open Graph : ce qui s'affiche quand le lien du site
# est collé dans Slack, LinkedIn, iMessage ou X.
#
# Le gabarit est assets/og-image.html, rendu par WebKit. Aucun outil à
# installer : Swift et WebKit sont livrés avec macOS.
#
# 1200×630 est le format attendu par Open Graph. La capture se fait à l'échelle
# de l'écran (×2 sur un Retina), puis redescend à 1200×630 : le texte y gagne
# un anticrénelage que le rendu direct en 1× ne donne pas.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$PROJECT_DIR/assets/og-image.html"
OUT="$PROJECT_DIR/site/og-image.png"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -f "$TEMPLATE" ]] || { echo "Introuvable : $TEMPLATE" >&2; exit 1; }

echo "==> Rendu du gabarit"
swift "$PROJECT_DIR/scripts/render-html.swift" "$TEMPLATE" "$TMP/og.png" 1200 630

echo "==> Mise au format 1200×630"
sips -z 630 1200 "$TMP/og.png" --out "$OUT" >/dev/null

echo ""
echo "Image d'aperçu prête :"
ls -lh "$OUT" | sed 's/^/  /'
