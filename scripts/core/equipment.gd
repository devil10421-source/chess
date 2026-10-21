class_name Equipment
extends RefCounted
## 裝備資料查詢與三選一抽取（V0.4：沒有品質分級；固定屬性＋唯一特性）。
## V0.5：基礎組件（component）、合成裝備（craft）、特殊首領裝備（special）。三選一只從特殊首領裝備抽。
## drop（normal／advanced）只決定各回合從哪個掉落池抽，不在介面顯示。


static func pool(faction: String, drop: String) -> Array:
	var out: Array = []
	for it in GameData.items():
		if str(it.get("source", "special")) == "special" and str(it.get("faction", "")) == faction and str(it.get("drop", "normal")) == drop:
			out.append(str(it["id"]))
	return out


## 從該勢力、該掉落池抽出不重複的 n 件；不足時從同掉落池其他勢力補（不會無限迴圈）
static func roll_choices(rng: SeededRng, faction: String, drop: String) -> Array:
	var n := int(GameData.equipment().get("choices_per_reward", 3))
	var candidates := pool(faction, drop)
	var out: Array = []
	while out.size() < n and not candidates.is_empty():
		var i := rng.randi_range(0, candidates.size() - 1)
		out.append(candidates[i])
		candidates.remove_at(i)
	if out.size() < n:
		for it in GameData.items():
			if out.size() >= n:
				break
			if str(it.get("source", "special")) == "special" and str(it.get("drop", "normal")) == drop and not out.has(it["id"]):
				out.append(str(it["id"]))
	return out


static func type_info(item_id: String) -> Dictionary:
	var it := GameData.item(item_id)
	return GameData.equipment().get("types", {}).get(str(it.get("type", "")), {})


## 這個組件可以合成哪些裝備：[{with, result}]
static func recipes_for(component_id: String) -> Array:
	var out: Array = []
	for r in GameData.equipment().get("recipes", []):
		if r["a"] == component_id:
			out.append({"with": str(r["b"]), "result": str(r["result"])})
		elif r["b"] == component_id:
			out.append({"with": str(r["a"]), "result": str(r["result"])})
	return out


## 來源說明（組件／合成裝備／特殊首領裝備）
static func source_name(item_id: String) -> String:
	match str(GameData.item(item_id).get("source", "special")):
		"component":
			return "基礎組件"
		"craft":
			return "合成裝備"
	return faction_name(item_id)


static func faction_name(item_id: String) -> String:
	return str(GameData.equipment().get("factions", {}).get(str(GameData.item(item_id).get("faction", "")), {}).get("name", ""))


## 唯一特性 {id, name, desc}
static func unique_of(item_id: String) -> Dictionary:
	return GameData.item(item_id).get("unique", {})


## 固定格式的唯一特性文字：「唯一特性・名稱：一句話描述」
static func unique_line(item_id: String) -> String:
	var u := unique_of(item_id)
	if u.is_empty():
		return ""
	return "唯一特性・%s：%s" % [u.get("name", ""), u.get("desc", "")]


const STAT_TEXT := {
	"atk_flat": "攻擊 +%s", "hp_flat": "生命 +%s", "armor_flat": "物防 +%s", "mr_flat": "魔防 +%s",
	"atk_speed_pct": "攻速 +%s%%", "crit_chance_add": "暴擊率 +%s%%", "crit_dmg_add": "暴擊傷害 +%s%%",
	"skill_dmg_pct": "技能傷害 +%s%%", "heal_shield_pct": "治療與護盾 +%s%%", "start_mana": "初始魔力 +%s",
	"phys_pen": "物理穿透 +%s%%", "magic_pen": "魔法穿透 +%s%%",
}


## 給玩家看的基礎屬性摘要（每項一筆）
static func stat_lines(item_id: String) -> Array:
	var out: Array = []
	var stats: Dictionary = GameData.item(item_id).get("stats", {})
	for k in stats.keys():
		var v := float(stats[k])
		var shown := str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
		out.append(str(STAT_TEXT.get(k, k + " %s")) % shown)
	return out


## 一行的基礎屬性文字
static func stat_text(item_id: String) -> String:
	return "、".join(stat_lines(item_id))
