class_name CombatUnit
extends RefCounted
## 戰鬥中的單位（只存在於一場模擬內）。

const NEGATIVE_KINDS := ["stun", "root", "slow", "dot", "atk_down", "armor_down", "taunt", "mark"]
## 森林祝禱「去除一項負面效果」的優先順序
const CLEANSE_ORDER := ["stun", "root", "slow", "dot", "atk_down", "armor_down", "taunt"]

var cid := 0
var side := 0            # 0 = 玩家、1 = 敵方
var uid := 0             # 玩家棋子實例 id（敵方為 0）
var unit_id := ""
var star := 1
var data: Dictionary = {}
var mods: Dictionary = {}
var cell := Vector2i.ZERO

var max_hp := 1.0
var hp := 1.0
var atk := 1.0
var armor := 0.0
var mr := 0.0
var atk_speed := 0.8
var attack_range := 1
var move_speed := 2.0
var mana := 0.0
var mana_max := 60.0
var crit_chance := 0.05
var crit_mult := 1.5

var alive := true
var ready_at := 0.0
## 一般攻擊的鎖定目標：選定後持續追擊到目標死亡（嘲諷只暫時覆蓋，不改這個值）
var target_cid := -1
## 開戰時的部署深度：0 = 己方最前排、3 = 最後排（索敵用，戰鬥中不變）
var front_rank := 0
## 鎖定目標「無法攻擊也無法接近」開始的時間（防卡死用，-1 = 沒有卡住）
var stuck_since := -1.0
## 非死亡原因的換目標次數（測試用）
var target_switches := 0
## 狀態：{kind, value, until, src, next_tick?, tick_amount?, dtype?, tag?}
var statuses: Array = []
## 護盾：{amount, until}
var shields: Array = []

# 戰鬥貢獻統計（以單位實例為準，同名兩隻分開計算）
var damage_dealt := 0.0      # 有效 HP 傷害（不含被護盾吸收、不含溢出擊殺）
var damage_taken := 0.0      # 實際損失的 HP
var shield_absorbed := 0.0   # 自己施放的護盾實際吸收的傷害（未消耗的不算）
var healing_done := 0.0      # 有效治療（超過最大生命的不算）
var raw_damage := 0.0        # 除錯用：結算後總傷害（含護盾吸收與溢出）
var overkill := 0.0          # 除錯用：擊殺時溢出的傷害
var casts := 0


func is_melee() -> bool:
	return attack_range <= 1


func is_assassin() -> bool:
	return str(data.get("class", "")) == "assassin"


func hp_ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


func has_status(kind: String) -> bool:
	for s in statuses:
		if s["kind"] == kind:
			return true
	return false


func status_sum(kind: String) -> float:
	var total := 0.0
	for s in statuses:
		if s["kind"] == kind:
			total += float(s.get("value", 0.0))
	return total


func status_from(kind: String, src_cid: int) -> Dictionary:
	for s in statuses:
		if s["kind"] == kind and int(s.get("src", -1)) == src_cid:
			return s
	return {}


func shield_total() -> float:
	var t := 0.0
	for s in shields:
		t += float(s["amount"])
	return t


func effective_atk() -> float:
	var pct := status_sum("atk_up") - status_sum("atk_down")
	return atk * maxf(0.1, 1.0 + pct / 100.0)


## 有效防禦：套用破甲／增益後的數值，最低為 0（不產生負防禦）
func effective_armor() -> float:
	return maxf(0.0, armor + status_sum("armor_up") - status_sum("armor_down"))


func effective_mr() -> float:
	return maxf(0.0, mr + status_sum("mr_up") - status_sum("mr_down"))


func effective_atk_speed() -> float:
	var pct := status_sum("as_up") - status_sum("slow")
	return atk_speed * maxf(0.25, 1.0 + pct / 100.0)


func effective_move_speed() -> float:
	return move_speed * maxf(0.3, 1.0 - status_sum("slow") / 100.0)


func snapshot() -> Dictionary:
	return {
		"cid": cid, "side": side, "uid": uid, "id": unit_id, "star": star,
		"cell": cell, "hp": hp, "max_hp": max_hp, "mana": mana, "mana_max": mana_max,
		"shield": shield_total(),
	}
