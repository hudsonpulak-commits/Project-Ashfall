extends Node
## The world heartbeat. Everything that changes game state does so on a tick
## (0.6 s), never per-frame; rendering interpolates between ticks via alpha().
## Exactly one listener (the Simulation in main.gd) drives actors in a fixed
## order so results are deterministic; UI may listen too but must not mutate.

signal ticked(tick: int)

const TICK_SECONDS := 0.6

var tick_count: int = 0
var running: bool = true
var time_scale: float = 1.0
var _acc: float = 0.0
## 0.3.19 QA (not the perf scenario): each rendered frame is 1/60 s of game
## time, and now_ms() advances 16 ms per frame. Waits then don't expire early
## when a loaded machine draws slowly.
var fixed_step := false
var virtual_msec := 0
var _virtual_ready := false


func _process(delta: float) -> void:
	if fixed_step:
		if not _virtual_ready:
			virtual_msec = Time.get_ticks_msec()
			_virtual_ready = true
		else:
			virtual_msec += 16
	if not running:
		return
	var d := (1.0 / 60.0) if fixed_step else delta
	_acc += minf(d, 0.25) * time_scale
	while _acc >= TICK_SECONDS:
		_acc -= TICK_SECONDS
		step()


## Wall clock, or the QA virtual clock when fixed_step is on.
func now_ms() -> int:
	return virtual_msec if fixed_step else Time.get_ticks_msec()


## Advance exactly one tick (also used by headless tests to fast-forward).
func step() -> void:
	tick_count += 1
	ticked.emit(tick_count)


## 0..1 progress towards the next tick, for smooth movement.
func alpha() -> float:
	return clampf(_acc / TICK_SECONDS, 0.0, 1.0)
