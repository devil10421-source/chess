class_name LeaderPanel
extends VBoxContainer
## 右側可收合的戰鬥貢獻面板（V0.3）：傷害輸出／承受傷害／護盾吸收／有效治療。
## 戰鬥中顯示即時統計；戰鬥結束後保留上一場，直到下一場開始。

signal collapse_toggled(collapsed: bool)

const TAB_ICONS := {"damage": "sword", "taken": "shield", "shielded": "magic_shield", "healing": "heal"}
const BAR_COLORS := {"damage": Color(1.0, 0.62, 0.3), "taken": Color(0.95, 0.38, 0.38), "shielded": Color(0.8, 0.9, 1.0), "healing": Color(0.42, 0.86, 0.52)}

var metric := "damage"
var collapsed := false
var _title: Label
var _toggle: Button
var _tabs: Dictionary = {}
var _tab_row: HBoxContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _stats: Array = []


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	_title = Label.new()
	_title.text = "戰鬥貢獻"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", UiStyle.GOLD)
	_title.clip_text = true
	_toggle = Button.new()
	_toggle.custom_minimum_size = Vector2(40, 32)
	_toggle.text = "▶"
	UiStyle.style_button(_toggle, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 14)
	_toggle.pressed.connect(func(): set_collapsed(not collapsed))
	head.add_child(_title)
	head.add_child(_toggle)
	add_child(head)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 4)
	for m in Leaderboard.ORDER:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = Leaderboard.METRICS[m]
		var ic := UiIcon.make(TAB_ICONS[m], Color.WHITE, 20)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		ic.position -= Vector2(10, 10)
		b.add_child(ic)
		var mm: String = m
		b.pressed.connect(func(): set_metric(mm))
		_tab_row.add_child(b)
		_tabs[m] = b
	add_child(_tab_row)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list)
	add_child(_scroll)
	set_metric("damage")


func set_collapsed(v: bool) -> void:
	collapsed = v
	_title.visible = not v
	_tab_row.visible = not v
	_scroll.visible = not v
	_toggle.text = "◀" if v else "▶"
	collapse_toggled.emit(v)


func set_metric(m: String) -> void:
	metric = m
	for k in _tabs.keys():
		UiStyle.style_button(_tabs[k], Color(0.55, 0.36, 0.08) if k == m else Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 13)
	_title.text = "戰鬥貢獻：%s" % Leaderboard.METRICS[m]
	_rebuild()


func set_stats(stats: Array) -> void:
	_stats = stats
	_rebuild()


func _rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var rows := Leaderboard.rows(_stats, metric, 0)
	var total := Leaderboard.total(_stats, metric, 0)
	if rows.is_empty() or total <= 0.0:
		var l := Label.new()
		l.text = "尚無資料" if _stats.is_empty() else "本場沒有%s紀錄" % Leaderboard.METRICS[metric]
		l.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		l.add_theme_font_size_override("font_size", 13)
		_list.add_child(l)
		return
	for r in rows:
		_list.add_child(_row(r))


func _row(r: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	var badge := PanelContainer.new()
	var u := GameData.unit(r["id"])
	var sb := StyleBoxFlat.new()
	sb.bg_color = GameData.race_color(str(u.get("race", "")))
	sb.border_color = GameData.tier_color(int(u.get("cost", 1)))
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(11)
	badge.add_theme_stylebox_override("panel", sb)
	badge.custom_minimum_size = Vector2(22, 22)
	var bl := Label.new()
	bl.text = str(u.get("short", "?")).substr(0, 1)
	bl.add_theme_font_size_override("font_size", 12)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	var name := Label.new()
	name.text = "%s%s" % [r["name"], "★".repeat(int(r["star"]))]
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.add_theme_font_size_override("font_size", 13)
	var val := Label.new()
	val.text = "%d・%d%%" % [int(r["value"]), roundi(float(r["pct"]))]
	val.add_theme_font_size_override("font_size", 13)
	h.add_child(badge)
	h.add_child(name)
	h.add_child(val)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = float(r["ratio"])
	bar.custom_minimum_size = Vector2(0, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BAR_COLORS.get(metric, Color.WHITE)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	v.add_child(h)
	v.add_child(bar)
	return v


func row_count() -> int:
	return _list.get_child_count()
