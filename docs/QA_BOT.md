# Ashfen QA bot

A tester bot that plays the real game, with real rendering, through the real
touch input path, captures **every frame**, and checks the frames and game
state for the glitches we have shipped before: facing flip-flop, ghosting,
diagonal zigzag, jitter, double-toggling taps, stacked hit bubbles, roof
cut-away problems and broken shop / player-shop / blacksmith flows.

```
tools/qa_bot/run.sh                 # all scenarios -> build/qa/<version>/
tools/qa_bot/run.sh walk smithy     # just some
QA_KEEP_FRAMES=1 tools/qa_bot/run.sh   # keep raw frames even on PASS
QA_OUT=/tmp/qa tools/qa_bot/run.sh walk   # report elsewhere (keeps the release report)
```

Exit code 0 = every check passed. `scripts/release.sh` runs it and **only
stages the APK in build/dropbox/ when it passes** (after the selftest).

## How it works

1. `run.sh` starts Xvfb if there is no display, then launches one real Godot
   instance per scenario (`--rendering-driver opengl3 --resolution 360x780
   -- --fresh --qa=<scenario> --zoom=3`). All scenarios run in parallel.
2. `tools/qa_bot/qa_driver.gd` (loaded by `src/main.gd` for `--qa`; the
   `tools/` folder is not exported into the APK) drives the scenario:
   * taps are `InputEventScreenTouch` events fed to `Input.parse_input_event`.
     With `emulate_mouse_from_touch` on, Godot itself generates the emulated
     mouse event, which is exactly the touch + mouse pair an Android phone
     delivers. HUD buttons are tapped at their on-screen rectangles; world
     tiles at their on-screen position (camera transform).
   * after every rendered frame (`RenderingServer.frame_post_draw`) it saves
     `frames/fNNNNN.png` and one JSON line in `log.jsonl`: player position,
     tile, `flip_h`, animation frame, screen anchor, camera, sprint, panel,
     roof alpha per nearby building, actors visible under a showing roof,
     hit bubbles, coins, nearby actors (for occlusion).
   * `result.json` holds driver facts (panel opened, coins before/after...)
     and every event (taps, chat lines, shop_opened, hitsplats).
3. `tools/qa_bot/analyze.py` runs the checks and writes `report.md`,
   `report.html` (pass/fail table with thumbnails) and `evidence/` (GIFs,
   contact sheets, path plots, stills). Walk evidence is also copied to
   `build/verify/walk_*`, and the diagonal strip to
   `screenshots/v<ver>_walk_diagonal.png`.

### Image analysis

The player sheet (`assets/sprites/actors/player.png`, every frame, plain and
mirrored, with the gear layers the game reports as worn on that frame composited
on top in draw order, 0.3.1) is scaled to screen size and matched against the frame at the
logged screen anchor (masked mean absolute RGB error; an exact sprite scores
~0). That gives the **facing as rendered** (not as the code believes), a
residual (blended / ghosted sprite), the sprite offset from its anchor (jitter)
and a search beside the player for a second copy (ghost). Frames where another
actor's sprite or name label overlaps the player's box, or a panel is open,
are skipped (and counted in the report).

## Scenarios

| id | what it does |
|---|---|
| walk | walk right, reverse to the left mid-walk, 45-degree diagonals up-right and down-left, tap the Energy bar (sprint on), sprint 2:1 diagonal, sprint left, sprint diagonal, tap Energy (off), tap Pack open and closed |
| combat | fight the training dummy, then a giant rat |
| shop | an AI walks into a specialist shop while you are outside; tap the keeper, walk in, greeting, shop opens; close; walk out |
| pshop | tap the estate agent, tap Buy, stock two stands through the panel, close; AI agents shop (the real `AIBrain.shop_browse`), one walks in; tap the keeper, Collect; walk out |
| smithy | walk into the Blacksmith, tap the furnace (smelt bronze), tap the anvil (forge a dagger), walk out |
| world | 0.3.1: stand next to a chicken, a Fenhollow guard and a citizen (10 ticks each); tap the guard (it fights back); stand 3 tiles from a wolf; walk north across the Scorch line, out, and back in; count road tiles over water; look at the nearest copper/tin mine |
| church | 0.3.1: from the street below Fenhollow Church (Prayer at 0) tap the altar under the roof: walk in, kneel, Prayer full; walk to the door and back out. Saves `screenshots/v031_church_inside.png` |
| markers | open Map, long-press to add a marker, edit, Walk here, delete, clear-all; persist across save/load |
| daynight | day → dusk → night tints, town lights, HUD clock; check smooth transition |
| pk | (0.3.1) walk north into the Scorch (chat warning, warning card, HUD row); a raider hunts you down (you carry iron sword, steel helm, bronze cap, food, logs, 120 marks) and you die; wait for it to collect its private pile; tap an AI player from outside the zone (refused), then from inside (you are skulled); finish the AI off and watch a new level-1 player take its slot |
| gear | (0.3.1) visible gear on the player: standing still, equip then unequip each slot (head, body, legs, shield, weapon) through the real equip path, noting the frame of each change; walk the C1/C2 legs (right, turn left, both diagonals, sprint left/right) wearing a mixed set; then, on a quiet spot, wear each tier set (bronze, iron, steel, dusk, mixed + bow) facing right and left |

## Checks

| id | check | fails when |
|---|---|---|
| C0 | runtime | a scenario is missing or Godot printed SCRIPT ERROR |
| C1 | facing | the rendered facing disagrees with the horizontal motion, lags more than one frame after a direction change, flips while the direction is unchanged, or differs from `flip_h` |
| C2 | ghosting | a second player copy beside the sprite, a degraded (blended) sprite, or A/B/A mirrored alternation |
| C3 | diagonal | a diagonal leg is not monotonic in x and y or strays > 2.5 world px from the straight line (path plots in evidence) |
| C4 | jitter | non-integer sprite / camera positions, backwards steps inside a leg, or the sprite moving on screen (camera and sprite out of step) |
| C5 | single tap | one tap does not toggle sprint / the Pack panel exactly once |
| C6 | hit bubbles | more bubbles than targets, or two bubbles on top of each other |
| C7 | roof | the roof does not fade (in-between frames) within ~0.5 s on entering, does not come back on leaving, another building's roof changes, an actor is visible under a showing roof, or the player stands on a blocked tile |
| C8 | shops | wrong shop / no greeting before the panel; player shop buy, stock, AI sale, collect amounts wrong |
| C9 | blacksmith | stations not inside, no bars / no forged item, not back outside, no smith greeting |
| C10 | markers | long-press/tap double-fire, add/edit/delete/clear-all wrong, or markers lost on save/load |
| C11 | daynight | abrupt tint jumps, missing lights, or HUD unreadable / wrong phase |
| C12 | world | a chicken/guard/citizen starts a fight or hurts you; a tapped guard does not fight back; a wolf does not aggro; no "The Scorch - anyone can attack you" banner within 3 frames of the first PK tile, or a banner on the second crossing; skull row visible outside / missing inside; banner border+fill or skull row not actually in the frame pixels; any road tile on lake water without a bridge |
| C13 | church | never inside / no kneel / Prayer not at max after praying; any Prayer XP from the altar; not back outside; the church roof not cut away inside; the blue Prayer bar fill not (near) empty before and full after in the frame pixels |
| C14 | aggro | a Combat 12 player walking past a rat camp is targeted or loses HP (rats are level 1; combat.json aggro_level_gap 10); a fresh Combat 3 player is not aggroed; the HUD does not read 'Total N  Combat N'; enemy names lack '(level N)' |
| C15 | farm | the title does not name the village on arrival; fewer than 2 wheat harvested or the stalks not cut to stubble; no flour from the quern craft panel; no bread from the hearth; the pasture cow never kicks back, does not die or is not 8 HP; its drops lack bones, raw beef or a cowhide; no lights at night in the village; the in-game map does not open; the wheat field not golden in the frame pixels |
| C16 | city | a city (Fenhollow, Cinderholt, Saltmere) is not named in the title, is not darker at night or shows fewer than 2 lit facade windows on screen (zoom 1 overview from the square, day + night); walking out of Fenhollow's road gate does not pass the gate, ends inside the town, steps on a blocked tile, or the road starts more than 2 tiles from the gate; fewer than 2 calm, stationary guards at that gate; a tap just outside the wall is not reached via a gate (or a frame stands on a wall); the gate's wall torches show no warm pixels at night |
| C17 | cookhouse | tapping the cook does not walk in and open the store titled Cook House; the bought cooked meal is not cheaper than the general store, the price paid differs, or the finite shelf does not drop by one; no cooked/charred carp from the Cook House oven; the player does not walk back out; the Cook House windows show no warm pixels at night |
| C18 | Scorch PK | no entry warning / card / HUD row; the raider never hits you, isn't skulled, or you get skulled for defending; on death the kept items aren't the 3 most valuable, the pile isn't private to the killer, the fee isn't 10 %, or you respawn in the zone; the killer never collects its pile; an outside tap starts a fight; the inside attack doesn't skull you (HUD timer + the skull icon matched in the rendered frame above your head) or skulls the victim; the killed AI isn't replaced by a new 25-mark player with an estate sale |
| C19 | visible gear | an equip/unequip is not visible in the first or second rendered frame after it (image must match body + new layers better than the old look); a geared frame does not match the body with its layers composited at the same walk frame and facing (layer lag, ghost, wrong order); a tier set does not render in the order legs < body < head < shield < weapon facing right and left. Evidence: `v031_gear_player.png` (tiers side by side), `gear_walk.gif`, `gear_equip_*.png` |

The checks were validated against re-injected bugs: setting the camera before
the player's visual update (the 0.2.5 blur cause) fails C4 (33 px anchor
spread); flipping `flip_h` every 9th frame fails C1 and C2. Its first real catch
after the walk rework was a one-frame "moonwalk" on reversing mid-step
(the sprite finished the old step by 1 px while already facing the new way);
fixed in `Actor.on_tick`, and the walk scenario then passed 4 runs in a row.

## Adding a check

1. If the check needs new state, add it to `_state()` in `qa_driver.gd` (one
   key per frame) or to `_notes` (once per run).
2. If it needs new actions, add a scenario function (`_myscenario()`), list
   it in the `match` in `_run()`, and add its id to `SCENARIOS` in
   `analyze.py` and the default list in `run.sh`. Use `label = "..."` to name
   the phases you want to analyse, `tap_tile()` / `tap_control()` for input
   and `until()` / `frames()` to wait. Never call game functions to do what a
   player would do with a tap; setup (giving items, placing the player) is
   fine.
3. In `analyze.py` write `def check_mything(ctx) -> list[Result]`, using
   `ctx.runs["scenario"].log` (per-frame rows), `.events`, `.res`, and
   `ctx.track(name)` for sprite matching. Return `Result(check_id, name, ok,
   detail, evidence_paths)`; `ctx.gif()`, `ctx.sheet_for()`, `ctx.still()`
   and `ctx.plot_leg()` make evidence.
4. Add it to `CHECKS`, run `tools/qa_bot/run.sh <scenario>`, then prove the
   check can fail by re-injecting the bug once (and revert).

## Boot QA on the exported build (0.3.2, release gate step 3/4)

`tools/qa_bot/boot_check.py --pck build/qa_boot/ashfen.pck` runs the **Android preset's pack** (same include/exclude filters as the APK) on the size-optimised engine template built with the Android feature profile (`templates-custom/linux_release_ashfen_*`), with the compatibility renderer, under Xvfb. It clicks through the real menu with `xdotool` and films every run with ffmpeg. The game writes a flushed boot trace to `user://qa_boot.log` when started with `--qa-boot`.

| id | check | fails when |
|---|---|---|
| B1 | cold start | no main menu (title + buttons) after a start with no save |
| B2 | new game | New Game -> slot 1 -> Start does not reach gameplay (HUD in the frame), or slot 1 is not saved |
| B3 | 0.3.0 save | a real 0.3.0 (v3) save left 6 h ago in slot 1 does not migrate (v3 -> v8) and reach gameplay, has script errors, or the catch-up does not run in loading-screen chunks |
| B4 | damaged save | a damaged save does not bring you back to the menu with a message, or the file is not kept aside (`*.bad-<unix>.json`) |
| B5 | no blank screen | any run shows one flat colour for more than 3 s |

Evidence: `build/qa_boot/boot_menu.png`, `boot_loading.png`, `boot_ingame_new.png`, `boot_menu_with_save.png`, `boot_loading_v030.png`, `boot_ingame_loaded.png`, `boot_bad_save.png`, `boot_report.md`.
