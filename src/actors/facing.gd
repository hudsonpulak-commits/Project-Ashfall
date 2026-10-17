class_name Facing
extends RefCounted
## Which way an actor's sprite faces. 0.3.0: IMMEDIATE, no hysteresis.
## The 0.2.5 hysteresis (persist/min-flip ticks, judged from the destination)
## made the avatar keep facing the old way after a real turn. Now:
##   - moving: face the x direction of this tick's movement, on the same tick;
##   - purely vertical movement (dx == 0): keep the previous facing;
##   - fighting while standing: face the target.
## Paths are straightened (Pathfinder.straighten), so a straight run never
## contains opposite x steps and facing can't oscillate within one.
## Set in exactly one place per actor (Actor.on_tick / Enemy.tick); _process only
## copies it to flip_h. Art opt-out: sprites.json actor "flip": false.

var left := false
var flips := 0               # total turns (tests / QA bot)
## 0.3.9 four-way facing: "side" (mirrored by `left`), "down" (front), "up" (back).
var dir := "side"


## 0.3.9 the dominant axis of the movement picks the sheet: mostly vertical ->
## back (up) / front (down); otherwise the side sheet, dx < 0 left, dx > 0 right.
## No movement keeps everything. Returns true if it turned.
func observe(dx: float, _t: int = 0, dy: float = 0.0) -> bool:
	if absf(dy) > absf(dx) + 0.001:
		var want_dir := "up" if dy < 0.0 else "down"
		if want_dir == dir:
			return false
		dir = want_dir
		flips += 1
		return true
	if absf(dx) < 0.001:
		return false
	if dir != "side":
		dir = "side"
		left = dx < 0.0
		flips += 1
		return true
	var want := dx < 0.0
	if want == left:
		return false
	left = want
	flips += 1
	return true


## Sheet row name for a facing (tests / QA).
static func sheet_for(f) -> String:
	return "back" if f.dir == "up" else ("front" if f.dir == "down" else "side")


static func cfg() -> Dictionary:
	return GameData.fx.get("facing", {})


## Walk/idle animation frame from continuous time (never reset per tick).
static func anim_frame(anim_t: float, fps: float, frames: int) -> int:
	return int(anim_t * fps) % maxi(1, frames)
