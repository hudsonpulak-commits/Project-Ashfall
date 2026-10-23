class_name ItemContainer
extends RefCounted
## Slot-based item container. Used for the 24-slot pack (non-stackables take a
## slot each) and for the bank (always stacks, many slots).
## A slot is null or {"id": String, "qty": int, "dur": int (tools only)}.

signal changed()

var slots: Array = []
var always_stack: bool = false


func _init(size: int = 24, p_always_stack: bool = false) -> void:
	always_stack = p_always_stack
	slots.resize(size)


func size() -> int:
	return slots.size()


func _stacks(id: String) -> bool:
	if GameData.is_stackable(id):
		return true
	# Tools never stack (each keeps its own durability), even in the bank,
	# otherwise banking a worn tool would "repair" it.
	return always_stack and not GameData.item(id).has("tool")


## Index of the first slot holding `id`, or -1.
func find(id: String) -> int:
	for i in slots.size():
		if slots[i] != null and slots[i]["id"] == id:
			return i
	return -1


func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s["id"] == id:
			n += int(s["qty"])
	return n


func free_slots() -> int:
	var n := 0
	for s in slots:
		if s == null:
			n += 1
	return n


func is_full() -> bool:
	return free_slots() == 0


## How many of `id` could be added right now.
func room_for(id: String) -> int:
	if _stacks(id):
		for s in slots:
			if s != null and s["id"] == id:
				return 1 << 30
		return (1 << 30) if free_slots() > 0 else 0
	return free_slots()


## Adds up to qty; returns how many were actually added.
func add(id: String, qty: int = 1, dur: int = -1) -> int:
	if qty <= 0 or GameData.item(id).is_empty():
		return 0
	var added := 0
	if _stacks(id):
		for s in slots:
			if s != null and s["id"] == id:
				s["qty"] = int(s["qty"]) + qty
				changed.emit()
				return qty
		var idx := slots.find(null)
		if idx < 0:
			return 0
		slots[idx] = {"id": id, "qty": qty}
		changed.emit()
		return qty
	while added < qty:
		var idx := slots.find(null)
		if idx < 0:
			break
		var entry := {"id": id, "qty": 1}
		var tool: Dictionary = GameData.item(id).get("tool", {})
		if not tool.is_empty():
			entry["dur"] = dur if dur >= 0 else int(tool.get("durability", 100))
		slots[idx] = entry
		added += 1
	if added > 0:
		changed.emit()
	return added


## Removes up to qty; returns how many were removed.
func remove(id: String, qty: int = 1) -> int:
	var removed := 0
	for i in range(slots.size() - 1, -1, -1):
		if removed >= qty:
			break
		var s = slots[i]
		if s == null or s["id"] != id:
			continue
		var take := mini(int(s["qty"]), qty - removed)
		s["qty"] = int(s["qty"]) - take
		removed += take
		if int(s["qty"]) <= 0:
			slots[i] = null
	if removed > 0:
		changed.emit()
	return removed


func remove_at(index: int) -> Variant:
	var s = slots[index]
	slots[index] = null
	if s != null:
		changed.emit()
	return s


## 0.3.17 organizing: move slot a onto b (empty b = move, item in b = swap).
func move_slot(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= slots.size() or b >= slots.size() or slots[a] == null:
		return false
	var t = slots[b]
	slots[b] = slots[a]
	slots[a] = t
	changed.emit()
	return true


func has_all(req: Dictionary) -> bool:
	for id in req.keys():
		if count(id) < int(req[id]):
			return false
	return true


## Best tool in this container for `skill` -> slot index or -1.
func best_tool_index(skill: String) -> int:
	var best := -1
	var best_power := -1.0
	for i in slots.size():
		var s = slots[i]
		if s == null:
			continue
		var tool: Dictionary = GameData.item(s["id"]).get("tool", {})
		if tool.get("skill", "") == skill and float(tool.get("power", 0)) > best_power:
			best = i
			best_power = float(tool.get("power", 0))
	return best


## Wears the tool at `index` by one use. Returns true if it broke.
func wear_tool(index: int) -> bool:
	var s = slots[index]
	if s == null or not s.has("dur"):
		return false
	s["dur"] = int(s["dur"]) - 1
	if int(s["dur"]) <= 0:
		slots[index] = null
		changed.emit()
		return true
	return false


func clear() -> void:
	for i in slots.size():
		slots[i] = null
	changed.emit()


func to_save() -> Array:
	var out := []
	for s in slots:
		out.append(s.duplicate() if s != null else null)
	return out


func from_save(arr: Array) -> void:
	for i in slots.size():
		slots[i] = null
	for i in mini(arr.size(), slots.size()):
		var s = arr[i]
		if s != null and typeof(s) == TYPE_DICTIONARY and not GameData.item(str(s.get("id", ""))).is_empty():
			var e := {"id": str(s["id"]), "qty": int(s.get("qty", 1))}
			if s.has("dur"):
				e["dur"] = int(s["dur"])
			slots[i] = e
	changed.emit()
