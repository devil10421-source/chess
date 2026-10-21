class_name UnitStats
extends RefCounted
## 由資料計算棋子屬性：稀有度基礎值 × 職業修正 × 星級倍率（全部來自 game_config.json）。

const BUDGET_KEYS := ["dmg", "dmg2", "heal", "shield", "hot", "dot"]


static func _star_value(key: String, star: int) -> float:
	var arr: Array = GameData.cfg("star").get(key, [1, 1, 1])
	return float(arr[clampi(star, 1, arr.size()) - 1])


## 未套用文明／羈絆的屬性
static func base_stats(unit_id: String, star: int) -> Dictionary:
	var u := GameData.unit(unit_id)
	var tier: Dictionary = GameData.cfg("tiers").get(str(int(u.get("cost", 1))), {})
	var cls: Dictionary = GameData.cfg("classes").get(str(u.get("class", "")), {})
	var combat := GameData.cfg("combat")
	var phase_hp := 1.0
	var phase_atk := 1.0
	if u.has("phase") and not u.has("stats"):
		# 異界變體：沿用基礎棋子的稀有度與職業數值，再乘階段倍率（只乘一次，關卡本身不另外灌數值）
		var ph := GameData.phase(str(u["phase"]))
		phase_hp = float(ph.get("hp_mult", 1.0))
		phase_atk = float(ph.get("atk_mult", 1.0))
	if u.has("stats"):
		# 特殊單位：直接使用資料中指定的屬性
		var fixed: Dictionary = u["stats"]
		tier = {"hp": fixed.get("hp", 1), "atk": fixed.get("atk", 1), "armor": fixed.get("armor", 0), "mr": fixed.get("mr", 0),
			"atk_speed": fixed.get("atk_speed", 0.8)}
		cls = {}
	var hp := roundf(float(tier.get("hp", 100)) * float(cls.get("hp", 1.0))) * _star_value("hp_mult", star)
	var atk := float(tier.get("atk", 10)) * float(cls.get("atk", 1.0)) * _star_value("atk_mult", star)
	var armor := roundf(float(tier.get("armor", 0)) * float(cls.get("armor", 1.0))) + _star_value("armor_add", star)
	var mr := roundf(float(tier.get("mr", 0)) * float(cls.get("mr", 1.0))) + _star_value("mr_add", star)
	return {
		"hp": float(roundi(hp * phase_hp)),
		"atk": snappedf(atk * phase_atk, 0.1),
		"armor": armor,
		"mr": mr,
		"atk_speed": float(tier.get("atk_speed", 0.8)) * float(cls.get("atk_speed", 1.0)),
		"range": int(u.get("range", 1)),
		"move_speed": float(u.get("move_speed", combat.get("move_speed", 2.0))),
		"mana_max": float(u.get("mana_max", combat.get("mana_max", 60))),
		"crit_chance": float(u.get("crit_chance", combat.get("crit_chance", 0.05))),
		"crit_mult": float(u.get("crit_mult", combat.get("crit_mult", 1.5))),
	}


## 套用 Modifiers 後的戰鬥屬性。固定值（裝備）先加，再乘百分比。
static func final_stats(unit_id: String, star: int, mods: Dictionary) -> Dictionary:
	var s := base_stats(unit_id, star)
	s["hp"] = float(maxi(1, roundi((s["hp"] + float(mods.get("hp_flat", 0.0))) * (1.0 + float(mods.get("hp_pct", 0.0)) / 100.0))))
	s["atk"] = s["atk"] + float(mods.get("atk_flat", 0.0))
	s["atk_speed"] = s["atk_speed"] * maxf(0.25, 1.0 + float(mods.get("atk_speed_pct", 0.0)) / 100.0)
	s["crit_chance"] = clampf(s["crit_chance"] + float(mods.get("crit_chance_add", 0.0)) / 100.0, 0.0, 1.0)
	s["crit_mult"] = s["crit_mult"] + float(mods.get("crit_dmg_add", 0.0)) / 100.0
	s["armor"] = s["armor"] + float(mods.get("armor_flat", 0.0))
	s["mr"] = s["mr"] + float(mods.get("mr_flat", 0.0))
	s["start_mana"] = float(mods.get("start_mana", 0.0))
	s["move_speed"] = s["move_speed"] * maxf(0.2, 1.0 + float(mods.get("move_speed_pct", 0.0)) / 100.0)
	return s


static func skill(unit_id: String) -> Dictionary:
	return GameData.unit(unit_id).get("skill", {})


static func skill_param(unit_id: String, key: String, default_value: Variant = 0.0) -> Variant:
	return skill(unit_id).get("params", {}).get(key, default_value)


## 技能固定量（傷害、治療、護盾、持續量）＝ 稀有度預算 × 參數 × 星級技能倍率
static func skill_amount(unit_id: String, star: int, key: String) -> float:
	var mult := float(skill_param(unit_id, key, 0.0))
	if mult == 0.0:
		return 0.0
	var cost := GameData.unit_cost(unit_id)
	var budget := float(GameData.cfg("tiers").get(str(cost), {}).get("skill_budget", 24))
	return roundf(budget * mult * _star_value("skill_mult", star))


## 控制時間：1×/1.1×/1.2×，且 2 星最多 +0.2 秒、3 星最多 +0.4 秒
static func cc_duration(base: float, star: int) -> float:
	var scaled := base * _star_value("cc_mult", star)
	return minf(scaled, base + _star_value("cc_max_extra", star))


## 持續治療的時間：最多微幅 +10%/+20%（總量不因時間變長而再放大）
static func hot_duration(base: float, star: int) -> float:
	return base * _star_value("hot_duration_mult", star)


static func _fmt(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.1f" % v


## 依星級把技能說明中的 {參數} 換成實際數值
static func skill_text(unit_id: String, star: int) -> String:
	var sk := skill(unit_id)
	var text := str(sk.get("desc", ""))
	var params: Dictionary = sk.get("params", {})
	for key in params.keys():
		var v: Variant = params[key]
		var shown := ""
		if key in BUDGET_KEYS:
			shown = _fmt(skill_amount(unit_id, star, key))
		elif key == "cc":
			shown = _fmt(cc_duration(float(v), star))
		elif key == "dur" and sk.get("kind", "") == "rejuvenate":
			shown = _fmt(hot_duration(float(v), star))
		elif typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			shown = _fmt(float(v))
		else:
			shown = str(v)
		text = text.replace("{" + str(key) + "}", shown)
	return text


## 防禦減傷率（物防、魔防共用）：max_reduction × D / (D + k)，D 最低為 0。
## 參數在 game_config.json → defense；只在這裡計算，戰鬥與 UI 都呼叫這個函式。
static func defense_reduction(defense: float) -> float:
	var d := maxf(0.0, defense)
	var cfg := GameData.cfg("defense")
	var cap := float(cfg.get("max_reduction", 0.75))
	var k := float(cfg.get("k", 75.0))
	if d <= 0.0 or k + d <= 0.0:
		return 0.0
	return cap * d / (d + k)


static func sell_value(unit_id: String, star: int) -> int:
	return Economy.sell_value(GameData.unit_cost(unit_id), star)
