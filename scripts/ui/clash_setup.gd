extends Control
## 《氏族爭霸》開局設定：輸入國家名稱與玩家名稱、選擇 AI 難度。國家制度不是開局選擇（第 8 回合才選）。

var country_edit: LineEdit
var name_edit: LineEdit
var level_opt: OptionButton
var seed_edit: LineEdit
var start_btn: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	UiStyle.apply_panel(panel)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "氏族爭霸"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UiStyle.GOLD)
	v.add_child(title)
	var sub := Label.new()
	sub.text = "10 人 PvPvE 競技自走棋・核心原型 V%s（1 名真人＋9 名 AI）" % str(GameData.clash_config().get("version", "0.1"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	v.add_child(sub)
	country_edit = _field(v, "國家名稱", "永遠正確的人民共和國")
	name_edit = _field(v, "統治者（玩家名稱）", "玩家001")
	var row := HBoxContainer.new()
	var ll := Label.new()
	ll.text = "AI 難度"
	ll.custom_minimum_size = Vector2(160, 0)
	row.add_child(ll)
	level_opt = OptionButton.new()
	level_opt.add_item("普通（維持經濟、湊羈絆、追升星）")
	level_opt.add_item("簡單（不刷新、升級慢）")
	level_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(level_opt)
	v.add_child(row)
	seed_edit = _field(v, "固定種子（選填，除錯用）", "")
	seed_edit.placeholder_text = "留空＝隨機"
	var note := Label.new()
	note.text = "規則：所有玩家都能買全部氏族的棋子，十人共用有限棋池。多數回合為 PvP；每隔數回合隨機兩兩合作 PvE（開打前可交易一項資源、先清場的一方派援軍救隊友）。第 8 回合選國家制度、第 16 回合選深化政策。最後存活者獲勝。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	v.add_child(note)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(140, 48)
	UiStyle.style_button(back, Color(0.18, 0.21, 0.28))
	back.pressed.connect(func(): Session.goto(Session.SCENE_MENU))
	btns.add_child(back)
	start_btn = Button.new()
	start_btn.name = "StartClash"
	start_btn.text = "開始對局"
	start_btn.custom_minimum_size = Vector2(0, 48)
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_button(start_btn, Color(0.55, 0.36, 0.08), UiStyle.GOLD, 20)
	start_btn.pressed.connect(start)
	btns.add_child(start_btn)
	v.add_child(btns)


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(160, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.max_length = 24
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 40)
	row.add_child(e)
	parent.add_child(row)
	return e


func start() -> void:
	var seed_value := seed_edit.text.strip_edges().to_int() if seed_edit.text.strip_edges().is_valid_int() else 0
	Session.new_clash(name_edit.text.strip_edges(), country_edit.text.strip_edges(), "easy" if level_opt.selected == 1 else "normal", seed_value)
	Session.goto(Session.SCENE_CLASH)
