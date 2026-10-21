class_name Equipment
extends RefCounted
## 裝備資料查詢與三選一抽取（V0.3）。


static func pool(faction: String, tier: String) -> Array:
	var out: Array = []
	for it in GameData.items():
		if str(it["faction"]) == faction and str(it["tier"]) == tier:
			out.append(str(it["id"]))
	return out


## 從該勢力、該階級的掉落池抽出不重複的 n 件；不足時從同階級其他勢力補（不會無限迴圈）
static func roll_choices(rng: SeededRng, faction: String, tier: String) -> Array:
	var n := int(GameData.equipment().get("choices_per_reward", 3))
	var candidates := pool(faction, tier)
	var out: Array = []
	while out.size() < n and not candidates.is_empty():
		var i := rng.randi_range(0, candidates.size() - 1)
		out.append(candidates[i])
		candidates.remove_at(i)
	if out.size() < n:
		for it in GameData.items():
			if out.size() >= n:
				break
			if str(it["tier"]) == tier and not out.has(it["id"]):
				out.append(str(it["id"]))
	return out


static func type_info(item_id: String) -> Dictionary:
	var it := GameData.item(item_id)
	return GameData.equipment().get("types", {}).get(str(it.get("type", "")), {})


static func tier_info(item_id: String) -> Dictionary:
	var it := GameData.item(item_id)
	return GameData.equipment().get("tiers", {}).get(str(it.get("tier", "")), {})


const STAT_TEXT := {
	"atk_flat": "攻擊 +%s", "hp_flat": "生命 +%s", "armor_flat": "物防 +%s", "mr_flat": "魔防 +%s",
	"atk_speed_pct": "攻速 +%s%%", "crit_chance_add": "暴擊率 +%s%%", "crit_dmg_add": "暴擊傷害 +%s%%",
	"skill_dmg_pct": "技能傷害 +%s%%", "heal_shield_pct": "治療與護盾 +%s%%", "start_mana": "初始魔力 +%s",
}


## 給玩家看的屬性摘要
static func stat_lines(item_id: String) -> Array:
	var out: Array = []
	var stats: Dictionary = GameData.item(item_id).get("stats", {})
	for k in stats.keys():
		var v := float(stats[k])
		var shown := str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
		out.append(str(STAT_TEXT.get(k, k + " %s")) % shown)
	return out
