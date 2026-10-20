extends Control
## 遠征結算畫面：通關／戰敗／未完成。

@onready var title: Label = $Center/Panel/VBox/Title
@onready var summary: RichTextLabel = $Center/Panel/VBox/Summary
@onready var new_btn: Button = $Center/Panel/VBox/Buttons/NewButton
@onready var menu_btn: Button = $Center/Panel/VBox/Buttons/MenuButton


func _ready() -> void:
	UiStyle.apply_panel($Center/Panel, Color(0.10, 0.12, 0.17, 0.98), UiStyle.GOLD)
	UiStyle.style_button(new_btn, Color(0.55, 0.36, 0.08), UiStyle.GOLD, 20)
	UiStyle.style_button(menu_btn, Color(0.18, 0.21, 0.28))
	new_btn.pressed.connect(func(): Session.goto(Session.SCENE_CIV))
	menu_btn.pressed.connect(func(): Session.goto(Session.SCENE_MENU))
	var run: RunState = Session.run
	if run == null:
		title.text = "遠征結束"
		summary.text = ""
		return
	match run.outcome:
		"victory":
			title.text = "遠征完成！"
			title.add_theme_color_override("font_color", UiStyle.GOLD)
		"incomplete":
			title.text = "遠征未完成"
			title.add_theme_color_override("font_color", UiStyle.BAD)
		_:
			title.text = "遠征失敗"
			title.add_theme_color_override("font_color", UiStyle.BAD)
	var cleared := 0
	for h in run.history:
		if h["cleared"]:
			cleared += 1
	var lines: Array = []
	lines.append("文明：[b]%s[/b]　文明等級 Lv.%d" % [run.civ_name(), run.level()])
	lines.append("完成回合：%d / %d　全清關卡：%d" % [run.history.size(), GameData.total_rounds(), cleared])
	lines.append("剩餘遠征生命：%d / %d　剩餘金幣：%d" % [run.hp, Economy.max_hp(), run.gold])
	if run.outcome == "incomplete":
		lines.append("[color=#f07a70]第 24 回合未能全清敵軍，遠征未完成。[/color]")
	elif run.outcome == "defeat":
		lines.append("[color=#f07a70]遠征生命在第 %d 回合歸零。[/color]" % run.round_no)
	var units: Array = []
	for u in run.all_units():
		units.append("%s%s" % [GameData.unit(u["id"])["name"], UiStyle.stars(int(u["star"]))])
	if not units.is_empty():
		lines.append("")
		lines.append("[color=#9aa3ad]最終陣容：%s[/color]" % "、".join(units))
	lines.append("")
	lines.append("[color=#7d8494]（遠征徽記與替代型態屬於後續階段，尚未開放）[/color]")
	summary.text = "\n".join(lines)
	SaveSystem.clear()
