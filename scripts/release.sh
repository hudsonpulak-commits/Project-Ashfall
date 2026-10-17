#!/usr/bin/env bash
# Release pipeline (0.3.0+): selftest -> release APK -> boot QA on the exported build (0.3.2) -> QA bot -> stage.
# The APK is copied to build/dropbox/ashfen-<version>.apk ONLY when the
# headless selftest and the QA bot (tools/qa_bot/run.sh, real rendering) both
# pass. Nothing is uploaded anywhere; staging is a local copy.
#   scripts/release.sh            full pipeline
#   SKIP_BUILD=1 scripts/release.sh   reuse build/android/ashfen-release.apk
set -uo pipefail
source "$(dirname "$0")/env.sh"
cd "$PROJECT_DIR"
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
CODE=$(sed -n 's/^version\/code=\([0-9]*\)/\1/p' export_presets.cfg | head -1)
APK=build/android/ashfen-release.apk
DEST=build/dropbox/ashfen-$VERSION.apk
echo "== release $VERSION (versionCode $CODE)"

echo "== 1/4 selftest"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -- --selftest > build/release_selftest.log 2>&1
st=$?
if [ $st -ne 0 ] || grep -q "SCRIPT ERROR" build/release_selftest.log; then
  grep -E "FAIL|SCRIPT ERROR" build/release_selftest.log | head -20
  echo "RELEASE BLOCKED: selftest failed (exit $st) - see build/release_selftest.log"; exit 1
fi
grep "SELFTEST" build/release_selftest.log | tail -1

if [ -z "${SKIP_BUILD:-}" ]; then
  echo "== 2/4 release APK"
  scripts/build_android_release.sh || { echo "RELEASE BLOCKED: APK build failed"; exit 1; }
fi
[ -f "$APK" ] || { echo "RELEASE BLOCKED: $APK missing"; exit 1; }
size=$(stat -c %s "$APK")
[ "$size" -lt $((25 * 1024 * 1024)) ] || { echo "RELEASE BLOCKED: APK is $size bytes (>= 25 MB)"; exit 1; }

echo "== 3/4 boot QA on the exported build (Android preset pack, stripped engine, compatibility renderer)"
mkdir -p build/qa_boot
"$GODOT" --headless --path . --export-pack "Android" build/qa_boot/ashfen.pck > build/qa_boot/export_pack.log 2>&1 || { echo "RELEASE BLOCKED: pack export failed"; exit 1; }
if ! python3 tools/qa_bot/boot_check.py --pck build/qa_boot/ashfen.pck --out build/qa_boot; then
  echo "RELEASE BLOCKED: boot QA failed - see build/qa_boot/boot_report.md"; exit 1
fi

echo "== 4/4 QA bot"
if ! tools/qa_bot/run.sh; then
  echo "RELEASE BLOCKED: QA bot failed - see build/qa/$VERSION/report.md"; exit 1
fi

mkdir -p build/dropbox
cp "$APK" "$DEST"
echo "STAGED $DEST ($(stat -c %s "$DEST") bytes) - selftest + QA passed"
