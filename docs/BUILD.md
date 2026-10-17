# Ashfen: build and toolchain

Everything was installed and verified on the shared Linux build box (Debian 13 x86_64) on 2026-10-08. All tools live under `/workspace/tools` (no system packages). Godot's export templates live in the user data dir that Godot expects.

## Versions and paths

| Tool | Version | Path |
|---|---|---|
| Godot editor (Linux x86_64, official) | **4.7.2-stable** (`4.7.2.stable.official.ed1daf0bf`) | `/workspace/tools/godot/Godot_v4.7.2-stable_linux.x86_64` |
| Godot export templates | 4.7.2.stable (Android, Web and Linux subset of the official `.tpz`) | `~/.local/share/godot/export_templates/4.7.2.stable/` |
| OpenJDK | **Temurin 17.0.20.1+1** | `/workspace/tools/jdk/jdk-17.0.20.1+1` |
| Android SDK cmdline-tools | 23.0.0 (pkg `commandlinetools-linux-16111833`) | `/workspace/tools/android-sdk/cmdline-tools/latest` |
| Android platform-tools (adb) | 37.0.1 | `/workspace/tools/android-sdk/platform-tools` |
| Android build-tools | **36.1.0** (matches Godot 4.7's target SDK 36); 35.0.1 also installed | `/workspace/tools/android-sdk/build-tools/` |
| Android platform | **android-36** (and android-35) | `/workspace/tools/android-sdk/platforms/` |
| Debug keystore | PKCS12, alias `androiddebugkey`, password `android` | `/workspace/tools/keystores/debug.keystore` |
| Godot editor settings | Java/Android SDK and debug keystore paths set | `~/.config/godot/editor_settings-4.7.tres` |

Not installed: **NDK r28b and CMake 3.10.2**. They are only needed for Gradle ("custom") builds, which you need for an **AAB** (Play Store upload) or for Android plugins. The prebuilt-template APK path used in M1 doesn't need them. The install line is commented out in `scripts/setup_toolchain.sh`.

## Scripts

| Script | What it does |
|---|---|
| `scripts/env.sh` | Shared paths/env (sourced by everything else). Also sets the `GODOT_ANDROID_KEYSTORE_DEBUG_*` env vars |
| `scripts/setup_toolchain.sh` | Reproducible install of everything above (idempotent), then `configure_editor.sh` |
| `scripts/configure_editor.sh` | Writes Java SDK / Android SDK / debug keystore paths into Godot editor settings |
| `scripts/test.sh` | Headless gameplay self-test (`-- --selftest`). Exit code = failed checks |
| `scripts/build_web.sh` | Web export → `build/web/` (single-threaded, so no COOP/COEP headers are needed) |
| `scripts/build_android.sh` | Debug APK (arm64-v8a) → `build/android/ashfen-debug.apk`, then `apksigner verify` |
| `scripts/screenshot.sh` | Renders the game under Xvfb (Mesa llvmpipe, GL Compatibility) → `screenshots/*.png` |
| `tools/gen_art.py` | Regenerates placeholder sprites (never overwrites hand-made art without `--force`) |
| `tools/art_status.py` | Lists which sprites are still placeholders, hand-made, or missing |
| `tools/web_smoke/` | Headless-Chrome (puppeteer-core) screenshot plus touch-tap smoke test of the Web build |

Typical loop:
```bash
cd /workspace/ashfen
./scripts/test.sh            # expect: SELFTEST PASS 44/44
./scripts/build_web.sh       # build/web/index.html
./scripts/build_android.sh   # build/android/ashfen-debug.apk
```

## Install the APK on a phone
1. On the phone, enable Developer options → USB debugging. Or just copy the APK over and allow "install unknown apps" for your file manager.
2. `adb install -r build/android/ashfen-debug.apk`
3. The app is "Ashfen", package `com.ashfen.game`, minSdk 24 (Android 7.0+), targetSdk 36. It is portrait-only and immersive.

## Run the Web build locally
```bash
python3 -m http.server -d build/web 8080   # open http://localhost:8080 (phone on the same LAN: http://<box-ip>:8080)
```

## Verified results (2026-10-08)
- `scripts/test.sh`: **SELFTEST PASS 44/44**, exit 0. It covers data loading, the XP curve, sprite mapping, deterministic world gen, streaming, A* (including "tap water → walk to shore"), chopping, tool wear and breakage, a full pack, the bank (deposit/withdraw), furnace, hearth, dummy, node respawn, a save round-trip, AI players gaining XP without standing on blocked tiles, market regulation helpers, and chunk-gen timing (~1.3 ms per chunk).
- `godot --headless --path . --fixed-fps 60 --quit-after 3600 -- --fresh`: exit 0, no errors in the output. It ran 100 ticks and the autosave was written.
- Web export: `index.wasm` 39.5 MB (uncompressed; serve it gzip/brotli in production), `index.pck` 165 KB. It loads in headless Chrome (WebGL2 via SwiftShader), and a touch tap walks the player (screenshots `m1_web_*.png`).
- Android export: `ashfen-debug.apk` **28,398,542 bytes (~27 MiB)**, arm64-v8a only, signed with the debug keystore (v2+ scheme, verified by `apksigner`). The manifest has package `com.ashfen.game`, versionName 0.1.0-m1, minSdk 24, targetSdk 36, and a LAUNCHER activity-alias. **It has not been run on a physical device or emulator yet** (see the report's known gaps).

## Release signing (later)
Create a private release keystore (never commit it):
`keytool -v -genkey -keystore ashfen-release.keystore -alias ashfen -keyalg RSA -validity 10000`
and export with `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD` env vars. For a Play Store upload, enable Gradle build in the Android preset (needs the NDK/CMake above) and export an AAB.

## Gotchas found while setting up
- Godot 4.7 Android export **requires** `rendering/textures/vram_compression/import_etc2_astc=true` (it is set in `project.godot`).
- Godot 4.7 targets API 36. With only build-tools 35 installed, Godot warns "Could not find version of build tools that matches Target SDK". Installing build-tools 36.1.0 fixed that.
- `data/*.json` are not Godot resources, so the export presets add `include_filter="data/*.json, data/towns/*.json"`. Without it, the exported game would have no content.
- `sdkmanager` now prints a deprecation notice pointing to the new `android sdk` CLI. It still works.

## Device testing status
- **Not yet run on Android hardware.** An emulator attempt on this box (emulator 36.x, `system-images;android-34;google_apis;x86_64`, KVM reported "usable") never booted. The guest vCPU sat at about 1% CPU and adb stayed `offline`, almost certainly because nested virtualisation doesn't work inside this cloud VM. The emulator and system image were removed afterwards, and `/dev/kvm` permissions were restored to `root:103 0660`.
- To test: sideload `build/android/ashfen-debug.apk` on any arm64 Android 7+ phone, or run an emulator on a machine with real virtualisation. You'd need an arm64 system image on Apple Silicon, or an x86_64 Android 11+ image, which translates arm64 apps.

## Small release APK for sideloading (custom engine template)
The owner gets builds sent over chat, which has a 25 MB limit, so the shareable build is a **release-template APK signed with the same debug keystore**. Because the package (`com.ashfen.game`) and signing cert (SHA-256 `41519b0b…e3381c`) match the M1 debug APK, it installs over it as an update.

| Build | Template | Size |
|---|---|---|
| `ashfen-debug.apk` | official debug | 28.4 MB |
| release, official template | official release | 26.6 MB (25.7 MB after zopfli; still too big) |
| **`ashfen-release.apk`** | **custom 4.7.2 release template** (`tools/engine/ashfen_custom.py`) | **14.6 MB** (0.2.5, versionCode 7; 0.2.4 and 0.2.3 14.6 MB; 0.2.2, 0.2.1 and M2 14.5 MB, M1 14.3 MB) |

The custom template is built from the `4.7.2-stable` source (commit `ed1daf0bf`) with `optimize=size_extra`, `lto=full`, Swappy frame pacing, and these features disabled: 3D, 2D/3D physics, 2D/3D navigation, XR, the advanced text server (it uses the fallback text server: no complex-script shaping) and 44 unused modules (networking, video, image importers, gltf, …). `libgodot_android.so` drops from 71 MB to 33 MB uncompressed.
- Build it: `scripts/build_engine_template.sh` (about 6 min for Android + Gradle on 8 cores; SCons auto-installs **NDK r29 / 29.0.14206865**, and Swappy comes via `misc/scripts/install_swappy_android.py`). The template is written to `/workspace/tools/templates-custom/android_release_ashfen_4.7.2.apk`. Extra tools: SCons 4.11.1 in `/workspace/tools/scons-venv`, plus `g++` and `pkgconf` from apt for the Linux build.
- Export: `scripts/build_android_release.sh` → `build/android/ashfen-release.apk`.
- **Verification:** a Linux x86_64 template built with the *same* feature profile (`linux_release_ashfen_4.7.2.x86_64`, export preset "LinuxVerify") runs `-- --selftest` → **44/44 pass**, and renders correctly under Xvfb. This shows that the stripped engine runs everything the game uses.
- If a future feature needs a disabled module (e.g. 2D physics for collisions, or networking), flip it in `tools/engine/ashfen_custom.py` and rebuild. To fall back to the official template, clear `custom_template/release` in `export_presets.cfg`.


## Release pipeline and QA bot (0.3.0)

```
scripts/release.sh     # selftest -> release APK (<25 MB) -> QA bot -> stage
```

`build/dropbox/ashfen-<version>.apk` is written **only** if the headless
selftest (no failed checks, no SCRIPT ERROR) and the QA bot both pass.
Staging is a local copy; nothing is uploaded. The QA bot can be run alone
with `tools/qa_bot/run.sh`. It needs Xvfb (started automatically when there
is no display) and Python with numpy, Pillow and matplotlib. Reports go to
`build/qa/<version>/report.md` and `report.html`. See docs/QA_BOT.md.

Other 0.3.0 tools:
* `python3 tools/layout_towns.py` regenerates `data/towns/*.json` (buildings,
  expanded towns) from the frozen 0.2.x sources in `tools/town_sources/`.
* World map: `$GODOT --headless --path . --script res://tools/export_world_map.gd -- --out=$PWD/build/map`
  then `python3 tools/render_world_map.py` (footprints and doors are drawn).
* Soak with simulated player shops: `-- --soak=7 --pshop=1.0` (0.8, 1.3 ...).
