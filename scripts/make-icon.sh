#!/usr/bin/env bash
set -euo pipefail

# Builds the app icon set from assets/icon.svg using only tools shipped with
# macOS: qlmanage renders the SVG, sips resizes it. Nothing to install.
#
# Re-run after editing assets/icon.svg, then rebuild the app.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$PROJECT_DIR/assets/icon.svg"
ICONSET="$PROJECT_DIR/Sources/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -f "$SVG" ]] || { echo "Not found: $SVG" >&2; exit 1; }

echo "==> Rendering the SVG at 1024x1024"
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
MASTER="$TMP/$(basename "$SVG").png"
[[ -f "$MASTER" ]] || { echo "SVG rendering failed." >&2; exit 1; }

echo "==> Restoring transparent corners"
# qlmanage flattens its output onto an OPAQUE WHITE background, so without this
# step the corners left empty by the SVG's rx="232" come out solid white.
# Invisible in the macOS 26 Dock, which re-masks app icons, but plainly visible
# on macOS 14 and 15 and in the GitHub README, which show the PNG as-is.
swift "$PROJECT_DIR/scripts/round-corners.swift" "$MASTER" "$TMP/master-rounded.png"
MASTER="$TMP/master-rounded.png"

echo "==> Generating the size variants"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512 1024; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}.png" >/dev/null
done

# The README image is produced here so it can no longer drift from the icon:
# it used to be made by hand, which is how it kept the white corners.
cp "$ICONSET/icon_256.png" "$PROJECT_DIR/assets/icon-256.png"

echo "==> Writing the asset catalog"
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
echo "Icon set ready: $ICONSET"
ls -1 "$ICONSET" | sed 's/^/  /'
