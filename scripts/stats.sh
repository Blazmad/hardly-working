#!/usr/bin/env bash
set -euo pipefail

# Affiche tout ce que GitHub compte déjà gratuitement sur le projet.
# Aucun traceur, aucun compte tiers : ces chiffres existent sans rien installer.
#
# Deux natures de données, à ne pas confondre :
#   - les TÉLÉCHARGEMENTS sont cumulatifs et permanents, comptés depuis la
#     publication de chaque release ;
#   - le TRAFIC est une fenêtre glissante de 14 jours, effacée ensuite par
#     GitHub. Relancer ce script régulièrement est le seul moyen d'en garder
#     une trace.
#
# Ce que ce script ne peut PAS dire : combien de personnes visitent la landing
# page (GitHub Pages ne fournit aucune statistique), ni combien utilisent
# réellement l'app (il faudrait que l'app appelle un serveur).

REPO="Blazmad/hardly-working"

command -v gh >/dev/null || { echo "gh (GitHub CLI) est requis." >&2; exit 1; }

echo "══ TÉLÉCHARGEMENTS ══ (cumulatif depuis la publication)"
gh api "repos/$REPO/releases" --jq '
  .[] | "  \(.tag_name)  \(.published_at[0:10])   \(
    [.assets[].download_count] | add // 0
  ) téléchargements"'

TOTAL=$(gh api "repos/$REPO/releases" --jq '[.[].assets[].download_count] | add // 0')
echo "  ─────────────────────────────────"
echo "  TOTAL toutes versions : $TOTAL"

echo ""
echo "══ TRAFIC DU DÉPÔT ══ (14 derniers jours seulement, puis effacé)"
gh api "repos/$REPO/traffic/views" --jq '
  "  \(.count) vues, \(.uniques) visiteurs uniques"'
gh api "repos/$REPO/traffic/clones" --jq '
  "  \(.count) clones, \(.uniques) cloneurs uniques"'

echo ""
echo "══ D'OÙ VIENNENT LES VISITEURS ══ (14 derniers jours)"
gh api "repos/$REPO/traffic/popular/referrers" --jq '
  if length == 0 then "  (aucune source enregistrée)"
  else .[] | "  \(.referrer)  —  \(.count) vues, \(.uniques) uniques" end'

echo ""
echo "  Rappel : les visites de https://blazmad.github.io/hardly-working/"
echo "  ne sont comptées nulle part. GitHub Pages ne fournit rien."
