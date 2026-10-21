class_name ClashBattle
extends RefCounted
## 《氏族爭霸》一場戰鬥（全部沿用 CombatSim，同一套戰鬥邏輯與判定）：
##   pvp   ：玩家 A（下方，side 0）對 玩家 B（棋盤上下翻轉後放在上方，side 1）
##   ghost ：奇數人時的落單者對「另一名玩家陣容的鏡像」（只是戰鬥快照，不佔棋池、不影響原玩家）
##   coop  ：雙人合作 PvE。兩張獨立棋盤各自打同一組 PvE 敵軍；先清場的一方，存活棋子在行軍延遲後
##           以戰鬥快照（星級、裝備、修正值、剩餘生命與魔力）加入另一方的棋盤。全滅的一方戰場凍結等待救援。
##   solo  ：奇數人時落單者的單人 PvE（敵軍依 solo_scale 調整，沒有隊友救援）
## 本類別也是 BattlePlayer 的推進器（step_to／run／is_finished），讓畫面與模擬同步。

const EPS := 0.0001

var kind := "pvp"
var a := -1                 # 座位（side 0 的玩家）
var b := -1                 # pvp：對手座位；coop：隊友座位；ghost／solo：-1
var ghost_of := -1          # ghost：被複製陣容的玩家
var sims: Array = []        # [CombatSim]；coop 為 [A 的棋盤, B 的棋盤]
var labels: Array = []      # 每張棋盤上我方的國家名稱（援軍事件用）
var stage_round := 0
var pve_index := 0
var finished := false
var _tick := 0
var _tick_len := 0.05
var _arrivals: Array = []   # [{at, to, from, snaps}]
var _sent := [false, false]
## 給畫面的合作狀態：每張棋盤 "fighting"／"cleared"／"wiped"／"failed"＋援軍 "marching"／"arrived"
var reinforce_state := ["", ""]


# ---------- 陣容快照與修正值 ----------
## 玩家目前棋盤的戰鬥快照：[{uid, id, star, cell, items}] 與每隻的修正值（羈絆＋裝備＋國家制度）
static func lineup_snapshot(p: ClashPlayer) -> Dictionary:
	var lineup := p.run.board_lineup()
	return {"lineup": lineup, "mods": lineup_mods(p, lineup), "label": p.country, "seat": p.index}


static func lineup_sources(p: ClashPlayer, lineup: Array) -> Array:
	var ids: Array = []
	var its: Array = []
	for u in lineup:
		ids.append(u["id"])
		its.append(u.get("items", []))
	var src := Modifiers.sources_for_lineup(ids, "", true, its)
	var gov := ClashGovernment.sources_for(p, lineup)
	for i in src.size():
		(src[i] as Array).append_array(gov[i])
	return src


static func lineup_mods(p: ClashPlayer, lineup: Array) -> Array:
	var out: Array = []
	for list in lineup_sources(p, lineup):
		out.append(Modifiers.sum_sources(list))
	return out


## 對手棋盤上下翻轉（錯位六角：(c, r) → (6 − c, 7 − r)，相當於繞棋盤中心旋轉 180°）
static func mirror_cell(c: Vector2i) -> Vector2i:
	return Vector2i(HexGrid.COLS - 1 - c.x, HexGrid.ROWS - 1 - c.y)


static func _add_side(sim: CombatSim, snap: Dictionary, side: int) -> void:
	var lineup: Array = snap["lineup"]
	for i in lineup.size():
		var u: Dictionary = lineup[i]
		var cell: Vector2i = u["cell"] if side == 0 else mirror_cell(u["cell"])
		sim.add_unit(str(u["id"]), int(u["star"]), cell, side, snap["mods"][i], int(u["uid"]) if side == 0 else 0, u.get("items", []))


# ---------- 建立 ----------
static func make_pvp(snap_a: Dictionary, snap_b: Dictionary, seed_value: int, is_ghost: bool) -> ClashBattle:
	var bt := ClashBattle.new()
	bt.kind = "ghost" if is_ghost else "pvp"
	bt.a = int(snap_a["seat"])
	if is_ghost:
		bt.ghost_of = int(snap_b["seat"])
	else:
		bt.b = int(snap_b["seat"])
	var sim := CombatSim.new(seed_value)
	_add_side(sim, snap_a, 0)
	_add_side(sim, snap_b, 1)
	bt.sims = [sim]
	bt.labels = [str(snap_a["label"])]
	return bt


## 第 n 次 PvE 使用的敵軍（《六族遠征》的關卡回合）與強度倍率
static func pve_stage(pve_index: int) -> Dictionary:
	var c := GameData.clash_cfg("pve")
	var stages: Array = c.get("stages", [2])
	var i := clampi(pve_index - 1, 0, stages.size() - 1)
	var extra := maxi(0, pve_index - stages.size())
	return {"round": int(stages[i]), "scale": 1.0 + float(c.get("extra_scale_per_repeat", 0.25)) * extra}


static func _pve_sim(snap: Dictionary, stage_round: int, scale: float, seed_value: int, hold: bool) -> CombatSim:
	var sim := CombatSim.new(seed_value)
	_add_side(sim, snap, 0)
	var enemies := BattleSetup.stage_units(stage_round)
	var e_ids: Array = []
	for e in enemies:
		e_ids.append(e["id"])
	var e_mods := Modifiers.for_lineup(e_ids, "", bool(GameData.cfg("enemy").get("use_synergies", false)))
	for i in enemies.size():
		var m: Dictionary = e_mods[i]
		m["hp_pct"] = float(m.get("hp_pct", 0.0)) + (scale - 1.0) * 100.0
		m["atk_pct"] = float(m.get("atk_pct", 0.0)) + (scale - 1.0) * 100.0
		sim.add_unit(enemies[i]["id"], enemies[i]["star"], enemies[i]["cell"], 1, m)
	if hold:
		sim.hold_on_wipe = true
		sim.max_time = float(GameData.clash_cfg("pve").get("max_active_time", 45.0))
	return sim


static func make_coop(snap_a: Dictionary, snap_b: Dictionary, pve_index: int, seed_value: int) -> ClashBattle:
	var bt := ClashBattle.new()
	bt.kind = "coop"
	bt.a = int(snap_a["seat"])
	bt.b = int(snap_b["seat"])
	bt.pve_index = pve_index
	var st := pve_stage(pve_index)
	bt.stage_round = int(st["round"])
	var scale := float(st["scale"]) * float(GameData.clash_cfg("pve").get("duo_scale", 1.0))
	bt.sims = [_pve_sim(snap_a, bt.stage_round, scale, SeededRng.mix(seed_value, 1), true),
		_pve_sim(snap_b, bt.stage_round, scale, SeededRng.mix(seed_value, 2), true)]
	bt.labels = [str(snap_a["label"]), str(snap_b["label"])]
	bt.reinforce_state = ["fighting", "fighting"]
	return bt


static func make_solo(snap_a: Dictionary, pve_index: int, seed_value: int) -> ClashBattle:
	var bt := ClashBattle.new()
	bt.kind = "solo"
	bt.a = int(snap_a["seat"])
	bt.pve_index = pve_index
	var st := pve_stage(pve_index)
	bt.stage_round = int(st["round"])
	var scale := float(st["scale"]) * float(GameData.clash_cfg("pve").get("solo_scale", 0.85))
	bt.sims = [_pve_sim(snap_a, bt.stage_round, scale, seed_value, false)]
	bt.labels = [str(snap_a["label"])]
	bt.reinforce_state = ["fighting", ""]
	return bt


# ---------- 推進（BattlePlayer 與對局管理器共用） ----------
## 某座位在這場戰鬥中「自己的棋盤」
func sim_for(seat: int) -> CombatSim:
	if kind == "coop" and seat == b:
		return sims[1]
	return sims[0]


func is_finished() -> bool:
	return finished


func step_to(sim_time: float) -> void:
	for s in sims:
		(s as CombatSim).start()
	if kind != "coop":
		var s0: CombatSim = sims[0]
		s0.step_to(sim_time)
		finished = s0.finished
		return
	while not finished and _tick * _tick_len <= sim_time + EPS:
		_coop_tick()


func run() -> void:
	for s in sims:
		(s as CombatSim).start()
	if kind != "coop":
		(sims[0] as CombatSim).run()
		finished = true
		return
	var guard := 0
	while not finished and guard < 100000:
		guard += 1
		_coop_tick()


func _coop_tick() -> void:
	var now := _tick * _tick_len
	# 1) 到達的援軍加入目標棋盤（目標已結束就不需要）
	for arr in _arrivals.duplicate():
		if float(arr["at"]) <= now + EPS:
			_arrivals.erase(arr)
			var to := int(arr["to"])
			var target: CombatSim = sims[to]
			if not target.finished:
				var added := target.add_reinforcements(arr["snaps"], str(labels[int(arr["from"])]))
				if not added.is_empty():
					reinforce_state[int(arr["from"])] = "arrived"
					if reinforce_state[to] == "wiped":
						reinforce_state[to] = "fighting"
	# 2) 兩張棋盤同步推進一步（結束的不再推進）
	for s in sims:
		var sim: CombatSim = s
		if not sim.finished:
			sim.step()
	_tick += 1
	# 3) 狀態轉換：清場 → 派援軍；全滅 → 等待；無法救援 → 失敗
	for i in 2:
		var j := 1 - i
		var si: CombatSim = sims[i]
		var sj: CombatSim = sims[j]
		if si.holding and reinforce_state[i] == "fighting":
			reinforce_state[i] = "wiped"
		if si.finished and not _sent[i]:
			_sent[i] = true
			if bool(si.result().get("cleared", false)):
				reinforce_state[i] = "cleared"
				var snaps := si.survivor_snapshots()
				if not snaps.is_empty() and not sj.finished:
					_arrivals.append({"at": now + float(GameData.clash_cfg("pve").get("reinforce_delay", 1.5)), "to": j, "from": i, "snaps": snaps})
					reinforce_state[i] = "marching"
			else:
				reinforce_state[i] = "failed"
	for i in 2:
		var j := 1 - i
		var si: CombatSim = sims[i]
		var sj: CombatSim = sims[j]
		if si.holding and not si.finished and not _has_arrival_to(i):
			# 隊友已結束且沒有援軍要來，或雙方都在等待 → 無法救援，判定失敗
			if sj.finished or sj.holding:
				si.force_finish()
				reinforce_state[i] = "failed"
				_sent[i] = true
	if (sims[0] as CombatSim).finished and (sims[1] as CombatSim).finished:
		finished = true


func _has_arrival_to(i: int) -> bool:
	for arr in _arrivals:
		if int(arr["to"]) == i:
			return true
	return false


## 給畫面：某座位視角的合作狀態
func coop_status(seat: int) -> Dictionary:
	if kind != "coop":
		return {}
	var mine := 0 if seat == a else 1
	var other := 1 - mine
	var out := {}
	for k in [["me", mine], ["mate", other]]:
		var s: CombatSim = sims[k[1]]
		out[k[0]] = {"allies": s.alive_of(0).size(), "enemies": s.alive_of(1).size(), "state": reinforce_state[k[1]],
			"holding": s.holding, "finished": s.finished}
	out["incoming"] = _has_arrival_to(mine)
	out["outgoing"] = _has_arrival_to(other)
	return out


# ---------- 結果 ----------
## pvp／ghost：{winner: "a"／"b"／"draw", a_alive, b_alive, a_units: [star...], b_units: [star...]}
## coop／solo：{success}
func outcome() -> Dictionary:
	if kind == "coop":
		return {"success": bool((sims[0] as CombatSim).result().get("cleared", false)) and bool((sims[1] as CombatSim).result().get("cleared", false))}
	var s: CombatSim = sims[0]
	if kind == "solo":
		return {"success": bool(s.result().get("cleared", false))}
	var a_stars: Array = []
	var b_stars: Array = []
	for u in s.alive_of(0):
		a_stars.append(u.star)
	for u in s.alive_of(1):
		b_stars.append(u.star)
	var w := "draw"
	if b_stars.is_empty() and not a_stars.is_empty():
		w = "a"
	elif a_stars.is_empty() and not b_stars.is_empty():
		w = "b"
	return {"winner": w, "a_stars": a_stars, "b_stars": b_stars}
