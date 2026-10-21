extends Control
## 文明六選一：每張卡顯示 2 Buff、2 Debuff 與本文明的頂尖棋子。

@onready var grid: GridContainer = $Margin/VBox/CivGrid
@onready var back_btn: Button = $Margin/VBox/Buttons/BackButton
@onready var start_btn: Button = $Margin/VBox/Buttons/StartButton

var _selected := ""
var _cards: Dictionary = {}   # civ_id -> Button


func _ready() -> void:
	UiStyle.style_button(back_btn, Color(0.18, 0.21, 0.28))
	UiStyle.style_button(start_btn, Color(0.55, 0.36, 0.08), UiStyle.GOLD, 20)
	for c in GameData.civs():
		var card := _make_card(c)
		grid.add_child(card)
		_cards[str(c["id"])] = card
	back_btn.pressed.connect(func(): Session.goto(Session.SCENE_MENU))
	start_btn.pressed.connect(_on_start)


func _make_card(c: Dictionary) -> Button:
	var id := str(c["id"])
	var race_col := GameData.race_color(str(c["race"]))
	var b := Button.new()
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(300, 210)
	b.clip_contents = true
	var normal := UiStyle.panel_box(Color(0.12, 0.14, 0.19), Color(race_col, 0.5), 12, 2)
	var sel := UiStyle.panel_box(Color(race_col.darkened(0.55)), UiStyle.GOLD, 12, 3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", UiStyle.panel_box(Color(0.15, 0.17, 0.24), race_col, 12, 2))
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	rich.add_theme_font_size_override("normal_font_size", 15)
	rich.add_theme_font_size_override("bold_font_size", 24)
	var four: Array = Shop.pool_for(id, 4).filter(func(x): return not GameData.is_neutral(x))
	var four_name := str(GameData.unit(four[0])["name"]) if not four.is_empty() else "?"
	var lines: Array = []
	lines.append("[b][color=%s]%s[/color][/b]　[color=#9aa3ad]頂尖棋子：%s[/color]" % [UiStyle.hex_color(race_col.lightened(0.25)), c["name"], four_name])
	for bf in c["buffs"]:
		lines.append("[color=#6bdc85]▲ %s[/color]" % bf["text"])
	for df in c["debuffs"]:
		lines.append("[color=#f07a70]▼ %s[/color]" % df["text"])
	rich.text = "\n".join(lines)
	b.add_child(rich)
	b.pressed.connect(func(): _select(id))
	return b


func _select(id: String) -> void:
	_selected = id
	for k in _cards.keys():
		_cards[k].set_pressed_no_signal(k == id)
	start_btn.disabled = false
	start_btn.text = "以「%s」出發遠征" % GameData.civ(id)["name"]


func _on_start() -> void:
	if _selected == "":
		return
	Session.new_run(_selected)
	Session.goto(Session.SCENE_GAME)
