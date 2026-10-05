#!/bin/bash
set -euo pipefail
domain="gui/$(id -u)"
if launchctl print "$domain/local.codex.touchbar" >/dev/null 2>&1; then
  launchctl bootout "$domain/local.codex.touchbar"
fi
rm -f "$HOME/Library/LaunchAgents/local.codex.touchbar.plist"
echo "Autostart disabled."
echo "To remove the app, move ~/Applications/Codex Touch Bar.app to the Trash."
echo "Your Codex account, chats and settings have not been removed."
