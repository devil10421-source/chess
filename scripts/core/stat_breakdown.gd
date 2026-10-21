class_name StatBreakdown
extends RefCounted
## 棋子屬性的「最終數值 + 來源明細」，給資訊面板使用。純計算、不依賴畫面。
## 每列：{key, label, value(數值), text(顯示字串), extra(附註), lines: [{label, text, sign}]}
## sign：1 = 增加（藍字）、-1 = 減少（紅字）、0 = 基礎或無修正（一般文字）。

const PCT_ROWS := {
	"basic": {"label": "普攻傷害", "stats": ["basic_dmg_pct", "melee_basic_pct", "ranged_basic_pct"]},
	"skill": {"label": "技能傷害", "stats": ["skill_dmg_pct", "skill_direct_pct", "magic_dmg_pct", "magic_direct_pct"]},
	"heal": {"label": "給出的治療與護盾", "stats": ["heal_shield_pct"]},
	"heal_in": {"label": "接受治療量", "stats": ["heal_received_pct"]},
	"cc": {"label": "施加控制時間", "stats": ["cc_duration_pct"]},
	"cc_in": {"label": "受到控制時間", "stats": ["cc_received_pct"]},
	"special": {"label": "條件增傷", "stats": ["low_hp_direct_pct", "execute_pct"]},
}

const STAT_NAMES := {
	"basic_dmg_pct": "普攻", "melee_basic_pct": "近戰普攻", "ranged_basic_pct": "遠程普攻",
	"skill_dmg_pct": "技能（含持續傷害）", "skill_direct_pct": "技能直接傷害", "magic_dmg_pct": "法術傷害",
	"magic_direct_pct": "法術直接傷害", "low_hp_direct_pct": "自身 HP<50% 直接傷害", "execute_pct": "對 HP<35% 敵人",
}

const STATUS_NAMES := {"atk_up": "攻擊力提升", "atk_down": "攻擊力降低", "armor_up": "護甲提升", "armor_down": "破甲",
	"mr_up": "魔抗提升", "mr_down": "魔抗降低", "slow": "緩速", "as_up": "攻速提升", "dmg_up": "直接傷害提升",
	"phys_dr": "物理減傷", "mark": "被標記", "stun": "暈眩", "root": "定身", "taunt": "被嘲諷", "dot": "持續傷害", "hot": "持續治療"}


static func _f(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.1f" % v


static func _signed(v: float, suffix: String = "") -> String:
	return ("+" if v >= 0.0 else "") + _f(v) + suffix


static func _sign(v: float) -> int:
	if v > 0.0001:
		return 1
	if v < -0.0001:
		return -1
	return 0


## sources：Modifiers.sources_for_lineup 的單隻結果；statuses：戰鬥中的狀態 [{kind, value}]（備戰傳空陣列）
static func build(unit_id: String, star: int, sources: Array, statuses: Array = []) -> Array:
	var u := GameData.unit(unit_id)
	var cost := int(u.get("cost", 1))
	var tier: Dictionary = GameData.cfg("tiers").get(str(cost), {})
	var cls: Dictionary = GameData.cfg("classes").get(str(u.get("class", "")), {})
	var base1 := UnitStats.base_stats(unit_id, 1)
	var base := UnitStats.base_stats(unit_id, star)
	var mods := Modifiers.sum_sources(sources)
	var fin := UnitStats.final_stats(unit_id, star, mods)
	var rows: Array = []
	var origin := "%s %d 費 × %s" % [GameData.tier_name(cost), cost, cls.get("name", "")] if not u.has("stats") else "特殊單位固定值"

	# 生命
	var hp_lines: Array = [{"label": "基礎生命（%s）" % origin, "text": _f(base1["hp"]), "sign": 0}]
	if star > 1:
		hp_lines.append({"label": "星級 %s ×%s" % ["★".repeat(star), _f(base["hp"] / maxf(1.0, base1["hp"]))], "text": _signed(base["hp"] - base1["hp"]), "sign": 1})
	for e in sources:
		if e["stat"] == "hp_pct":
			hp_lines.append({"label": e["label"], "text": "%s（%s）" % [_signed(e["value"], "%"), _signed(base["hp"] * e["value"] / 100.0)], "sign": _sign(e["value"])})
	rows.append({"key": "hp", "label": "生命", "value": fin["hp"], "text": _f(fin["hp"]), "net": fin["hp"] - base["hp"], "lines": hp_lines})

	# 攻擊力
	var atk_lines: Array = [{"label": "基礎攻擊（%s）" % origin, "text": _f(base1["atk"]), "sign": 0}]
	if star > 1:
		atk_lines.append({"label": "星級 %s ×%s" % ["★".repeat(star), _f(snappedf(base["atk"] / maxf(0.1, base1["atk"]), 0.01))], "text": _signed(base["atk"] - base1["atk"]), "sign": 1})
	var atk_pct := 0.0
	for st in statuses:
		if st["kind"] in ["atk_up", "atk_down"]:
			var v := float(st["value"]) * (1.0 if st["kind"] == "atk_up" else -1.0)
			atk_pct += v
			atk_lines.append({"label": "狀態：" + STATUS_NAMES[st["kind"]], "text": _signed(v, "%"), "sign": _sign(v)})
	var atk_now: float = base["atk"] * maxf(0.1, 1.0 + atk_pct / 100.0)
	rows.append({"key": "atk", "label": "攻擊力", "value": atk_now, "text": _f(snappedf(atk_now, 0.1)), "net": atk_pct, "lines": atk_lines})

	# 普攻傷害（攻擊力 × 普攻加成）
	var melee := int(u.get("range", 1)) <= 1
	var b_lines: Array = [{"label": "攻擊力", "text": _f(snappedf(atk_now, 0.1)), "sign": 0}]
	var b_pct := 0.0
	for e in sources:
		var st_key := str(e["stat"])
		if st_key == "basic_dmg_pct" or (st_key == "melee_basic_pct" and melee) or (st_key == "ranged_basic_pct" and not melee):
			b_pct += float(e["value"])
			b_lines.append({"label": e["label"], "text": _signed(e["value"], "%"), "sign": _sign(e["value"])})
	if b_lines.size() == 1:
		b_lines.append({"label": "文明加成／羈絆加成／負面修正", "text": "0%", "sign": 0})
	var basic_dmg: float = atk_now * maxf(0.0, 1.0 + b_pct / 100.0)
	rows.append({"key": "basic", "label": "普攻傷害", "value": basic_dmg, "text": "%s（%s）" % [_f(snappedf(basic_dmg, 0.1)), _signed(b_pct, "%")],
		"net": b_pct, "extra": "暴擊率 %d%%、暴擊傷害 %d%%" % [roundi(base["crit_chance"] * 100.0), roundi(base["crit_mult"] * 100.0)], "lines": b_lines})

	# 護甲、魔抗
	for pair in [["armor", "護甲（物防）", "armor_flat", "armor_up", "armor_down", "armor_add"], ["mr", "魔抗（魔防）", "mr_flat", "mr_up", "mr_down", "mr_add"]]:
		var key: String = pair[0]
		var lines: Array = [{"label": "基礎（%s）" % origin, "text": _f(base1[key]), "sign": 0}]
		if star > 1:
			lines.append({"label": "星級 %s" % "★".repeat(star), "text": _signed(base[key] - base1[key]), "sign": 1})
		var total := float(fin[key])
		for e in sources:
			if e["stat"] == pair[2]:
				lines.append({"label": e["label"], "text": _signed(e["value"]), "sign": _sign(e["value"])})
		for st in statuses:
			if st["kind"] == pair[3] or st["kind"] == pair[4]:
				var v := float(st["value"]) * (1.0 if st["kind"] == pair[3] else -1.0)
				total += v
				lines.append({"label": "狀態：" + STATUS_NAMES[st["kind"]], "text": _signed(v), "sign": _sign(v)})
		var eff := maxf(0.0, total)
		var red := UnitStats.defense_reduction(eff)
		lines.append({"label": "減傷率 = %s × D ÷ (D + %s)" % [_f(GameData.cfg("defense").get("max_reduction", 0.75) * 100.0) + "%", _f(GameData.cfg("defense").get("k", 75))], "text": "%.1f%%" % (red * 100.0), "sign": 0})
		rows.append({"key": key, "label": pair[1], "value": eff, "text": "%s（減傷 %.1f%%）" % [_f(eff), red * 100.0], "net": eff - float(base[key]), "lines": lines})

	# 攻速
	var as_lines: Array = [{"label": "基礎攻速（不隨星級成長）", "text": "%.2f" % base["atk_speed"], "sign": 0}]
	var as_pct := 0.0
	for st in statuses:
		if st["kind"] == "slow" or st["kind"] == "as_up":
			var v := float(st["value"]) * (-1.0 if st["kind"] == "slow" else 1.0)
			as_pct += v
			as_lines.append({"label": "狀態：" + STATUS_NAMES[st["kind"]], "text": _signed(v, "%"), "sign": _sign(v)})
	var as_now: float = base["atk_speed"] * maxf(0.25, 1.0 + as_pct / 100.0)
	rows.append({"key": "as", "label": "攻速（次／秒）", "value": as_now, "text": "%.2f" % as_now, "net": as_pct, "lines": as_lines})

	# 射程、移速
	rows.append({"key": "range", "label": "射程", "value": base["range"], "text": "%d 格" % int(base["range"]),
		"lines": [{"label": "近戰 1 格、遠程 3 格（不隨星級成長）", "text": str(int(base["range"])), "sign": 0}]})
	var mv_lines: Array = [{"label": "基礎移動速度", "text": "%s 格／秒" % _f(base["move_speed"]), "sign": 0}]
	for e in sources:
		if e["stat"] == "move_speed_pct":
			mv_lines.append({"label": e["label"], "text": _signed(e["value"], "%"), "sign": _sign(e["value"])})
	rows.append({"key": "move", "label": "移動速度", "value": fin["move_speed"], "text": "%.2f 格／秒" % fin["move_speed"], "net": fin["move_speed"] - base["move_speed"], "lines": mv_lines})

	# 魔力
	var mana_lines: Array = [{"label": "技能所需魔力", "text": _f(base["mana_max"]), "sign": 0}]
	for e in sources:
		if e["stat"] == "start_mana":
			mana_lines.append({"label": e["label"] + "（初始魔力）", "text": _signed(e["value"]), "sign": _sign(e["value"])})
	var no_skill := str(u.get("skill", {}).get("kind", "")) == "none"
	rows.append({"key": "mana", "label": "魔力", "value": base["mana_max"],
		"net": fin["start_mana"], "text": "無主動技能" if no_skill else "初始 %s／上限 %s" % [_f(fin["start_mana"]), _f(base["mana_max"])],
		"lines": [{"label": "這個單位沒有主動技能", "text": "—", "sign": 0}] if no_skill else mana_lines})

	# 其他百分比修正（只在有來源時顯示）
	for key in ["skill", "heal", "heal_in", "cc", "cc_in", "special"]:
		var def: Dictionary = PCT_ROWS[key]
		var lines: Array = []
		var total := 0.0
		for e in sources:
			if str(e["stat"]) in def["stats"]:
				total += float(e["value"])
				var nm := str(STAT_NAMES.get(e["stat"], ""))
				lines.append({"label": e["label"] + ("（%s）" % nm if nm != "" else ""), "text": _signed(e["value"], "%"), "sign": _sign(e["value"])})
		if not lines.is_empty():
			rows.append({"key": key, "label": def["label"], "value": total, "text": _signed(total, "%"), "net": total, "lines": lines})
	return rows
