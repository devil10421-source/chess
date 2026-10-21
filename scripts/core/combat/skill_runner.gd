class_name SkillRunner
extends RefCounted
## 34 種棋子（六族 24＋中立 10）的技能行為。數值一律來自 units.json 的 skill.params，經 UnitStats 依星級換算。
## cast() 回傳 false 代表沒有有效目標，不消耗魔力。

const KINDS := ["self_shield", "mark_prey", "area_cc", "dash_strike", "heal_lowest", "shield_taunt", "rally",
	"strike", "blood_rage", "warlord_roar", "rapid_shot", "brace", "thunder_charge", "living_bark",
	"rejuvenate", "forest_prayer", "bleed_strike", "curse", "shadow_step", "hellfire", "eldritch_pulse",
	"surround_guard", "focus_fire", "rune_ward", "oath_guard", "void_rift", "riposte", "shadow_dance", "prophecy"]

const COLORS := {
	"physical": "#ffb347", "magic": "#c27bff", "heal": "#59e38b", "shield": "#cfe8ff", "buff": "#ffd34d", "cc": "#7fd6ff",
}


static func _p(u: CombatUnit, key: String, default_value: Variant = 0.0) -> Variant:
	return u.data.get("skill", {}).get("params", {}).get(key, default_value)


static func _amt(u: CombatUnit, key: String) -> float:
	return UnitStats.skill_amount(u.unit_id, u.star, key)


static func _cc(u: CombatUnit) -> float:
	return UnitStats.cc_duration(float(_p(u, "cc", 1.0)), u.star)


static func _dtype(u: CombatUnit) -> String:
	return str(_p(u, "dtype", "physical"))


static func _cast_event(sim: CombatSim, u: CombatUnit, color: String, cells: Array, tgt_cid: int = -1) -> void:
	sim.emit({"k": "cast", "cid": u.cid, "name": str(u.data.get("skill", {}).get("name", "")), "cells": cells,
		"color": color, "tgt": tgt_cid})


static func _current_or_nearest(sim: CombatSim, u: CombatUnit) -> CombatUnit:
	var cur := sim.unit_by_cid(u.target_cid)
	if cur != null and cur.alive and cur.side != u.side:
		return cur
	var info := sim.acquire_target(u)
	return info.get("target")


static func _sorted_enemies(sim: CombatSim, u: CombatUnit, mode: String) -> Array:
	var list := sim.enemies_of(u)
	list.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		var da := HexGrid.distance(u.cell, a.cell)
		var db := HexGrid.distance(u.cell, b.cell)
		match mode:
			"farthest":
				if da != db:
					return da > db
			"lowest_hp":
				if not is_equal_approx(a.hp, b.hp):
					return a.hp < b.hp
			_:
				if da != db:
					return da < db
		if not is_equal_approx(a.hp, b.hp):
			return a.hp < b.hp
		return a.cid < b.cid)
	return list


static func _lowest_hp_allies(sim: CombatSim, u: CombatUnit) -> Array:
	var list := sim.allies_of(u)
	list.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if not is_equal_approx(a.hp_ratio(), b.hp_ratio()):
			return a.hp_ratio() < b.hp_ratio()
		return a.cid < b.cid)
	return list


static func _in_radius(list: Array, center: Vector2i, radius: int) -> Array:
	return list.filter(func(x: CombatUnit) -> bool: return HexGrid.distance(x.cell, center) <= radius)


## 技能附帶的自身穿透（V0.4 取代「破甲」）：params.pen（%）、pen_dur（秒）；穿透屬性依技能傷害屬性決定
static func _self_pen(sim: CombatSim, u: CombatUnit) -> void:
	var pen := float(_p(u, "pen", 0))
	if pen <= 0.0:
		return
	var kind := "magic_pen" if _dtype(u) == "magic" else "phys_pen"
	sim.add_status(u, kind, pen, float(_p(u, "pen_dur", 4)), u.cid, {"tag": "skill"})


## 這次能不能施放（給施法前搖判斷；與 cast() 的提早返回條件一致，不改變任何狀態）
static func can_cast(sim: CombatSim, u: CombatUnit) -> bool:
	var kind := str(u.data.get("skill", {}).get("kind", ""))
	match kind:
		"none", "focus_fire":
			return false
		"strike", "rapid_shot", "bleed_strike", "curse":
			# 需要目標在射程內：沒有鎖定目標時看最近的敵人是否在射程內
			var cur := sim.unit_by_cid(u.target_cid)
			if cur != null and cur.alive and cur.side != u.side:
				return HexGrid.distance(u.cell, cur.cell) <= u.attack_range
			for e in sim.enemies_of(u):
				if HexGrid.distance(u.cell, e.cell) <= u.attack_range:
					return true
			return false
		"surround_guard":
			return sim.enemies_of(u).filter(func(e: CombatUnit) -> bool: return HexGrid.distance(e.cell, u.cell) <= 1).size() >= int(_p(u, "min_adj", 2))
		"shadow_dance":
			return _reachable_lowest_ratio(sim, u) != null
	return not sim.enemies_of(u).is_empty()


static func cast(sim: CombatSim, u: CombatUnit) -> bool:
	var kind := str(u.data.get("skill", {}).get("kind", ""))
	match kind:
		"none":
			return false

		"self_shield":
			_cast_event(sim, u, COLORS["shield"], [u.cell])
			sim.add_shield(u, u, _amt(u, "shield"), float(_p(u, "dur", 4)))
			return true

		"mark_prey":
			var tg := _current_or_nearest(sim, u)
			if tg == null:
				return false
			_cast_event(sim, u, COLORS["physical"], [tg.cell], tg.cid)
			sim.deal_damage(u, tg, _amt(u, "dmg"), _dtype(u), "skill", false)
			sim.add_status(tg, "mark", float(_p(u, "pct", 40)), float(_p(u, "dur", 4)), u.cid)
			u.target_cid = tg.cid
			return true

		"area_cc":
			var tg := _current_or_nearest(sim, u)
			if tg == null:
				return false
			var radius := int(_p(u, "radius", 1))
			var center := tg.cell
			_cast_event(sim, u, COLORS["cc"] if str(_p(u, "cc_kind", "")) == "slow" else COLORS["heal"], HexGrid.cells_in_range(center, radius), tg.cid)
			for e in _in_radius(sim.enemies_of(u), center, radius):
				sim.deal_damage(u, e, _amt(u, "dmg"), _dtype(u), "skill", false)
				if e.alive:
					sim.apply_cc(u, e, str(_p(u, "cc_kind", "slow")), _cc(u))
			return true

		"dash_strike":
			var list := _sorted_enemies(sim, u, str(_p(u, "pick", "nearest")))
			if list.is_empty():
				return false
			var tg: CombatUnit = list[0]
			sim.dash_next_to(u, tg)
			_cast_event(sim, u, COLORS["physical"], [tg.cell], tg.cid)
			_self_pen(sim, u)
			sim.deal_damage(u, tg, _amt(u, "dmg"), _dtype(u), "skill", false)
			u.target_cid = tg.cid
			return true

		"heal_lowest":
			var allies := _lowest_hp_allies(sim, u)
			if allies.is_empty():
				return false
			var a: CombatUnit = allies[0]
			_cast_event(sim, u, COLORS["heal"], [a.cell], a.cid)
			sim.heal(u, a, _amt(u, "heal"))
			return true

		"shield_taunt":
			var radius := int(_p(u, "radius", 2))
			_cast_event(sim, u, COLORS["shield"], HexGrid.cells_in_range(u.cell, radius))
			sim.add_shield(u, u, _amt(u, "shield"), float(_p(u, "dur", 4)))
			for e in _in_radius(sim.enemies_of(u), u.cell, radius):
				sim.apply_cc(u, e, "taunt", _cc(u))
			return true

		"rally":
			var radius := int(_p(u, "radius", 2))
			var dur := float(_p(u, "dur", 5))
			_cast_event(sim, u, COLORS["buff"], HexGrid.cells_in_range(u.cell, radius))
			for a in _in_radius(sim.allies_of(u), u.cell, radius):
				sim.add_status(a, "armor_up", float(_p(u, "armor", 15)), dur, u.cid)
				sim.add_status(a, "atk_up", float(_p(u, "pct", 20)), dur, u.cid)
			sim.add_shield(u, u, _amt(u, "shield"), dur)
			return true

		"strike":
			var tg := _current_or_nearest(sim, u)
			if tg == null or HexGrid.distance(u.cell, tg.cell) > u.attack_range:
				return false
			_cast_event(sim, u, COLORS["physical"], [tg.cell], tg.cid)
			_self_pen(sim, u)
			sim.deal_damage(u, tg, _amt(u, "dmg"), _dtype(u), "skill", false)
			return true

		"blood_rage":
			var low := u.hp_ratio() < 0.5
			var pct := float(_p(u, "pct2", 50)) if low else float(_p(u, "pct", 25))
			_cast_event(sim, u, COLORS["buff"], [u.cell])
			sim.add_status(u, "dmg_up", pct, float(_p(u, "dur", 5)), u.cid)
			sim.heal(u, u, _amt(u, "heal"))
			return true

		"warlord_roar":
			var radius := int(_p(u, "radius", 2))
			var dur := float(_p(u, "dur", 5))
			_cast_event(sim, u, COLORS["buff"], HexGrid.cells_in_range(u.cell, radius))
			sim.add_status(u, "atk_up", float(_p(u, "pct", 40)), dur, u.cid)
			sim.heal(u, u, _amt(u, "heal"))
			for a in _in_radius(sim.allies_of(u), u.cell, radius):
				if a != u and a.is_melee():
					sim.add_status(a, "dmg_up", float(_p(u, "pct2", 15)), dur, u.cid)
			return true

		"rapid_shot":
			var tg := _current_or_nearest(sim, u)
			if tg == null or HexGrid.distance(u.cell, tg.cell) > u.attack_range:
				return false
			_cast_event(sim, u, COLORS["physical"], [tg.cell], tg.cid)
			sim.emit({"k": "attack", "cid": u.cid, "tgt": tg.cid, "ranged": true})
			var raw := u.effective_atk() * float(_p(u, "atk_pct", 100)) / 100.0 + _amt(u, "dmg")
			sim.deal_damage(u, tg, raw, _dtype(u), "skill", false)
			if int(_p(u, "retreat", 0)) > 0:
				sim.retreat_step(u)   # 施法後後撤一格（風箏）
			return true

		"brace":
			_cast_event(sim, u, COLORS["shield"], [u.cell])
			sim.add_status(u, "phys_dr", float(_p(u, "pct", 45)), float(_p(u, "dur", 4)), u.cid)
			sim.heal(u, u, _amt(u, "heal"))
			return true

		"thunder_charge":
			var tg := _current_or_nearest(sim, u)
			if tg == null:
				return false
			var path := HexGrid.line(u.cell, tg.cell)
			var cells := {}
			for c in path:
				for n in HexGrid.cells_in_range(c, 1):
					cells[n] = true
			sim.dash_next_to(u, tg)
			_cast_event(sim, u, COLORS["magic"], cells.keys(), tg.cid)
			var hits: Array = sim.enemies_of(u).filter(func(e: CombatUnit) -> bool: return cells.has(e.cell))
			for e in hits:
				sim.deal_damage(u, e, _amt(u, "dmg"), _dtype(u), "skill", false)
				if e.alive:
					sim.apply_cc(u, e, "stun", _cc(u))
			u.target_cid = tg.cid
			return true

		"living_bark":
			_cast_event(sim, u, COLORS["shield"], [u.cell])
			sim.add_status(u, "armor_up", float(_p(u, "armor", 20)), float(_p(u, "dur", 4)), u.cid)
			sim.heal(u, u, _amt(u, "heal"))
			return true

		"rejuvenate":
			var allies := _lowest_hp_allies(sim, u)
			var n := mini(int(_p(u, "count", 2)), allies.size())
			if n <= 0:
				return false
			var picked: Array = allies.slice(0, n)
			var cells: Array = []
			for a in picked:
				cells.append(a.cell)
			_cast_event(sim, u, COLORS["heal"], cells)
			var dur := UnitStats.hot_duration(float(_p(u, "dur", 4)), u.star)
			for a in picked:
				sim.add_periodic(u, a, "hot", _amt(u, "hot"), dur)
			return true

		"forest_prayer":
			var radius := int(_p(u, "radius", 3))
			_cast_event(sim, u, COLORS["heal"], HexGrid.cells_in_range(u.cell, radius))
			for a in _in_radius(sim.allies_of(u), u.cell, radius):
				sim.heal(u, a, _amt(u, "heal"))
				sim.cleanse_one(a)
			return true

		"bleed_strike":
			var tg := _current_or_nearest(sim, u)
			if tg == null or HexGrid.distance(u.cell, tg.cell) > u.attack_range:
				return false
			_cast_event(sim, u, COLORS["physical"], [tg.cell], tg.cid)
			sim.deal_damage(u, tg, _amt(u, "dmg"), _dtype(u), "skill", false)
			sim.add_periodic(u, tg, "dot", _amt(u, "dot"), float(_p(u, "dur", 3)), "physical", "skill", "skill")
			return true

		"curse":
			var tg := _current_or_nearest(sim, u)
			if tg == null or HexGrid.distance(u.cell, tg.cell) > u.attack_range:
				return false
			_cast_event(sim, u, COLORS["magic"], [tg.cell], tg.cid)
			sim.deal_damage(u, tg, _amt(u, "dmg"), _dtype(u), "skill", false)
			sim.add_status(tg, "atk_down", float(_p(u, "pct", 30)), float(_p(u, "dur", 4)), u.cid)
			return true

		"shadow_step":
			var list := _sorted_enemies(sim, u, "farthest")
			if list.is_empty():
				return false
			var tg: CombatUnit = list[0]
			sim.dash_next_to(u, tg)
			_cast_event(sim, u, COLORS["physical"], [tg.cell], tg.cid)
			sim.deal_damage(u, tg, _amt(u, "dmg"), _dtype(u), "skill", false)
			u.target_cid = tg.cid
			if not tg.alive:
				var next_list := _sorted_enemies(sim, u, "lowest_hp")
				if not next_list.is_empty():
					var nt: CombatUnit = next_list[0]
					sim.dash_next_to(u, nt)
					_cast_event(sim, u, COLORS["physical"], [nt.cell], nt.cid)
					sim.deal_damage(u, nt, _amt(u, "dmg2"), _dtype(u), "skill", false)
					u.target_cid = nt.cid
			return true

		"hellfire":
			var tg := _current_or_nearest(sim, u)
			if tg == null:
				return false
			var radius := int(_p(u, "radius", 2))
			var center := tg.cell
			_cast_event(sim, u, COLORS["magic"], HexGrid.cells_in_range(center, radius), tg.cid)
			for e in _in_radius(sim.enemies_of(u), center, radius):
				sim.deal_damage(u, e, _amt(u, "dmg"), _dtype(u), "skill", false)
				if e.alive:
					sim.add_periodic(u, e, "dot", _amt(u, "dot"), float(_p(u, "dur", 4)), "magic", "skill", "skill")
			return true

		"eldritch_pulse":
			# 古神化身（最終首領）：全場法術傷害＋暈眩＋持續傷害，自身獲得魔法穿透與護盾
			var foes := sim.enemies_of(u)
			if foes.is_empty():
				return false
			var cells: Array = []
			for e in foes:
				cells.append(e.cell)
			_cast_event(sim, u, COLORS["magic"], cells)
			_self_pen(sim, u)
			for e in foes:
				sim.deal_damage(u, e, _amt(u, "dmg"), _dtype(u), "skill", false)
				if e.alive:
					sim.apply_cc(u, e, "stun", _cc(u))
					sim.add_periodic(u, e, "dot", _amt(u, "dot"), float(_p(u, "dur", 4)), "magic", "skill", "skill")
			sim.add_shield(u, u, _amt(u, "shield"), float(_p(u, "dur", 4)))
			return true

		# ---------- 中立陣營（V0.4） ----------
		"focus_fire":
			return false   # 被動技能：效果在普攻時處理（CombatSim.basic_attack）

		"surround_guard":
			var adj := sim.enemies_of(u).filter(func(e: CombatUnit) -> bool: return HexGrid.distance(e.cell, u.cell) <= 1)
			if adj.size() < int(_p(u, "min_adj", 2)):
				return false   # 沒被包圍：保留魔力
			_cast_event(sim, u, COLORS["shield"], [u.cell])
			sim.add_status(u, "armor_up", float(_p(u, "armor", 30)), float(_p(u, "dur", 4)), u.cid)
			return true

		"rune_ward":
			var radius := int(_p(u, "radius", 1))
			_cast_event(sim, u, COLORS["shield"], HexGrid.cells_in_range(u.cell, radius))
			for a in _in_radius(sim.allies_of(u), u.cell, radius):
				sim.add_shield(u, a, _amt(u, "shield"), float(_p(u, "dur", 4)))
			return true

		"oath_guard":
			var others: Array = _lowest_hp_allies(sim, u).filter(func(a: CombatUnit) -> bool: return a != u)
			var dur := float(_p(u, "link_dur", 5))
			_cast_event(sim, u, COLORS["shield"], [u.cell] + ([others[0].cell] if not others.is_empty() else []), others[0].cid if not others.is_empty() else -1)
			sim.add_shield(u, u, _amt(u, "shield"), float(_p(u, "dur", 5)))
			if not others.is_empty():
				var a: CombatUnit = others[0]
				sim.add_shield(u, a, _amt(u, "shield2"), float(_p(u, "dur", 5)))
				sim.add_status(a, "guard_link", 1.0, dur, u.cid, {"tag": "oath"})
			return true

		"void_rift":
			var center := _best_area_center(sim, u, int(_p(u, "radius", 1)))
			if center == HexGrid.INVALID:
				return false
			var cells := HexGrid.cells_in_range(center, int(_p(u, "radius", 1)))
			var delay := float(_p(u, "delay", 1.2))
			_cast_event(sim, u, COLORS["magic"], cells)
			sim.emit({"k": "rift", "cid": u.cid, "cells": cells, "delay": delay})
			sim.add_delayed({"at": sim.t + delay, "kind": "rift", "src": u.cid, "center": center, "radius": int(_p(u, "radius", 1)),
				"dmg": _amt(u, "dmg"), "dot": _amt(u, "dot"), "dur": float(_p(u, "dur", 3))})
			return true

		"riposte":
			_cast_event(sim, u, COLORS["shield"], [u.cell])
			sim.add_status(u, "parry", float(_p(u, "block", 60)), float(_p(u, "dur", 3)), u.cid,
				{"tag": "riposte", "counter_pct": float(_p(u, "atk_pct", 160))})
			return true

		"shadow_dance":
			var tg := _reachable_lowest_ratio(sim, u)
			if tg == null:
				return false   # 沒有可到達的目標：不施放、不卡住
			sim.dash_next_to(u, tg)
			var raw := u.effective_atk() * float(_p(u, "atk_pct", 220)) / 100.0
			_cast_event(sim, u, COLORS["physical"], [tg.cell], tg.cid)
			sim.deal_damage(u, tg, raw, "physical", "skill", false)
			u.target_cid = tg.cid
			if not tg.alive:
				var nt := _reachable_lowest_ratio(sim, u)
				if nt != null:
					sim.dash_next_to(u, nt)
					_cast_event(sim, u, COLORS["physical"], [nt.cell], nt.cid)
					sim.deal_damage(u, nt, raw * float(_p(u, "chase_pct", 60)) / 100.0, "physical", "skill", false)
					u.target_cid = nt.cid
			return true

		"prophecy":
			var allies := _lowest_hp_allies(sim, u)
			if allies.is_empty():
				return false
			var a: CombatUnit = allies[0]
			_cast_event(sim, u, COLORS["heal"], [a.cell], a.cid)
			sim.add_status(a, "blessing", float(_p(u, "threshold", 40)), float(_p(u, "dur", 6)), u.cid,
				{"tag": "prophecy", "heal": _amt(u, "heal"), "end_heal": _amt(u, "heal2")})
			sim._check_blessing(a)
			return true

	push_warning("未實作的技能種類：%s（%s）" % [kind, u.unit_id])
	return false


## 能覆蓋最多敵人的格子（範圍 radius）；同數時：包含目前目標者 → 離施法者近者 → 排序固定
static func _best_area_center(sim: CombatSim, u: CombatUnit, radius: int) -> Vector2i:
	var foes := sim.enemies_of(u)
	if foes.is_empty():
		return HexGrid.INVALID
	var cur := sim.unit_by_cid(u.target_cid)
	var best := HexGrid.INVALID
	var best_key: Array = []
	for c in HexGrid.all_cells():
		var n := 0
		for e in foes:
			if HexGrid.distance(e.cell, c) <= radius:
				n += 1
		if n == 0:
			continue
		var has_cur := 0 if (cur != null and cur.alive and HexGrid.distance(cur.cell, c) <= radius) else 1
		var key: Array = [-n, has_cur, HexGrid.distance(u.cell, c), c.y, c.x]
		if best_key.is_empty() or CombatSim._key_less(key, best_key):
			best = c
			best_key = key
	return best


## 虛空裂隙爆炸（延遲效果到期時由 CombatSim 呼叫）：只打當下站在範圍內的敵人
static func explode_rift(sim: CombatSim, e: Dictionary) -> void:
	var src := sim.unit_by_cid(int(e["src"]))
	if src == null:
		return
	var cells := HexGrid.cells_in_range(e["center"], int(e["radius"]))
	sim.emit({"k": "burst", "cid": src.cid, "cells": cells, "color": COLORS["magic"]})
	for foe in sim.alive_of(1 - src.side):
		if HexGrid.distance(foe.cell, e["center"]) <= int(e["radius"]):
			sim.deal_damage(src, foe, float(e["dmg"]), "magic", "skill", false)
			if foe.alive:
				sim.add_periodic(src, foe, "dot", float(e["dot"]), float(e["dur"]), "magic", "skill", "skill")


## 生命比例最低、且能到達（已相鄰或旁邊有空格）的敵人
static func _reachable_lowest_ratio(sim: CombatSim, u: CombatUnit) -> CombatUnit:
	var list := sim.enemies_of(u)
	list.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if not is_equal_approx(a.hp_ratio(), b.hp_ratio()):
			return a.hp_ratio() < b.hp_ratio()
		return a.cid < b.cid)
	for e in list:
		if HexGrid.distance(u.cell, e.cell) <= 1:
			return e
		for n in HexGrid.neighbors(e.cell):
			if not sim.occupancy.has(n):
				return e
	return null
