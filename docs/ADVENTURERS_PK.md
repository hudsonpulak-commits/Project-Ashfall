# 0.3.1 Adventurer AI and Scorch PK (as built, AI track)

Spec: `docs/specs/0.3.1_adventurers_pk.md`. Data: `data/adventurers.json`, `data/pk.json`,
`data/pk_zones.json` (stub, owned by the world track). Code: `src/ai/adventurer.gd` (AdvBrain),
`src/combat/pk_rules.gd` (PkRules); hooks in actor / player / ai_player / ai_brain / ai_director /
combat_rules / hud / ground_items. Tests: `src/tests/selftest_pk.gd`, `src/tests/soak_adv.gd`, QA `pk` + C18.

## Adventurer-class AI
- Personas with `"class": "adventurer"` in personas.json: hero (shown as "Adventurer"), raider and
  opportunist. They are spawned on top of the 40 as `adv_0..` (6 / 4 / 2 by default). The older
  "adventurer" persona is now labelled "Sellsword" (id kept for saves).
- They train Attack / Strength / Defence / Vitality (abstract fights use the same Combat formulas;
  detailed ones fight for real), bury bones (Prayer), pray (Prayer.ai_pick), eat (and cook their own
  rat meat), bank (stash) and keep a best-in-slot list by stats and level requirements.
- Target choice is generic: every enemy kind in enemies.json with camps is scored per camp:
  `xp_weight x XP/tick x xp_value + loot_weight x loot/tick - food cost`, times a travel factor;
  only "safe" targets (damage per kill <= 0.3 x max HP + 0.5 x food heals, level <= cb + 6).
  Camps in a PK zone need `scorch_min_level` and get `scorch_loot_bonus`, scaled down by raiders out.
- Gear: each trading round (at most every `gear_check_ticks` unless levels / coin change) it buys
  the best affordable upgrade per slot from the cheapest source in town: the Exchange, your
  player shop, or a shop line. If nothing in town sells it, it commissions a smith there
  (reference x 1.2, paid on delivery agent-to-agent; smiths fill it from stock or buy bars).
- Worn gear is drawn on the AI sprite (gear layers per slot and tier, weapon class aware).

## Scorch PK
- Zones from `data/pk_zones.json` (`GameData.pk_zones` if the world track loads it). `PkRules.is_pk(tile)`
  is the helper (World.is_pk was not added to avoid world.gd conflicts). PK zones are always
  multi-combat (CombatRules.is_multi).
- Anyone may attack anyone inside (player and AI); you can only attack an AI player while both
  of you are inside. First strike on someone who hasn't hit you: skulled 10 min (1000 ticks);
  hitting back never skulls.
- Death inside: keep the 3 most valuable item units (worn or packed; none while skulled); the
  rest + carried coin minus the 10 % healer fee drops in a pile private to the killer for 100
  ticks, then public (killed by a creature: private to you for 300). AI killers collect their pile
  (on screen by walking to it, off screen directly).
- Raiders: raid spots in the zone from raid_min_level, hunt weak / rich-looking victims
  (drop value x win odds >= 0.6), gang up, flee when losing; victims flee or fight back.
  Off-screen fights resolve by `PkRules.win_p` (logistic on time-to-kill ratio). Raiders sell
  looted gear on the Exchange (normal surplus selling).

## AI Scorch death = new player
- An AI killed inside a PK zone quits; `AdvBrain.reincarnate` gives the slot to a new player:
  id `<base>~<gen>`, new name and tint, persona re-rolled within its class (adventurer class:
  hero / raider / opportunist by population weights; others keep their persona), home re-rolled by
  home weights, skills as a new player (Vitality 10, others 1), starter kit (hatchet, pick, rod,
  bronze sword), 25 marks. Population stays constant.
- The old character's bank, kept items and open orders go to an estate sale (`estate:<old id>`)
  on the Exchange at 0.9 x reference; proceeds and its purse are sunk. Unsold after 7200 ticks
  is lost. AI deaths elsewhere and player deaths never reset. `data/pk.json ai.new_players`
  switches it off.
- Churches: `World.nearest_altar(tile)` (world track) is used if present: adventurers, acolytes and
  fighters in a town with an altar top their Prayer up during trading rounds.

## Later additions (0.3.1 AI track)
- **Living costs.** Adventurers live like players: they pay no inn bill (`daily_needs`) and no upkeep (`adventurers.json` `pays_inn: false`). Their coin sinks are food, gear, wear, commissions and PK fees. Before this change they drained about 15k marks over 30 days and never had money for gear.
- **Re-rolling the persona of a new player.** The new character's sub-type is drawn from the class population weights, plus `reroll_refill_weight` × the shortfall for any sub-type that is now under its target. Otherwise opportunists, who die most in the Scorch, were bred out of the population.
- **Visible gear on everyone.** The gear layers live in `Actor`, so the player gets the same layers as AI players. Art lookup order: `gear_item_<id>`, then `gear_<slot>_<class>_<tier>`, then `gear_<slot>_<tier>`. The sheet format is in docs/ART_GUIDE.md. QA scenario `gear`, check C19.
