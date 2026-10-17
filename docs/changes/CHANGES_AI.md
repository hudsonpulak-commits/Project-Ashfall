# AshFall – AI immersion patch (on 0.3.2 + Prayer 30 s/level)

## What the AI did before (weak spots)
- **Silent.** `Actor.say()` was a no-op for AI ("M2: overhead chat bubbles" never landed). The only sign of life was a name label and movement.
- **Pure economy brain.** `AIBrain.choose()` is a utility max over gather/craft/pray/fight. When nothing beat `RESERVATION` the agent got `rest`, which on screen meant a random stroll of ±6 tiles around home. That's the "aimless shuffle" look.
- **No awareness of the player or each other.** Nothing reacted to you walking up, to your kills, to level-ups, or to other AIs.
- **Market is invisible.** Agents read prices (`glut`, `price_health`, memo), but never surfaced it, so the economy simulation is not felt.
- Personas differ only in focus, risk and patience. They have no voice.

## What changed
1. **Chat bubbles** (`src/ai/ai_chatter.gd`, `data/ai_chatter.json`)
   - Pixel-style parchment bubble above on-screen AI players (`AIPlayer.show_bubble`). Long lines wrap at 90 px. The bubble is clamped to the screen edge and hidden when its speaker is off screen.
   - Categories: gather, craft, fight, bank, trading, idle, well, sit, watch, low_hp, levelup, death, greet, greet_strong, player_kill, market_up, market_down, reply. Each has generic lines plus persona-specific lines, which are used 60% of the time. Templates: `{item} {skill} {level} {enemy} {name}`.
   - Limits:
     - Per-agent cooldown of 34–66 ticks (20–40 s).
     - At most 3 bubbles on screen.
     - About 4 s on screen.
     - Ambient chance is checked every 5 ticks and scaled by persona `chattiness`.
   - Only the detailed tier (`AIDirector.agents`) is ever touched. Off-screen agents do no work and allocate nothing.
   - **Replies:** when an AI speaks, there is a 35% chance that a nearby AI (≤6 tiles, off cooldown) answers about 2 s later.
2. **Reactions and idle variety**
   - **Greeting:** when you come within 4 tiles, the AI greets you. Lines are persona-flavoured; raiders are menacing and traders pitch. If you are 10 or more combat levels above it, it says a "nice gear" line instead. The AI also turns to face you. Each agent greets at most once per 500 ticks.
   - **Your kills:** the closest AI within 8 tiles comments and turns toward the kill (`Player.on_kill` → `AIChatter.on_player_kill`).
   - **Level-ups** (the `Skills.leveled` signal is connected while the agent is on screen), **deaths**, **low HP** (under 40%) and **banking** (30% chance) have their own lines.
   - **Market talk:** about 30% of ambient lines check the agent's own persona buy/sell items for a daily move of ±20% or more (`TownMarket.day_change`). They then say, for example, "Copper ore crashed..." or "Who's buying all the plank?".
   - **Idle behaviours:** in a low-utility moment, `AIBrain.choose()` picks `{"type":"idle","mode": well|sit|watch}` 55% of the time. This happens only when the agent is on screen; abstract agents keep `rest`, so the economy and soak results are unchanged.
     - `well`: walks to the town well and has a drink.
     - `sit`: stays put for 20–40 ticks.
     - `watch`: walks up to a busy AI, faces it and cheers it on.
     - Each behaviour has its own lines.
3. **Tests**
   - `src/tests/selftest_chatter.gd` adds 13 checks:
     - every category has lines;
     - AIs talk in town;
     - the cap of 3 holds over 600 ticks;
     - off-screen agents never speak or hold state;
     - the cooldown works;
     - templating works;
     - the greeting fires;
     - the kill reaction fires;
     - sitting works;
     - abstract agents never roll idle.
   - Fixed 3 stale Prayer tests that still expected 10 ticks per level after the 30 s/level data change.
   - The QA bot (`--qa`) mutes chatter by default, because its pixel-exact player-sprite checks read a bubble over the player as ghosting. `--qa-chatter` turns it back on.
   - Screenshot mode: `--chatter=ambient|greet|react [--chatter_ticks=N]`.

## Files
- New: `data/ai_chatter.json`, `src/ai/ai_chatter.gd`, `src/tests/selftest_chatter.gd`.
- Changed:
  - `autoload/game_data.gd`: loads `ai_chatter.json`.
  - `autoload/ai_director.gd`: calls `AIChatter.tick` each tick and clears it.
  - `src/ai/ai_agent.gd`: adds the runtime `chat` dict, which is not saved.
  - `src/ai/ai_brain.gd`: idle pick, on-screen agents only.
  - `src/actors/ai_player.gd`: bubble, `face_toward`, hooks, `_idle_think`.
  - `src/actors/player.gd`: registers itself and adds the kill hook.
  - `src/main.gd`: QA mute and the screenshot mode.
  - `src/tests/selftest.gd`: Prayer test fixes and the chatter suite.

The save format is unchanged; old saves load as before. To tune or add lines, edit only `data/ai_chatter.json`.

## Ideas for the next step (not done)
- Small emote icons (!, ♪, zzz) as an alternative to text when the screen is busy.
- AIs remembering the player (whether you traded with them or killed near them) to change their greeting.
- Small groups: two same-persona AIs walking to a mine together.
