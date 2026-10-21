class_name UiIcon
extends Control
## 以向量圖形繪製的小圖示（不需要圖片檔）。kind 決定圖案、tint 決定顏色。
## 屬性：sword 攻擊、shield 物防、magic_shield 魔防、bolt 攻速、foot 移速、aim 射程、crosshair 暴擊率、
##       swords 暴擊傷害、mana 魔力、skill 技能、heal 治療護盾、chain 控制
## 介面：coin 金幣、heart 生命、people 人口、refresh 刷新、lock／unlock 鎖定、play 開戰、bag 背包、plus 空欄位、
##       civ 文明徽章、weapon／armor／trinket 裝備類型、damage／taken／absorb／healing 排行
## 羈絆（V0.4）：civ_elf 葉、civ_human 王冠、civ_orc 獠牙、civ_centaur 馬蹄、civ_deer 鹿角、civ_oni 鬼角、
##       cls_<職業>、type_<類型>（見 trait_kind）；remover 裝備卸除器
## 繪圖本身寫成靜態函式 paint()，棋盤上的棋子（Node2D）也能直接畫同一套圖示。

@export var kind := "sword"
@export var tint := Color.WHITE

const KINDS := ["sword", "shield", "magic_shield", "bolt", "foot", "aim", "crosshair", "swords", "mana", "skill", "heal",
	"chain", "coin", "heart", "people", "refresh", "lock", "unlock", "play", "bag", "plus", "civ", "weapon", "armor",
	"trinket", "damage", "taken", "absorb", "healing", "civ_elf", "civ_human", "civ_orc", "civ_centaur", "civ_deer", "civ_oni",
	"cls_warrior", "cls_guardian", "cls_archer", "cls_mage", "cls_assassin", "cls_priest",
	"type_vanguard", "type_rear", "type_mobile", "type_support", "remover", "neutral", "chart"]


## 羈絆對應的圖示：race → 文明徽章；class／type → 職業／類型圖示
static func trait_kind(group: String, key: String) -> String:
	match group:
		"race":
			return "civ_" + key
		"class":
			return "cls_" + key
		"type":
			return "type_" + key
	return "civ"


static func make(p_kind: String, p_tint: Color = Color.WHITE, size: float = 24.0) -> UiIcon:
	var ic := UiIcon.new()
	ic.kind = p_kind
	ic.tint = p_tint
	ic.custom_minimum_size = Vector2(size, size)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func set_icon(p_kind: String, p_tint: Color) -> void:
	kind = p_kind
	tint = p_tint
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	paint(self, kind, (size - Vector2(s, s)) * 0.5, s, tint)


## 在任何 CanvasItem 上畫圖示：o＝左上角、s＝邊長
static func paint(ci: CanvasItem, kind: String, o: Vector2, s: float, c: Color) -> void:
	var w := maxf(1.5, s * 0.09)
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match kind:
		"sword", "weapon", "damage":
			ci.draw_line(P.call(0.22, 0.78), P.call(0.8, 0.2), c, w * 1.3)
			ci.draw_line(P.call(0.18, 0.55), P.call(0.45, 0.82), c, w)
			ci.draw_line(P.call(0.12, 0.88), P.call(0.25, 0.75), c, w * 1.4)
		"swords":
			ci.draw_line(P.call(0.18, 0.82), P.call(0.82, 0.18), c, w)
			ci.draw_line(P.call(0.18, 0.18), P.call(0.82, 0.82), c, w)
			ci.draw_line(P.call(0.1, 0.62), P.call(0.38, 0.9), c, w)
			ci.draw_line(P.call(0.62, 0.9), P.call(0.9, 0.62), c, w)
		"shield", "armor", "taken":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.1), P.call(0.86, 0.22), P.call(0.8, 0.6), P.call(0.5, 0.9), P.call(0.2, 0.6), P.call(0.14, 0.22)]), Color(c, 0.85))
			ci.draw_line(P.call(0.5, 0.2), P.call(0.5, 0.8), Color(0, 0, 0, 0.35), w * 0.7)
		"magic_shield", "absorb":
			ci.draw_arc(P.call(0.5, 0.5), s * 0.38, 0, TAU, 28, c, w)
			ci.draw_arc(P.call(0.5, 0.5), s * 0.24, 0, TAU, 20, Color(c, 0.6), w * 0.8)
			ci.draw_circle(P.call(0.5, 0.5), s * 0.08, c)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.58, 0.06), P.call(0.24, 0.56), P.call(0.48, 0.56), P.call(0.38, 0.94), P.call(0.78, 0.4), P.call(0.53, 0.4)]), c)
		"foot":
			ci.draw_set_transform(P.call(0.38, 0.62), -0.3, Vector2(0.75, 1.0))
			ci.draw_circle(Vector2.ZERO, s * 0.17, c)
			ci.draw_set_transform(Vector2.ZERO)
			for i in 3:
				ci.draw_circle(P.call(0.3 + i * 0.12, 0.3 - (0.04 if i == 1 else 0.0)), s * 0.06, c)
			ci.draw_circle(P.call(0.72, 0.42), s * 0.07, Color(c, 0.6))
		"aim":
			ci.draw_arc(P.call(0.5, 0.5), s * 0.38, 0, TAU, 28, c, w)
			ci.draw_arc(P.call(0.5, 0.5), s * 0.2, 0, TAU, 20, c, w)
			ci.draw_circle(P.call(0.5, 0.5), s * 0.06, c)
		"crosshair":
			ci.draw_arc(P.call(0.5, 0.5), s * 0.3, 0, TAU, 28, c, w)
			ci.draw_line(P.call(0.5, 0.05), P.call(0.5, 0.32), c, w)
			ci.draw_line(P.call(0.5, 0.68), P.call(0.5, 0.95), c, w)
			ci.draw_line(P.call(0.05, 0.5), P.call(0.32, 0.5), c, w)
			ci.draw_line(P.call(0.68, 0.5), P.call(0.95, 0.5), c, w)
		"mana":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.08), P.call(0.78, 0.55), P.call(0.5, 0.92), P.call(0.22, 0.55)]), c)
			ci.draw_circle(P.call(0.42, 0.52), s * 0.07, Color(1, 1, 1, 0.6))
		"skill":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + i * PI / 5
				var r := 0.42 if i % 2 == 0 else 0.18
				pts.append(P.call(0.5 + cos(a) * r, 0.52 + sin(a) * r))
			ci.draw_colored_polygon(pts, c)
		"heal", "healing":
			ci.draw_rect(Rect2(P.call(0.38, 0.12), Vector2(0.24, 0.76) * s), c)
			ci.draw_rect(Rect2(P.call(0.12, 0.38), Vector2(0.76, 0.24) * s), c)
		"chain":
			ci.draw_arc(P.call(0.35, 0.5), s * 0.2, 0, TAU, 20, c, w)
			ci.draw_arc(P.call(0.65, 0.5), s * 0.2, 0, TAU, 20, c, w)
		"coin":
			ci.draw_circle(P.call(0.5, 0.5), s * 0.42, c)
			ci.draw_circle(P.call(0.5, 0.5), s * 0.3, c.darkened(0.25))
			ci.draw_rect(Rect2(P.call(0.44, 0.3), Vector2(0.12, 0.4) * s), c.lightened(0.3))
		"heart":
			ci.draw_circle(P.call(0.33, 0.38), s * 0.2, c)
			ci.draw_circle(P.call(0.67, 0.38), s * 0.2, c)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.14, 0.46), P.call(0.86, 0.46), P.call(0.5, 0.9)]), c)
		"people":
			ci.draw_circle(P.call(0.36, 0.32), s * 0.14, c)
			ci.draw_circle(P.call(0.66, 0.36), s * 0.12, Color(c, 0.7))
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.12, 0.88), P.call(0.18, 0.56), P.call(0.54, 0.56), P.call(0.6, 0.88)]), c)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.56, 0.86), P.call(0.58, 0.58), P.call(0.86, 0.58), P.call(0.9, 0.86)]), Color(c, 0.7))
		"refresh":
			ci.draw_arc(P.call(0.5, 0.5), s * 0.32, 0.4, TAU - 0.6, 24, c, w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.76, 0.18), P.call(0.86, 0.46), P.call(0.58, 0.4)]), c)
		"lock", "unlock":
			ci.draw_rect(Rect2(P.call(0.22, 0.46), Vector2(0.56, 0.42) * s), c)
			if kind == "lock":
				ci.draw_arc(P.call(0.5, 0.46), s * 0.2, PI, TAU, 16, c, w * 1.2)
			else:
				ci.draw_arc(P.call(0.62, 0.4), s * 0.18, PI, TAU - 0.4, 16, c, w * 1.2)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.26, 0.14), P.call(0.86, 0.5), P.call(0.26, 0.86)]), c)
		"bag":
			ci.draw_rect(Rect2(P.call(0.18, 0.36), Vector2(0.64, 0.52) * s), c)
			ci.draw_arc(P.call(0.5, 0.36), s * 0.18, PI, TAU, 16, c, w)
		"plus":
			ci.draw_line(P.call(0.5, 0.22), P.call(0.5, 0.78), c, w * 1.3)
			ci.draw_line(P.call(0.22, 0.5), P.call(0.78, 0.5), c, w * 1.3)
		"civ":
			var hex := PackedVector2Array()
			for i in 6:
				var a := deg_to_rad(60.0 * i - 90.0)
				hex.append(P.call(0.5 + cos(a) * 0.44, 0.5 + sin(a) * 0.44))
			ci.draw_colored_polygon(hex, c)
			hex.append(hex[0])
			ci.draw_polyline(hex, c.lightened(0.45), w * 0.8)
			ci.draw_circle(P.call(0.5, 0.5), s * 0.13, c.lightened(0.55))
		"trinket":
			ci.draw_arc(P.call(0.5, 0.58), s * 0.3, 0, TAU, 24, c, w * 1.1)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.06), P.call(0.64, 0.24), P.call(0.5, 0.36), P.call(0.36, 0.24)]), c)
		"civ_elf":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.06), P.call(0.8, 0.32), P.call(0.78, 0.62), P.call(0.5, 0.86), P.call(0.22, 0.62), P.call(0.2, 0.32)]), c)
			ci.draw_line(P.call(0.5, 0.2), P.call(0.5, 0.96), c.darkened(0.45), w)
			ci.draw_line(P.call(0.5, 0.45), P.call(0.68, 0.33), c.darkened(0.45), w * 0.7)
			ci.draw_line(P.call(0.5, 0.6), P.call(0.32, 0.48), c.darkened(0.45), w * 0.7)
		"civ_human":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.12, 0.78), P.call(0.12, 0.3), P.call(0.32, 0.5), P.call(0.5, 0.18), P.call(0.68, 0.5), P.call(0.88, 0.3), P.call(0.88, 0.78)]), c)
			ci.draw_rect(Rect2(P.call(0.12, 0.8), Vector2(0.76, 0.1) * s), c)
			ci.draw_circle(P.call(0.5, 0.6), s * 0.07, c.darkened(0.5))
		"civ_orc":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.18, 0.12), P.call(0.36, 0.2), P.call(0.42, 0.86), P.call(0.28, 0.62)]), c)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.82, 0.12), P.call(0.64, 0.2), P.call(0.58, 0.86), P.call(0.72, 0.62)]), c)
		"civ_centaur":
			ci.draw_arc(P.call(0.5, 0.46), s * 0.32, PI * 0.95, TAU + PI * 0.05, 20, c, w * 2.0)
			for x in [0.22, 0.5, 0.78]:
				ci.draw_circle(P.call(x, 0.28 if x == 0.5 else 0.42), s * 0.045, c.darkened(0.5))
			ci.draw_rect(Rect2(P.call(0.12, 0.62), Vector2(0.16, 0.24) * s), c)
			ci.draw_rect(Rect2(P.call(0.72, 0.62), Vector2(0.16, 0.24) * s), c)
		"civ_deer":
			ci.draw_line(P.call(0.5, 0.92), P.call(0.5, 0.55), c, w * 1.2)
			ci.draw_line(P.call(0.5, 0.6), P.call(0.22, 0.12), c, w * 1.2)
			ci.draw_line(P.call(0.5, 0.6), P.call(0.78, 0.12), c, w * 1.2)
			ci.draw_line(P.call(0.33, 0.32), P.call(0.1, 0.3), c, w)
			ci.draw_line(P.call(0.67, 0.32), P.call(0.9, 0.3), c, w)
			ci.draw_line(P.call(0.4, 0.45), P.call(0.22, 0.5), c, w)
			ci.draw_line(P.call(0.6, 0.45), P.call(0.78, 0.5), c, w)
		"civ_oni":
			ci.draw_circle(P.call(0.5, 0.62), s * 0.3, c)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.24, 0.48), P.call(0.14, 0.06), P.call(0.4, 0.38)]), c)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.76, 0.48), P.call(0.86, 0.06), P.call(0.6, 0.38)]), c)
			ci.draw_circle(P.call(0.4, 0.6), s * 0.05, c.darkened(0.6))
			ci.draw_circle(P.call(0.6, 0.6), s * 0.05, c.darkened(0.6))
		"neutral":
			ci.draw_arc(P.call(0.5, 0.5), s * 0.38, 0, TAU, 28, c, w * 1.3)
			ci.draw_line(P.call(0.26, 0.5), P.call(0.74, 0.5), c, w * 1.3)
		"cls_warrior":
			paint(ci, "swords", o, s, c)
		"cls_guardian":
			paint(ci, "shield", o, s, c)
		"cls_archer":
			ci.draw_arc(P.call(0.32, 0.5), s * 0.38, -PI * 0.42, PI * 0.42, 16, c, w * 1.2)
			ci.draw_line(P.call(0.47, 0.14), P.call(0.47, 0.86), Color(c, 0.7), w * 0.6)
			ci.draw_line(P.call(0.2, 0.5), P.call(0.9, 0.5), c, w)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.94, 0.5), P.call(0.78, 0.4), P.call(0.78, 0.6)]), c)
		"cls_mage":
			ci.draw_line(P.call(0.3, 0.92), P.call(0.62, 0.36), c, w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.7, 0.06), P.call(0.86, 0.26), P.call(0.7, 0.46), P.call(0.54, 0.26)]), c)
		"cls_assassin":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.04), P.call(0.62, 0.6), P.call(0.5, 0.68), P.call(0.38, 0.6)]), c)
			ci.draw_line(P.call(0.26, 0.68), P.call(0.74, 0.68), c, w * 1.2)
			ci.draw_line(P.call(0.5, 0.7), P.call(0.5, 0.94), c, w * 1.4)
		"cls_priest":
			paint(ci, "heal", o, s, c)
		"type_vanguard":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.14, 0.2), P.call(0.86, 0.2), P.call(0.86, 0.52), P.call(0.5, 0.9), P.call(0.14, 0.52)]), Color(c, 0.9))
			ci.draw_line(P.call(0.3, 0.5), P.call(0.5, 0.32), c.darkened(0.55), w)
			ci.draw_line(P.call(0.5, 0.32), P.call(0.7, 0.5), c.darkened(0.55), w)
		"type_rear":
			paint(ci, "aim", o, s, c)
		"type_mobile":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.1, 0.2), P.call(0.42, 0.5), P.call(0.1, 0.8), P.call(0.24, 0.5)]), Color(c, 0.6))
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.42, 0.2), P.call(0.9, 0.5), P.call(0.42, 0.8), P.call(0.58, 0.5)]), c)
		"type_support":
			paint(ci, "heart", o, s, c)
			ci.draw_line(P.call(0.5, 0.36), P.call(0.5, 0.64), c.darkened(0.6), w)
			ci.draw_line(P.call(0.36, 0.5), P.call(0.64, 0.5), c.darkened(0.6), w)
		"chart":
			ci.draw_rect(Rect2(P.call(0.12, 0.5), Vector2(0.18, 0.4) * s), c)
			ci.draw_rect(Rect2(P.call(0.41, 0.2), Vector2(0.18, 0.7) * s), c)
			ci.draw_rect(Rect2(P.call(0.7, 0.36), Vector2(0.18, 0.54) * s), c)
		"remover":
			ci.draw_line(P.call(0.2, 0.86), P.call(0.62, 0.42), c, w * 1.6)
			ci.draw_arc(P.call(0.7, 0.32), s * 0.2, PI * 0.75, PI * 2.6, 16, c, w * 1.4)
		_:
			ci.draw_circle(P.call(0.5, 0.5), s * 0.3, c)
