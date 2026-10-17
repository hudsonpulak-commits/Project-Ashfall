#!/usr/bin/env bash
# Exports a debug-signed arm64 APK to build/android/ashfen-debug.apk
# Install on a phone (USB debugging on):  adb install -r build/android/ashfen-debug.apk
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_DIR"
mkdir -p build/android
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-debug "Android" build/android/ashfen-debug.apk 2>&1 | tee build/android_export.log | grep -E "ERROR|error|Export" || true
test -f build/android/ashfen-debug.apk
apksigner verify --print-certs build/android/ashfen-debug.apk | head -3
unzip -l build/android/ashfen-debug.apk | grep -E "lib/|assets/.*pck" || true
ls -la build/android
