#!/usr/bin/env bash
# Builds Nextlet.app into mac/build/. Works with just the Xcode Command Line Tools.
#   ./scripts/build-app.sh            release build
#   ./scripts/build-app.sh debug      debug build
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-release}"
version="0.1.0"
app="build/Nextlet.app"

swift build -c "$config"
binary="$(swift build -c "$config" --show-bin-path)/Nextlet"

if [[ ! -f build/AppIcon.icns ]]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
  rm -rf build/AppIcon.iconset
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Fonts"
cp "$binary" "$app/Contents/MacOS/Nextlet"
cp Resources/Fonts/*.woff2 Resources/Fonts/*.txt "$app/Contents/Resources/Fonts/"
cp build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Nextlet</string>
  <key>CFBundleDisplayName</key><string>Nextlet</string>
  <key>CFBundleIdentifier</key><string>app.nextlet.mac</string>
  <key>CFBundleExecutable</key><string>Nextlet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Nextlet</string>
  <!-- The server address is yours to choose, and self-hosted servers often use plain http. -->
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS runs it locally. Use your Developer ID to distribute it.
codesign --force --sign - --timestamp=none "$app" >/dev/null
echo "Built $(pwd)/$app"
