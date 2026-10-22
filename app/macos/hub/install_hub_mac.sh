#!/bin/bash
# Installs (or updates) the LiveNow sync hub on a Mac: an always-on background
# copy of the app (`--hub`, no window, no Dock icon) started at login by launchd.
# Run it again after every new LiveNow build: it replaces the copy.
#
#   ./install_hub_mac.sh [/path/to/LiveNow.app]      (default /Applications/LiveNow.app)
#
# Why a COPY with its own bundle id: macOS runs one process per app bundle, so a
# hub started from the same LiveNow.app would stop you from opening the window
# (and the other way round). The copy is "LiveNow Hub.app", id io.livenow.hub.
# It keeps its data in the SAME folder the window looks in
# (~/Library/Application Support/io.livenow.livenow/hub), so the window can find
# the hub's pairing text ("Connect to the local hub").
set -euo pipefail

SRC="${1:-/Applications/LiveNow.app}"
[ -d "$SRC" ] || { echo "LiveNow.app not found at: $SRC"; exit 1; }

LABEL="io.livenow.hub"
HUB_ROOT="$HOME/Library/Application Support/LiveNowHub"
DEST="$HUB_ROOT/LiveNow Hub.app"
DATA_DIR="$HOME/Library/Application Support/io.livenow.livenow/hub"
LOG_DIR="$HOME/Library/Logs/LiveNowHub"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"
PB=/usr/libexec/PlistBuddy

mkdir -p "$HUB_ROOT" "$DATA_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"

# Stop a running hub before its files are replaced.
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true

rm -rf "$DEST"
ditto "$SRC" "$DEST"
$PB -c "Set :CFBundleIdentifier $LABEL" "$DEST/Contents/Info.plist"
$PB -c "Set :CFBundleName LiveNow Hub" "$DEST/Contents/Info.plist"
# An unsigned download carries the quarantine flag: drop it from the copy, then
# sign it ad hoc again (changing the bundle id broke the old signature).
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
codesign --force --deep -s - "$DEST"

EXE_NAME="$($PB -c 'Print :CFBundleExecutable' "$DEST/Contents/Info.plist")"
EXE="$DEST/Contents/MacOS/$EXE_NAME"
[ -x "$EXE" ] || { echo "executable not found: $EXE"; exit 1; }

# KeepAlive only after a crash (exit code != 0): the hub exits 0 when its port is
# already taken (another hub runs), which must not become a restart loop.
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$EXE</string>
		<string>--hub</string>
		<string>--hub-dir</string>
		<string>$DATA_DIR</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ThrottleInterval</key>
	<integer>30</integer>
	<key>StandardOutPath</key>
	<string>$LOG_DIR/stdout.log</string>
	<key>StandardErrorPath</key>
	<string>$LOG_DIR/stderr.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl kickstart -k "gui/$UID_NUM/$LABEL"

echo "LiveNow hub installed and started."
echo "  app copy : $DEST"
echo "  data     : $DATA_DIR  (hub.log is inside)"
echo "  launchd  : $LABEL  (starts at login; restarts after a crash)"
echo "The first start may ask to allow incoming connections: choose Allow."
