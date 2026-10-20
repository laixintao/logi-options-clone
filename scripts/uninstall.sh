#!/bin/bash
set -euo pipefail
launchctl bootout "gui/$(id -u)/local.mouse-speed-keeper" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.mouse-speed-keeper.plist"
echo 'Automatic DPI restore disabled. Binary, configuration and logs retained in ~/Library/Application Support/MouseSpeedKeeper.'
