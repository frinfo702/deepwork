#!/bin/sh
# Icon pipeline: Blender scene -> Deepwork.icon -> Assets.car / Deepwork.icns / docs/icon.png
#
#   scripts/icon/build.sh            # compile only (uses the committed layer PNGs)
#   scripts/icon/build.sh --render   # re-render the layers in Blender first (~minutes)
#
# Needs Xcode 26+ (actool and Icon Composer's ictool read .icon). The outputs are
# committed, so CI and plain `./build.sh` never need Blender or a new Xcode.
set -e
cd "$(dirname "$0")/../.."
ICON=Resources/Deepwork.icon
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ "$1" = "--render" ]; then
  blender -b -P scripts/icon/scene.py -- --out "$ICON/Assets" --save scripts/icon/deepwork.blend
fi

# macOS 26+: Liquid Glass icon (light, dark, clear, tinted) compiled from the .icon
xcrun actool "$ICON" --compile "$TMP" --platform macosx --minimum-deployment-target 15.0 \
  --app-icon Deepwork --output-partial-info-plist "$TMP/partial.plist" >/dev/null
cp "$TMP/Assets.car" Resources/Assets.car

# macOS 15 fallback: full-size .icns rendered by Icon Composer, on the classic
# 1024 grid (824 px body, 100 px margin) so it sits right next to other icons.
render() { # size -> png with grid margin
  body=$(( $1 * 824 / 1024 ))
  "$ICTOOL" "$ICON" --export-image --output-file "$TMP/body.png" --platform macOS --rendition Default \
    --width "$body" --height "$body" --scale 1 >/dev/null
  sips --padToHeightWidth "$1" "$1" "$TMP/body.png" --out "$2" >/dev/null
}
mkdir "$TMP/Deepwork.iconset"
for s in 16 32 128 256 512; do
  render $s "$TMP/Deepwork.iconset/icon_${s}x${s}.png"
  render $((s * 2)) "$TMP/Deepwork.iconset/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$TMP/Deepwork.iconset" -o Resources/Deepwork.icns
cp "$TMP/Deepwork.iconset/icon_256x256@2x.png" docs/icon.png
echo "icon: Resources/Assets.car Resources/Deepwork.icns docs/icon.png"
