class_name Synergy
extends RefCounted
## 羈絆計數（企劃第 9 節）：只計棋盤上「不同名稱」的棋子；候補區不算。


static func _tag(unit: Dictionary, group: String) -> String:
	return str(unit.get(group, ""))


## unit_ids：棋盤上每一隻棋子的 id（可重複）。
## 回傳 {"race": {"elf": 2, ...}, "type": {...}, "class": {...}}
static func count(unit_ids: Array) -> Dictionary:
	var distinct := {}
	for id in unit_ids:
		distinct[str(id)] = true
	var out := {"race": {}, "type": {}, "class": {}}
	for id in distinct.keys():
		var u := GameData.unit(id)
		if u.is_empty():
			continue
		for group in GameData.trait_groups():
			var key := _tag(u, group)
			if group == "race" and not GameData.traits().get("race", {}).has(key):
				continue   # 中立棋子：不計入任何種族羈絆，也沒有自己的陣營羈絆
			var d: Dictionary = out[group]
			d[key] = int(d.get(key, 0)) + 1
	return out


## 某羈絆在 n 種棋子時達到的階層索引（-1 = 未啟動）
static func tier_index(group: String, key: String, n: int) -> int:
	var tdef: Dictionary = GameData.traits().get(group, {}).get(key, {})
	var idx := -1
	var tiers: Array = tdef.get("tiers", [])
	for i in tiers.size():
		if n >= int(tiers[i]["count"]):
			idx = i
	return idx


## 已啟動的羈絆：[{group, key, count, tier, effects, text}]
static func active(counts: Dictionary) -> Array:
	var out: Array = []
	for group in GameData.trait_groups():
		var d: Dictionary = counts.get(group, {})
		for key in d.keys():
			var n := int(d[key])
			var ti := tier_index(group, key, n)
			if ti < 0:
				continue
			var tdef: Dictionary = GameData.traits()[group][key]
			var tier: Dictionary = tdef["tiers"][ti]
			out.append({"group": group, "key": key, "count": n, "tier": ti, "effects": tier.get("effects", []), "text": tier.get("text", "")})
	return out


## 給 UI 的完整清單（含未啟動）：[{group, key, name, count, thresholds, tier, text_next}]
static func summary(counts: Dictionary) -> Array:
	var out: Array = []
	for group in GameData.trait_groups():
		var d: Dictionary = counts.get(group, {})
		for key in d.keys():
			var n := int(d[key])
			var tdef: Dictionary = GameData.traits().get(group, {}).get(key, {})
			var thresholds: Array = []
			var texts: Array = []
			for t in tdef.get("tiers", []):
				thresholds.append(int(t["count"]))
				texts.append(str(t.get("text", "")))
			var ti := tier_index(group, key, n)
			out.append({"group": group, "key": key, "name": str(tdef.get("name", key)), "count": n,
				"thresholds": thresholds, "texts": texts, "tier": ti})
	out.sort_custom(func(a, b):
		if a["tier"] != b["tier"]:
			return a["tier"] > b["tier"]
		if a["count"] != b["count"]:
			return a["count"] > b["count"]
		return str(a["group"]) + str(a["key"]) < str(b["group"]) + str(b["key"]))
	return out


static func distinct_races(unit_ids: Array) -> int:
	return count(unit_ids)["race"].size()


## 羈絆詳細名單（給 UI）。board_units／bench_units：[{id, star}]。
## 回傳 {group, key, name, count, tier, thresholds, texts, members: [{id, name, cost, state, stars}]}
## state：board 已上場／bench 持有但未上場／none 尚未持有／unavailable 目前文明無法取得（其他文明的 4 費）
static func detail(group: String, key: String, board_units: Array, bench_units: Array, civ_id: String) -> Dictionary:
	var tdef: Dictionary = GameData.traits().get(group, {}).get(key, {})
	var board_ids: Array = []
	for u in board_units:
		board_ids.append(u["id"])
	var n := int(count(board_ids).get(group, {}).get(key, 0))
	var thresholds: Array = []
	var texts: Array = []
	for t in tdef.get("tiers", []):
		thresholds.append(int(t["count"]))
		texts.append(str(t.get("text", "")))
	var pool := Shop.full_pool(civ_id)
	var members: Array = []
	for u in GameData.units():
		if str(u.get(group, "")) != key:
			continue
		var id := str(u["id"])
		var on_board: Array = []
		var on_bench: Array = []
		for b in board_units:
			if b["id"] == id:
				on_board.append(int(b["star"]))
		for b in bench_units:
			if b["id"] == id:
				on_bench.append(int(b["star"]))
		var state := "none"
		if not on_board.is_empty():
			state = "board"
		elif not on_bench.is_empty():
			state = "bench"
		elif not pool.has(id):
			state = "unavailable"
		members.append({"id": id, "name": str(u["name"]), "cost": int(u["cost"]), "state": state,
			"stars": on_board if state == "board" else on_bench})
	var order := {"board": 0, "bench": 1, "none": 2, "unavailable": 3}
	members.sort_custom(func(a, b) -> bool:
		if order[a["state"]] != order[b["state"]]:
			return order[a["state"]] < order[b["state"]]
		return a["cost"] < b["cost"])
	return {"group": group, "key": key, "name": str(tdef.get("name", key)), "count": n, "tier": tier_index(group, key, n),
		"thresholds": thresholds, "texts": texts, "members": members}
