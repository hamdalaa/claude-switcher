#!/bin/zsh
# Builds dist/Claude Switcher.app — universal (Apple silicon + Intel), ad-hoc signed — and a
# release zip. No Xcode needed: each architecture is built separately and merged with lipo.
#   scripts/bundle.sh             build the app + zip
#   scripts/bundle.sh --install   also copy it to /Applications and launch it
set -euo pipefail
cd "${0:A:h}/.."

VERSION=$(sed -n 's/^CCX_VERSION="\(.*\)"/\1/p' cli/ccx)
APP="dist/Claude Switcher.app"
BIN=ClaudeSwitcher

for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx15.0"
done
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/$BIN" \
  ".build/arm64-apple-macosx/release/$BIN" ".build/x86_64-apple-macosx/release/$BIN"
install -m 755 cli/ccx "$APP/Contents/Resources/ccx"
install -m 755 cli/statusline.sh "$APP/Contents/Resources/statusline.sh"

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude Switcher</string>
  <key>CFBundleDisplayName</key><string>Claude Switcher</string>
  <key>CFBundleIdentifier</key><string>io.github.hamdalaa.ClaudeSwitcher</string>
  <key>CFBundleExecutable</key><string>$BIN</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Claude Switcher opens new iTerm2 windows for your Claude Code sessions.</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with Anthropic or OpenAI.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

ZIP="dist/Claude-Switcher-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/$BIN"))"

if [[ "${1:-}" == --install ]]; then
  pkill -x "$BIN" 2>/dev/null || true
  while pgrep -x "$BIN" >/dev/null; do sleep 0.3; done
  rm -rf "/Applications/Claude Switcher.app"
  cp -R "$APP" /Applications/
  # Clean env (no inherited Claude session vars). LaunchServices can briefly report -600 right
  # after the old copy exits, so retry a few times.
  for attempt in 1 2 3 4 5; do
    env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin /usr/bin/open "/Applications/Claude Switcher.app" 2>/dev/null && break
    sleep 1
  done
  echo "Installed and launched /Applications/Claude Switcher.app"
fi
