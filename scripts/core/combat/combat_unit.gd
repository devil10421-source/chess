class_name CombatUnit
extends RefCounted
## 戰鬥中的單位（只存在於一場模擬內）。

## V0.4 共用戰鬥術語：緩速（移速 −25%、攻速 −10%，不疊加）、重傷（受到的治療 −40%，不疊加）、持續傷害（統一名稱）。
## 「破甲／降低防禦」已取消，改為攻擊者自身的物理穿透／魔法穿透（phys_pen／magic_pen）。
const NEGATIVE_KINDS := ["stun", "root", "slow", "wound", "dot", "atk_down", "taunt", "mark"]
## 森林祝禱「去除一項負面效果」的優先順序
const CLEANSE_ORDER := ["stun", "root", "slow", "wound", "dot", "atk_down", "taunt"]

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
## 裝備（V0.3）：身上的裝備 id 與其被動
var items: Array = []
var passives: Array = []
var item_counter := 0
## 追跡獵手（被動）：連續普攻同一目標的層數
var focus_target := -1
## 施法前搖中（V0.5）
var winding_up := false
## 裝備特效的冷卻（唯一特性 id -> 可再次觸發的時間）
var item_cd: Dictionary = {}
var focus_stacks := 0
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


## 被動技能（沒有主動施放，例如追跡獵手）
func has_passive_skill() -> bool:
	return bool(data.get("skill", {}).get("passive", false))


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


## 有效防禦：套用增益後的數值，最低為 0（V0.4 起沒有降低防禦的效果，改用攻擊方的穿透）
func effective_armor() -> float:
	return maxf(0.0, armor + status_sum("armor_up"))


func effective_mr() -> float:
	return maxf(0.0, mr + status_sum("mr_up"))


## 緩速規則（game_config.json → combat.status）
static func slow_move_pct() -> float:
	return float(GameData.cfg("combat").get("status", {}).get("slow_move_pct", 25))


static func slow_as_pct() -> float:
	return float(GameData.cfg("combat").get("status", {}).get("slow_as_pct", 10))


func effective_atk_speed() -> float:
	var pct := status_sum("as_up") - (slow_as_pct() if has_status("slow") else 0.0)
	return atk_speed * maxf(0.25, 1.0 + pct / 100.0)


func effective_move_speed() -> float:
	return move_speed * maxf(0.3, 1.0 - (slow_move_pct() if has_status("slow") else 0.0) / 100.0)


## 穿透（百分比）：mods（裝備、文明、羈絆）＋自身狀態（技能），同類加總後上限 combat.status.penetration_max_pct
func penetration(dtype: String) -> float:
	var key := "magic_pen" if dtype == "magic" else "phys_pen"
	var cap := float(GameData.cfg("combat").get("status", {}).get("penetration_max_pct", 60))
	return clampf(float(mods.get(key, 0.0)) + status_sum(key), 0.0, cap)


func snapshot() -> Dictionary:
	return {
		"cid": cid, "side": side, "uid": uid, "id": unit_id, "star": star,
		"cell": cell, "hp": hp, "max_hp": max_hp, "mana": mana, "mana_max": mana_max,
		"shield": shield_total(), "atk": atk, "armor": armor, "mr": mr, "atk_speed": atk_speed,
		"range": attack_range, "move_speed": move_speed, "mods": mods.duplicate(), "items": items.duplicate(),
		"crit_chance": crit_chance, "crit_mult": crit_mult,
	}
