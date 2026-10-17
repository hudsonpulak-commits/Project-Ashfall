#!/usr/bin/env bash
# Ashfen QA bot: launch the real game with rendering (xvfb when there is no
# display), drive every scenario through the real touch input path, capture
# every frame, analyze. Exit 0 = all checks pass.
#
#   tools/qa_bot/run.sh [scenario ...]        (default: all)
#   QA_KEEP_FRAMES=1  keep the raw frames (default: deleted after a PASS)
#
# Output: build/qa/<version>/report.md, report.html, evidence/ (GIFs, contact
# sheets, path plots), runs/<scenario>/ (log.jsonl, result.json, godot.log).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
source scripts/env.sh
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
OUT="${QA_OUT:-$ROOT/build/qa/$VERSION}"   # QA_OUT=dir to keep the release report
RUNS="$OUT/runs"
SCEN=("$@")

[ ${#SCEN[@]} -eq 0 ] && SCEN=(walk combat shop pshop smithy markers daynight world church aggro farm city cookhouse pk gear archery bank v036 quest xp capital autotile gfx)
RES=${QA_RESOLUTION:-360x780}
ZOOM=${QA_ZOOM:-3}

XVFB_PID=""
if [ -z "${DISPLAY:-}" ] || ! xdpyinfo >/dev/null 2>&1; then
  export DISPLAY=:97
  Xvfb :97 -screen 0 1280x1024x24 >/dev/null 2>&1 &
  XVFB_PID=$!
  sleep 1
fi
cleanup() { [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null; }
trap cleanup EXIT

rm -rf "$OUT"
mkdir -p "$RUNS"
echo "QA bot $VERSION: scenarios ${SCEN[*]} at $RES zoom $ZOOM on DISPLAY=$DISPLAY"
"$GODOT" --headless --path . --import >/dev/null 2>&1
pids=()
# 0.3.1: 13 scenarios at once starved the frame rate on 8 cores (fades then
# showed 0-1 in-between frames): run at most QA_JOBS games at a time.
JOBS=${QA_JOBS:-6}
for s in "${SCEN[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do sleep 0.5; done
  ( timeout 400 "$GODOT" --path . --rendering-driver opengl3 --resolution "$RES" -- --fresh \
      --qa="$s" --qa-out="$RUNS/$s" --zoom="$ZOOM" > "$RUNS/$s.godot.log" 2>&1
    echo "exit $?" >> "$RUNS/$s.godot.log"
    mkdir -p "$RUNS/$s"; mv "$RUNS/$s.godot.log" "$RUNS/$s/godot.log" ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
python3 tools/qa_bot/analyze.py --runs "$RUNS" --out "$OUT" --version "$VERSION" --scenarios "$(IFS=,; echo "${SCEN[*]}")" --verify-dir "$ROOT/build/verify"
rc=$?
[ -f "$OUT/evidence/walk_diagonal_strip.png" ] && cp "$OUT/evidence/walk_diagonal_strip.png" "$ROOT/screenshots/v${VERSION//./}_walk_diagonal.png"
[ -f "$OUT/evidence/v031_village.png" ] && cp "$OUT/evidence/v031_village.png" "$ROOT/screenshots/v031_village.png"
for f in v031_city_fenhollow_day v031_city_fenhollow_night v031_city_cinderholt_day v031_city_cinderholt_night v031_city_saltmere_day v031_city_saltmere_night v031_city_gate_night v031_cookhouse_store v031_cookhouse_oven v031_cookhouse_night; do
  [ -f "$OUT/evidence/$f.png" ] && cp "$OUT/evidence/$f.png" "$ROOT/screenshots/$f.png"
done
[ -f "$OUT/evidence/v031_church_inside.png" ] && cp "$OUT/evidence/v031_church_inside.png" "$ROOT/screenshots/v031_church_inside.png"
if [ $rc -eq 0 ] && [ -z "${QA_KEEP_FRAMES:-}" ]; then
  rm -rf "$RUNS"/*/frames
fi
echo "report: $OUT/report.md  ($OUT/report.html)"
exit $rc
