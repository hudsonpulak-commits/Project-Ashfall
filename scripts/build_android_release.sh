#!/usr/bin/env bash
# Small sideload APK: release template (custom, size-optimised; see
# build_engine_template.sh), arm64 only, signed with the DEBUG keystore so it
# can be sent/installed directly. Not for Play Store (needs a release key + AAB).
#   -> build/android/ashfen-release.apk
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_DIR"
TPL="$TOOLS_DIR/templates-custom/android_release_ashfen_4.7.2.apk"
[ -f "$TPL" ] || { echo "Missing $TPL - run scripts/build_engine_template.sh (or clear custom_template/release in export_presets.cfg to use the official 26.6 MB template)"; exit 1; }
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$DEBUG_KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"
mkdir -p build/android
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Android" build/android/ashfen-release.apk > build/android_release_export.log 2>&1
apksigner verify --print-certs build/android/ashfen-release.apk | head -1
ls -la build/android/ashfen-release.apk
