class_name UnitToken
extends Node2D
## 棋子外觀。有 res://assets/units/<ID>/star<N>.png 時顯示圖片，否則以幾何圖形占位。
## 稀有度＝外環顏色與左下費用徽章（灰／藍／紫／金）；星級＝上方星星 + 外觀特效（2 星銀色雙環、3 星粉紅光環與環繞光點），兩者刻意分開。

const STATUS_GLYPH := {"stun": "暈", "root": "定", "slow": "緩", "taunt": "嘲", "dot": "灼", "atk_down": "弱",
	"armor_down": "破", "mark": "標", "atk_up": "攻", "armor_up": "甲", "dmg_up": "怒", "phys_dr": "守", "hot": "癒"}
const NEGATIVE := ["stun", "root", "slow", "taunt", "dot", "atk_down", "armor_down", "mark"]

@onready var art: Sprite2D = $Art

var unit_id := ""
var star := 1
var side := 0
var radius := 26.0
var uid := 0
var cid := 0
var show_bars := false
var hp := 1.0
var max_hp := 1.0
var shield := 0.0
var mana := 0.0
var mana_max := 60.0
var selected := false
var dragging := false
var bump := Vector2.ZERO
var flash_color := Color(1, 1, 1, 0)
var statuses: Dictionary = {}   # kind -> 剩餘秒數（畫面時間）
var _time := 0.0
var _move_tween: Tween
var _has_art := false


func setup(p_unit_id: String, p_star: int, p_side: int, p_radius: float) -> void:
	unit_id = p_unit_id
	star = p_star
	side = p_side
	radius = p_radius
	if is_node_ready():
		_refresh_art()
	queue_redraw()


func _ready() -> void:
	_refresh_art()


func _refresh_art() -> void:
	var path := "res://assets/units/%s/star%d.png" % [unit_id, star]
	_has_art = ResourceLoader.exists(path)
	if _has_art:
		var tex: Texture2D = load(path)
		art.texture = tex
		var s := (radius * 1.9) / maxf(1.0, maxf(tex.get_width(), tex.get_height()))
		art.scale = Vector2(s, s)
		art.visible = true
	else:
		art.visible = false


func set_star(p_star: int) -> void:
	if p_star != star:
		star = p_star
		_refresh_art()
		queue_redraw()


func set_bars(p_hp: float, p_max: float, p_shield: float = 0.0) -> void:
	hp = p_hp
	max_hp = p_max
	shield = p_shield
	queue_redraw()


func move_to(target: Vector2, dur: float) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	if dur <= 0.0:
		position = target
		return
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, dur)


func lunge(toward: Vector2, dur: float) -> void:
	var dir := (toward - position).normalized() * radius * 0.35
	var tw := create_tween()
	tw.tween_property(self, "bump", dir, dur * 0.4)
	tw.tween_property(self, "bump", Vector2.ZERO, dur * 0.6)


func flash(color: Color, dur: float = 0.35) -> void:
	flash_color = color
	var tw := create_tween()
	tw.tween_property(self, "flash_color", Color(color.r, color.g, color.b, 0.0), dur)


func add_status(kind: String, dur: float) -> void:
	statuses[kind] = maxf(float(statuses.get(kind, 0.0)), dur)


func die(dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, dur)
	tw.tween_callback(hide)


func _process(delta: float) -> void:
	_time += delta
	if not statuses.is_empty():
		for k in statuses.keys():
			statuses[k] = float(statuses[k]) - delta * Session.playback_rate
			if statuses[k] <= 0.0:
				statuses.erase(k)
	queue_redraw()
	if art.visible:
		art.position = bump


func _draw() -> void:
	var r := radius
	var o := bump
	var u := GameData.unit(unit_id)
	if u.is_empty():
		return
	var cost := int(u["cost"])
	var rarity := GameData.tier_color(cost)
	var body := GameData.race_color(str(u["race"]))
	# 底座（陣營）
	var plate := UiStyle.PLAYER_SIDE if side == 0 else UiStyle.ENEMY_SIDE
	draw_set_transform(o + Vector2(0, r * 0.62), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, r * 1.02, Color(plate, 0.55))
	draw_set_transform(Vector2.ZERO)
	# 3 星：粉紅光環＋環繞光點
	if star >= 3:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_circle(o, r * (1.28 + 0.05 * pulse), Color(UiStyle.AURA_3STAR, 0.22 + 0.12 * pulse))
		for i in 3:
			var a := _time * 2.2 + TAU * i / 3.0
			draw_circle(o + Vector2(cos(a), sin(a)) * r * 1.2, r * 0.11, Color(1, 0.85, 0.95, 0.95))
	# 2 星以上：銀色外環
	if star >= 2:
		draw_arc(o, r * 1.13, 0, TAU, 40, Color(0.86, 0.9, 1.0, 0.95), 2.5, true)
	# 稀有度外環
	draw_circle(o, r, rarity)
	# 本體
	if not _has_art:
		draw_circle(o, r * 0.84, body.darkened(0.15))
		draw_circle(o + Vector2(-r * 0.2, -r * 0.25), r * 0.45, Color(body.lightened(0.25), 0.35))
		_draw_class_mark(o, r, str(u["class"]))
		var label := str(u.get("short", u["name"]))
		draw_string(UiStyle.FONT, o + Vector2(-r, r * 0.22), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 0.62), Color.WHITE)
	else:
		draw_arc(o, r * 0.86, 0, TAU, 32, Color(0, 0, 0, 0.3), 2.0)
	# 費用徽章
	var bp := o + Vector2(-r * 0.78, r * 0.62)
	draw_circle(bp, r * 0.3, Color(0.08, 0.09, 0.12))
	draw_circle(bp, r * 0.25, rarity)
	draw_string(UiStyle.FONT, bp + Vector2(-r * 0.3, r * 0.13), str(cost), HORIZONTAL_ALIGNMENT_CENTER, r * 0.6, int(r * 0.36), Color(0.05, 0.05, 0.08))
	# 星級
	var stars := "★".repeat(star)
	var star_col := UiStyle.STAR_COLOR if star < 3 else Color(1, 0.75, 0.9)
	draw_string(UiStyle.FONT, o + Vector2(-r, -r * 1.02), stars, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 0.5), star_col)
	# 受擊／施法閃光
	if flash_color.a > 0.01:
		draw_circle(o, r * 1.05, flash_color)
	# 選取：金色粗外框＋呼吸光暈（比 V0.1 明顯）
	if selected:
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		draw_arc(o, r * 1.32, 0, TAU, 48, Color(1.0, 0.88, 0.4, 0.35 + 0.25 * pulse), 7.0, true)
		draw_arc(o, r * 1.2, 0, TAU, 48, Color(1.0, 0.95, 0.6, 1.0), 3.0 + 1.5 * pulse, true)
	# 戰鬥血條／魔力條
	if show_bars:
		var bw := r * 2.0
		var top := o + Vector2(-r, -r * 1.55)
		draw_rect(Rect2(top, Vector2(bw, 6)), Color(0, 0, 0, 0.7))
		var total := maxf(max_hp, hp + shield)
		var hp_w := bw * clampf(hp / total, 0.0, 1.0)
		draw_rect(Rect2(top, Vector2(hp_w, 6)), Color(0.35, 0.85, 0.45) if side == 0 else Color(0.92, 0.32, 0.32))
		if shield > 0.0:
			draw_rect(Rect2(top + Vector2(hp_w, 0), Vector2(bw * clampf(shield / total, 0.0, 1.0), 6)), Color(0.95, 0.95, 1.0))
		draw_rect(Rect2(top + Vector2(0, 7), Vector2(bw, 3)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(top + Vector2(0, 7), Vector2(bw * clampf(mana / maxf(1.0, mana_max), 0.0, 1.0), 3)), Color(0.35, 0.6, 1.0))
		if not statuses.is_empty():
			var glyphs := ""
			for k in statuses.keys():
				glyphs += str(STATUS_GLYPH.get(k, ""))
			draw_string(UiStyle.FONT, o + Vector2(-r * 1.5, -r * 1.65), glyphs, HORIZONTAL_ALIGNMENT_CENTER, r * 3.0, int(r * 0.42), Color(1, 0.95, 0.6))


func _draw_class_mark(o: Vector2, r: float, cls: String) -> void:
	var c := Color(1, 1, 1, 0.28)
	match cls:
		"warrior":
			draw_line(o + Vector2(-r * 0.45, r * 0.45), o + Vector2(r * 0.45, -r * 0.45), c, r * 0.12)
			draw_line(o + Vector2(-r * 0.45, -r * 0.45), o + Vector2(r * 0.45, r * 0.45), c, r * 0.12)
		"guardian":
			draw_colored_polygon(PackedVector2Array([o + Vector2(-r * 0.45, -r * 0.5), o + Vector2(r * 0.45, -r * 0.5), o + Vector2(r * 0.4, r * 0.1), o + Vector2(0, r * 0.55), o + Vector2(-r * 0.4, r * 0.1)]), c)
		"archer":
			draw_arc(o + Vector2(-r * 0.15, 0), r * 0.5, -PI * 0.45, PI * 0.45, 12, c, r * 0.1)
			draw_line(o + Vector2(-r * 0.15, 0), o + Vector2(r * 0.55, 0), c, r * 0.08)
		"mage":
			draw_colored_polygon(PackedVector2Array([o + Vector2(0, -r * 0.6), o + Vector2(r * 0.45, 0), o + Vector2(0, r * 0.6), o + Vector2(-r * 0.45, 0)]), c)
		"assassin":
			draw_colored_polygon(PackedVector2Array([o + Vector2(0, -r * 0.6), o + Vector2(r * 0.18, r * 0.35), o + Vector2(0, r * 0.6), o + Vector2(-r * 0.18, r * 0.35)]), c)
		"priest":
			draw_line(o + Vector2(0, -r * 0.55), o + Vector2(0, r * 0.55), c, r * 0.16)
			draw_line(o + Vector2(-r * 0.4, -r * 0.1), o + Vector2(r * 0.4, -r * 0.1), c, r * 0.16)
