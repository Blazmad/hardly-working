#!/usr/bin/env bash
set -euo pipefail

# Prints everything GitHub already counts about this project for free.
# No tracker, no third-party account: these numbers exist without installing
# anything.
#
# Two different kinds of data, not to be confused:
#   - DOWNLOADS are cumulative and permanent, counted since each release was
#     published;
#   - TRAFFIC is a rolling 14-day window that GitHub then discards. Running this
#     script regularly is the only way to keep a record of it.
#
# What this script cannot tell you: how many people visit the landing page
# (GitHub Pages provides no statistics), nor how many actually use the app
# (that would require the app to call home).

REPO="Blazmad/hardly-working"

command -v gh >/dev/null || { echo "gh (GitHub CLI) is required." >&2; exit 1; }

echo "== DOWNLOADS == (cumulative since publication)"
gh api "repos/$REPO/releases" --jq '
  .[] | "  \(.tag_name)  \(.published_at[0:10])   \(
    [.assets[].download_count] | add // 0
  ) downloads"'

TOTAL=$(gh api "repos/$REPO/releases" --jq '[.[].assets[].download_count] | add // 0')
echo "  ---------------------------------"
echo "  TOTAL across all versions: $TOTAL"

echo ""
echo "== REPOSITORY TRAFFIC == (last 14 days only, then discarded)"
gh api "repos/$REPO/traffic/views" --jq '
  "  \(.count) views, \(.uniques) unique visitors"'
gh api "repos/$REPO/traffic/clones" --jq '
  "  \(.count) clones, \(.uniques) unique cloners"'

echo ""
echo "== WHERE VISITORS COME FROM == (last 14 days)"
gh api "repos/$REPO/traffic/popular/referrers" --jq '
  if length == 0 then "  (no referrer recorded)"
  else .[] | "  \(.referrer)  -  \(.count) views, \(.uniques) unique" end'

echo ""
echo "  Note: visits to https://blazmad.github.io/hardly-working/ are counted"
echo "  nowhere. GitHub Pages provides nothing."
