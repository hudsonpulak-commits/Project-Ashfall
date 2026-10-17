# AshFall 0.3.7.1 (hotfix, versionCode 16)

## Root cause: no quest arrow after accepting Goblin Slayer
`QuestSystem.objective_tile()` only looked for a target within 40 tiles of the
player and returned null otherwise. Kell stands in Fenhollow and the nearest
goblin camp is 70+ tiles away, so right after starting the quest (and on the
way to the Warlord) there was no target, so no arrow and no marker. QA missed it
because the scenario teleported the player next to the goblins first.

Fix: `QuestSystem.objective()` now always returns a target during a kill
stage. It picks the nearest live target at any distance, or the nearest spawn
camp of that enemy (from data/enemies.json) if every target is dead.

## Changes
- **Quest guidance:**
  - The edge arrow is bigger (18 logical px, which is 54 px on a 1080-wide phone), pulses and has a dark backing.
  - A gold marker bobs above the target goblin or Warlord while it is on screen.
  - A pulsing red objective-area marker is drawn on the world map and the minimap, on the goblin camp or the Warlord spot. On the minimap it is pinned to the edge when the area is out of view.
- **NPC '?' / '!':** much bigger (font 20, outline 5).
- **Chat log:** overhead name and level labels are hidden where they would cover chat-log lines.
- **Quest dialog:**
  - Tapping a quest NPC opens a panel with the NPC's name, the text and response buttons. It is data-driven: `dialog` nodes and choices in data/quests.json.
  - Goblin Slayer offers Accept and Decline with Kell's lines. Decline leaves the quest not started (still '?'); Accept starts it.
  - While the quest is in progress Kell gives a reminder with your progress; at turn-in he gives the completion text.
  - Talking never starts a quest on its own.
- **Markers toggle:**
  - A "Markers" button on the world map and a small "M" icon on the minimap.
  - It hides or shows player map markers and quest map markers (?, !, objective areas) on both maps. The overhead ?/! and the edge arrow are always shown.
  - The setting is saved in user://settings.cfg ([map] markers, default shown).
- **World map touch:**
  - Two-finger pinch zooms around the pinch centre (1x-6x).
  - One-finger drag pans, clamped to the map edges.
  - A tap without dragging (10 px slop) drops a marker on the correct tile at any zoom. Long-press still works.
  - There are +/- buttons, and the mouse wheel zooms.
- **Version:** 0.3.7.1 (versionCode 16).

## Tests
- **Unit tests:** src/tests/patch0371_tests.gd covers:
  - the dialog (opening it doesn't start the quest, Decline, Accept, reminder, completion);
  - the objective from town and the camp fallback;
  - the Warlord area;
  - the Markers setting and its persistence;
  - overhead labels hidden over the chat log;
  - simulated ScreenTouch/ScreenDrag: pinch zooms, drag pans without dropping a marker, a tap at zoom drops it on the right tile.

  patch037_tests now goes through the dialog.
- **QA (C29):**
  - Decline/Accept through the real dialog buttons.
  - The arrow is shown, with its gold pixels counted, right after accepting in Fenhollow and during the goblin and Warlord steps. The check fails if none are drawn.
  - The map Markers toggle, its persistence and the zoom buttons, with frames.
- **Boot B7:** 0.3.7 saves with Goblin Slayer at the goblin step and at the Warlord step, loaded from the exported .pck at 1080x2400 on the Mobile (Vulkan) renderer. It checks there are no script errors and that gold arrow pixels are drawn.
