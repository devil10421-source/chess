extends Control
## 主選單：開始新遠征、繼續遊戲、規則／圖鑑。

@onready var new_btn: Button = $Center/Box/NewGameButton
@onready var cont_btn: Button = $Center/Box/ContinueButton
@onready var codex_btn: Button = $Center/Box/CodexButton
@onready var unlock_btn: Button = $Center/Box/UnlockButton
@onready var quit_btn: Button = $Center/Box/QuitButton
@onready var confirm: ConfirmationDialog = $ConfirmNewGame
@onready var version_label: Label = $Version


func _ready() -> void:
	UiStyle.style_button(new_btn, Color(0.55, 0.36, 0.08), UiStyle.GOLD, 22)
	UiStyle.style_button(cont_btn, Color(0.16, 0.30, 0.52), Color(0.4, 0.6, 1.0, 0.6), 20)
	UiStyle.style_button(codex_btn, Color(0.18, 0.21, 0.28))
	UiStyle.style_button(unlock_btn, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.1), 15)
	UiStyle.style_button(quit_btn, Color(0.18, 0.21, 0.28))
	var has_save := SaveSystem.has_save()
	cont_btn.disabled = not has_save
	if has_save:
		var r := SaveSystem.load_run()
		cont_btn.text = "繼續遠征（%s・第 %d 回合・生命 %d）" % [r.civ_name(), r.round_no, r.hp]
	version_label.text = "V%s 原型・Godot %s%s" % [str(GameData.config().get("version", "0.1")), Engine.get_version_info()["string"], "・除錯模式" if Session.debug_enabled else ""]
	new_btn.pressed.connect(_on_new)
	cont_btn.pressed.connect(_on_continue)
	codex_btn.pressed.connect(func(): Session.open_codex(Session.SCENE_MENU))
	quit_btn.pressed.connect(func(): get_tree().quit())
	confirm.confirmed.connect(func():
		SaveSystem.clear()
		Session.goto(Session.SCENE_CIV))
	# 手機平台沒有「離開」的慣例
	quit_btn.visible = not (OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web"))
	new_btn.grab_focus()


func _on_new() -> void:
	if SaveSystem.has_save():
		confirm.popup_centered()
	else:
		Session.goto(Session.SCENE_CIV)


func _on_continue() -> void:
	if Session.continue_run():
		Session.goto(Session.SCENE_GAME)
