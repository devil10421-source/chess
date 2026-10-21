class_name RewardDots
extends Control
## 左上角七個裝備回合節點（第 3、6、9、12、15、18、21 回合）。
## 尚未抵達＝暗色、已完成並領取＝亮色、目前為裝備回合＝發光。點擊（或滑鼠懸停）可看回合與掉落勢力。

signal dot_pressed(round_no: int, text: String)

var current_round := 1
var claimed: Array = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_state(round_no: int, claimed_rounds: Array) -> void:
	current_round = round_no
	claimed = claimed_rounds
	tooltip_text = _all_text()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _centers() -> Array:
	var out: Array = []
	var n := GameData.reward_rounds().size()
	var gap := size.x / maxf(1.0, float(n))
	for i in n:
		out.append(Vector2(gap * (i + 0.5), size.y * 0.5))
	return out


static func dot_text(r: Dictionary) -> String:
	var fac := str(GameData.equipment().get("factions", {}).get(r["faction"], {}).get("name", ""))
	var extra := "＋%s" % GameData.remover_name() if GameData.remover_rounds().any(func(x): return int(x) == int(r["round"])) else ""
	return "第 %d 回合：%s三選一%s" % [int(r["round"]), fac, extra]


func _all_text() -> String:
	var lines: Array = []
	for r in GameData.reward_rounds():
		lines.append(dot_text(r))
	return "\n".join(lines)


func _draw() -> void:
	var rr := GameData.reward_rounds()
	var cs := _centers()
	var rad := minf(size.y * 0.42, 6.0)
	for i in rr.size():
		var r := int(rr[i]["round"])
		var base := GameData.race_color(str(rr[i]["faction"])).lightened(0.35)   # 依掉落勢力上色（邪教紫、惡魔紅、古神青）
		var col := Color(base, 0.22)
		if claimed.has(r):
			col = base
		if r == current_round:
			var pulse := 0.5 + 0.5 * sin(_time * 5.0)
			draw_circle(cs[i], rad * (1.7 + 0.3 * pulse), Color(base, 0.25 + 0.2 * pulse))
			col = base.lightened(0.2)
		draw_circle(cs[i], rad, col)
		draw_arc(cs[i], rad, 0, TAU, 16, Color(base, 0.6), 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cs := _centers()
		var rr := GameData.reward_rounds()
		var best := -1
		var best_d := INF
		for i in cs.size():
			var d: float = (cs[i] as Vector2).distance_to(event.position)
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			var r: Dictionary = rr[best]
			var state := "已領取" if claimed.has(int(r["round"])) else ("本回合" if int(r["round"]) == current_round else ("尚未抵達" if int(r["round"]) > current_round else "未領取"))
			dot_pressed.emit(int(r["round"]), dot_text(r) + "・" + state)
		accept_event()
