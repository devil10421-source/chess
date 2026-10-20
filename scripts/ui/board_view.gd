class_name BoardView
extends Node2D
## 7×8 錯位六角棋盤＋12 格候補區。負責繪製與輸入（點選、拖曳），實際規則交給 RunState。
## 操作：點棋子＝選取；再點空格＝移動；拖曳到任一格＝移動／互換；拖曳到商店列＝出售。

signal unit_selected(uid: int)                 # -1 = 取消選取
signal enemy_selected(unit_id: String, star: int)
signal move_to_board_requested(uid: int, cell: Vector2i)
signal move_to_bench_requested(uid: int, index: int)
signal sell_requested(uid: int)

const TOKEN_SCENE := preload("res://scenes/unit_token.tscn")
const DRAG_THRESHOLD := 12.0

@onready var tokens_root: Node2D = $Tokens
@onready var fx: BattleFx = $Fx
@onready var battle_player: BattlePlayer = $BattlePlayer

var hex_size := 36.0
var bench_count := 12
var interactive := true
## 回傳某畫面座標是否位於出售區（由 GameScreen 設定）
var is_over_sell_zone: Callable = func(_p: Vector2) -> bool: return false

var _run: RunState
var _prep_tokens: Dictionary = {}   # uid -> UnitToken
var _enemy_tokens: Array = []
var _selected_uid := -1
var _press_uid := -1
var _press_pos := Vector2.ZERO
var _dragging := false
var _hover_cell := HexGrid.INVALID
var _hover_bench := -1
var _show_prep := true


func _ready() -> void:
	bench_count = Shop.bench_size()


# ---------- 版面 ----------
func board_size() -> Vector2:
	return HexGrid.board_pixel_size(hex_size)


func slot_size() -> float:
	return hex_size * 1.5


func bench_gap() -> float:
	return hex_size * 0.25


func bench_width() -> float:
	return bench_count * slot_size() + (bench_count - 1) * 4.0


func total_size() -> Vector2:
	var b := board_size()
	return Vector2(maxf(b.x, bench_width()), b.y + bench_gap() + slot_size())


func bench_origin() -> Vector2:
	return Vector2((board_size().x - bench_width()) * 0.5, board_size().y + bench_gap())


func bench_rect(i: int) -> Rect2:
	return Rect2(bench_origin() + Vector2(i * (slot_size() + 4.0), 0), Vector2(slot_size(), slot_size()))


func bench_center(i: int) -> Vector2:
	return bench_rect(i).get_center()


func cell_center(c: Vector2i) -> Vector2:
	return HexGrid.to_pixel(c, hex_size)


## 在 rect（畫面座標）中放到最大
func fit(rect: Rect2) -> void:
	var size := 48.0
	while size > 14.0:
		hex_size = size
		var t := total_size()
		if t.x <= rect.size.x and t.y <= rect.size.y:
			break
		size -= 0.5
	var t := total_size()
	var top_left := rect.position + (rect.size - t) * 0.5
	position = top_left + Vector2((t.x - board_size().x) * 0.5, 0).floor()
	position = position.floor()
	fx.hex_size = hex_size
	_relayout_tokens()
	queue_redraw()


# ---------- 備戰棋子 ----------
func show_prep(run: RunState) -> void:
	_run = run
	_show_prep = true
	tokens_root.visible = true
	sync_prep()


func sync_prep() -> void:
	if _run == null:
		return
	var alive := {}
	for i in _run.bench.size():
		var u = _run.bench[i]
		if u != null:
			alive[int(u["uid"])] = true
			_place_token(u, bench_center(i))
	for c in _run.board.keys():
		var u: Dictionary = _run.board[c]
		alive[int(u["uid"])] = true
		_place_token(u, cell_center(c))
	for uid in _prep_tokens.keys():
		if not alive.has(uid):
			_prep_tokens[uid].queue_free()
			_prep_tokens.erase(uid)
	if _selected_uid >= 0 and not alive.has(_selected_uid):
		select(-1)
	_sync_enemy_preview()
	queue_redraw()


func _place_token(u: Dictionary, pos: Vector2) -> void:
	var uid := int(u["uid"])
	var tk: UnitToken = _prep_tokens.get(uid)
	if tk == null:
		tk = TOKEN_SCENE.instantiate()
		tokens_root.add_child(tk)
		tk.uid = uid
		tk.setup(str(u["id"]), int(u["star"]), 0, hex_size * 0.72)
		_prep_tokens[uid] = tk
	tk.radius = hex_size * 0.72
	tk.set_star(int(u["star"]))
	tk.selected = uid == _selected_uid
	tk.visible = _show_prep
	tk.modulate.a = 1.0
	if not (_dragging and uid == _press_uid):
		tk.position = pos


func _sync_enemy_preview() -> void:
	for t in _enemy_tokens:
		t.queue_free()
	_enemy_tokens.clear()
	if _run == null or not _show_prep:
		return
	for e in BattleSetup.stage_units(_run.round_no):
		var tk: UnitToken = TOKEN_SCENE.instantiate()
		tokens_root.add_child(tk)
		tk.setup(e["id"], e["star"], 1, hex_size * 0.72)
		tk.position = cell_center(e["cell"])
		tk.modulate.a = 0.85
		_enemy_tokens.append(tk)


func _relayout_tokens() -> void:
	if _run != null and _show_prep:
		for t in _prep_tokens.values():
			t.radius = hex_size * 0.72
		sync_prep()


func set_prep_visible(v: bool) -> void:
	_show_prep = v
	for t in _prep_tokens.values():
		t.visible = v
	if not v:
		for t in _enemy_tokens:
			t.queue_free()
		_enemy_tokens.clear()
	else:
		sync_prep()


func select(uid: int) -> void:
	_selected_uid = uid
	for k in _prep_tokens.keys():
		_prep_tokens[k].selected = k == uid
	unit_selected.emit(uid)
	queue_redraw()


func selected_uid() -> int:
	return _selected_uid


# ---------- 輸入 ----------
func _local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _hit(screen_pos: Vector2) -> Dictionary:
	var p := _local(screen_pos)
	for i in bench_count:
		if bench_rect(i).has_point(p):
			return {"where": "bench", "index": i}
	var c := HexGrid.from_pixel(p, hex_size)
	if c != HexGrid.INVALID:
		return {"where": "board", "cell": c}
	return {}


func _uid_at(hit: Dictionary) -> int:
	if _run == null or hit.is_empty():
		return -1
	if hit["where"] == "bench":
		var u = _run.bench[hit["index"]]
		return -1 if u == null else int(u["uid"])
	var b = _run.board.get(hit["cell"])
	return -1 if b == null else int(b["uid"])


func _enemy_at(hit: Dictionary) -> Dictionary:
	if _run == null or hit.is_empty() or hit["where"] != "board":
		return {}
	for e in BattleSetup.stage_units(_run.round_no):
		if e["cell"] == hit["cell"]:
			return e
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if not interactive or _run == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit := _hit(event.position)
		if hit.is_empty():
			return
		get_viewport().set_input_as_handled()
		var uid := _uid_at(hit)
		if uid >= 0:
			_press_uid = uid
			_press_pos = event.position
			_dragging = false
			return
		var enemy := _enemy_at(hit)
		if not enemy.is_empty():
			enemy_selected.emit(enemy["id"], enemy["star"])
			return
		# 點到己方空格：若已選取棋子就移動過去；點敵方空格則取消選取
		var own_side: bool = hit["where"] == "bench" or HexGrid.is_player_cell(hit["cell"])
		if _selected_uid >= 0 and own_side:
			_request_move(_selected_uid, hit)
			return
		select(-1)


## 拖曳中改用 _input 攔截，避免經過介面面板時事件被吃掉
func _input(event: InputEvent) -> void:
	if _press_uid < 0:
		return
	if event is InputEventMouseMotion:
		if not _dragging and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
			select(_press_uid)
		if _dragging:
			var tk: UnitToken = _prep_tokens.get(_press_uid)
			if tk:
				tk.position = _local(event.position)
				tk.z_index = 10
			var hit := _hit(event.position)
			_hover_cell = hit.get("cell", HexGrid.INVALID)
			_hover_bench = int(hit.get("index", -1))
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var uid := _press_uid
		var was_drag := _dragging
		_press_uid = -1
		_dragging = false
		_hover_cell = HexGrid.INVALID
		_hover_bench = -1
		var tk: UnitToken = _prep_tokens.get(uid)
		if tk:
			tk.z_index = 0
		get_viewport().set_input_as_handled()
		if was_drag:
			if is_over_sell_zone.call(event.position):
				sell_requested.emit(uid)
			else:
				var hit := _hit(event.position)
				if hit.is_empty():
					sync_prep()
				else:
					_request_move(uid, hit)
		else:
			# 單純點擊：切換選取
			select(-1 if _selected_uid == uid else uid)
		sync_prep()


func _request_move(uid: int, hit: Dictionary) -> void:
	if hit["where"] == "bench":
		move_to_bench_requested.emit(uid, int(hit["index"]))
	else:
		move_to_board_requested.emit(uid, hit["cell"])


# ---------- 繪製 ----------
func _hex_points(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(a), sin(a)) * size)
	return pts


func _draw() -> void:
	var holding := _selected_uid >= 0 or _dragging
	for c in HexGrid.all_cells():
		var center := cell_center(c)
		var player_side := HexGrid.is_player_cell(c)
		var base := Color(0.16, 0.22, 0.34) if player_side else Color(0.30, 0.15, 0.17)
		if (c.x + c.y) % 2 == 0:
			base = base.lightened(0.05)
		if holding and player_side and _show_prep:
			base = base.lightened(0.08)
		if c == _hover_cell and player_side:
			base = base.lightened(0.25)
		var pts := _hex_points(center, hex_size * 0.96)
		draw_colored_polygon(pts, base)
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.10), 1.5, true)
	# 中線
	var y := (cell_center(Vector2i(0, 3)).y + cell_center(Vector2i(0, 4)).y) * 0.5
	draw_line(Vector2(0, y), Vector2(board_size().x, y), Color(1, 0.85, 0.4, 0.55), 2.0)
	draw_string(UiStyle.FONT, Vector2(4, y - 6), "敵方", HORIZONTAL_ALIGNMENT_LEFT, -1, int(hex_size * 0.36), Color(1, 0.6, 0.6, 0.7))
	draw_string(UiStyle.FONT, Vector2(4, y + hex_size * 0.42), "我方", HORIZONTAL_ALIGNMENT_LEFT, -1, int(hex_size * 0.36), Color(0.6, 0.8, 1, 0.7))
	# 候補區
	if _show_prep:
		for i in bench_count:
			var r := bench_rect(i)
			var col := Color(0.13, 0.15, 0.21)
			if i == _hover_bench:
				col = col.lightened(0.25)
			draw_rect(r, col, true)
			draw_rect(r, Color(1, 1, 1, 0.12), false, 1.5)
