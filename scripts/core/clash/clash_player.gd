class_name ClashPlayer
extends RefCounted
## 《氏族爭霸》一名玩家（真人或 AI）。經濟、商店、棋盤、候補、背包沿用 RunState（同一套規則方法）；
## 這裡只加上十人對局需要的身份、生命、名次、國家制度與政策狀態。

var index := 0              # 房間座位 0～9
var player_name := ""       # 玩家名稱（統治者）
var country := ""           # 國家名稱（房間與排行榜以它為主）
var is_human := false
var ai_level := "normal"    # AI 難度：easy／normal
var run: RunState
var hp := 100
var alive := true
var placement := 0          # 最終名次（存活中為 0）
var eliminated_round := 0
var hp_at_round_start := 100

# 國家制度與深化政策（第 8／16 回合選擇）
var government := ""        # democracy／empire／commune
var policy := ""            # 該制度的兩條政策之一
var core_uid := -1          # 朕即是國家：核心棋子
var loyalty := 0            # 帝國永不退讓：忠誠層數
var last_lineup_ids: Array = []   # 上一場的上場陣容（棋子 id）
var plan_round := 0         # 五回合計畫：開始執行的回合
var plan_cycles := 0        # 五回合計畫：已完成的週期（＝發展等級）

# 對戰紀錄
var recent_opponents: Array = []   # 最近的 PvP 對手座位（新的在後）
var wins := 0
var losses := 0
var round_log: Array = []          # 每回合摘要


func display_name() -> String:
	return "%s（%s）" % [country, player_name]


func government_name() -> String:
	return str(GameData.clash_cfg("government").get("systems", {}).get(government, {}).get("name", ""))


func policy_name() -> String:
	return str(GameData.clash_cfg("government").get("policies", {}).get(policy, {}).get("name", ""))


func level() -> int:
	return run.level()


## 上場陣容的簡單戰力（排行榜、AI 用）
func board_power() -> float:
	var p := 0.0
	for u in run.board.values():
		p += float(GameData.unit_cost(str(u["id"]))) * [1.0, 3.0, 9.0][clampi(int(u["star"]), 1, 3) - 1]
	return p
