class_name Modifiers
extends RefCounted
## 把文明 Buff/Debuff 與羈絆效果加總成每隻棋子的修正值。
## 同類百分比先加總，戰鬥時再一次套用，避免乘法膨脹。

## 修正鍵一覽（數值為百分比，除非註明為固定值）
const KEYS := [
	"hp_pct",             # 最大 HP %
	"armor_flat",         # 護甲（固定值）
	"mr_flat",            # 魔抗（固定值）
	"start_mana",         # 初始魔力（固定值）
	"move_speed_pct",     # 戰場移動速度 %
	"basic_dmg_pct",      # 普攻傷害 %
	"melee_basic_pct",    # 近戰棋子普攻傷害 %
	"ranged_basic_pct",   # 遠程棋子普攻傷害 %
	"skill_direct_pct",   # 技能直接傷害 %（不含持續傷害）
	"magic_dmg_pct",      # 造成的法術傷害 %（含持續傷害）
	"magic_direct_pct",   # 法術直接傷害 %（不含持續傷害）
	"heal_shield_pct",    # 給出的治療與護盾 %
	"heal_received_pct",  # 接受治療量 %
	"cc_duration_pct",    # 施加的控制時間 %（上限見 combat.civ_cc_extra_cap）
	"cc_received_pct",    # 受到的控制時間 %（上限同上）
	"low_hp_direct_pct",  # 自身 HP 低於門檻時直接傷害 %
	"execute_pct",        # 攻擊 HP 低於門檻的敵人時傷害 %
]


static func empty() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = 0.0
	return d


static func cond_ok(cond: Dictionary, unit: Dictionary, ctx: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("range"):
		var melee := int(unit.get("range", 1)) <= 1
		if (cond["range"] == "melee") != melee:
			return false
	if cond.has("type") and str(unit.get("type", "")) != str(cond["type"]):
		return false
	if cond.has("race") and str(unit.get("race", "")) != str(cond["race"]):
		return false
	if cond.has("class") and str(unit.get("class", "")) != str(cond["class"]):
		return false
	if cond.has("min_distinct_races") and int(ctx.get("distinct_races", 0)) < int(cond["min_distinct_races"]):
		return false
	return true


static func add_effects(mods: Dictionary, effects: Array, unit: Dictionary, ctx: Dictionary) -> void:
	for e in effects:
		if not cond_ok(e.get("cond", {}), unit, ctx):
			continue
		var stat := str(e["stat"])
		if not mods.has(stat):
			push_warning("未知的修正鍵：%s" % stat)
		mods[stat] = float(mods.get(stat, 0.0)) + float(e["value"])


## 文明效果（buffs + debuffs）
static func civ_effects(civ_id: String) -> Array:
	var out: Array = []
	var c := GameData.civ(civ_id)
	for group in ["buffs", "debuffs"]:
		for b in c.get(group, []):
			out.append_array(b.get("effects", []))
	return out


## 計算一方棋盤上每隻棋子的修正值。
## unit_ids：棋盤上每一隻的 id（可重複，順序對應回傳陣列）。
## civ_id：玩家文明（敵方傳 ""）；use_synergy：是否套用羈絆。
static func for_lineup(unit_ids: Array, civ_id: String, use_synergy: bool) -> Array:
	var counts := Synergy.count(unit_ids)
	var actives: Array = Synergy.active(counts) if use_synergy else []
	var ctx := {"distinct_races": counts["race"].size()}
	var civ_fx := civ_effects(civ_id) if civ_id != "" else []
	var out: Array = []
	for id in unit_ids:
		var u := GameData.unit(str(id))
		var m := empty()
		add_effects(m, civ_fx, u, ctx)
		for a in actives:
			if str(u.get(a["group"], "")) == str(a["key"]):
				add_effects(m, a["effects"], u, ctx)
		out.append(m)
	return out
