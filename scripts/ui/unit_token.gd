class_name UnitToken
extends Node2D
## 棋子外觀。有 res://assets/units/<ID>/star<N>.png 時顯示圖片，否則以幾何圖形占位。
## 稀有度＝外環顏色與左下費用徽章（灰／藍／紫／金）。
## V0.4：頭上固定顯示「星級標記＋HP／MP 條」：一星＝一個小圓點、二星＝兩個小圓點、三星＝一顆金色星星（在狀態條左側）；
##       有裝備時在狀態條下方顯示 1～2 個小圖示，沒有裝備就完全不畫（不畫空格）。2 星銀環、3 星光環仍保留作為輔助。

const STATUS_GLYPH := {"stun": "暈", "root": "定", "slow": "緩", "taunt": "嘲", "dot": "蝕", "atk_down": "弱", "wound": "傷",
	"mark": "標", "atk_up": "攻", "armor_up": "甲", "dmg_up": "怒", "phys_dr": "守", "hot": "癒", "phys_pen": "穿", "magic_pen": "穿",
	"guard_link": "誓", "parry": "架", "blessing": "祝"}
const NEGATIVE := ["stun", "root", "slow", "taunt", "dot", "atk_down", "wound", "mark"]

@onready var art: Sprite2D = $Art

var unit_id := ""
var star := 1
var side := 0
var radius := 26.0
var uid := 0
var cid := 0
var show_bars := false
var show_head := true           # 頭上狀態條／星級／裝備（資訊卡頭像關閉）
var on_bench := false           # 候補區：不畫 HP／MP 與裝備，只在頭上畫星級標記（V0.5）
var hp := 1.0
var max_hp := 1.0
var shield := 0.0
var mana := 0.0
var mana_max := 60.0
var selected := false
var items: Array = []           # 身上的裝備 id（畫小方塊提示）
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


## 施法前搖：短暫發光
var _windup_left := 0.0
var _windup_total := 0.0


func windup(dur: float) -> void:
	_windup_left = dur
	_windup_total = maxf(0.01, dur)


func die(dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, dur)
	tw.tween_callback(hide)


func _process(delta: float) -> void:
	_time += delta
	if _windup_left > 0.0:
		_windup_left = maxf(0.0, _windup_left - delta)
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
	# 施法前搖：外圈逐漸收束的光環
	if _windup_left > 0.0:
		var k := 1.0 - _windup_left / _windup_total
		draw_arc(o, r * (1.6 - 0.45 * k), 0, TAU, 40, Color(1.0, 0.85, 0.35, 0.35 + 0.5 * k), 3.0, true)
	# 受擊／施法閃光
	if flash_color.a > 0.01:
		draw_circle(o, r * 1.05, flash_color)
	# 選取：金色粗外框＋呼吸光暈（比 V0.1 明顯）
	if selected:
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		draw_arc(o, r * 1.32, 0, TAU, 48, Color(1.0, 0.88, 0.4, 0.35 + 0.25 * pulse), 7.0, true)
		draw_arc(o, r * 1.2, 0, TAU, 48, Color(1.0, 0.95, 0.6, 1.0), 3.0 + 1.5 * pulse, true)
	if show_head and on_bench:
		_draw_bench_star(o, r)
	elif show_head:
		_draw_head(o, r)


## 頭上元件的位置（以棋子中心為原點）：bar＝HP＋MP 條、mark＝星級標記中心、items＝每件裝備圖示（沒有裝備＝空陣列）
func head_layout(o: Vector2 = Vector2.ZERO, r: float = -1.0) -> Dictionary:
	if r < 0.0:
		r = radius
	var hp_h := clampf(r * 0.22, 5.0, 8.0)
	var mp_h := clampf(r * 0.1, 2.0, 4.0)
	var mark_w := r * 0.56
	var bar_w := r * 1.7
	var left := o.x - (mark_w + bar_w) * 0.5
	var top := o.y - r - 3.0 - hp_h - 1.0 - mp_h
	var item_rects: Array = []
	if not items.is_empty():
		var isz := maxf(9.0, r * 0.44)
		var gap := 2.0
		var row_w := items.size() * isz + (items.size() - 1) * gap
		for i in items.size():
			item_rects.append(Rect2(Vector2(o.x - row_w * 0.5 + i * (isz + gap), top + hp_h + mp_h + 3.0), Vector2(isz, isz)))
	return {"bar": Rect2(Vector2(left + mark_w, top), Vector2(bar_w, hp_h + 1.0 + mp_h)), "hp_h": hp_h, "mp_h": mp_h,
		"mark": Vector2(left + mark_w * 0.45, top + (hp_h + mp_h + 1.0) * 0.5), "items": item_rects}


## 候補區：只在棋子正上方畫星級標記（深色底，不會被棋子或選取框蓋住）
func bench_star_center(o: Vector2 = Vector2.ZERO, r: float = -1.0) -> Vector2:
	if r < 0.0:
		r = radius
	return o + Vector2(0, -r - maxf(5.0, r * 0.22))


func _draw_bench_star(o: Vector2, r: float) -> void:
	var c := bench_star_center(o, r)
	var w := maxf(14.0, r * 0.7) if star < 3 else maxf(12.0, r * 0.55)
	var h := maxf(9.0, r * 0.38)
	draw_rect(Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), Color(0, 0, 0, 0.7))
	draw_star_mark(self, c, r, star)


## 頭上的星級標記、HP／MP 條、裝備圖示、狀態字
func _draw_head(o: Vector2, r: float) -> void:
	var L := head_layout(o, r)
	var bar: Rect2 = L["bar"]
	var hp_h: float = L["hp_h"]
	var mp_h: float = L["mp_h"]
	var bx := bar.position.x
	var top := bar.position.y
	var bar_w := bar.size.x
	draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.75))
	var total := maxf(max_hp, hp + shield)
	var hp_w := bar_w * clampf(hp / maxf(total, 0.001), 0.0, 1.0)
	draw_rect(Rect2(Vector2(bx, top), Vector2(hp_w, hp_h)), Color(0.35, 0.85, 0.45) if side == 0 else Color(0.92, 0.32, 0.32))
	if shield > 0.0:
		draw_rect(Rect2(Vector2(bx + hp_w, top), Vector2(bar_w * clampf(shield / total, 0.0, 1.0), hp_h)), Color(0.95, 0.95, 1.0))
	draw_rect(Rect2(Vector2(bx, top + hp_h + 1.0), Vector2(bar_w * clampf(mana / maxf(1.0, mana_max), 0.0, 1.0), mp_h)), Color(0.35, 0.6, 1.0))
	# 星級標記（狀態條左側）
	draw_star_mark(self, L["mark"], r, star)
	# 裝備圖示：狀態條下方，只畫實際持有的件數（沒有裝備就不畫）
	var rects: Array = L["items"]
	for i in rects.size():
		var id := str(items[i])
		var col := Color(str(Equipment.type_info(id).get("color", "#ffffff")))
		var rect: Rect2 = rects[i]
		draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.8))
		draw_rect(rect, col.darkened(0.55))
		UiIcon.paint(self, str(GameData.item(id).get("type", "weapon")), rect.position + Vector2(1, 1), rect.size.x - 2.0, col.lightened(0.3))
	if not statuses.is_empty():
		var glyphs := ""
		for k in statuses.keys():
			glyphs += str(STATUS_GLYPH.get(k, ""))
		draw_string(UiStyle.FONT, Vector2(o.x - r * 1.5, top - 3.0), glyphs, HORIZONTAL_ALIGNMENT_CENTER, r * 3.0, int(r * 0.42), Color(1, 0.95, 0.6))


## 星級標記：一星一點、二星兩點、三星金色星星（棋子頭上與資訊卡共用）
static func draw_star_mark(ci: CanvasItem, c: Vector2, r: float, p_star: int) -> void:
	if p_star >= 3:
		var pts := PackedVector2Array()
		var rad := maxf(5.0, r * 0.26)
		for i in 10:
			var a := -PI / 2 + i * PI / 5
			var rr := rad if i % 2 == 0 else rad * 0.45
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		var outline := PackedVector2Array()
		for q in pts:
			outline.append(c + (q - c) * 1.25)
		ci.draw_colored_polygon(outline, Color(0, 0, 0, 0.8))
		ci.draw_colored_polygon(pts, Color(1.0, 0.82, 0.25))
		return
	var dr := maxf(2.6, r * 0.12)
	var n := clampi(p_star, 1, 2)
	for i in n:
		var dx := 0.0 if n == 1 else (i - 0.5) * dr * 2.6
		ci.draw_circle(c + Vector2(dx, 0), dr + 1.2, Color(0, 0, 0, 0.85))
		ci.draw_circle(c + Vector2(dx, 0), dr, Color(0.92, 0.94, 1.0))


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
