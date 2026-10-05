#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
root="$PWD"
build_root=$(mktemp -d /private/tmp/codex-touchbar.XXXXXX)
trap 'rm -rf "$build_root"' EXIT
app="$build_root/Codex Touch Bar.app"
mkdir -p "$app/Contents/MacOS" "$root/dist"
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun clang -arch arm64 -arch x86_64 -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
  -framework AppKit src/main.m -o "$app/Contents/MacOS/CodexTouchBar"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codex.touchbar</string>
<key>CFBundleName</key><string>Codex Touch Bar</string>
<key>CFBundleExecutable</key><string>CodexTouchBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.1</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
"$app/Contents/MacOS/CodexTouchBar" --self-test
"$app/Contents/MacOS/CodexTouchBar" --preview "$root/assets/touchbar-preview.png"
cp Install.command Uninstall.command "$build_root/"
cp README.md README.ru.md "$build_root/"
mkdir -p "$build_root/assets"
cp assets/touchbar-preview.png "$build_root/assets/"
chmod +x "$build_root/Install.command" "$build_root/Uninstall.command"
ditto --norsrc -c -k "$build_root" "$root/dist/CodexTouchBar-v1.2.1-universal.zip"
(cd "$root/dist" && shasum -a 256 CodexTouchBar-v1.2.1-universal.zip > SHA256SUMS.txt)
echo "Built dist/CodexTouchBar-v1.2.1-universal.zip"
