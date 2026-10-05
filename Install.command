#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source_app="$PWD/Codex Touch Bar.app"
destination="$HOME/Applications/Codex Touch Bar.app"
plist="$HOME/Library/LaunchAgents/local.codex.touchbar.plist"
domain="gui/$(id -u)"
if [ ! -x "$source_app/Contents/MacOS/CodexTouchBar" ]; then
  echo "Download the release ZIP and extract it before running Install.command."
  exit 1
fi
codesign --verify --strict "$source_app"
if launchctl print "$domain/local.codex.touchbar" >/dev/null 2>&1; then
  launchctl bootout "$domain/local.codex.touchbar"
fi
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
ditto --norsrc "$source_app" "$destination"
temporary_plist=$(mktemp "${TMPDIR:-/tmp/}codex-touchbar-plist.XXXXXX")
trap 'rm -f "$temporary_plist"' EXIT
plutil -create xml1 "$temporary_plist"
plutil -insert Label -string local.codex.touchbar "$temporary_plist"
plutil -insert ProgramArguments -json '[]' "$temporary_plist"
plutil -insert ProgramArguments.0 -string "$destination/Contents/MacOS/CodexTouchBar" "$temporary_plist"
plutil -insert RunAtLoad -bool YES "$temporary_plist"
plutil -insert ProcessType -string Interactive "$temporary_plist"
plutil -insert LimitLoadToSessionType -string Aqua "$temporary_plist"
plutil -lint "$temporary_plist"
cp "$temporary_plist" "$plist"
chmod 644 "$plist"
launchctl bootstrap "$domain" "$plist"
echo "Installed. Open ChatGPT or Codex to see your limits."
echo "Choose CX → Оформление in the menu bar to change the Touch Bar style."
