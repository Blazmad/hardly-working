#!/usr/bin/env bash
set -euo pipefail

# Publishes the contents of site/ to the gh-pages branch.
#
# Replaces the manual "copy index.html, switch branch, paste, switch back"
# routine: that one copied a single file, so anything else added to the site
# (favicon, images) stayed on main and returned 404 once live.
#
# Uses a throwaway worktree rather than `git checkout gh-pages`, so the current
# branch is never left behind if the script is interrupted.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE="$PROJECT_DIR/site"
BRANCH="gh-pages"
URL="https://blazmad.github.io/hardly-working/"

cd "$PROJECT_DIR"

[[ -d "$SITE" ]] || { echo "Not found: $SITE" >&2; exit 1; }
[[ -f "$SITE/index.html" ]] || { echo "No index.html in $SITE" >&2; exit 1; }

WORKTREE="$(mktemp -d)"
cleanup() { git worktree remove --force "$WORKTREE" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> Fetching $BRANCH"
git fetch origin "$BRANCH" --quiet
git worktree add --quiet "$WORKTREE" "$BRANCH"
git -C "$WORKTREE" reset --hard --quiet "origin/$BRANCH"

echo "==> Copying the site"
# --delete: a file removed from site/ also disappears from the live site.
rsync -a --delete --exclude '.git' "$SITE/" "$WORKTREE/"
# .nojekyll tells GitHub Pages to serve the files as-is, without running Jekyll.
touch "$WORKTREE/.nojekyll"

git -C "$WORKTREE" add -A
if git -C "$WORKTREE" diff --cached --quiet; then
    echo "==> Nothing to publish: the live site is already up to date"
    exit 0
fi

echo "==> Publishing"
git -C "$WORKTREE" -c user.name="$(git config user.name)" \
                   -c user.email="$(git config user.email)" \
                   commit --quiet -m "chore(site): update the landing page"
git -C "$WORKTREE" push --quiet origin "$BRANCH"

echo ""
echo "Published to $URL"
git -C "$WORKTREE" log -1 --oneline
