class_name UnitCard
extends VBoxContainer
## 棋子資訊卡（V0.3）：圖像＋名稱＋星級＋種族類型職業 → 生命數字與 HP 條（含護盾）→ 3×4 屬性宮格 → 兩格裝備 → 技能。
## 宮格平常只有「圖示＋最終數字」，數字顏色：高於目前星級基礎值＝藍、低於＝紅、相同＝白。
## 點格子才在卡片內展開該屬性的來源明細；再點一次、按 ×、或點其他地方即關閉。
## 同一隻棋子在戰鬥中定時呼叫 refresh()：只更新文字與顏色，不重建節點，點擊不會被打斷。

signal equip_slot_pressed(slot: int)

const COLOR_UP := Color("#5aa9ff")
const COLOR_DOWN := Color("#ff6b6b")
const COLOR_SAME := Color("#f2f4f8")
const TOKEN_SCENE := preload("res://scenes/unit_token.tscn")

var _portrait_token: UnitToken
var _name: Label
var _line: Label
var _hp_label: Label
var _hp_bar: ProgressBar
var _shield_bar: ProgressBar
var _grid: GridContainer
var _cells: Dictionary = {}          # key -> {button, icon, label}
var _cell_data: Dictionary = {}      # key -> 格子資料
var _popup: PanelContainer
var _popup_text: RichTextLabel
var _open_key := ""
var _slots: Array[Button] = []
var _skill: RichTextLabel
var _note: Label
var _unit_key := ""


func _init() -> void:
	add_theme_constant_override("separation", 5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 標頭：圖像＋名稱
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(52, 52)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_token = TOKEN_SCENE.instantiate()
	_portrait_token.position = Vector2(26, 28)
	_portrait_token.show_head = false
	portrait.add_child(_portrait_token)
	head.add_child(portrait)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 18)
	_name.clip_text = true
	_line = Label.new()
	_line.add_theme_font_size_override("font_size", 13)
	_line.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
	_line.clip_text = true
	names.add_child(_name)
	names.add_child(_line)
	head.add_child(names)
	add_child(head)
	# 生命與 HP 條
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 15)
	add_child(_hp_label)
	var bars := Control.new()
	bars.custom_minimum_size = Vector2(0, 12)
	_hp_bar = _make_bar(Color(0.36, 0.84, 0.46), Color(1, 1, 1, 0.10))
	_shield_bar = _make_bar(Color(0.92, 0.95, 1.0, 0.85), Color(0, 0, 0, 0))
	for b in [_hp_bar, _shield_bar]:
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bars.add_child(b)
	add_child(bars)
	# 3×4 宮格
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	for key in StatBreakdown.ORDER:
		_add_cell(key)
	add_child(_grid)
	# 點擊後的明細（卡片內，不遮棋盤）
	_popup = PanelContainer.new()
	_popup.visible = false
	UiStyle.apply_panel(_popup, Color(0.06, 0.08, 0.12, 0.97), Color(1.0, 0.85, 0.4, 0.7))
	var pv := VBoxContainer.new()
	var ph := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(36, 30)
	close.flat = true
	close.pressed.connect(close_detail)
	ph.add_child(spacer)
	ph.add_child(close)
	_popup_text = RichTextLabel.new()
	_popup_text.bbcode_enabled = true
	_popup_text.fit_content = true
	_popup_text.scroll_active = false
	_popup_text.add_theme_font_size_override("normal_font_size", 13)
	_popup_text.add_theme_font_size_override("bold_font_size", 16)
	pv.add_child(ph)
	pv.add_child(_popup_text)
	ph.move_to_front()
	_popup.add_child(pv)
	add_child(_popup)
	# 裝備欄
	var eq := HBoxContainer.new()
	eq.add_theme_constant_override("separation", 6)
	var eq_label := Label.new()
	eq_label.text = "裝備"
	eq_label.add_theme_font_size_override("font_size", 13)
	eq_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	eq.add_child(eq_label)
	for i in GameData.item_slots():
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 44)
		var idx := i
		b.pressed.connect(func(): equip_slot_pressed.emit(idx))
		var ic := UiIcon.make("plus", Color(1, 1, 1, 0.45), 22)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.position -= Vector2(11, 11)
		b.add_child(ic)
		eq.add_child(b)
		_slots.append(b)
	add_child(eq)
	# 技能
	_skill = RichTextLabel.new()
	_skill.bbcode_enabled = true
	_skill.fit_content = true
	_skill.scroll_active = false
	_skill.add_theme_font_size_override("normal_font_size", 13)
	add_child(_skill)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 12)
	_note.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)


static func _make_bar(fill_col: Color, bg_col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_col
	bg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b


func _add_cell(key: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(72, 54)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_button(b, Color(0.13, 0.15, 0.21), Color(1, 1, 1, 0.08), 14)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	var ic := UiIcon.make("sword", Color(0.85, 0.88, 0.95), 22)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	v.add_child(l)
	b.add_child(v)
	b.pressed.connect(func(): _toggle_detail(key))
	_grid.add_child(b)
	_cells[key] = {"button": b, "icon": ic, "label": l}


## data：{id, star, side, sources, statuses, live: {hp, max_hp, shield, mana}?, items, note, readonly_items}
func show_unit(data: Dictionary) -> void:
	var key := "%s|%s|%s" % [data.get("ref", ""), data["id"], data["star"]]
	if key != _unit_key:
		_unit_key = key
		close_detail()
	refresh(data)


func refresh(data: Dictionary) -> void:
	var id := str(data["id"])
	var star := int(data["star"])
	var u := GameData.unit(id)
	_portrait_token.setup(id, star, int(data.get("side", 0)), 20.0)
	_portrait_token.items = data.get("items", [])
	_name.text = "%s %s" % [u.get("name", id), "★".repeat(star)]
	if GameData.is_special(id) and u.has("phase"):
		_line.text = "%s・異界敵軍" % GameData.race_name(str(u.get("race", "")))
	elif u.has("stats"):
		_line.text = "教學用弱敵"
	else:
		_line.text = "%s %d 費・%s" % [GameData.tier_name(int(u["cost"])), int(u["cost"]), UiStyle.unit_line(id)]
	var sources: Array = data.get("sources", [])
	var hp := StatBreakdown.hp_info(id, star, sources)
	var live: Dictionary = data.get("live", {})
	var max_hp := float(live.get("max_hp", hp["max"]))
	var cur := float(live.get("hp", max_hp))
	var shield := float(live.get("shield", 0.0))
	_hp_label.text = "生命 %d / %d%s" % [roundi(cur), roundi(max_hp), ("　護盾 %d" % roundi(shield)) if shield > 0.0 else ""]
	_hp_label.add_theme_color_override("font_color", COLOR_UP if hp["sign"] > 0 else (COLOR_DOWN if hp["sign"] < 0 else COLOR_SAME))
	var total := maxf(max_hp, cur + shield)
	_hp_bar.max_value = total
	_hp_bar.value = cur
	_shield_bar.max_value = total
	_shield_bar.value = cur + shield if shield > 0.0 else 0.0
	_shield_bar.visible = shield > 0.0
	_hp_bar.move_to_front()
	var cells := StatBreakdown.cells(id, star, sources, data.get("statuses", []), live)
	for c in cells:
		_cell_data[c["key"]] = c
		var it: Dictionary = _cells[c["key"]]
		(it["label"] as Label).text = str(c["text"])
		var col := COLOR_UP if int(c["sign"]) > 0 else (COLOR_DOWN if int(c["sign"]) < 0 else COLOR_SAME)
		(it["label"] as Label).add_theme_color_override("font_color", col)
		(it["icon"] as UiIcon).set_icon(str(c["icon"]), col.lerp(Color.WHITE, 0.25))
		(it["button"] as Button).tooltip_text = str(c["label"])
	if _open_key != "":
		_render_detail(_open_key)
	# 裝備欄
	var items: Array = data.get("items", [])
	for i in _slots.size():
		var b := _slots[i]
		var ic: UiIcon = b.get_child(0)
		if i < items.size():
			var info := Equipment.type_info(str(items[i]))
			ic.set_icon(str(GameData.item(items[i]).get("type", "weapon")), Color(str(info.get("color", "#ffffff"))))
			UiStyle.style_button(b, Color(0.16, 0.18, 0.24), Color(str(info.get("color", "#888888"))).darkened(0.2), 13)
			b.tooltip_text = str(GameData.item(items[i]).get("name", ""))
		else:
			ic.set_icon("plus", Color(1, 1, 1, 0.4))
			var sb := UiStyle.panel_box(Color(0.10, 0.11, 0.15), Color(1, 1, 1, 0.25), 8)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			b.tooltip_text = "空裝備欄"
	var sk := UnitStats.skill(id)
	_skill.text = "[color=#ffd34d]%s[/color]　%s" % [sk.get("name", ""), UnitStats.skill_text(id, star)]
	_note.text = str(data.get("note", ""))


func _toggle_detail(key: String) -> void:
	if _open_key == key and _popup.visible:
		close_detail()
		return
	_open_key = key
	_render_detail(key)
	_popup.visible = true
	_scroll_into_view.call_deferred()


## 明細展開後捲動到看得見的位置（卡片放在可捲動的面板裡）
func _scroll_into_view() -> void:
	await get_tree().process_frame
	var p := get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p is ScrollContainer and _popup.visible:
		(p as ScrollContainer).ensure_control_visible(_popup)


func close_detail() -> void:
	_open_key = ""
	if _popup:
		_popup.visible = false


func is_detail_open() -> bool:
	return _popup.visible


func detail_rect() -> Rect2:
	return _popup.get_global_rect()


func _render_detail(key: String) -> void:
	var c: Dictionary = _cell_data.get(key, {})
	if c.is_empty():
		return
	var col := "#5aa9ff" if int(c["sign"]) > 0 else ("#ff6b6b" if int(c["sign"]) < 0 else "#f2f4f8")
	var lines: Array = ["[b]%s：[color=%s]%s[/color][/b]" % [c["label"], col, c["text"]]]
	for l in c["lines"]:
		var lc := "#5aa9ff" if int(l["sign"]) > 0 else ("#ff6b6b" if int(l["sign"]) < 0 else "#dfe4ee")
		var cat := str(StatBreakdown.CAT_NAMES.get(l["cat"], ""))
		lines.append("[color=%s]• %s%s：%s[/color]" % [lc, ("［%s］" % cat) if l["cat"] != "base" else "", l["label"], l["text"]])
	lines.append("[color=%s]• 最終：%s[/color]" % [col, c["text"]])
	for e in c.get("extra", []):
		lines.append("[color=#8a90a0]%s[/color]" % e)
	_popup_text.text = "\n".join(lines)


## 點卡片以外（或卡片內明細以外）的地方時關閉明細（不吃掉事件）
func _input(event: InputEvent) -> void:
	if not _popup.visible or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _popup.get_global_rect().has_point(event.position):
			return
		for k in _cells.keys():
			if (_cells[k]["button"] as Button).get_global_rect().has_point(event.position):
				return
		close_detail()


func cell_button(key: String) -> Button:
	return _cells[key]["button"]


func cell_text(key: String) -> String:
	return (_cells[key]["label"] as Label).text


func cell_color(key: String) -> Color:
	return (_cells[key]["label"] as Label).get_theme_color("font_color")


func detail_text() -> String:
	return _popup_text.text


func slot_button(i: int) -> Button:
	return _slots[i]
