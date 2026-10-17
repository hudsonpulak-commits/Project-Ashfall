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


func _process(delta: float) -> void:
	if not running:
		return
	_acc += minf(delta, 0.25) * time_scale
	while _acc >= TICK_SECONDS:
		_acc -= TICK_SECONDS
		step()


## Advance exactly one tick (also used by headless tests to fast-forward).
func step() -> void:
	tick_count += 1
	ticked.emit(tick_count)


## 0..1 progress towards the next tick, for smooth movement.
func alpha() -> float:
	return clampf(_acc / TICK_SECONDS, 0.0, 1.0)
