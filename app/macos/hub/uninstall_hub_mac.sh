#!/bin/bash
# Removes the LiveNow sync hub from this Mac: stops it, deletes the launchd agent
# and the app copy. The hub's DATA (~/Library/Application Support/
# io.livenow.livenow/hub) is kept; delete that folder yourself to forget it.
set -euo pipefail

LABEL="io.livenow.hub"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HUB_ROOT="$HOME/Library/Application Support/LiveNowHub"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$HUB_ROOT"

echo "LiveNow hub removed (its data folder was kept)."
