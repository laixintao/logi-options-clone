#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -O -module-cache-path /tmp/logi-speed-module-cache Sources/MouseSpeed.swift -o .build/mouse-speed
