class_name UiIcon
extends Control
## 以向量圖形繪製的小圖示（不需要圖片檔）。kind 決定圖案、tint 決定顏色。
## 屬性：sword 攻擊、shield 物防、magic_shield 魔防、bolt 攻速、foot 移速、aim 射程、crosshair 暴擊率、
##       swords 暴擊傷害、mana 魔力、skill 技能、heal 治療護盾、chain 控制
## 介面：coin 金幣、heart 生命、people 人口、refresh 刷新、lock／unlock 鎖定、play 開戰、bag 背包、plus 空欄位、
##       civ 文明徽章、weapon／armor／trinket 裝備類型、damage／taken／absorb／healing 排行

@export var kind := "sword"
@export var tint := Color.WHITE

const KINDS := ["sword", "shield", "magic_shield", "bolt", "foot", "aim", "crosshair", "swords", "mana", "skill", "heal",
	"chain", "coin", "heart", "people", "refresh", "lock", "unlock", "play", "bag", "plus", "civ", "weapon", "armor",
	"trinket", "damage", "taken", "absorb", "healing"]


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
	var o := (size - Vector2(s, s)) * 0.5
	var c := tint
	var w := maxf(1.5, s * 0.09)
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match kind:
		"sword", "weapon", "damage":
			draw_line(P.call(0.22, 0.78), P.call(0.8, 0.2), c, w * 1.3)
			draw_line(P.call(0.18, 0.55), P.call(0.45, 0.82), c, w)
			draw_line(P.call(0.12, 0.88), P.call(0.25, 0.75), c, w * 1.4)
		"swords":
			draw_line(P.call(0.18, 0.82), P.call(0.82, 0.18), c, w)
			draw_line(P.call(0.18, 0.18), P.call(0.82, 0.82), c, w)
			draw_line(P.call(0.1, 0.62), P.call(0.38, 0.9), c, w)
			draw_line(P.call(0.62, 0.9), P.call(0.9, 0.62), c, w)
		"shield", "armor", "taken":
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.1), P.call(0.86, 0.22), P.call(0.8, 0.6), P.call(0.5, 0.9), P.call(0.2, 0.6), P.call(0.14, 0.22)]), Color(c, 0.85))
			draw_line(P.call(0.5, 0.2), P.call(0.5, 0.8), Color(0, 0, 0, 0.35), w * 0.7)
		"magic_shield", "absorb":
			draw_arc(P.call(0.5, 0.5), s * 0.38, 0, TAU, 28, c, w)
			draw_arc(P.call(0.5, 0.5), s * 0.24, 0, TAU, 20, Color(c, 0.6), w * 0.8)
			draw_circle(P.call(0.5, 0.5), s * 0.08, c)
		"bolt":
			draw_colored_polygon(PackedVector2Array([P.call(0.58, 0.06), P.call(0.24, 0.56), P.call(0.48, 0.56), P.call(0.38, 0.94), P.call(0.78, 0.4), P.call(0.53, 0.4)]), c)
		"foot":
			draw_set_transform(P.call(0.38, 0.62), -0.3, Vector2(0.75, 1.0))
			draw_circle(Vector2.ZERO, s * 0.17, c)
			draw_set_transform(Vector2.ZERO)
			for i in 3:
				draw_circle(P.call(0.3 + i * 0.12, 0.3 - (0.04 if i == 1 else 0.0)), s * 0.06, c)
			draw_circle(P.call(0.72, 0.42), s * 0.07, Color(c, 0.6))
		"aim":
			draw_arc(P.call(0.5, 0.5), s * 0.38, 0, TAU, 28, c, w)
			draw_arc(P.call(0.5, 0.5), s * 0.2, 0, TAU, 20, c, w)
			draw_circle(P.call(0.5, 0.5), s * 0.06, c)
		"crosshair":
			draw_arc(P.call(0.5, 0.5), s * 0.3, 0, TAU, 28, c, w)
			draw_line(P.call(0.5, 0.05), P.call(0.5, 0.32), c, w)
			draw_line(P.call(0.5, 0.68), P.call(0.5, 0.95), c, w)
			draw_line(P.call(0.05, 0.5), P.call(0.32, 0.5), c, w)
			draw_line(P.call(0.68, 0.5), P.call(0.95, 0.5), c, w)
		"mana":
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.08), P.call(0.78, 0.55), P.call(0.5, 0.92), P.call(0.22, 0.55)]), c)
			draw_circle(P.call(0.42, 0.52), s * 0.07, Color(1, 1, 1, 0.6))
		"skill":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + i * PI / 5
				var r := 0.42 if i % 2 == 0 else 0.18
				pts.append(P.call(0.5 + cos(a) * r, 0.52 + sin(a) * r))
			draw_colored_polygon(pts, c)
		"heal", "healing":
			draw_rect(Rect2(P.call(0.38, 0.12), Vector2(0.24, 0.76) * s), c)
			draw_rect(Rect2(P.call(0.12, 0.38), Vector2(0.76, 0.24) * s), c)
		"chain":
			draw_arc(P.call(0.35, 0.5), s * 0.2, 0, TAU, 20, c, w)
			draw_arc(P.call(0.65, 0.5), s * 0.2, 0, TAU, 20, c, w)
		"coin":
			draw_circle(P.call(0.5, 0.5), s * 0.42, c)
			draw_circle(P.call(0.5, 0.5), s * 0.3, c.darkened(0.25))
			draw_rect(Rect2(P.call(0.44, 0.3), Vector2(0.12, 0.4) * s), c.lightened(0.3))
		"heart":
			draw_circle(P.call(0.33, 0.38), s * 0.2, c)
			draw_circle(P.call(0.67, 0.38), s * 0.2, c)
			draw_colored_polygon(PackedVector2Array([P.call(0.14, 0.46), P.call(0.86, 0.46), P.call(0.5, 0.9)]), c)
		"people":
			draw_circle(P.call(0.36, 0.32), s * 0.14, c)
			draw_circle(P.call(0.66, 0.36), s * 0.12, Color(c, 0.7))
			draw_colored_polygon(PackedVector2Array([P.call(0.12, 0.88), P.call(0.18, 0.56), P.call(0.54, 0.56), P.call(0.6, 0.88)]), c)
			draw_colored_polygon(PackedVector2Array([P.call(0.56, 0.86), P.call(0.58, 0.58), P.call(0.86, 0.58), P.call(0.9, 0.86)]), Color(c, 0.7))
		"refresh":
			draw_arc(P.call(0.5, 0.5), s * 0.32, 0.4, TAU - 0.6, 24, c, w * 1.2)
			draw_colored_polygon(PackedVector2Array([P.call(0.76, 0.18), P.call(0.86, 0.46), P.call(0.58, 0.4)]), c)
		"lock", "unlock":
			draw_rect(Rect2(P.call(0.22, 0.46), Vector2(0.56, 0.42) * s), c)
			if kind == "lock":
				draw_arc(P.call(0.5, 0.46), s * 0.2, PI, TAU, 16, c, w * 1.2)
			else:
				draw_arc(P.call(0.62, 0.4), s * 0.18, PI, TAU - 0.4, 16, c, w * 1.2)
		"play":
			draw_colored_polygon(PackedVector2Array([P.call(0.26, 0.14), P.call(0.86, 0.5), P.call(0.26, 0.86)]), c)
		"bag":
			draw_rect(Rect2(P.call(0.18, 0.36), Vector2(0.64, 0.52) * s), c)
			draw_arc(P.call(0.5, 0.36), s * 0.18, PI, TAU, 16, c, w)
		"plus":
			draw_line(P.call(0.5, 0.22), P.call(0.5, 0.78), c, w * 1.3)
			draw_line(P.call(0.22, 0.5), P.call(0.78, 0.5), c, w * 1.3)
		"civ":
			var hex := PackedVector2Array()
			for i in 6:
				var a := deg_to_rad(60.0 * i - 90.0)
				hex.append(P.call(0.5 + cos(a) * 0.44, 0.5 + sin(a) * 0.44))
			draw_colored_polygon(hex, c)
			hex.append(hex[0])
			draw_polyline(hex, c.lightened(0.45), w * 0.8)
			draw_circle(P.call(0.5, 0.5), s * 0.13, c.lightened(0.55))
		"trinket":
			draw_arc(P.call(0.5, 0.58), s * 0.3, 0, TAU, 24, c, w * 1.1)
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.06), P.call(0.64, 0.24), P.call(0.5, 0.36), P.call(0.36, 0.24)]), c)
		_:
			draw_circle(P.call(0.5, 0.5), s * 0.3, c)
