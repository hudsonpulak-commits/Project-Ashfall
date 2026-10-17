#!/usr/bin/env bash
# Renders the game under a virtual X display (Mesa llvmpipe) and saves PNGs to screenshots/.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_DIR"
DISP="${SHOT_DISPLAY:-:99}"
if ! xdpyinfo -display "$DISP" >/dev/null 2>&1; then
  Xvfb "$DISP" -screen 0 1280x1024x24 +extension GLX >/dev/null 2>&1 & sleep 2
fi
mkdir -p screenshots
shot() { DISPLAY="$DISP" "$GODOT" --path . --rendering-driver opengl3 --resolution 360x780 -- --fresh --screenshot="$PROJECT_DIR/screenshots/$1.png" ${@:2} 2>&1 | grep SCREENSHOT; }
shot m1_town --ticks=40
shot m1_pack --ticks=40 --chop --panel=pack
shot m1_bank --ticks=60 --panel=bank
shot m1_skills_zoom1 --ticks=80 --panel=skills --zoom=1
