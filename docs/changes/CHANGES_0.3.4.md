# AshFall 0.3.4: music + overhead labels that work on phones

## Music (autoload `Music`, `autoload/music.gd`)
- Six tracks from Dropbox /Game/Game music, in `res://assets/music/`:
  title, ambient, combat, fenhollow, cinderholt and saltmere.
  - They are re-encoded to **Ogg Vorbis, 56 kbps mono** (6.7 MB in total).
  - The size-optimised export template (`tools/engine/ashfen_custom.py`) is built without the MP3 module,
    so MP3s would load in the editor but play silence on phones. Ogg Vorbis is in the template.
- Rules:
  - Combat starts **instantly at full volume**, in the same frame.
  - Leaving combat fades the combat track out over **1.5 s**, then the area track starts.
  - Each town's theme plays inside that town and ambient plays everywhere else.
  - The title theme plays on the main menu, and again after "save and exit to menu".
  - Tracks loop and pause while the Android app is in the background.
- Wiring:
  - `main.gd` calls `Music.set_combat` from the player's combat state and `Music.set_area` from the town at the player's tile, every tick.
  - The main menu calls `Music.set_title()`.
- **Music volume** slider under Main menu > Settings, saved to `user://settings.cfg`.
- Changes from Grok's `music_manager.gd`:
  - Combat no longer relies on a wall-clock "linger" timer.
  - Tracks loop.
  - The town key now matches the town id: the file is `fenhollow`, not Grok's `fenhallow`.
  - Added the volume setting, the app-pause handling and a testable `step()`.
  - Getting back into a fight mid-fade snaps straight back to full volume.

## Overhead labels (`src/ui/overhead.gd`)
- **Why they were missing on phones:** 0.3.3 drew them with an MSDF copy of the UI font.
  The export template is built without the `msdfgen` module, so the APK drew no glyphs at all.
  Desktop editor runs have the module, which is why the 0.3.3 QA frames looked fine.
- **Fix:**
  - Labels are now ordinary Labels in a screen-space overlay. That overlay is a CanvasLayer at layer 5: above the world and every actor, below the HUD (layer 10).
  - They use the normal UI font at **8 logical px**, which is 24 px on a 1080-wide phone (x3 content scale).
  - Every frame each label is placed just above its owner's sprite. It is hidden when the owner is hidden, dead or off screen, kept inside the screen edges, and faded over your own head so it never covers your skull.
- Content is unchanged: `Name (cb)` on AI players, and coloured `Name (lvl)` on combat enemies (green lower, yellow near, red higher).
  Shopkeepers, citizens and chickens still get none.

## Tests
- Unit tests:
  - `src/tests/music_tests.gd` (new): the tracks load and loop; title, wilds and town tracks are picked correctly;
    combat is at full volume in the same call; the fade takes 1.5 s (±2 frames) and is quieter halfway; getting back into a fight mid-fade snaps to full.
  - The archery tests also check that labels are 8 px+ and sit in the overlay.
- QA bot C20 now also needs at least 2 labels actually drawn on screen.
- Boot check **B6** (new) counts label-coloured pixels in frames from the **exported build** on the stripped engine with the compatibility renderer.
  It fails on the 0.3.3 build, which scores 0 px.
- Version 0.3.4, versionCode 12.
