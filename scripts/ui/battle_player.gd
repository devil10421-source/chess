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
			var tk: UnitToken = _tokens.get(int(e["cid"]))
			if tk and not instant:
				tk.add_status(str(e["kind"]), float(e["dur"]))
		"cleanse":
			var tk: UnitToken = _tokens.get(int(e["cid"]))
			if tk:
				tk.statuses.erase(str(e["kind"]))
		"death":
			var cid := int(e["cid"])
			var tk: UnitToken = _tokens.get(cid)
			if tk:
				tk.die(0.0 if instant else 0.35 / sp)
				tk.show_bars = false
			if _alive_enemy.has(cid):
				_alive_enemy.erase(cid)
				_emit_threat()
		"end":
			pass
