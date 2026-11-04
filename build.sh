#!/bin/sh
# Builds build/Deepwork.app and build/Deepwork.zip (upload the zip to a GitHub Release).
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}
VERSION=${VERSION:-0.0.0}
APP=build/Deepwork.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 -target $arch-apple-macos15.0 Sources/*.swift -o build/Deepwork-$arch
done
lipo -create build/Deepwork-arm64 build/Deepwork-x86_64 -output "$APP/Contents/MacOS/Deepwork" && rm build/Deepwork-*
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.frinfo702.deepwork</string>
  <key>CFBundleName</key><string>Deepwork</string>
  <key>CFBundleDisplayName</key><string>Deepwork</string>
  <key>CFBundleExecutable</key><string>Deepwork</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Deepwork checks which site is open in Dia during focus time.</string>
</dict></plist>
EOF
codesign -s - --force "$APP"
ditto -c -k --keepParent "$APP" build/Deepwork.zip
echo "built $APP and build/Deepwork.zip"
