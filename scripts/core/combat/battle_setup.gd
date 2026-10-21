class_name BattleSetup
extends RefCounted
## 把 RunState（玩家棋盤）與 StageData（敵軍）組成一場 CombatSim。


static func stage_units(round_no: int) -> Array:
	var out: Array = []
	var st := GameData.stage(round_no)
	for e in st.get("units", []):
		out.append({"id": str(e["id"]), "star": int(e["star"]), "cell": Vector2i(int(e["col"]), int(e["row"]))})
	return out


static func battle_seed(run_seed: int, round_no: int) -> int:
	var st := GameData.stage(round_no)
	return SeededRng.mix(run_seed, round_no * 1000 + int(st.get("seed", 0)))


## player_units：[{uid, id, star, cell}]
static func build(player_units: Array, civ_id: String, round_no: int, seed_value: int) -> CombatSim:
	var sim := CombatSim.new(seed_value)
	var p_ids: Array = []
	var p_items: Array = []
	for p in player_units:
		p_ids.append(p["id"])
		p_items.append(p.get("items", []))
	var p_mods := Modifiers.for_lineup(p_ids, civ_id, true, p_items)
	for i in player_units.size():
		var p: Dictionary = player_units[i]
		sim.add_unit(p["id"], int(p["star"]), p["cell"], 0, p_mods[i], int(p.get("uid", 0)), p.get("items", []))
	var enemies := stage_units(round_no)
	var e_ids: Array = []
	for e in enemies:
		e_ids.append(e["id"])
	var use_syn := bool(GameData.cfg("enemy").get("use_synergies", false))
	var e_mods := Modifiers.for_lineup(e_ids, "", use_syn)
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		sim.add_unit(e["id"], e["star"], e["cell"], 1, e_mods[i])
	return sim
