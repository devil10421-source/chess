extends Node
## 全域單例（autoload 名稱：Session）：保存目前這局、負責場景切換。

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_CIV := "res://scenes/civ_select.tscn"
const SCENE_GAME := "res://scenes/game.tscn"
const SCENE_CODEX := "res://scenes/codex.tscn"
const SCENE_END := "res://scenes/end_screen.tscn"
const SCENE_CLASH_SETUP := "res://scenes/clash_setup.tscn"
const SCENE_CLASH := "res://scenes/clash_game.tscn"

var run: RunState = null
## 《氏族爭霸》進行中的十人對局（單人模式為 null）
var clash: ClashMatch = null
## 除錯工具只在除錯版（編輯器中執行、或匯出時勾選 Debug）出現
var debug_enabled := OS.is_debug_build()
## 從圖鑑返回時要回去的場景
var codex_return := SCENE_MENU
var battle_speed := 1.0
## 目前實際的播放倍率（戰鬥加速分段 × 玩家選的速度），動畫與狀態倒數都用這個值
var playback_rate := 1.0
## 從圖鑑返回同一回合時，接續備戰剩餘秒數（避免開圖鑑重置倒數）
var prep_time_left := 0.0
var prep_time_round := -1

const THEME_PATH := "res://assets/theme/main_theme.tres"


func _ready() -> void:
	# 全域主題（繁中字型）在執行時套用，避免專案第一次匯入時字型尚未匯入而報錯
	if ResourceLoader.exists(THEME_PATH):
		get_tree().root.theme = load(THEME_PATH)


func new_run(civ_id: String) -> void:
	end_clash()
	var seed_value := int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
	run = RunState.create(civ_id, seed_value)
	SaveSystem.save_run(run)


## 開始《氏族爭霸》：1 名真人＋9 名 AI
func new_clash(player_name: String, country: String, ai_level: String, seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
	clash = ClashMatch.create(player_name, country, seed_value, ai_level, true)
	run = clash.human().run


## 離開《氏族爭霸》：還原中立棋子的氏族歸屬，避免影響單人模式
func end_clash() -> void:
	clash = null
	GameData.set_clash_clans(false)


func continue_run() -> bool:
	end_clash()
	run = SaveSystem.load_run()
	return run != null


func goto(scene_path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", scene_path)


func open_codex(return_to: String) -> void:
	codex_return = return_to
	goto(SCENE_CODEX)
