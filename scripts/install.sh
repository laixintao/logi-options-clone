#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -x .build/mouse-speed || { echo 'Run bash scripts/build.sh first'; exit 1; }
test -f mouse-config.json || { echo 'Run .build/mouse-speed capture mouse-config.json first'; exit 1; }
destination="$HOME/Library/Application Support/MouseSpeedKeeper"
plist="$HOME/Library/LaunchAgents/local.mouse-speed-keeper.plist"
mkdir -p "$destination" "$HOME/Library/LaunchAgents"
launchctl bootout "gui/$(id -u)/local.mouse-speed-keeper" 2>/dev/null || true
cp .build/mouse-speed "$destination/mouse-speed"
cp mouse-config.json "$destination/config.json"
/usr/bin/python3 - "$destination" "$plist" <<'PY'
import plistlib, sys
from pathlib import Path
destination, plist = sys.argv[1:]
data = {
    'Label': 'local.mouse-speed-keeper',
    'ProgramArguments': [destination + '/mouse-speed', 'watch', destination + '/config.json'],
    'RunAtLoad': True,
    'KeepAlive': True,
    'ThrottleInterval': 15,
    'ProcessType': 'Background',
    'StandardOutPath': destination + '/agent.log',
    'StandardErrorPath': destination + '/error.log',
}
Path(plist).write_bytes(plistlib.dumps(data))
PY
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl print "gui/$(id -u)/local.mouse-speed-keeper"
