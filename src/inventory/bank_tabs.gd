class_name BankTabs
extends RefCounted
## 0.3.17 custom bank tabs (account-wide, every town vault). Tab 0 is the main tab
## (items with no tab), -1 = All. p.bank_tabs = [{"name", "icon"}],
## p.bank_tab_of = {item id: tab number 1..MAX}.

const MAX := 8
const ALL := -1


static func add(p, name: String = "") -> int:
	if p.bank_tabs.size() >= MAX:
		return -1
	p.bank_tabs.append({"name": name if name.strip_edges() != "" else "Tab %d" % (p.bank_tabs.size() + 1), "icon": ""})
	return p.bank_tabs.size()


static func rename(p, tab: int, name: String) -> void:
	if tab >= 1 and tab <= p.bank_tabs.size() and name.strip_edges() != "":
		p.bank_tabs[tab - 1]["name"] = name.strip_edges().left(12)


static func set_icon(p, tab: int, item_id: String) -> void:
	if tab >= 1 and tab <= p.bank_tabs.size() and not GameData.item(item_id).is_empty():
		p.bank_tabs[tab - 1]["icon"] = item_id


## Delete a tab: its items go back to the main tab, later tabs shift down.
static func remove(p, tab: int) -> void:
	if tab < 1 or tab > p.bank_tabs.size():
		return
	p.bank_tabs.remove_at(tab - 1)
	for id in p.bank_tab_of.keys():
		var t := int(p.bank_tab_of[id])
		if t == tab:
			p.bank_tab_of.erase(id)
		elif t > tab:
			p.bank_tab_of[id] = t - 1


static func assign(p, item_id: String, tab: int) -> void:
	if tab <= 0 or tab > p.bank_tabs.size():
		p.bank_tab_of.erase(item_id)
	else:
		p.bank_tab_of[item_id] = tab


static func tab_of(p, item_id: String) -> int:
	return int(p.bank_tab_of.get(item_id, 0))


## Container indices of the non-empty bank slots shown on `tab`, in slot order.
static func indices(p, bank: ItemContainer, tab: int) -> Array:
	var out := []
	for i in bank.slots.size():
		var s = bank.slots[i]
		if s != null and (tab == ALL or tab_of(p, str(s["id"])) == tab):
			out.append(i)
	return out


static func to_save(p) -> Dictionary:
	return {"tabs": p.bank_tabs.duplicate(true), "of": p.bank_tab_of.duplicate()}


static func from_save(p, d: Dictionary) -> void:
	p.bank_tabs = []
	for t in d.get("tabs", []):
		if typeof(t) == TYPE_DICTIONARY and p.bank_tabs.size() < MAX:
			p.bank_tabs.append({"name": str(t.get("name", "Tab")), "icon": str(t.get("icon", ""))})
	p.bank_tab_of = {}
	var of: Dictionary = d.get("of", {})
	for id in of.keys():
		var t := int(of[id])
		if t >= 1 and t <= p.bank_tabs.size():
			p.bank_tab_of[str(id)] = t
