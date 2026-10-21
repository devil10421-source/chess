class_name CombatSim
extends RefCounted
## 固定步長、可重現的自動戰鬥模擬（企劃第 7 節）。
## V0.5：改為逐步推進（step／step_to），畫面依播放時間推進模擬，所以戰鬥中可以即時介入（例如替場上棋子穿裝備）。
## 操作排入下一個步進的開頭套用並記錄在 op_log；用同一種子＋相同的 op_log（scheduled_ops）重跑，事件完全相同。
## run() 仍可一次跑完整場（測試、模擬 bot、略過動畫用）。畫面不做任何判定。
##
## 事件格式（皆含 t 與 k）：
##   move   {cid, from, to, dur}           dash  {cid, from, to}
##   attack {cid, tgt, ranged}             damage{src, tgt, v, absorbed, hp, shield, crit, dtype, source, basic, dot}
##   （damage.source 為傷害來源：basic 普攻／skill 技能／item 裝備（V0.3 預留）；dtype 為屬性：physical／magic）
##   heal   {src, tgt, v, hp}              shield{src, tgt, v, shield, dur}
##   mana   {cid, v}                       cast  {cid, name, cells, color, tgt}
##   status {cid, kind, dur, value, src}   cleanse{cid, kind}
##   death  {cid}                          end   {cleared, time}
##   item   {cid, kind, hp}（裝備被動，例如開戰時的生命交換）
##   retreat{cid, from, to, dur}（施法後後撤一格，例如草原弓手；播放時同 move）
##   rift   {cid, cells, delay}（延遲爆炸的範圍標記）   burst {cid, cells, color}（延遲效果引爆）
##   damage 另有 redirect_from（守護連結代為承受）、parried（返刃格擋）、counter（反擊）
##   cast_start {cid, name}（施法前搖）     items {cid, items, hp, max_hp}（戰鬥中更換裝備，之後的計算立即使用新數值）
##   attack.ranged＝true 時，傷害在投射物飛行時間後才結算（damage 事件時間＝命中時間）

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
## 延遲效果（例如虛空裂隙、遠程投射物）：{at, kind, src, ...}，依加入順序在到期的那一步結算
var _delayed: Array = []
## 逐步推進（V0.5）
var started := false
var finished := false
var _tick_index := 0
var _max_steps := 0
var _snaps: Array = []
var _result: Dictionary = {}
var _pending_ops: Array = []      # 等待下一步套用的操作
var op_log: Array = []            # 已套用的操作 [{tick, uid, items}]（重播用）
var scheduled_ops: Dictionary = {}  # 重播：tick -> [{uid, items}]


func _init(seed_value: int) -> void:
	cfg = GameData.cfg("combat")
	rng = SeededRng.new(seed_value)
	tick = float(cfg.get("tick", 0.05))
	max_time = float(cfg.get("max_time", 45.0))


# ---------- 建立單位 ----------
func add_unit(unit_id: String, star: int, cell: Vector2i, side: int, mods: Dictionary, uid: int = 0, items: Array = []) -> CombatUnit:
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
	u.front_rank = (cell.y - HexGrid.PLAYER_ROW_MIN) if side == 0 else (HexGrid.ENEMY_ROW_MAX - cell.y)
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
	u.items = items.duplicate()
	u.passives = ItemPassives.unique_passives(items)   # 相同唯一特性只生效一次
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


# ---------- 主迴圈（逐步推進） ----------
## 開戰：記錄開場快照、觸發「開戰時」的裝備特效（只觸發這一次；戰鬥中途穿上的裝備不會補觸發）
func start() -> void:
	if started:
		return
	started = true
	_snaps.clear()
	for u in units:
		_snaps.append(u.snapshot())
	for u in units:
		ItemPassives.on_battle_start(self, u)
	_max_steps = int(round(max_time / tick))


## 推進一步（固定時間 tick）。回傳 false 表示戰鬥已結束。
func step() -> bool:
	if finished:
		return false
	start()
	t = _tick_index * tick
	_apply_ops(_tick_index)
	_update_statuses()
	_run_delayed()
	if _is_over():
		_finish()
		return false
	for u in units:
		if not u.alive or t + EPS < u.ready_at:
			continue
		if u.has_status("stun"):
			continue
		_act(u)
	if _is_over():
		_finish()
		return false
	_tick_index += 1
	if _tick_index > _max_steps:
		t = max_time
		_finish()
		return false
	return true


## 推進到模擬時間 sim_time（含）為止
func step_to(sim_time: float) -> void:
	start()
	while not finished and _tick_index * tick <= sim_time + EPS:
		step()


## 目前已推進到的模擬時間
func now() -> float:
	return t


## 一次跑完整場（測試、bot、略過動畫）
func run() -> Dictionary:
	start()
	while step():
		pass
	return _result


func result() -> Dictionary:
	return _result


## 開場快照（開戰時每個單位的狀態）
func snapshots() -> Array:
	start()
	return _snaps


# ---------- 戰鬥中的操作（V0.5） ----------
## 替我方棋子（以玩家棋子 uid 指定）更換裝備：排入下一步開頭套用，之前已結算的事件不受影響
func queue_items(uid: int, items: Array) -> bool:
	if finished:
		return false
	for u in units:
		if u.side == 0 and u.uid == uid:
			_pending_ops.append({"uid": uid, "items": items.duplicate()})
			return true
	return false


func _apply_ops(tick_index: int) -> void:
	var ops: Array = scheduled_ops.get(tick_index, []).duplicate()
	ops.append_array(_pending_ops)
	_pending_ops.clear()
	for op in ops:
		for u in units:
			if u.side == 0 and u.uid == int(op["uid"]):
				apply_items(u, op["items"])
				op_log.append({"tick": tick_index, "uid": int(op["uid"]), "items": (op["items"] as Array).duplicate()})


## 立即套用新的裝備：移除舊裝備的數值、加上新裝備的數值、重新登記唯一特性。
## 生命上限增加時目前生命一起增加；減少時只把目前生命壓到新上限。初始魔力等「開戰時」效果不補觸發。
func apply_items(u: CombatUnit, items: Array) -> void:
	if not u.alive:
		return
	var mods := u.mods.duplicate()
	var old_m := Modifiers.item_mods(u.items)
	var new_m := Modifiers.item_mods(items)
	for k in old_m.keys():
		mods[k] = float(mods.get(k, 0.0)) - float(old_m[k])
	for k in new_m.keys():
		mods[k] = float(mods.get(k, 0.0)) + float(new_m[k])
	u.mods = mods
	u.items = items.duplicate()
	u.passives = ItemPassives.unique_passives(items)
	var s := UnitStats.final_stats(u.unit_id, u.star, mods)
	var delta_hp := float(s["hp"]) - u.max_hp
	u.max_hp = float(s["hp"])
	u.hp = minf(u.max_hp, u.hp + maxf(0.0, delta_hp))
	u.atk = s["atk"]
	u.armor = s["armor"]
	u.mr = s["mr"]
	u.atk_speed = s["atk_speed"]
	u.move_speed = s["move_speed"]
	u.crit_chance = s["crit_chance"]
	u.crit_mult = s["crit_mult"]
	emit({"k": "items", "cid": u.cid, "items": u.items.duplicate(), "hp": u.hp, "max_hp": u.max_hp, "atk": u.atk})


func _finish() -> void:
	if finished:
		return
	finished = true
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
		stats.append({"cid": u.cid, "uid": u.uid, "side": u.side, "id": u.unit_id, "star": u.star, "alive": u.alive,
			"damage": roundi(u.damage_dealt), "taken": roundi(u.damage_taken), "shielded": roundi(u.shield_absorbed),
			"healing": roundi(u.healing_done), "raw_damage": roundi(u.raw_damage), "overkill": roundi(u.overkill),
			"casts": u.casts, "target_switches": u.target_switches})
	_result = {
		"cleared": cleared,
		"time": t,
		"alive_enemies": alive_enemies,
		"threat": Economy.threat(stars),
		"player_alive": alive_of(0).size(),
		"units": _snaps,
		"events": events,
		"stats": stats,
		"ops": op_log.duplicate(true),
	}


func _is_over() -> bool:
	return alive_of(0).is_empty() or alive_of(1).is_empty()


func _act(u: CombatUnit) -> void:
	# 1) 魔力滿 → 施法前搖（cast_windup 秒，可看出要放技能）→ 施放技能（被動技能的單位沒有魔力，不會施放）
	if u.mana_max > 0.0 and u.mana >= u.mana_max - EPS:
		var windup := float(cfg.get("cast_windup", 0.0))
		if windup > 0.0 and not u.winding_up and SkillRunner.can_cast(self, u):
			u.winding_up = true
			emit({"k": "cast_start", "cid": u.cid, "name": str(u.data.get("skill", {}).get("name", "")), "dur": windup})
			u.ready_at = t + windup
			return
		u.winding_up = false
		if SkillRunner.cast(self, u):
			u.casts += 1
			u.mana = maxf(0.0, u.mana - u.mana_max)
			emit({"k": "mana", "cid": u.cid, "v": u.mana})
			ItemPassives.on_cast(self, u)
			u.ready_at = t + float(cfg.get("cast_time", 0.3))
			return
	# 2) 索敵（嘲諷只暫時覆蓋，不改變原本的鎖定）
	var info := acquire_target(u)
	var tgt: CombatUnit = info.get("target")
	if tgt == null:
		u.ready_at = t + float(cfg.get("idle_retry", 0.2))
		return
	if not info.get("forced", false) and tgt.cid != u.target_cid:
		var old := unit_by_cid(u.target_cid)
		if old != null and old.alive:
			u.target_switches += 1
		u.target_cid = tgt.cid
	# 3) 射程內 → 普攻（遠程：投射物飛行時間後才結算傷害，讓畫面命中與結算同步）
	if HexGrid.distance(u.cell, tgt.cell) <= u.attack_range:
		var flight := projectile_time(u, tgt)
		if flight > 0.0:
			emit({"k": "attack", "cid": u.cid, "tgt": tgt.cid, "ranged": true, "flight": flight})
			add_delayed({"at": t + flight, "kind": "projectile", "src": u.cid, "tgt": tgt.cid})
		else:
			basic_attack(u, tgt)
		u.ready_at = t + 1.0 / u.effective_atk_speed()
		return
	# 4) 移動一格
	if u.has_status("root") or not info.has("step"):
		u.ready_at = t + float(cfg.get("idle_retry", 0.2))
		return
	var step_cell: Vector2i = info["step"]
	var dur := 1.0 / u.effective_move_speed()
	move_unit(u, step_cell, dur)
	ItemPassives.on_move(self, u)
	u.ready_at = t + dur


## 遠程普攻的投射物飛行時間（近戰為 0）：projectile_base ＋ 每格 projectile_per_hex
func projectile_time(u: CombatUnit, tgt: CombatUnit) -> float:
	if u.is_melee():
		return 0.0
	return float(cfg.get("projectile_base", 0.0)) + float(cfg.get("projectile_per_hex", 0.0)) * HexGrid.distance(u.cell, tgt.cell)


# ---------- 索敵與找路 ----------
## 索敵規則（參數在 game_config.json → targeting）：
## 1. 被嘲諷：強制攻擊嘲諷者（forced），但不改變原本的鎖定目標，嘲諷結束後回到原目標。
## 2. 已鎖定目標且仍存活：持續追擊與攻擊，不因其他敵人變近而換目標。
##    只有在「既打不到、也找不到路接近」持續超過 stuck_retarget_time 秒時，才改找其他可到達的敵人（防卡死）。
## 3. 需要新目標時（開戰、目標死亡、卡死）依職能挑選：
##    - 遠程（射程 ≥ 2）：六角距離 → 血量 → 編號。
##    - 刺客：走到可攻擊位置的步數 → 血量 → 編號（不受前排掩護）。
##    - 其他近戰：步數 + front_weight × 目標部署深度 → 部署深度 → 正面欄位差 → 編號。
##      步數以 BFS 計算、會被其他棋子擋住，所以前排會自然掩護後排；但側翼若明顯更近仍可被突破。
func acquire_target(u: CombatUnit) -> Dictionary:
	var enemies := enemies_of(u)
	if enemies.is_empty():
		return {}
	var taunter := _taunter_of(u)
	if taunter != null:
		var forced := _with_step(u, taunter)
		forced["forced"] = true
		return forced
	var cur := unit_by_cid(u.target_cid)
	var exclude := -1
	if cur != null and cur.alive and cur.side != u.side:
		var info := _with_step(u, cur)
		if HexGrid.distance(u.cell, cur.cell) <= u.attack_range or info.has("step"):
			u.stuck_since = -1.0
			return info
		if u.stuck_since < 0.0:
			u.stuck_since = t
		if t - u.stuck_since < float(GameData.cfg("targeting").get("stuck_retarget_time", 1.5)) - EPS:
			return info
		exclude = cur.cid
	u.stuck_since = -1.0
	var picked := pick_new_target(u, exclude)
	if picked == null:
		return _with_step(u, cur) if cur != null and cur.alive else {}
	return _with_step(u, picked)


func _taunter_of(u: CombatUnit) -> CombatUnit:
	for s in u.statuses:
		if s["kind"] == "taunt":
			var src := unit_by_cid(int(s["src"]))
			if src != null and src.alive:
				return src
	return null


## 依職能挑新目標（不含 exclude_cid）。優先選可到達或已在射程內的敵人；全都到不了時回傳分數最好的那個（原地等待）。
func pick_new_target(u: CombatUnit, exclude_cid: int = -1) -> CombatUnit:
	var blocked := occupancy.duplicate()
	blocked.erase(u.cell)
	var dist := HexGrid.distance_map(u.cell, blocked)
	var weight := float(GameData.cfg("targeting").get("front_weight", 2))
	var best: CombatUnit = null
	var best_key: Array = []
	for e in enemies_of(u):
		if e.cid == exclude_cid:
			continue
		var steps := _steps_to_attack(u, e, dist)
		var reachable := 0 if steps < 999 else 1
		var key: Array
		if not u.is_melee():
			key = [reachable, HexGrid.distance(u.cell, e.cell), e.hp, e.cid]
		elif u.is_assassin():
			key = [reachable, steps, e.hp, e.cid]
		else:
			key = [reachable, steps + weight * e.front_rank, e.front_rank, absi(e.cell.x - u.cell.x), e.cid]
		if best == null or _key_less(key, best_key):
			best = e
			best_key = key
	return best


## 走到「能攻擊 e 的空格」需要的步數；已在射程內為 0；到不了為 999
func _steps_to_attack(u: CombatUnit, e: CombatUnit, dist: Dictionary) -> int:
	if HexGrid.distance(u.cell, e.cell) <= u.attack_range:
		return 0
	var best := 999
	for c in HexGrid.cells_in_range(e.cell, u.attack_range):
		if dist.has(c) and not occupancy.has(c):
			best = mini(best, int(dist[c]))
	return best


static func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


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
## 立即完成的普攻（近戰；也給測試直接呼叫）
func basic_attack(u: CombatUnit, tgt: CombatUnit) -> void:
	emit({"k": "attack", "cid": u.cid, "tgt": tgt.cid, "ranged": not u.is_melee()})
	basic_hit(u, tgt)


## 普攻命中結算（遠程在投射物抵達時呼叫）
func basic_hit(u: CombatUnit, tgt: CombatUnit) -> void:
	if tgt == null or not tgt.alive:
		return
	if u.has_passive_skill() and str(u.data.get("skill", {}).get("kind", "")) == "focus_fire":
		# 追跡：連續命中同一目標逐步提高普攻傷害；換目標重置
		if u.focus_target == tgt.cid:
			u.focus_stacks = mini(u.focus_stacks + 1, int(u.data["skill"]["params"].get("max_stacks", 5)))
		else:
			u.focus_target = tgt.cid
			u.focus_stacks = 0
	deal_damage(u, tgt, u.effective_atk(), "physical", "basic", false)
	gain_mana(u, float(cfg.get("mana_per_attack", 10)))
	ItemPassives.on_basic_hit(self, u, tgt)


func gain_mana(u: CombatUnit, amount: float) -> void:
	if not u.alive or u.mana_max <= 0.0:
		return
	var before := u.mana
	u.mana = minf(u.mana_max, u.mana + amount)
	if u.mana != before:
		emit({"k": "mana", "cid": u.cid, "v": u.mana})


## 傷害公式。source（來源）：basic 普攻／skill 技能／item 裝備；dtype（屬性）：physical 物理／magic 法術；is_dot：持續傷害的每次結算。
## 步驟：同類加成先加總 → 暴擊（僅普攻）→ 防禦減傷 max×D/(D+k) → 額外百分比減傷（如迎擊姿態）→ 護盾吸收；原始傷害 > 0 時至少 1。
## 持續傷害在「每次結算」時套用一次加成（施加時不乘），所以不會重複乘算。
func deal_damage(src: CombatUnit, tgt: CombatUnit, raw: float, dtype: String, source: String, is_dot: bool) -> float:
	if tgt == null or not tgt.alive or raw <= 0.0:
		return 0.0
	var pct := damage_bonus_pct(src, tgt, dtype, source, is_dot)
	var amount := raw * maxf(0.0, 1.0 + pct / 100.0)
	var crit := false
	if source == "basic" and rng.randf() < src.crit_chance:
		amount *= src.crit_mult
		crit = true
	var defense := tgt.effective_mr() if dtype == "magic" else tgt.effective_armor()
	amount *= 1.0 - effective_reduction(src, defense, dtype)
	if dtype != "magic":
		var dr := minf(float(cfg.get("max_phys_reduction", 0.8)), tgt.status_sum("phys_dr") / 100.0)
		amount *= (1.0 - dr)
	# 返刃（流浪劍聖）：架勢中第一次受到普攻，該次傷害降低並準備反擊
	var parry := {}
	if source == "basic" and not is_dot:
		for i in tgt.statuses.size():
			if tgt.statuses[i]["kind"] == "parry":
				parry = tgt.statuses[i]
				tgt.statuses.remove_at(i)
				emit({"k": "cleanse", "cid": tgt.cid, "kind": "parry"})
				break
		if not parry.is_empty():
			amount *= 1.0 - float(parry.get("value", 60)) / 100.0
	var dmg := float(maxi(1, roundi(amount)))
	src.raw_damage += dmg
	var hp_damage := _apply_hit(src, tgt, dmg, {"crit": crit, "dtype": dtype, "source": source, "dot": is_dot, "parried": not parry.is_empty()}, true)
	if crit:
		ItemPassives.on_crit(self, src, tgt)
	if tgt.alive and source == "basic":
		gain_mana(tgt, float(cfg.get("mana_per_hit", 5)))
		ItemPassives.on_basic_taken(self, tgt, src, dmg)
	ItemPassives.on_damage_dealt(self, src, hp_damage)
	# 反擊：視為技能傷害（不回魔、不會再觸發返刃），只反擊這一次
	if not parry.is_empty() and tgt.alive and src.alive:
		var counter_raw := tgt.effective_atk() * float(parry.get("counter_pct", 160)) / 100.0
		emit({"k": "attack", "cid": tgt.cid, "tgt": src.cid, "ranged": false, "counter": true})
		deal_damage(tgt, src, counter_raw, "physical", "skill", false)
	return dmg


## 結算一次傷害到 tgt：護盾吸收 → （致命時）守護連結轉移 → 扣生命 → 事件與統計 → 陣亡／祝福觸發。回傳有效 HP 傷害。
## allow_redirect：被轉移過來的傷害不會再被轉移（不會連鎖）。
func _apply_hit(src: CombatUnit, tgt: CombatUnit, dmg: float, meta: Dictionary, allow_redirect: bool) -> float:
	var absorbed := 0.0
	var remaining := dmg
	var absorb_by: Array = []
	for sh in tgt.shields:
		if remaining <= 0.0:
			break
		var take := minf(float(sh["amount"]), remaining)
		sh["amount"] = float(sh["amount"]) - take
		remaining -= take
		absorbed += take
		var provider := unit_by_cid(int(sh.get("src", tgt.cid)))
		if provider != null and take > 0.0:
			provider.shield_absorbed += take
			absorb_by.append([provider.cid, take])
	tgt.shields = tgt.shields.filter(func(x): return float(x["amount"]) > 0.0)
	# 守護誓約：即將承受致命傷害時，由施法的騎士承受這次剩下的傷害（一次連結只攔截一次）
	var guard: CombatUnit = null
	if allow_redirect and remaining >= tgt.hp - EPS and remaining > 0.0:
		for i in tgt.statuses.size():
			var st: Dictionary = tgt.statuses[i]
			if st["kind"] != "guard_link":
				continue
			var k := unit_by_cid(int(st["src"]))
			if k != null and k.alive and k != tgt:
				guard = k
				tgt.statuses.remove_at(i)
				emit({"k": "cleanse", "cid": tgt.cid, "kind": "guard_link"})
				break
	var moved := 0.0
	if guard != null:
		moved = remaining
		remaining = 0.0
	var hp_before := tgt.hp
	tgt.hp = maxf(0.0, tgt.hp - remaining)
	var hp_damage := hp_before - tgt.hp
	src.damage_dealt += hp_damage
	src.overkill += remaining - hp_damage
	tgt.damage_taken += hp_damage
	var e := {"k": "damage", "src": src.cid, "tgt": tgt.cid, "v": dmg, "absorbed": absorbed, "hp": tgt.hp,
		"shield": tgt.shield_total(), "crit": bool(meta.get("crit", false)), "dtype": str(meta.get("dtype", "physical")),
		"source": str(meta.get("source", "skill")), "basic": meta.get("source", "") == "basic", "dot": bool(meta.get("dot", false)),
		"hp_dmg": hp_damage, "absorb_by": absorb_by}
	if meta.has("redirect_from"):
		e["redirect_from"] = meta["redirect_from"]
	if bool(meta.get("parried", false)):
		e["parried"] = true
	emit(e)
	if tgt.hp <= 0.0:
		kill(tgt)
	else:
		_check_blessing(tgt)
	if guard != null:
		var m2 := meta.duplicate()
		m2["redirect_from"] = tgt.cid
		m2.erase("parried")
		hp_damage += _apply_hit(src, guard, moved, m2, false)
	return hp_damage


## 生命預言：生命比例低於門檻時立刻觸發一次治療（死亡的棋子不會觸發）
func _check_blessing(u: CombatUnit) -> void:
	if not u.alive:
		return
	for i in u.statuses.size():
		var st: Dictionary = u.statuses[i]
		if st["kind"] == "blessing" and u.hp_ratio() < float(st["value"]) / 100.0:
			u.statuses.remove_at(i)
			emit({"k": "cleanse", "cid": u.cid, "kind": "blessing"})
			var healer := unit_by_cid(int(st["src"]))
			heal(healer if healer != null else u, u, float(st.get("heal", 0.0)))
			return


## 穿透後的防禦減傷率：減傷率 × (1 − 穿透%)。按比例忽略既有減傷，不是扣除百分點；不會低於 0。
## 物理穿透只作用於物理傷害、魔法穿透只作用於魔法傷害；額外的百分比減傷（迎擊姿態）不受穿透影響。
static func reduction_after_pen(defense: float, pen_pct: float) -> float:
	return maxf(0.0, UnitStats.defense_reduction(defense) * (1.0 - clampf(pen_pct, 0.0, 100.0) / 100.0))


func effective_reduction(src: CombatUnit, defense: float, dtype: String) -> float:
	return reduction_after_pen(defense, src.penetration(dtype) if src != null else 0.0)


## 傷害加成百分比（加總後一次套用）。拆成獨立函式方便測試與 UI 說明。
func damage_bonus_pct(src: CombatUnit, tgt: CombatUnit, dtype: String, source: String, is_dot: bool) -> float:
	var m := src.mods
	var pct := 0.0
	if source == "basic":
		pct += float(m.get("basic_dmg_pct", 0.0))
		pct += float(m.get("melee_basic_pct", 0.0)) if src.is_melee() else float(m.get("ranged_basic_pct", 0.0))
		if src.focus_stacks > 0 and src.focus_target == tgt.cid:
			pct += src.focus_stacks * float(src.data.get("skill", {}).get("params", {}).get("pct", 8))
		var mark := tgt.status_from("mark", src.cid)
		if not mark.is_empty():
			pct += float(mark.get("value", 0.0))
	elif source == "skill":
		pct += float(m.get("skill_dmg_pct", 0.0))          # 所有技能傷害（含技能造成的持續傷害）
		if not is_dot:
			pct += float(m.get("skill_direct_pct", 0.0))   # 只限技能直接傷害
	if dtype == "magic":
		pct += float(m.get("magic_dmg_pct", 0.0))
		if not is_dot:
			pct += float(m.get("magic_direct_pct", 0.0))
	if not is_dot:
		pct += src.status_sum("dmg_up")
		pct += ItemPassives.bonus_pct(src)
		if src.hp_ratio() < float(cfg.get("low_hp_threshold", 0.5)):
			pct += float(m.get("low_hp_direct_pct", 0.0))
	if tgt.hp_ratio() < float(cfg.get("execute_threshold", 0.35)):
		pct += float(m.get("execute_pct", 0.0))
	return pct


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
	if tgt.has_status("wound"):
		mult *= 1.0 - wound_pct() / 100.0   # 重傷：固定 −40%，不疊加，不影響護盾
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
	tgt.shields.append({"amount": v, "until": t + dur, "src": src.cid})
	emit({"k": "shield", "src": src.cid, "tgt": tgt.cid, "v": v, "shield": tgt.shield_total(), "dur": dur})


# ---------- 狀態 ----------
## 只會有一份的狀態（不同來源不相加，取最強效果、時間取較長者）：緩速、重傷
const UNIQUE_STATUSES := ["slow", "wound"]
## 同一來源重複施加時刷新（不重複堆疊）：持續傷害、持續治療、穿透增益、標記、守護連結、返刃架勢、生命祝福
const REFRESH_STATUSES := ["dot", "hot", "phys_pen", "magic_pen", "mark", "guard_link", "parry", "blessing"]


static func wound_pct() -> float:
	return float(GameData.cfg("combat").get("status", {}).get("wound_heal_reduction_pct", 40))


## 一般增減益（不受控制時間修正）
func add_status(tgt: CombatUnit, kind: String, value: float, dur: float, src_cid: int = -1, extra: Dictionary = {}) -> void:
	if tgt == null or not tgt.alive:
		return
	var s := {"kind": kind, "value": value, "until": t + dur, "src": src_cid}
	s.merge(extra)
	var tag := str(extra.get("tag", ""))
	for i in tgt.statuses.size():
		var old: Dictionary = tgt.statuses[i]
		if old["kind"] != kind:
			continue
		if kind in UNIQUE_STATUSES:
			old["until"] = maxf(float(old["until"]), t + dur)
			old["value"] = maxf(float(old["value"]), value)
			emit({"k": "status", "cid": tgt.cid, "kind": kind, "dur": float(old["until"]) - t, "value": old["value"], "src": src_cid})
			return
		if kind in REFRESH_STATUSES and int(old.get("src", -1)) == src_cid and str(old.get("tag", "")) == tag:
			tgt.statuses[i] = s
			emit({"k": "status", "cid": tgt.cid, "kind": kind, "dur": dur, "value": value, "src": src_cid})
			return
	tgt.statuses.append(s)
	emit({"k": "status", "cid": tgt.cid, "kind": kind, "dur": dur, "value": value, "src": src_cid})


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


## 持續傷害／治療：總量 total 分攤在 dur 秒內，每 dot_tick 秒結算一次。
## 不同施加者各自獨立；同一來源的同一效果（tag）重複施加時刷新（重新計時），不會無限堆疊。
func add_periodic(src: CombatUnit, tgt: CombatUnit, kind: String, total: float, dur: float, dtype: String = "physical", source: String = "skill", tag: String = "") -> void:
	if tgt == null or not tgt.alive or total <= 0.0:
		return
	var period := float(cfg.get("dot_tick", 0.5))
	var ticks := maxi(1, int(round(dur / period)))
	add_status(tgt, kind, 0.0, ticks * period + EPS, src.cid,
		{"next_tick": t + period, "tick_amount": total / ticks, "ticks_left": ticks, "dtype": dtype, "source": source,
		"tag": tag if tag != "" else source})


# ---------- 延遲效果 ----------
func add_delayed(e: Dictionary) -> void:
	_delayed.append(e)


func _run_delayed() -> void:
	if _delayed.is_empty():
		return
	var due: Array = _delayed.filter(func(x): return float(x["at"]) <= t + EPS)
	if due.is_empty():
		return
	_delayed = _delayed.filter(func(x): return float(x["at"]) > t + EPS)
	for e in due:
		match str(e["kind"]):
			"rift":
				SkillRunner.explode_rift(self, e)
			"projectile":
				var src := unit_by_cid(int(e["src"]))
				var tgt := unit_by_cid(int(e["tgt"]))
				if src != null and tgt != null and tgt.alive:
					basic_hit(src, tgt)


## 施法後後撤一格（草原弓手）：只走到相鄰合法空格；優先拉開與最近敵人的距離，
## 不走到會被更多敵人攻擊的位置；同分時保留在原目標射程內者優先，再依格子座標固定排序。沒有合適空格就不動。
func retreat_step(u: CombatUnit) -> bool:
	if not u.alive or u.has_status("root") or u.has_status("stun"):
		return false
	var foes := enemies_of(u)
	if foes.is_empty():
		return false
	var here := _retreat_eval(u.cell, foes)
	var tgt := unit_by_cid(u.target_cid)
	var best := Vector2i(-1, -1)
	var best_key: Array = []
	for c in HexGrid.neighbors(u.cell):
		if occupancy.has(c):
			continue
		var ev := _retreat_eval(c, foes)
		if int(ev["threat"]) > int(here["threat"]):
			continue
		if int(ev["near"]) < int(here["near"]) or (int(ev["near"]) == int(here["near"]) and int(ev["threat"]) >= int(here["threat"])):
			continue
		var keep := 0 if (tgt != null and tgt.alive and HexGrid.distance(c, tgt.cell) <= u.attack_range) else 1
		var key: Array = [-int(ev["near"]), int(ev["threat"]), keep, -int(ev["sum"]), c.y, c.x]
		if best_key.is_empty() or _key_less(key, best_key):
			best = c
			best_key = key
	if best_key.is_empty():
		return false
	var from := u.cell
	var dur := float(cfg.get("status", {}).get("retreat_move_time", 0.25))
	occupancy.erase(from)
	occupancy[best] = u.cid
	u.cell = best
	emit({"k": "retreat", "cid": u.cid, "from": from, "to": best, "dur": dur})
	return true


## 某格對敵人的情勢：near＝最近敵人距離、threat＝射程能打到這格的敵人數、sum＝與所有敵人距離總和
func _retreat_eval(c: Vector2i, foes: Array) -> Dictionary:
	var near := 999
	var threat := 0
	var total := 0
	for e in foes:
		var d := HexGrid.distance(c, e.cell)
		near = mini(near, d)
		total += d
		if d <= e.attack_range:
			threat += 1
	return {"near": near, "threat": threat, "sum": total}


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
					deal_damage(src, u, float(s["tick_amount"]), str(s.get("dtype", "physical")), str(s.get("source", "skill")), true)
				elif s["kind"] == "hot":
					heal(src, u, float(s["tick_amount"]))
		if not u.alive:
			continue
		# 生命預言：時間到仍未觸發 → 結束時治療
		for s in u.statuses:
			if s["kind"] == "blessing" and float(s["until"]) <= t + EPS:
				var healer := unit_by_cid(int(s["src"]))
				heal(healer if healer != null else u, u, float(s.get("end_heal", 0.0)))
		u.statuses = u.statuses.filter(func(s): return float(s["until"]) > t + EPS and int(s.get("ticks_left", 1)) > 0)
		u.shields = u.shields.filter(func(s): return float(s["until"]) > t + EPS)
