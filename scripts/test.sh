#!/usr/bin/env bash
# Headless gameplay self-test. Exit code = number of failed checks.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_DIR"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -- --selftest
