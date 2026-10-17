#!/usr/bin/env bash
# Shared toolchain paths for Ashfen build scripts. Source this file.
export TOOLS_DIR="${TOOLS_DIR:-/workspace/tools}"
export GODOT_VERSION="4.7.2-stable"
export GODOT="${GODOT:-$TOOLS_DIR/godot/Godot_v4.7.2-stable_linux.x86_64}"
export JAVA_HOME="${JAVA_HOME_OVERRIDE:-$TOOLS_DIR/jdk/jdk-17.0.20.1+1}"
export ANDROID_HOME="${ANDROID_HOME_OVERRIDE:-$TOOLS_DIR/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/36.1.0:$PATH"
export DEBUG_KEYSTORE="${DEBUG_KEYSTORE:-$TOOLS_DIR/keystores/debug.keystore}"
# Godot reads these at export time (override editor/preset values)
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$DEBUG_KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_DIR
