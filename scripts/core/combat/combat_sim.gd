class_name CombatSim
extends RefCounted
## 固定步長、可重現的自動戰鬥模擬（企劃第 7 節）。
## 按下開始戰鬥時一次算完整場，輸出事件清單給畫面播放；畫面不做任何判定。
##
## 事件格式（皆含 t 與 k）：
##   move   {cid, from, to, dur}           dash  {cid, from, to}
##   attack {cid, tgt, ranged}             damage{src, tgt, v, absorbed, hp, shield, crit, dtype, basic, dot}
##   heal   {src, tgt, v, hp}              shield{src, tgt, v, shield, dur}
##   mana   {cid, v}                       cast  {cid, name, cells, color, tgt}
##   status {cid, kind, dur}               cleanse{cid, kind}
##   death  {cid}                          end   {cleared, time}

const EPS := 0.0001

var cfg: Dictionary
var rng: SeededRng
var units: Array = []          # Array[CombatUnit]，依 cid 排序
var occupancy: Dictionary = {} # Vector2i -> cid
var events: Array = []
var t := 0.0
var tick := 0.05
var max_time := 45.0
var _next_cid := 1


func _init(seed_value: int) -> void:
	cfg = GameData.cfg("combat")
	rng = SeededRng.new(seed_value)
	tick = float(cfg.get("tick", 0.05))
	max_time = float(cfg.get("max_time", 45.0))


# ---------- 建立單位 ----------
func add_unit(unit_id: String, star: int, cell: Vector2i, side: int, mods: Dictionary, uid: int = 0) -> CombatUnit:
	if occupancy.has(cell):
		push_error("格子 %s 已有單位" % str(cell))
		return null
	var u := CombatUnit.new()
	u.cid = _next_cid
	_next_cid += 1
	u.side = side
	u.uid = uid
	u.unit_id = unit_id
	u.star = star
	u.data = GameData.unit(unit_id)
	u.mods = mods
	u.cell = cell
	var s := UnitStats.final_stats(unit_id, star, mods)
	u.max_hp = s["hp"]
	u.hp = u.max_hp
	u.atk = s["atk"]
	u.armor = s["armor"]
	u.mr = s["mr"]
	u.atk_speed = s["atk_speed"]
	u.attack_range = s["range"]
	u.move_speed = s["move_speed"]
	u.mana_max = s["mana_max"]
	u.mana = minf(s["start_mana"], u.mana_max)
	u.crit_chance = s["crit_chance"]
	u.crit_mult = s["crit_mult"]
	units.append(u)
	occupancy[cell] = u.cid
	return u


func unit_by_cid(cid: int) -> CombatUnit:
	for u in units:
		if u.cid == cid:
			return u
	return null


func alive_of(side: int) -> Array:
	var out: Array = []
	for u in units:
		if u.alive and u.side == side:
			out.append(u)
	return out


func enemies_of(u: CombatUnit) -> Array:
	return alive_of(1 - u.side)


func allies_of(u: CombatUnit) -> Array:
	return alive_of(u.side)


func emit(e: Dictionary) -> void:
	e["t"] = snappedf(t, 0.001)
	events.append(e)


# ---------- 主迴圈 ----------
func run() -> Dictionary:
	var snaps: Array = []
	for u in units:
		snaps.append(u.snapshot())
	var steps := int(round(max_time / tick))
	var finished := false
	for i in steps + 1:
		t = i * tick
		_update_statuses()
		if _is_over():
			finished = true
			break
		for u in units:
			if not u.alive or t + EPS < u.ready_at:
				continue
			if u.has_status("stun"):
				continue
			_act(u)
		if _is_over():
			finished = true
			break
	if not finished:
		t = max_time
	var cleared := alive_of(1).is_empty()
	emit({"k": "end", "cleared": cleared, "time": t})
	var alive_enemies: Array = []
	for u in alive_of(1):
		alive_enemies.append({"id": u.unit_id, "star": u.star, "cid": u.cid})
	var stars: Array = []
	for e in alive_enemies:
		stars.append(e["star"])
	var stats: Array = []
	for u in units:
		stats.append({"cid": u.cid, "side": u.side, "id": u.unit_id, "star": u.star, "alive": u.alive,
			"damage": roundi(u.damage_dealt), "healing": roundi(u.healing_done), "casts": u.casts})
	return {
		"cleared": cleared,
		"time": t,
		"alive_enemies": alive_enemies,
		"threat": Economy.threat(stars),
		"player_alive": alive_of(0).size(),
		"units": snaps,
		"events": events,
		"stats": stats,
	}


func _is_over() -> bool:
	return alive_of(0).is_empty() or alive_of(1).is_empty()


func _act(u: CombatUnit) -> void:
	# 1) 魔力滿 → 施放技能
	if u.mana >= u.mana_max - EPS:
		if SkillRunner.cast(self, u):
			u.casts += 1
			u.mana = maxf(0.0, u.mana - u.mana_max)
			emit({"k": "mana", "cid": u.cid, "v": u.mana})
			u.ready_at = t + float(cfg.get("cast_time", 0.3))
			return
	# 2) 索敵
	var info := acquire_target(u)
	var tgt: CombatUnit = info.get("target")
	if tgt == null:
		u.ready_at = t + float(cfg.get("idle_retry", 0.2))
		return
	u.target_cid = tgt.cid
	# 3) 射程內 → 普攻
	if HexGrid.distance(u.cell, tgt.cell) <= u.attack_range:
		basic_attack(u, tgt)
		u.ready_at = t + 1.0 / u.effective_atk_speed()
		return
	# 4) 移動一格
	if u.has_status("root") or not info.has("step"):
		u.ready_at = t + float(cfg.get("idle_retry", 0.2))
		return
	var step: Vector2i = info["step"]
	var dur := 1.0 / u.effective_move_speed()
	move_unit(u, step, dur)
	u.ready_at = t + dur


# ---------- 索敵與找路 ----------
## 選目標：嘲諷優先；已鎖定且在射程內則保持；否則依「距離 → 血量 → ID」挑第一個可到達／可攻擊的敵人
func acquire_target(u: CombatUnit) -> Dictionary:
	var enemies := enemies_of(u)
	if enemies.is_empty():
		return {}
	for s in u.statuses:
		if s["kind"] == "taunt":
			var src := unit_by_cid(int(s["src"]))
			if src != null and src.alive:
				return _with_step(u, src)
	var cur := unit_by_cid(u.target_cid)
	if cur != null and cur.alive and cur.side != u.side and HexGrid.distance(u.cell, cur.cell) <= u.attack_range:
		return {"target": cur}
	enemies.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		var da := HexGrid.distance(u.cell, a.cell)
		var db := HexGrid.distance(u.cell, b.cell)
		if da != db:
			return da < db
		if not is_equal_approx(a.hp, b.hp):
			return a.hp < b.hp
		return a.cid < b.cid)
	var fallback := {}
	for e in enemies:
		var info := _with_step(u, e)
		if HexGrid.distance(u.cell, e.cell) <= u.attack_range or info.has("step"):
			return info
		if fallback.is_empty():
			fallback = info
	return fallback


## 回傳 {target, step?}：step 為朝「可攻擊到 target 的空格」前進的第一步
func _with_step(u: CombatUnit, tgt: CombatUnit) -> Dictionary:
	var out := {"target": tgt}
	if HexGrid.distance(u.cell, tgt.cell) <= u.attack_range:
		return out
	var goals := {}
	for c in HexGrid.cells_in_range(tgt.cell, u.attack_range):
		if not occupancy.has(c):
			goals[c] = true
	if goals.is_empty():
		return out
	var blocked := occupancy.duplicate()
	blocked.erase(u.cell)
	var path := HexGrid.find_path_step(u.cell, goals, blocked)
	if not path.is_empty() and path["step"] != u.cell:
		out["step"] = path["step"]
	return out


func move_unit(u: CombatUnit, to: Vector2i, dur: float) -> void:
	var from := u.cell
	occupancy.erase(from)
	occupancy[to] = u.cid
	u.cell = to
	emit({"k": "move", "cid": u.cid, "from": from, "to": to, "dur": dur})


## 瞬移／衝刺到 target 旁的空格（找不到空格則原地不動）。回傳是否有移動。
func dash_next_to(u: CombatUnit, tgt: CombatUnit) -> bool:
	if HexGrid.distance(u.cell, tgt.cell) <= 1:
		return false
	var options: Array = []
	for n in HexGrid.neighbors(tgt.cell):
		if not occupancy.has(n):
			options.append(n)
	if options.is_empty():
		return false
	options.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := HexGrid.distance(a, u.cell)
		var db := HexGrid.distance(b, u.cell)
		if da != db:
			return da < db
		return a.y * 10 + a.x < b.y * 10 + b.x)
	var to: Vector2i = options[0]
	var from := u.cell
	occupancy.erase(from)
	occupancy[to] = u.cid
	u.cell = to
	emit({"k": "dash", "cid": u.cid, "from": from, "to": to})
	return true


# ---------- 傷害、治療、護盾 ----------
func basic_attack(u: CombatUnit, tgt: CombatUnit) -> void:
	emit({"k": "attack", "cid": u.cid, "tgt": tgt.cid, "ranged": not u.is_melee()})
	deal_damage(u, tgt, u.effective_atk(), "physical", true, false)
	gain_mana(u, float(cfg.get("mana_per_attack", 10)))


func gain_mana(u: CombatUnit, amount: float) -> void:
	if not u.alive:
		return
	var before := u.mana
	u.mana = minf(u.mana_max, u.mana + amount)
	if u.mana != before:
		emit({"k": "mana", "cid": u.cid, "v": u.mana})


## 傷害公式：同類加成先加總 → 暴擊（僅普攻）→ 護甲／魔抗減免 → 物理減傷 → 護盾吸收；原始傷害 > 0 時至少 1。
func deal_damage(src: CombatUnit, tgt: CombatUnit, raw: float, dtype: String, is_basic: bool, is_dot: bool) -> float:
	if tgt == null or not tgt.alive or raw <= 0.0:
		return 0.0
	var m := src.mods
	var pct := 0.0
	if is_basic:
		pct += float(m.get("basic_dmg_pct", 0.0))
		pct += float(m.get("melee_basic_pct", 0.0)) if src.is_melee() else float(m.get("ranged_basic_pct", 0.0))
		var mark := tgt.status_from("mark", src.cid)
		if not mark.is_empty():
			pct += float(mark.get("value", 0.0))
	elif not is_dot:
		pct += float(m.get("skill_direct_pct", 0.0))
	if dtype == "magic":
		pct += float(m.get("magic_dmg_pct", 0.0))
		if not is_dot:
			pct += float(m.get("magic_direct_pct", 0.0))
	if not is_dot:
		pct += src.status_sum("dmg_up")
		if src.hp_ratio() < float(cfg.get("low_hp_threshold", 0.5)):
			pct += float(m.get("low_hp_direct_pct", 0.0))
	if tgt.hp_ratio() < float(cfg.get("execute_threshold", 0.35)):
		pct += float(m.get("execute_pct", 0.0))
	var amount := raw * maxf(0.0, 1.0 + pct / 100.0)
	var crit := false
	if is_basic and rng.randf() < src.crit_chance:
		amount *= src.crit_mult
		crit = true
	if dtype == "magic":
		amount = amount * 100.0 / (100.0 + maxf(0.0, tgt.effective_mr()))
	else:
		amount = amount * 100.0 / (100.0 + maxf(0.0, tgt.effective_armor()))
		var dr := minf(float(cfg.get("max_phys_reduction", 0.8)), tgt.status_sum("phys_dr") / 100.0)
		amount *= (1.0 - dr)
	var dmg := float(maxi(1, roundi(amount)))
	var absorbed := 0.0
	var remaining := dmg
	for s in tgt.shields:
		if remaining <= 0.0:
			break
		var take := minf(float(s["amount"]), remaining)
		s["amount"] = float(s["amount"]) - take
		remaining -= take
		absorbed += take
	tgt.shields = tgt.shields.filter(func(s): return float(s["amount"]) > 0.0)
	tgt.hp = maxf(0.0, tgt.hp - remaining)
	src.damage_dealt += dmg
	emit({"k": "damage", "src": src.cid, "tgt": tgt.cid, "v": dmg, "absorbed": absorbed, "hp": tgt.hp,
		"shield": tgt.shield_total(), "crit": crit, "dtype": dtype, "basic": is_basic, "dot": is_dot})
	if tgt.hp <= 0.0:
		kill(tgt)
	elif is_basic:
		gain_mana(tgt, float(cfg.get("mana_per_hit", 5)))
	return dmg


func kill(u: CombatUnit) -> void:
	if not u.alive:
		return
	u.alive = false
	u.statuses.clear()
	u.shields.clear()
	occupancy.erase(u.cell)
	emit({"k": "death", "cid": u.cid})


func heal(src: CombatUnit, tgt: CombatUnit, amount: float) -> float:
	if tgt == null or not tgt.alive or amount <= 0.0:
		return 0.0
	var mult := (1.0 + float(src.mods.get("heal_shield_pct", 0.0)) / 100.0) * (1.0 + float(tgt.mods.get("heal_received_pct", 0.0)) / 100.0)
	var v := minf(tgt.max_hp - tgt.hp, roundf(amount * maxf(0.0, mult)))
	if v <= 0.0:
		return 0.0
	tgt.hp += v
	src.healing_done += v
	emit({"k": "heal", "src": src.cid, "tgt": tgt.cid, "v": v, "hp": tgt.hp})
	return v


func add_shield(src: CombatUnit, tgt: CombatUnit, amount: float, dur: float) -> void:
	if tgt == null or not tgt.alive or amount <= 0.0:
		return
	var v := roundf(amount * maxf(0.0, 1.0 + float(src.mods.get("heal_shield_pct", 0.0)) / 100.0))
	tgt.shields.append({"amount": v, "until": t + dur})
	emit({"k": "shield", "src": src.cid, "tgt": tgt.cid, "v": v, "shield": tgt.shield_total(), "dur": dur})


# ---------- 狀態 ----------
## 一般增減益（不受控制時間修正）
func add_status(tgt: CombatUnit, kind: String, value: float, dur: float, src_cid: int = -1, extra: Dictionary = {}) -> void:
	if tgt == null or not tgt.alive:
		return
	var s := {"kind": kind, "value": value, "until": t + dur, "src": src_cid}
	s.merge(extra)
	tgt.statuses.append(s)
	emit({"k": "status", "cid": tgt.cid, "kind": kind, "dur": dur})


## 控制效果（暈眩、定身、緩速、嘲諷）：base_dur 已含星級成長；再加上文明的施加／承受修正（各自最多 +0.2 秒）
func apply_cc(src: CombatUnit, tgt: CombatUnit, kind: String, base_dur: float, value: float = 0.0) -> void:
	if tgt == null or not tgt.alive:
		return
	var cap := float(cfg.get("civ_cc_extra_cap", 0.2))
	var dur := base_dur
	var out_pct := float(src.mods.get("cc_duration_pct", 0.0))
	var in_pct := float(tgt.mods.get("cc_received_pct", 0.0))
	if out_pct != 0.0:
		dur += clampf(base_dur * out_pct / 100.0, -cap, cap)
	if in_pct != 0.0:
		dur += clampf(base_dur * in_pct / 100.0, -cap, cap)
	add_status(tgt, kind, value, maxf(0.05, dur), src.cid)


## 持續傷害／治療：總量 total 分攤在 dur 秒內，每 dot_tick 秒結算一次
func add_periodic(src: CombatUnit, tgt: CombatUnit, kind: String, total: float, dur: float, dtype: String = "physical") -> void:
	if tgt == null or not tgt.alive or total <= 0.0:
		return
	var period := float(cfg.get("dot_tick", 0.5))
	var ticks := maxi(1, int(round(dur / period)))
	add_status(tgt, kind, 0.0, ticks * period + EPS, src.cid,
		{"next_tick": t + period, "tick_amount": total / ticks, "ticks_left": ticks, "dtype": dtype})


func cleanse_one(u: CombatUnit) -> String:
	for kind in CombatUnit.CLEANSE_ORDER:
		for i in u.statuses.size():
			if u.statuses[i]["kind"] == kind:
				u.statuses.remove_at(i)
				emit({"k": "cleanse", "cid": u.cid, "kind": kind})
				return kind
	return ""


func _update_statuses() -> void:
	for u in units:
		if not u.alive:
			continue
		# 持續效果結算
		for s in u.statuses.duplicate():
			if not s.has("next_tick"):
				continue
			while u.alive and int(s["ticks_left"]) > 0 and float(s["next_tick"]) <= t + EPS:
				s["ticks_left"] = int(s["ticks_left"]) - 1
				s["next_tick"] = float(s["next_tick"]) + float(cfg.get("dot_tick", 0.5))
				var src := unit_by_cid(int(s["src"]))
				if src == null:
					src = u
				if s["kind"] == "dot":
					deal_damage(src, u, float(s["tick_amount"]), str(s.get("dtype", "physical")), false, true)
				elif s["kind"] == "hot":
					heal(src, u, float(s["tick_amount"]))
		if not u.alive:
			continue
		u.statuses = u.statuses.filter(func(s): return float(s["until"]) > t + EPS and int(s.get("ticks_left", 1)) > 0)
		u.shields = u.shields.filter(func(s): return float(s["until"]) > t + EPS)
