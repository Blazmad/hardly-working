#!/usr/bin/env bash
set -euo pipefail

# Publie le contenu de site/ sur la branche gh-pages.
#
# Remplace la manœuvre manuelle « copier index.html, changer de branche,
# coller, revenir » : celle-ci ne copiait qu'un fichier, donc tout fichier
# ajouté au site (favicon, image) restait sur main et renvoyait 404 en ligne.
#
# Passe par un worktree jetable plutôt que par `git checkout gh-pages` :
# la branche courante n'est jamais quittée, donc aucun risque de rester
# coincé sur gh-pages si le script s'interrompt.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE="$PROJECT_DIR/site"
BRANCH="gh-pages"
URL="https://blazmad.github.io/hardly-working/"

cd "$PROJECT_DIR"

[[ -d "$SITE" ]] || { echo "Introuvable : $SITE" >&2; exit 1; }
[[ -f "$SITE/index.html" ]] || { echo "Pas d'index.html dans $SITE" >&2; exit 1; }

WORKTREE="$(mktemp -d)"
cleanup() { git worktree remove --force "$WORKTREE" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> Récupération de $BRANCH"
git fetch origin "$BRANCH" --quiet
git worktree add --quiet "$WORKTREE" "$BRANCH"
git -C "$WORKTREE" reset --hard --quiet "origin/$BRANCH"

echo "==> Copie du site"
# --delete : un fichier retiré de site/ disparaît aussi du site en ligne.
rsync -a --delete --exclude '.git' "$SITE/" "$WORKTREE/"
# .nojekyll dit à GitHub Pages de servir les fichiers tels quels, sans Jekyll.
touch "$WORKTREE/.nojekyll"

git -C "$WORKTREE" add -A
if git -C "$WORKTREE" diff --cached --quiet; then
    echo "==> Rien à publier : le site en ligne est déjà à jour"
    exit 0
fi

echo "==> Publication"
git -C "$WORKTREE" -c user.name="$(git config user.name)" \
                   -c user.email="$(git config user.email)" \
                   commit --quiet -m "chore(site): mise à jour de la landing page"
git -C "$WORKTREE" push --quiet origin "$BRANCH"

echo ""
echo "Publié sur $URL"
git -C "$WORKTREE" log -1 --oneline
