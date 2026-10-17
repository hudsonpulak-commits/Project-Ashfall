#!/usr/bin/env bash
# Reproducibly installs the Ashfen toolchain into $TOOLS_DIR (default /workspace/tools):
#   Godot 4.7.2-stable (Linux x86_64 editor) + export templates (Android + Web subset)
#   Temurin OpenJDK 17.0.20.1+1
#   Android SDK: cmdline-tools (16111833), platform-tools, build-tools 36.1.0, platforms;android-36 (Godot 4.7 targets API 36)
#   Debug keystore (androiddebugkey / android)
# and writes the Android paths into Godot's editor settings.
set -euo pipefail
source "$(dirname "$0")/env.sh"
DL="$TOOLS_DIR/dl"; mkdir -p "$DL"
GH=https://github.com/godotengine/godot/releases/download/$GODOT_VERSION

if [ ! -x "$GODOT" ]; then
  wget -q "$GH/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O "$DL/godot.zip"
  mkdir -p "$TOOLS_DIR/godot" && unzip -oq "$DL/godot.zip" -d "$TOOLS_DIR/godot"
fi
TPL="$HOME/.local/share/godot/export_templates/${GODOT_VERSION/-/.}"
if [ ! -f "$TPL/android_debug.apk" ]; then
  [ -f "$DL/templates.tpz" ] || wget -q "$GH/Godot_v${GODOT_VERSION}_export_templates.tpz" -O "$DL/templates.tpz"
  mkdir -p "$TPL"
  unzip -oqj "$DL/templates.tpz" 'templates/android_*' 'templates/web_*' 'templates/version.txt' \
    'templates/icudt_godot.dat' 'templates/linux_*x86_64' -d "$TPL"
fi
if [ ! -x "$JAVA_HOME/bin/java" ]; then
  wget -q "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_linux_hotspot_17.0.20.1_1.tar.gz" -O "$DL/jdk17.tar.gz"
  mkdir -p "$TOOLS_DIR/jdk" && tar xzf "$DL/jdk17.tar.gz" -C "$TOOLS_DIR/jdk"
fi
if [ ! -d "$ANDROID_HOME/build-tools/36.1.0" ]; then
  wget -q https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip -O "$DL/cmdline.zip"
  mkdir -p "$ANDROID_HOME/cmdline-tools" && unzip -oq "$DL/cmdline.zip" -d "$ANDROID_HOME/cmdline-tools"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest-bootstrap"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest-bootstrap"
  SDKM="$ANDROID_HOME/cmdline-tools/latest-bootstrap/bin/sdkmanager"
  yes | "$SDKM" --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true
  "$SDKM" --sdk_root="$ANDROID_HOME" "platform-tools" "build-tools;36.1.0" "platforms;android-36" "cmdline-tools;latest"
  # Only needed for Gradle (custom) builds / AAB for Play Store — not for M1 APKs:
  # "$SDKM" --sdk_root="$ANDROID_HOME" "ndk;28.1.13356709" "cmake;3.10.2.4988404"
fi
if [ ! -f "$DEBUG_KEYSTORE" ]; then
  mkdir -p "$(dirname "$DEBUG_KEYSTORE")"
  keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore "$DEBUG_KEYSTORE" \
    -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
fi
"$(dirname "$0")/configure_editor.sh"
echo "Toolchain ready."
