class_name SkillRunner
extends RefCounted
## 24 種棋子的技能行為。數值一律來自 units.json 的 skill.params，經 UnitStats 依星級換算。
## cast() 回傳 false 代表沒有有效目標，不消耗魔力。

const KINDS := ["self_shield", "mark_prey", "area_cc", "dash_strike", "heal_lowest", "shield_taunt", "rally",
	"strike", "blood_rage", "warlord_roar", "rapid_shot", "brace", "thunder_charge", "living_bark",
	"rejuvenate", "forest_prayer", "bleed_strike", "curse", "shadow_step", "hellfire"]

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
					sim.apply_cc(u, e, str(_p(u, "cc_kind", "slow")), _cc(u), float(_p(u, "pct", 0)))
			return true

		"dash_strike":
			var list := _sorted_enemies(sim, u, str(_p(u, "pick", "nearest")))
			if list.is_empty():
				return false
			var tg: CombatUnit = list[0]
			sim.dash_next_to(u, tg)
			_cast_event(sim, u, COLORS["physical"], [tg.cell], tg.cid)
			sim.deal_damage(u, tg, _amt(u, "dmg"), _dtype(u), "skill", false)
			if tg.alive and float(_p(u, "armor", 0)) > 0.0:
				sim.add_status(tg, "armor_down", float(_p(u, "armor", 0)), float(_p(u, "dur", 4)), u.cid)
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
			sim.deal_damage(u, tg, _amt(u, "dmg"), _dtype(u), "skill", false)
			if tg.alive and float(_p(u, "armor", 0)) > 0.0:
				sim.add_status(tg, "armor_down", float(_p(u, "armor", 0)), float(_p(u, "dur", 4)), u.cid)
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
			sim.add_periodic(u, tg, "dot", _amt(u, "dot"), float(_p(u, "dur", 3)), "physical")
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
					sim.add_periodic(u, e, "dot", _amt(u, "dot"), float(_p(u, "dur", 4)), "magic")
			return true

	push_warning("未實作的技能種類：%s（%s）" % [kind, u.unit_id])
	return false
