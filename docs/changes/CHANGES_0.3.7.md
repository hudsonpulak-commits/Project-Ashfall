# AshFall 0.3.7 (versionCode 15)
- Quest system (data/quests.json): quests are made of kill and talk stages. Per-quest state (not started, in progress, ready to turn in, completed) is saved with the player. Old saves load with every quest not started.
- Quest givers show "?" (quest available) or "!" (ready to turn in) overhead, on the minimap and on the world map. Nothing shows while you're hunting or after the quest is done.
- New Quests tab (Quest Journal): name, description and progress (e.g. "Kill 5 goblins: Goblins 3/5"), coloured red (not started), yellow (in progress) or green (completed). Your Influence total is shown at the top.
- Influence: a new saved player value. Every quest gives Influence, plus optional marks and items.
- Guidance arrow at the screen edge: points to the nearest goblin within 40 tiles, the Goblin Warlord (any distance) or Kell when it's time to report. It hides when the target is on screen.
- First quest, Goblin Slayer: Kell (Fenhollow plaza) asks for 5 goblins. Report back, then kill the level 12 Goblin Warlord south of Millbrook and turn in for +10 Influence, 150 marks and an iron sword. Only your own kills count; AI kills don't.
- Goblin Warlord: a new reusable enemy (level 12, 42 HP = 28 × 1.5, max hit 6, defence 7) that respawns. The art is a placeholder, swappable through sprites.json actors.goblin_warlord.
- XP feedback: every XP gain goes through Skills.add_xp, and the gains from one tick become one log line, e.g. "+12 Attack XP, +4 Vitality XP". The Skills panel shows XP gained this session for each skill (resets on load) and XP to the next level.
- Tests: Patch037Tests unit tests. New QA scenarios "quest" (C29: Goblin Slayer start to finish) and "xp" (C30: melee, chopping, mining and cooking XP lines and the tracker). The guard patrol test now parks wandering citizens and AIs so it no longer fails at random.
