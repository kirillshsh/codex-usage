#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRACKER_SRC="$REPO_ROOT/codex_usage_tracker/codex_usage_tracker.py"
TRACKER_DIR="$HOME/.codex/usage_tracker"
TRACKER_DST="$TRACKER_DIR/codex_usage_tracker.py"
TRACKER_CONFIG="$TRACKER_DIR/config.json"
SNAPSHOT_PATH="$TRACKER_DIR/latest_snapshot.json"

APP_DERIVED_DATA="${DERIVED_DATA_PATH:-/tmp/CodexUsageDerivedInstall}"
APP_BUILD_PATH="$APP_DERIVED_DATA/Build/Products/Debug/Codex Usage.app"
APP_INSTALL_DIR="$HOME/Applications"
APP_INSTALL_PATH="$APP_INSTALL_DIR/Codex Usage.app"
APP_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.codex.usage-menubar.plist"
APP_LAUNCH_LABEL="com.codex.usage-menubar"

if [[ ! -f "$TRACKER_SRC" ]]; then
  echo "tracker script not found: $TRACKER_SRC" >&2
  exit 1
fi

mkdir -p "$TRACKER_DIR"
cp "$TRACKER_SRC" "$TRACKER_DST"
chmod +x "$TRACKER_DST"

if [[ ! -f "$TRACKER_CONFIG" ]]; then
  cat > "$TRACKER_CONFIG" <<'JSON'
{
  "session_window_minutes": 300,
  "week_window_minutes": 10080,
  "session_limit_tokens": null,
  "week_limit_tokens": null
}
JSON
fi

python3 "$TRACKER_DST" snapshot --output "$SNAPSHOT_PATH"
python3 "$TRACKER_DST" install-autostart --interval 180 --output "$SNAPSHOT_PATH"

xcodebuild \
  -project "$REPO_ROOT/Codex Usage.xcodeproj" \
  -scheme "Codex Usage" \
  -configuration Debug \
  -derivedDataPath "$APP_DERIVED_DATA" \
  build CODE_SIGNING_ALLOWED=NO > /tmp/codex_usage_build.log

if [[ ! -d "$APP_BUILD_PATH" ]]; then
  echo "built app not found: $APP_BUILD_PATH" >&2
  exit 1
fi

mkdir -p "$APP_INSTALL_DIR"
rm -rf "$APP_INSTALL_PATH"
cp -R "$APP_BUILD_PATH" "$APP_INSTALL_PATH"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$APP_LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$APP_LAUNCH_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>$APP_INSTALL_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$TRACKER_DIR/menubar-launchd.log</string>
  <key>StandardErrorPath</key>
  <string>$TRACKER_DIR/menubar-launchd.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID" "$APP_LAUNCH_AGENT" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$APP_LAUNCH_AGENT"
launchctl enable "gui/$UID/$APP_LAUNCH_LABEL"
launchctl kickstart -k "gui/$UID/$APP_LAUNCH_LABEL" || true

open "$APP_INSTALL_PATH"

echo "installed tracker: $TRACKER_DST"
echo "snapshot autostart: com.codex.usage-tracker"
echo "menu bar app: $APP_INSTALL_PATH"
echo "menu bar autostart: $APP_LAUNCH_LABEL"
