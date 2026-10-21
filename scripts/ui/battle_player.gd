class_name BattlePlayer
extends Node
## 依時間播放 CombatSim 產生的事件清單。只負責動畫，不做任何戰鬥判定。

signal finished
signal threat_changed(threat: int)

const TOKEN_SCENE := preload("res://scenes/unit_token.tscn")
const DMG_COLORS := {"physical": Color(1.0, 0.72, 0.35), "magic": Color(0.80, 0.55, 1.0)}

var board: BoardView
var _events: Array = []
var _index := 0
var _clock := 0.0          # 已播放到的模擬秒數
var _real := 0.0           # 實際播放經過秒數（已乘玩家選的 1×/2×/4×）
var _delay := 0.0          # 開場前短暫停頓（實際秒）
var _end_time := 0.0
var _playing := false
var _tokens: Dictionary = {}   # cid -> UnitToken
var _units: Dictionary = {}    # cid -> snapshot
var _alive_enemy: Dictionary = {}
## 戰鬥中即時狀態（只由事件重建，給資訊面板查看）：cid -> [{kind, value, until}]
var _live_status: Dictionary = {}
## 即時貢獻統計（由事件累加；結束時等於戰鬥模擬的 stats）：cid -> {damage, taken, shielded, healing}
var _live_stats: Dictionary = {}
var _selected_cid := -1


func is_playing() -> bool:
	return _playing


func play(result: Dictionary, board_view: BoardView) -> void:
	board = board_view
	clear()
	_events = result.get("events", [])
	_end_time = float(result.get("time", 0.0)) + 0.6
	_index = 0
	_clock = 0.0
	_real = 0.0
	_delay = 0.4
	for s in result.get("units", []):
		var tk: UnitToken = TOKEN_SCENE.instantiate()
		board.tokens_root.add_child(tk)
		tk.setup(s["id"], int(s["star"]), int(s["side"]), board.hex_size * 0.72)
		tk.cid = int(s["cid"])
		tk.position = board.cell_center(s["cell"])
		tk.show_bars = true
		tk.mana = float(s["mana"])
		tk.mana_max = float(s["mana_max"])
		tk.set_bars(float(s["hp"]), float(s["max_hp"]), 0.0)
		tk.items = s.get("items", [])
		_tokens[tk.cid] = tk
		_units[tk.cid] = s
		if int(s["side"]) == 1:
			_alive_enemy[tk.cid] = int(s["star"])
	_emit_threat()
	_playing = true


func clear() -> void:
	for t in _tokens.values():
		t.queue_free()
	_tokens.clear()
	_units.clear()
	_alive_enemy.clear()
	_live_status.clear()
	_live_stats.clear()
	_selected_cid = -1
	_playing = false
	if board:
		board.fx.clear()


func skip() -> void:
	if not _playing:
		return
	while _index < _events.size():
		_apply(_events[_index], true)
		_index += 1
	_finish()


func _process(delta: float) -> void:
	if not _playing:
		return
	if _delay > 0.0:
		_delay -= delta
		return
	# 播放加速：實際經過秒數 → 模擬秒數（PlaybackClock），再乘上玩家選的速度
	_real += delta * Session.battle_speed
	_clock = PlaybackClock.sim_from_real(_real)
	Session.playback_rate = PlaybackClock.rate_at_real(_real) * Session.battle_speed
	while _index < _events.size() and float(_events[_index]["t"]) <= _clock:
		_apply(_events[_index], false)
		_index += 1
	if _index >= _events.size() and _clock >= _end_time:
		_finish()


## 目前播放到的模擬秒數與實際秒數（UI 顯示用）
func sim_time() -> float:
	return _clock


func real_time() -> float:
	return _real


func _finish() -> void:
	_playing = false
	Session.playback_rate = Session.battle_speed
	finished.emit()


func _emit_threat() -> void:
	threat_changed.emit(Economy.threat(_alive_enemy.values()))


func _pos(cid: int) -> Vector2:
	var tk: UnitToken = _tokens.get(cid)
	return tk.position if tk else Vector2.ZERO


func _apply(e: Dictionary, instant: bool) -> void:
	var sp := maxf(0.1, Session.playback_rate)
	match str(e["k"]):
		"move":
			var tk: UnitToken = _tokens.get(int(e["cid"]))
			if tk:
				tk.move_to(board.cell_center(e["to"]), 0.0 if instant else float(e["dur"]) / sp)
		"dash":
			var tk: UnitToken = _tokens.get(int(e["cid"]))
			if tk:
				tk.move_to(board.cell_center(e["to"]), 0.0 if instant else 0.12 / sp)
		"attack":
			if instant:
				return
			var src: UnitToken = _tokens.get(int(e["cid"]))
			var dst: UnitToken = _tokens.get(int(e["tgt"]))
			if src and dst:
				if bool(e["ranged"]):
					board.fx.projectile(src.position, dst.position, Color(1, 0.95, 0.7), 0.18)
				else:
					src.lunge(dst.position, 0.22 / sp)
		"damage":
			_acc(int(e["src"]), "damage", float(e.get("hp_dmg", 0.0)))
			_acc(int(e["tgt"]), "taken", float(e.get("hp_dmg", 0.0)))
			for pair in e.get("absorb_by", []):
				_acc(int(pair[0]), "shielded", float(pair[1]))
			var tk: UnitToken = _tokens.get(int(e["tgt"]))
			if tk:
				tk.set_bars(float(e["hp"]), tk.max_hp, float(e["shield"]))
				if not instant:
					var col: Color = DMG_COLORS.get(str(e["dtype"]), Color.WHITE)
					if bool(e.get("dot", false)):
						col = Color(1.0, 0.45, 0.3)
					var txt := str(int(e["v"])) + ("!" if bool(e["crit"]) else "")
					board.fx.float_text(tk.position + Vector2(0, -board.hex_size * 0.5), txt, col, 22 if bool(e["crit"]) else 17)
					if float(e["absorbed"]) > 0.0 and float(e["v"]) <= float(e["absorbed"]):
						tk.flash(Color(0.9, 0.95, 1.0, 0.5), 0.2)
					else:
						tk.flash(Color(1, 0.2, 0.2, 0.35), 0.2)
		"heal":
			_acc(int(e["src"]), "healing", float(e["v"]))
			var tk: UnitToken = _tokens.get(int(e["tgt"]))
			if tk:
				tk.set_bars(float(e["hp"]), tk.max_hp, tk.shield)
				if not instant:
					board.fx.float_text(tk.position + Vector2(0, -board.hex_size * 0.5), "+" + str(int(e["v"])), UiStyle.GOOD, 17)
		"shield":
			var tk: UnitToken = _tokens.get(int(e["tgt"]))
			if tk:
				tk.set_bars(tk.hp, tk.max_hp, float(e["shield"]))
				if not instant:
					board.fx.ring(tk.position, Color(0.85, 0.95, 1.0), board.hex_size * 0.8)
		"mana":
			var tk: UnitToken = _tokens.get(int(e["cid"]))
			if tk:
				tk.mana = float(e["v"])
		"cast":
			if instant:
				return
			var tk: UnitToken = _tokens.get(int(e["cid"]))
			var col := Color(str(e.get("color", "#ffffff")))
			var centers: Array = []
			for c in e.get("cells", []):
				centers.append(board.cell_center(c))
			board.fx.area(centers, col)
			if tk:
				tk.flash(Color(col, 0.6), 0.4)
				board.fx.float_text(tk.position + Vector2(0, -board.hex_size * 1.2), str(e["name"]), Color(1, 0.9, 0.5), 15, 1.0)
		"status":
			var cid := int(e["cid"])
			var list: Array = _live_status.get(cid, [])
			list.append({"kind": str(e["kind"]), "value": float(e.get("value", 0.0)), "until": float(e["t"]) + float(e["dur"])})
			_live_status[cid] = list
			var tk: UnitToken = _tokens.get(cid)
			if tk and not instant:
				tk.add_status(str(e["kind"]), float(e["dur"]))
		"cleanse":
			var cid := int(e["cid"])
			var tk: UnitToken = _tokens.get(cid)
			if tk:
				tk.statuses.erase(str(e["kind"]))
			var list: Array = _live_status.get(cid, [])
			for i in list.size():
				if list[i]["kind"] == str(e["kind"]):
					list.remove_at(i)
					break
		"death":
			var cid := int(e["cid"])
			var tk: UnitToken = _tokens.get(cid)
			if tk:
				tk.die(0.0 if instant else 0.35 / sp)
				tk.show_bars = false
			_live_status.erase(cid)
			if _alive_enemy.has(cid):
				_alive_enemy.erase(cid)
				_emit_threat()
		"item":
			var tk: UnitToken = _tokens.get(int(e["cid"]))
			if tk:
				tk.set_bars(float(e["hp"]), tk.max_hp, tk.shield)
		"end":
			pass


# ---------- 戰鬥中查看（唯讀） ----------
## BoardView 區域座標上的戰鬥單位 cid；沒有則 -1
func cid_at(local_pos: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius * radius
	for cid in _tokens.keys():
		var tk: UnitToken = _tokens[cid]
		if not tk.visible or tk.modulate.a < 0.5:
			continue
		var d := tk.position.distance_squared_to(local_pos)
		if d <= best_d:
			best_d = d
			best = int(cid)
	return best


func set_selected(cid: int) -> void:
	_selected_cid = cid
	for k in _tokens.keys():
		_tokens[k].selected = int(k) == cid


func has_unit(cid: int) -> bool:
	return _units.has(cid)


func is_alive(cid: int) -> bool:
	var tk: UnitToken = _tokens.get(cid)
	return tk != null and tk.visible and tk.modulate.a > 0.5


func unit_snapshot(cid: int) -> Dictionary:
	return _units.get(cid, {})


func token(cid: int) -> UnitToken:
	return _tokens.get(cid)


## 目前仍生效的狀態（剩餘秒數為模擬時間）：[{kind, value, left}]
func live_statuses(cid: int) -> Array:
	var out: Array = []
	for st in _live_status.get(cid, []):
		var left := float(st["until"]) - _clock
		if left > 0.0:
			out.append({"kind": st["kind"], "value": st["value"], "left": left})
	return out


## 我方上場棋子的快照（依 cid 順序，與 Modifiers 計算時的順序一致）
func player_lineup() -> Array:
	var out: Array = []
	for snap in _units.values():
		if int(snap["side"]) == 0:
			out.append(snap)
	out.sort_custom(func(a, b) -> bool: return int(a["cid"]) < int(b["cid"]))
	return out


func _acc(cid: int, key: String, v: float) -> void:
	var a: Dictionary = _live_stats.get(cid, {"damage": 0.0, "taken": 0.0, "shielded": 0.0, "healing": 0.0})
	a[key] = float(a[key]) + v
	_live_stats[cid] = a


## 即時統計，格式與 CombatSim 的 stats 相同（給 Leaderboard 使用）
func live_stats() -> Array:
	var out: Array = []
	for cid in _units.keys():
		var snap: Dictionary = _units[cid]
		var a: Dictionary = _live_stats.get(cid, {"damage": 0.0, "taken": 0.0, "shielded": 0.0, "healing": 0.0})
		out.append({"cid": int(cid), "side": int(snap["side"]), "id": snap["id"], "star": int(snap["star"]),
			"damage": roundi(a["damage"]), "taken": roundi(a["taken"]), "shielded": roundi(a["shielded"]), "healing": roundi(a["healing"])})
	out.sort_custom(func(x, y) -> bool: return int(x["cid"]) < int(y["cid"]))
	return out
