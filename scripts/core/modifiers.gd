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
	"skill_dmg_pct",      # 技能造成的所有傷害 %（含技能造成的持續傷害；不含普攻與裝備）
	"skill_direct_pct",   # 技能直接傷害 %（不含持續傷害）
	"magic_dmg_pct",      # 造成的法術傷害 %（含持續傷害）
	"magic_direct_pct",   # 法術直接傷害 %（不含持續傷害）
	"heal_shield_pct",    # 給出的治療與護盾 %
	"heal_received_pct",  # 接受治療量 %
	"cc_duration_pct",    # 施加的控制時間 %（上限見 combat.civ_cc_extra_cap）
	"cc_received_pct",    # 受到的控制時間 %（上限同上）
	"low_hp_direct_pct",  # 自身 HP 低於門檻時直接傷害 %
	"execute_pct",        # 攻擊 HP 低於門檻的敵人時傷害 %
	"hp_flat",            # 生命（固定值，裝備）
	"atk_flat",           # 攻擊力（固定值，裝備）
	"atk_speed_pct",      # 攻速 %
	"crit_chance_add",    # 暴擊率（百分點）
	"crit_dmg_add",       # 暴擊傷害（百分點）
	"phys_pen",           # 物理穿透 %：造成物理傷害時忽略目標該比例的物理減傷率（V0.4）
	"magic_pen",          # 魔法穿透 %：造成魔法傷害時忽略目標該比例的魔法減傷率（V0.4）
	"atk_pct",            # 攻擊力 %（《氏族爭霸》國家制度）
	"dmg_pct",            # 造成的所有傷害 %（《氏族爭霸》國家制度，普攻與技能都算）
	"mobilize",           # 人民的力量：> 0 時會累積動員值召喚村民（《氏族爭霸》）
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


## 每隻棋子的修正來源（可追溯）：回傳陣列，每隻一個 [{stat, value, source, label}]
## source：civ（文明 Buff／Debuff）或 trait（羈絆）；label 為給玩家看的來源說明。
## items_per_unit（可省略）：每隻棋子身上的裝備 id 陣列，順序對應 unit_ids；裝備效果以 source = "item" 列出。
static func sources_for_lineup(unit_ids: Array, civ_id: String, use_synergy: bool, items_per_unit: Array = []) -> Array:
	var counts := Synergy.count(unit_ids)
	var actives: Array = Synergy.active(counts) if use_synergy else []
	var ctx := {"distinct_races": counts["race"].size()}
	var c := GameData.civ(civ_id) if civ_id != "" else {}
	var out: Array = []
	for id in unit_ids:
		var u := GameData.unit(str(id))
		var list: Array = []
		for group in ["buffs", "debuffs"]:
			for b in c.get(group, []):
				for e in b.get("effects", []):
					if cond_ok(e.get("cond", {}), u, ctx):
						list.append({"stat": str(e["stat"]), "value": float(e["value"]), "source": "civ",
							"label": "%s文明：%s" % [c.get("name", ""), b.get("text", "")]})
		for a in actives:
			if str(u.get(a["group"], "")) != str(a["key"]):
				continue
			var tdef: Dictionary = GameData.traits()[a["group"]][a["key"]]
			for e in a["effects"]:
				if cond_ok(e.get("cond", {}), u, ctx):
					list.append({"stat": str(e["stat"]), "value": float(e["value"]), "source": "trait",
						"label": "%s %d：%s" % [tdef.get("name", a["key"]), int(a["count"]), a.get("text", "")]})
		var idx := out.size()
		if idx < items_per_unit.size() and items_per_unit[idx] != null:
			for item_id in items_per_unit[idx]:
				var it := GameData.item(str(item_id))
				for stat in it.get("stats", {}).keys():
					list.append({"stat": str(stat), "value": float(it["stats"][stat]), "source": "item",
						"label": "裝備：%s" % it.get("name", item_id)})
		out.append(list)
	return out


## 一組裝備的基礎屬性加總（戰鬥中更換裝備時用來扣除舊值、加上新值）
static func item_mods(items: Array) -> Dictionary:
	var m := {}
	for item_id in items:
		var st: Dictionary = GameData.item(str(item_id)).get("stats", {})
		for k in st.keys():
			m[k] = float(m.get(k, 0.0)) + float(st[k])
	return m


## 把來源清單加總成修正值字典
static func sum_sources(list: Array) -> Dictionary:
	var m := empty()
	for e in list:
		var stat := str(e["stat"])
		if not m.has(stat):
			push_warning("未知的修正鍵：%s" % stat)
		m[stat] = float(m.get(stat, 0.0)) + float(e["value"])
	return m


## 計算一方棋盤上每隻棋子的修正值（由來源清單加總，確保 UI 說明與實際數值一致）。
## unit_ids：棋盤上每一隻的 id（可重複，順序對應回傳陣列）。civ_id：玩家文明（敵方傳 ""）；use_synergy：是否套用羈絆。
static func for_lineup(unit_ids: Array, civ_id: String, use_synergy: bool, items_per_unit: Array = []) -> Array:
	var out: Array = []
	for list in sources_for_lineup(unit_ids, civ_id, use_synergy, items_per_unit):
		out.append(sum_sources(list))
	return out
