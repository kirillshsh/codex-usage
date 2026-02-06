#!/usr/bin/env bash
set -euo pipefail

TRACKER_DIR="$HOME/.codex/usage_tracker"
TRACKER_DST="$TRACKER_DIR/codex_usage_tracker.py"
TRACKER_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.codex.usage-tracker.plist"
MENU_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.codex.usage-menubar.plist"

if [[ -f "$TRACKER_DST" ]]; then
  python3 "$TRACKER_DST" uninstall-autostart --plist "$TRACKER_LAUNCH_AGENT" || true
fi

launchctl bootout "gui/$UID" "$MENU_LAUNCH_AGENT" >/dev/null 2>&1 || true
rm -f "$MENU_LAUNCH_AGENT"

echo "removed launch agents for codex tracker and menu bar app"
