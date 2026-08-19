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
REPO="Blazmad/hardly-working"

# Polls the Pages build until it settles. Pushing to gh-pages only queues a
# build; on 2026-08-17 one sat in "building" for two days while this script had
# already printed "Published", so the live site stayed stale and nothing said so.
# A wedged build is re-requested once - that unstuck the real one in 30 seconds.
wait_for_pages_build() {
    local limit="${1:-40}" build_status retried=0 i=0
    while (( i < limit )); do
        build_status="$(gh api "repos/$REPO/pages/builds" --jq '.[0].status' 2>/dev/null)"
        case "$build_status" in
            built)   return 0 ;;
            errored) echo "Pages build errored" >&2; return 1 ;;
        esac
        if (( i == limit / 2 )) && (( retried == 0 )); then
            echo "==> Build still pending, re-requesting it"
            gh api -X POST "repos/$REPO/pages/builds" >/dev/null 2>&1
            retried=1
        fi
        i=$(( i + 1 ))
        sleep 15
    done
    echo "Pages build never completed - the live site may be stale" >&2
    return 1
}

# Confirms the bytes actually served match what we pushed. The build reporting
# "built" is not proof: CDN caches, and a wrong file would still be "built".
live_site_matches() {
    local url="$1" reference="$2" attempts="${3:-8}" want served i
    want="$(shasum -a 256 < "$reference" | cut -d" " -f1)"
    for (( i = 0; i < attempts; i++ )); do
        served="$(curl -fsS -H 'Cache-Control: no-cache' "$url?v=$i" \
                  | shasum -a 256 | cut -d" " -f1)"
        [[ "$served" == "$want" ]] && return 0
        sleep 15
    done
    echo "Live page still differs from what was pushed" >&2
    return 1
}

cd "$PROJECT_DIR"

[[ -d "$SITE" ]] || { echo "Not found: $SITE" >&2; exit 1; }
[[ -f "$SITE/index.html" ]] || { echo "No index.html in $SITE" >&2; exit 1; }

# rsync publishes site/ from DISK, not from git: an untracked or git-ignored
# file dropped there (a stray credential, say) would go live on gh-pages.
STRAY="$(git status --porcelain --ignored -- "$SITE" | grep -E '^(\?\?|!!)' | grep -v '\.DS_Store' || true)"
if [[ -n "$STRAY" ]]; then
    echo "site/ contains files unknown to git - commit or remove them first:" >&2
    echo "$STRAY" >&2
    exit 1
fi

WORKTREE="$(mktemp -d)"
cleanup() { git worktree remove --force "$WORKTREE" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> Fetching $BRANCH"
git fetch origin "$BRANCH" --quiet
# The reset below rewinds the local branch ref: unpushed local commits on
# gh-pages would vanish silently (recoverable only via reflog until expiry).
if [[ -n "$(git rev-list "origin/$BRANCH..$BRANCH" 2>/dev/null)" ]]; then
    echo "Local $BRANCH has unpushed commits - push or drop them first" >&2
    exit 1
fi
git worktree add --quiet "$WORKTREE" "$BRANCH"
git -C "$WORKTREE" reset --hard --quiet "origin/$BRANCH"

echo "==> Copying the site"
# --delete: a file removed from site/ also disappears from the live site.
rsync -a --delete --exclude '.git' --exclude '.DS_Store' "$SITE/" "$WORKTREE/"
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

echo "==> Waiting for the Pages build"
wait_for_pages_build || exit 1

echo "==> Checking what is actually served"
live_site_matches "$URL" "$SITE/index.html" || exit 1

echo ""
echo "Published and verified live at $URL"
git -C "$WORKTREE" log -1 --oneline
