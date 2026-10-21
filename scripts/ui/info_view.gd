class_name InfoView
extends RefCounted
## 資訊面板內容（棋子數值＋可展開的來源明細）。只負責顯示。
## 同一隻棋子在戰鬥中會定時更新數值：update() 只改文字、不重建按鈕，點擊展開不會被打斷。

const COLOR_UP := "#5aa9ff"     # 增加：藍字
const COLOR_DOWN := "#ff6b6b"   # 減少：紅字
const COLOR_NORMAL := "#dfe4ee"

var body: VBoxContainer
var expanded: Dictionary = {}    # stat key -> 是否展開（切換棋子時保留，方便比較）
var _rows: Dictionary = {}       # key -> {button, detail}
var _order: Array = []
var _header: RichTextLabel
var _footer: RichTextLabel


func _init(container: VBoxContainer) -> void:
	body = container


func clear() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_rows.clear()
	_order.clear()
	_header = null
	_footer = null


static func make_rich(text: String, size: int = 15) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size + 1)
	r.text = text
	return r


## 只放文字（敵軍說明、羈絆名單等）
func show_text(text: String) -> void:
	clear()
	_header = make_rich(text)
	body.add_child(_header)


## 標題資訊 + 數值列 + 頁尾（技能、裝備欄）
func show_stats(header: String, rows: Array, footer: String) -> void:
	clear()
	_header = make_rich(header)
	body.add_child(_header)
	var hint := make_rich("[color=#8a90a0]點屬性可展開數值來源（藍字＝增加、紅字＝減少）[/color]", 12)
	body.add_child(hint)
	for row in rows:
		_add_row(row)
	_footer = make_rich(footer)
	body.add_child(_footer)


## 同一組屬性列：只更新文字（戰鬥中即時刷新用）；列的組成不同時才重建
func update_stats(header: String, rows: Array, footer: String) -> void:
	var keys: Array = []
	for r in rows:
		keys.append(r["key"])
	if keys != _order or _header == null:
		show_stats(header, rows, footer)
		return
	_header.text = header
	_footer.text = footer
	for r in rows:
		var it: Dictionary = _rows[r["key"]]
		(it["button"] as Button).text = _row_title(r)
		_color_row(it["button"], r)
		(it["detail"] as RichTextLabel).text = _row_detail(r)


func _row_title(r: Dictionary) -> String:
	var arrow := "▼" if expanded.get(r["key"], false) else "▶"
	return "%s %s：%s" % [arrow, r["label"], r["text"]]


static func _row_detail(r: Dictionary) -> String:
	var lines: Array = []
	for l in r.get("lines", []):
		var col := COLOR_NORMAL
		if int(l["sign"]) > 0:
			col = COLOR_UP
		elif int(l["sign"]) < 0:
			col = COLOR_DOWN
		lines.append("[color=%s]• %s：%s[/color]" % [col, l["label"], l["text"]])
	if r.has("extra"):
		lines.append("[color=#8a90a0]%s[/color]" % r["extra"])
	return "\n".join(lines)


## 列標題顏色依「修正後的淨變化」：增加為藍、減少為紅、無修正為一般文字（星級成長不算修正）
static func _color_row(b: Button, r: Dictionary) -> void:
	var net := float(r.get("net", 0.0))
	if net > 0.0001:
		b.add_theme_color_override("font_color", Color(COLOR_UP))
	elif net < -0.0001:
		b.add_theme_color_override("font_color", Color(COLOR_DOWN))
	else:
		b.remove_theme_color_override("font_color")


func _add_row(r: Dictionary) -> void:
	var key: String = r["key"]
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 15)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.clip_text = true
	_color_row(b, r)
	b.text = _row_title(r)
	var detail := make_rich(_row_detail(r), 13)
	detail.visible = expanded.get(key, false)
	var panel := MarginContainer.new()
	panel.add_theme_constant_override("margin_left", 14)
	panel.add_child(detail)
	b.pressed.connect(func():
		expanded[key] = not expanded.get(key, false)
		detail.visible = expanded[key]
		var arrow := "▼" if expanded[key] else "▶"
		b.text = arrow + b.text.substr(1))
	body.add_child(b)
	body.add_child(panel)
	_rows[key] = {"button": b, "detail": detail}
	_order.append(key)
