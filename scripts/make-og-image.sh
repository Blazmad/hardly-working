#!/usr/bin/env bash
set -euo pipefail

# Builds the Open Graph preview image: what shows up when the site link is
# pasted into Slack, LinkedIn, iMessage or X.
#
# The template is assets/og-image.html, rendered through WebKit. Nothing to
# install: Swift and WebKit ship with macOS.
#
# 1200x630 is the size Open Graph expects. The snapshot is taken at the screen
# scale (2x on a Retina display) and then scaled down, which antialiases the
# text better than rendering straight at 1x.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$PROJECT_DIR/assets/og-image.html"
OUT="$PROJECT_DIR/site/og-image.png"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -f "$TEMPLATE" ]] || { echo "Not found: $TEMPLATE" >&2; exit 1; }

echo "==> Rendering the template"
swift "$PROJECT_DIR/scripts/render-html.swift" "$TEMPLATE" "$TMP/og.png" 1200 630

echo "==> Scaling to 1200x630"
sips -z 630 1200 "$TMP/og.png" --out "$OUT" >/dev/null

echo ""
echo "Preview image ready:"
ls -lh "$OUT" | sed 's/^/  /'
