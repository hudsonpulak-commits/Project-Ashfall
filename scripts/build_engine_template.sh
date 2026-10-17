#!/usr/bin/env bash
# Builds Ashfen's size-optimised Android release export template from Godot
# 4.7.2-stable source (~10 min on 8 cores) and installs it to
# $TOOLS_DIR/templates-custom/android_release_ashfen_4.7.2.apk.
# Also builds a Linux template with the same feature profile, used only to
# verify (headlessly) that the game runs on the stripped engine.
set -euo pipefail
source "$(dirname "$0")/env.sh"
SRC="$TOOLS_DIR/godot-src"
PROFILE="$PROJECT_DIR/tools/engine/ashfen_custom.py"
SCONS="$TOOLS_DIR/scons-venv/bin/scons"
[ -x "$SCONS" ] || { python3 -m venv "$TOOLS_DIR/scons-venv"; "$TOOLS_DIR/scons-venv/bin/pip" install -q scons; }
[ -d "$SRC" ] || git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git "$SRC"
cd "$SRC"
[ -d thirdparty/swappy-frame-pacing/arm64-v8a ] || python3 misc/scripts/install_swappy_android.py
# Android: SCons auto-installs the NDK it wants (r29 / 29.0.14206865 for 4.7.2)
"$SCONS" platform=android target=template_release arch=arm64 profile="$PROFILE" -j"$(nproc)"
(cd platform/android/java && PATH="$TOOLS_DIR/scons-venv/bin:$PATH" ./gradlew generateGodotTemplates --no-daemon -q)
mkdir -p "$TOOLS_DIR/templates-custom"
cp bin/android_release.apk "$TOOLS_DIR/templates-custom/android_release_ashfen_4.7.2.apk"
# Linux verification template (needs g++ and pkg-config: apt install g++ pkgconf)
if [ "${SKIP_LINUX_VERIFY:-0}" != "1" ]; then
  "$SCONS" platform=linuxbsd target=template_release arch=x86_64 profile="$PROFILE" \
    lto=none swappy=no wayland=no accesskit=no -j"$(nproc)"
  cp bin/godot.linuxbsd.template_release.x86_64 "$TOOLS_DIR/templates-custom/linux_release_ashfen_4.7.2.x86_64"
fi
ls -la "$TOOLS_DIR/templates-custom"
