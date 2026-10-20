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
var target_cid := -1
## 狀態：{kind, value, until, src, next_tick?, tick_amount?, dtype?, tag?}
var statuses: Array = []
## 護盾：{amount, until}
var shields: Array = []

# 統計（結算畫面、測試用）
var damage_dealt := 0.0
var healing_done := 0.0
var casts := 0


func is_melee() -> bool:
	return attack_range <= 1


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


func effective_armor() -> float:
	return armor + status_sum("armor_up") - status_sum("armor_down")


func effective_mr() -> float:
	return mr


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
