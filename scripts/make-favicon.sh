#!/usr/bin/env bash
set -euo pipefail

# Builds the site favicon from assets/favicon.svg, using the same macOS-only
# tools as make-icon.sh: qlmanage and sips.
#
# The favicon has its own SVG because the app icon is unreadable at 16 px.
# The reasoning is at the top of assets/favicon.svg.
#
# The generated files live in site/ and are versioned, so the site stays
# deployable without re-running this script.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$PROJECT_DIR/assets/favicon.svg"
SITE="$PROJECT_DIR/site"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -f "$SVG" ]] || { echo "Not found: $SVG" >&2; exit 1; }

echo "==> Rendering the SVG at 1024x1024"
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
MASTER="$TMP/$(basename "$SVG").png"
[[ -f "$MASTER" ]] || { echo "SVG rendering failed." >&2; exit 1; }

echo "==> Restoring transparent corners"
# Same flattening as for the app icon: white corners are immediately obvious
# against a dark browser tab strip.
swift "$PROJECT_DIR/scripts/round-corners.swift" "$MASTER" "$TMP/master-rounded.png"
MASTER="$TMP/master-rounded.png"

echo "==> Generating the size variants"
# 16 and 32 for the browser tab (32 being that same tab on a Retina display),
# 180 for "Add to Home Screen" on iOS.
sips -z 16  16  "$MASTER" --out "$SITE/favicon-16.png"       >/dev/null
sips -z 32  32  "$MASTER" --out "$SITE/favicon-32.png"       >/dev/null
sips -z 180 180 "$MASTER" --out "$SITE/apple-touch-icon.png" >/dev/null

# The SVG is served as-is: browsers that support it (Chrome, Firefox) render it
# crisply at any size. Safari ignores it and falls back to the PNGs.
cp "$SVG" "$SITE/favicon.svg"

echo ""
echo "Favicon ready in $SITE"
ls -l "$SITE"/favicon-16.png "$SITE"/favicon-32.png \
      "$SITE"/apple-touch-icon.png "$SITE"/favicon.svg | sed 's/^/  /'
