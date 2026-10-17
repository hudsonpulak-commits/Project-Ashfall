#!/usr/bin/env bash
# Exports the Web build to build/web/ (single-threaded, works on any static host).
# Serve locally:  python3 -m http.server -d build/web 8080
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_DIR"
mkdir -p build/web
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" build/web/index.html 2>&1 | tee build/web_export.log | grep -E "ERROR|error|savepack|Export" || true
test -f build/web/index.wasm && test -f build/web/index.pck
ls -la build/web
