#!/usr/bin/env bash
# Milestone 2 screenshot set (towns, world map, shops, combat). Output: screenshots/m2_*.png
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_DIR"
DISP="${SHOT_DISPLAY:-:99}"
if ! xdpyinfo -display "$DISP" >/dev/null 2>&1; then
  Xvfb "$DISP" -screen 0 1280x1024x24 +extension GLX >/dev/null 2>&1 & sleep 2
fi
mkdir -p screenshots
shot() { DISPLAY="$DISP" "$GODOT" --path . --rendering-driver opengl3 --resolution 360x780 -- --fresh --screenshot="$PROJECT_DIR/screenshots/$1.png" ${@:2} 2>&1 | grep SCREENSHOT || true; }
for t in fenhollow saltmere cinderholt; do shot m2_town_$t --town=$t --ticks=60; done
shot m2_world_map --town=fenhollow --ticks=20 --panel=map
shot m2_exchange --town=fenhollow --ticks=200 --panel=exchange
shot m2_general_store --town=saltmere --ticks=40 --panel=store
shot m2_specialist --town=cinderholt --ticks=40 --panel=specialist
shot m2_anvil --town=fenhollow --ticks=20 --panel=craft
shot m2_combat_goblins --ticks=10 --fight=goblin --fight_ticks=14 --pray=ember_grip
shot m2_prayer_panel --ticks=10 --fight=goblin --fight_ticks=6 --pray=ember_grip --panel=prayer
# 0.2.1: single-way combat (an AI holds the second goblin; tapping it is refused)
shot v021_single_combat --ticks=10 --fight=goblin --fight_ticks=12 --contest
shot v022_hitsplat --ticks=10 --fight=goblin --fight_ticks=15 --contest
# 0.2.3: furnace (bronze / iron 40% fail / steel) and a specialist with the four metal tiers
shot v023_smelting --town=fenhollow --ticks=20 --panel=furnace
shot v023_shop --town=cinderholt --ticks=40 --panel=specialist
# 0.2.4: combat skills (style buttons), full-set bonus line, shop with full names, HUD bars + sprint
shot v024_skills --town=fenhollow --ticks=20 --gear=steel --panel=skills
shot v024_equipment --town=fenhollow --ticks=20 --gear=steel --panel=pack
shot v024_shop --town=saltmere --ticks=40 --panel=specialist --shop=maces
shot v024_hud --town=fenhollow --ticks=20 --sprint --sprint_dx=-40 --sprint_ticks=16
