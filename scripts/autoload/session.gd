extends Node
## 全域單例（autoload 名稱：Session）：保存目前這局、負責場景切換。

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_CIV := "res://scenes/civ_select.tscn"
const SCENE_GAME := "res://scenes/game.tscn"
const SCENE_CODEX := "res://scenes/codex.tscn"
const SCENE_END := "res://scenes/end_screen.tscn"

var run: RunState = null
## 除錯工具只在除錯版（編輯器中執行、或匯出時勾選 Debug）出現
var debug_enabled := OS.is_debug_build()
## 從圖鑑返回時要回去的場景
var codex_return := SCENE_MENU
var battle_speed := 1.0

const THEME_PATH := "res://assets/theme/main_theme.tres"


func _ready() -> void:
	# 全域主題（繁中字型）在執行時套用，避免專案第一次匯入時字型尚未匯入而報錯
	if ResourceLoader.exists(THEME_PATH):
		get_tree().root.theme = load(THEME_PATH)


func new_run(civ_id: String) -> void:
	var seed_value := int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
	run = RunState.create(civ_id, seed_value)
	SaveSystem.save_run(run)


func continue_run() -> bool:
	run = SaveSystem.load_run()
	return run != null


func goto(scene_path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", scene_path)


func open_codex(return_to: String) -> void:
	codex_return = return_to
	goto(SCENE_CODEX)
