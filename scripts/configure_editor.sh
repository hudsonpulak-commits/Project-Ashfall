#!/usr/bin/env bash
# Writes Java SDK / Android SDK / debug keystore paths into Godot 4.7 editor settings.
set -euo pipefail
source "$(dirname "$0")/env.sh"
CFG="$HOME/.config/godot/editor_settings-4.7.tres"
if [ ! -f "$CFG" ]; then
  # first run creates the file
  "$GODOT" --headless --path "$PROJECT_DIR" --editor --quit >/dev/null 2>&1 || true
fi
python3 - "$CFG" <<PY
import re, sys
p = sys.argv[1]; s = open(p).read()
vals = {
  "export/android/java_sdk_path": "$JAVA_HOME",
  "export/android/android_sdk_path": "$ANDROID_HOME",
  "export/android/debug_keystore": "$DEBUG_KEYSTORE",
  "export/android/debug_keystore_user": "androiddebugkey",
  "export/android/debug_keystore_pass": "android",
}
for k, v in vals.items():
    line = f'{k} = "{v}"'
    if re.search(rf'^{re.escape(k)} = .*$', s, re.M):
        s = re.sub(rf'^{re.escape(k)} = .*$', line, s, flags=re.M)
    else:
        s = s.rstrip("\n") + "\n" + line + "\n"
open(p, "w").write(s)
print("editor settings updated:", p)
PY
