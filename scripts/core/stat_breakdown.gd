class_name StatBreakdown
extends RefCounted
## 棋子屬性宮格資料（V0.3 最終版）。純計算、不依賴畫面。
## 每格只顯示「圖示＋最終數字」；顏色由「最終值 vs 目前星級的基礎值」決定：高於＝藍、低於＝紅、相等＝白。
## 升星本身已含在「目前星級基礎值」裡，所以正常升星不會讓數字變藍。
## 點擊格子才顯示 lines（來源明細），只列出實際存在的來源。
##
## 格子：{key, icon, label, value, base, text, sign(1/0/-1), lines: [{cat, label, text, sign}], extra: [String]}
## cat：base 基礎／civ 文明／trait 羈絆／item 裝備／status 暫時性戰鬥效果／cond 條件效果（不影響數字）

const CAT_NAMES := {"base": "基礎", "civ": "文明", "trait": "羈絆", "item": "裝備", "status": "戰鬥效果", "cond": "條件"}
const STATUS_NAMES := {"atk_up": "攻擊力提升", "atk_down": "攻擊力降低", "armor_up": "護甲提升", "armor_down": "破甲",
	"mr_up": "魔抗提升", "mr_down": "魔抗降低", "slow": "緩速", "as_up": "攻速提升", "dmg_up": "直接傷害提升",
	"phys_dr": "物理減傷", "mark": "被標記", "stun": "暈眩", "root": "定身", "taunt": "被嘲諷", "dot": "持續傷害", "hot": "持續治療"}

## 宮格順序：3 欄 × 4 列
const ORDER := ["atk", "armor", "mr", "as", "move", "range", "crit", "crit_dmg", "mana", "skill", "heal", "cc"]


static func _f(v: float, digits: int = 0) -> String:
	if digits == 0 or is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return ("%." + str(digits) + "f") % v


static func _signed(v: float, suffix: String = "", digits: int = 0) -> String:
	return ("+" if v >= 0.0 else "−") + _f(absf(v), digits) + suffix


static func _sign(v: float, eps: float = 0.0001) -> int:
	if v > eps:
		return 1
	if v < -eps:
		return -1
	return 0


static func _src_lines(sources: Array, stats: Array, suffix: String, filter: Callable = Callable()) -> Array:
	var out: Array = []
	for e in sources:
		if not (str(e["stat"]) in stats):
			continue
		if filter.is_valid() and not filter.call(e):
			continue
		var v := float(e["value"])
		if absf(v) < 0.0001:
			continue
		out.append({"cat": str(e["source"]), "label": str(e["label"]), "text": _signed(v, suffix), "sign": _sign(v)})
	return out


static func _status_sum(statuses: Array, kind: String) -> float:
	var t := 0.0
	for st in statuses:
		if st["kind"] == kind:
			t += float(st["value"])
	return t


static func _status_lines(statuses: Array, plus_kind: String, minus_kind: String, suffix: String) -> Array:
	var out: Array = []
	for st in statuses:
		var k := str(st["kind"])
		if k != plus_kind and k != minus_kind:
			continue
		var v := float(st["value"]) * (1.0 if k == plus_kind else -1.0)
		var left := " （剩 %.1f 秒）" % float(st["left"]) if st.has("left") else ""
		out.append({"cat": "status", "label": str(STATUS_NAMES.get(k, k)) + left, "text": _signed(v, suffix), "sign": _sign(v)})
	return out


static func _cell(key: String, icon: String, label: String, value: float, base: float, text: String, lines: Array, extra: Array = [], eps: float = 0.0001) -> Dictionary:
	return {"key": key, "icon": icon, "label": label, "value": value, "base": base, "text": text,
		"sign": _sign(value - base, eps), "lines": lines, "extra": extra}


## sources：Modifiers.sources_for_lineup 的單隻結果；statuses：戰鬥中的狀態 [{kind, value, left?}]；
## live：戰鬥中的即時值 {mana}（備戰傳空字典）
static func cells(unit_id: String, star: int, sources: Array, statuses: Array = [], live: Dictionary = {}) -> Array:
	var u := GameData.unit(unit_id)
	var base := UnitStats.base_stats(unit_id, star)
	var mods := Modifiers.sum_sources(sources)
	var fin := UnitStats.final_stats(unit_id, star, mods)
	var melee := int(u.get("range", 1)) <= 1
	var stars := "★".repeat(star)
	var out: Array = []

	# 1. 攻擊力（普攻傷害）＝（基礎攻擊＋裝備固定值）×（1＋狀態%）×（1＋普攻加成%）
	var atk_pct := _status_sum(statuses, "atk_up") - _status_sum(statuses, "atk_down")
	var atk_now := float(fin["atk"]) * maxf(0.1, 1.0 + atk_pct / 100.0)
	var basic_stats := ["basic_dmg_pct", "melee_basic_pct" if melee else "ranged_basic_pct"]
	var basic_pct := 0.0
	for e in sources:
		if str(e["stat"]) in basic_stats:
			basic_pct += float(e["value"])
	var atk_val := atk_now * maxf(0.0, 1.0 + basic_pct / 100.0)
	var lines: Array = [{"cat": "base", "label": "基礎攻擊（%s，已含星級）" % stars, "text": _f(base["atk"], 1), "sign": 0}]
	lines.append_array(_src_lines(sources, ["atk_flat"], ""))
	lines.append_array(_src_lines(sources, basic_stats, "%"))
	lines.append_array(_status_lines(statuses, "atk_up", "atk_down", "%"))
	lines.append_array(_cond_lines(sources))
	out.append(_cell("atk", "sword", "攻擊力", atk_val, float(base["atk"]), _f(atk_val), lines, [], 0.05))

	# 2、3. 物防、魔防
	for pair in [["armor", "shield", "物理防禦", "armor_flat", "armor_up", "armor_down"], ["mr", "magic_shield", "魔法防禦", "mr_flat", "mr_up", "mr_down"]]:
		var key: String = pair[0]
		var v := float(fin[key]) + _status_sum(statuses, pair[4]) - _status_sum(statuses, pair[5])
		v = maxf(0.0, v)
		var ls: Array = [{"cat": "base", "label": "基礎防禦（%s，已含星級）" % stars, "text": _f(base[key]), "sign": 0}]
		ls.append_array(_src_lines(sources, [pair[3]], ""))
		ls.append_array(_status_lines(statuses, pair[4], pair[5], ""))
		var red := UnitStats.defense_reduction(v)
		var dcfg := GameData.cfg("defense")
		out.append(_cell(key, pair[1], pair[2], v, float(base[key]), _f(v), ls,
			["目前換算減傷率：%.1f%%（%s × D ÷ (D + %s)）" % [red * 100.0, _f(float(dcfg.get("max_reduction", 0.75)) * 100.0) + "%", _f(float(dcfg.get("k", 75)))]]))

	# 4. 攻速
	var as_pct := _status_sum(statuses, "as_up") - _status_sum(statuses, "slow")
	var as_val := float(fin["atk_speed"]) * maxf(0.25, 1.0 + as_pct / 100.0)
	lines = [{"cat": "base", "label": "基礎攻速（次／秒，不隨星級成長）", "text": _f(base["atk_speed"], 2), "sign": 0}]
	lines.append_array(_src_lines(sources, ["atk_speed_pct"], "%"))
	lines.append_array(_status_lines(statuses, "as_up", "slow", "%"))
	out.append(_cell("as", "bolt", "攻擊速度", as_val, float(base["atk_speed"]), _f(as_val, 2), lines, ["單位：次／秒"], 0.005))

	# 5. 移動速度
	var mv_val := float(fin["move_speed"]) * maxf(0.3, 1.0 - _status_sum(statuses, "slow") / 100.0)
	lines = [{"cat": "base", "label": "基礎移動速度（格／秒）", "text": _f(base["move_speed"], 2), "sign": 0}]
	lines.append_array(_src_lines(sources, ["move_speed_pct"], "%"))
	for st in statuses:
		if st["kind"] == "slow":
			lines.append({"cat": "status", "label": "緩速", "text": _signed(-float(st["value"]), "%"), "sign": -1})
	out.append(_cell("move", "foot", "移動速度", mv_val, float(base["move_speed"]), _f(mv_val, 1), lines, ["單位：格／秒"], 0.005))

	# 6. 射程
	out.append(_cell("range", "aim", "攻擊射程", float(base["range"]), float(base["range"]), str(int(base["range"])),
		[{"cat": "base", "label": "射程（六角格，近戰 1、遠程 3）", "text": str(int(base["range"])), "sign": 0}]))

	# 7、8. 暴擊率、暴擊傷害
	var cc_val := float(fin["crit_chance"]) * 100.0
	lines = [{"cat": "base", "label": "基礎暴擊率（不隨星級成長）", "text": _f(base["crit_chance"] * 100.0) + "%", "sign": 0}]
	lines.append_array(_src_lines(sources, ["crit_chance_add"], "%"))
	out.append(_cell("crit", "crosshair", "暴擊率", cc_val, float(base["crit_chance"]) * 100.0, _f(cc_val) + "%", lines))
	var cd_val := float(fin["crit_mult"]) * 100.0
	lines = [{"cat": "base", "label": "基礎暴擊傷害", "text": _f(base["crit_mult"] * 100.0) + "%", "sign": 0}]
	lines.append_array(_src_lines(sources, ["crit_dmg_add"], "%"))
	out.append(_cell("crit_dmg", "swords", "暴擊傷害", cd_val, float(base["crit_mult"]) * 100.0, _f(cd_val) + "%", lines))

	# 9. 魔力（備戰顯示上限；戰鬥中顯示 目前／上限）；初始魔力加成視為正面修正
	var no_skill := str(u.get("skill", {}).get("kind", "")) == "none"
	var start := float(fin["start_mana"])
	lines = [{"cat": "base", "label": "施放技能所需魔力", "text": "—" if no_skill else _f(base["mana_max"]), "sign": 0}]
	lines.append_array(_src_lines(sources, ["start_mana"], "", Callable()).map(func(l):
		l["label"] = str(l["label"]) + "（初始魔力）"
		return l))
	var mana_text := "—" if no_skill else _f(base["mana_max"])
	if live.has("mana") and not no_skill:
		mana_text = "%d/%d" % [roundi(float(live["mana"])), roundi(float(base["mana_max"]))]
	var mana_cell := _cell("mana", "mana", "魔力", start, 0.0, mana_text, lines,
		["沒有主動技能"] if no_skill else ["初始魔力 %s；普攻 +10、受到普攻 +5" % _f(start)])
	out.append(mana_cell)

	# 10. 技能傷害（以 100% 為基準）
	var skill_stats := ["skill_dmg_pct", "skill_direct_pct"]
	var dtype := str(u.get("skill", {}).get("params", {}).get("dtype", ""))
	if dtype == "magic":
		skill_stats.append_array(["magic_dmg_pct", "magic_direct_pct"])
	var sk := 100.0
	for e in sources:
		if str(e["stat"]) in skill_stats:
			sk += float(e["value"])
	lines = [{"cat": "base", "label": "技能傷害基準", "text": "100%", "sign": 0}]
	lines.append_array(_src_lines(sources, skill_stats, "%"))
	lines.append_array(_cond_lines(sources))
	out.append(_cell("skill", "skill", "技能傷害", sk, 100.0, _f(sk) + "%", lines,
		["含技能造成的持續傷害（直接傷害類加成除外）"]))

	# 11. 治療與護盾（給出）；承受治療列在明細
	var hs := 100.0 + float(mods.get("heal_shield_pct", 0.0))
	lines = [{"cat": "base", "label": "給出的治療與護盾基準", "text": "100%", "sign": 0}]
	lines.append_array(_src_lines(sources, ["heal_shield_pct"], "%"))
	lines.append_array(_src_lines(sources, ["heal_received_pct"], "%").map(func(l):
		l["label"] = str(l["label"]) + "（自身受到的治療）"
		return l))
	out.append(_cell("heal", "heal", "治療與護盾", hs, 100.0, _f(hs) + "%", lines))

	# 12. 控制時間（施加）；受到控制列在明細
	var ccd := 100.0 + float(mods.get("cc_duration_pct", 0.0))
	lines = [{"cat": "base", "label": "施加控制時間基準", "text": "100%", "sign": 0}]
	lines.append_array(_src_lines(sources, ["cc_duration_pct"], "%"))
	lines.append_array(_src_lines(sources, ["cc_received_pct"], "%").map(func(l):
		l["label"] = str(l["label"]) + "（自身受到的控制）"
		l["sign"] = -int(l["sign"])
		return l))
	out.append(_cell("cc", "chain", "控制時間", ccd, 100.0, _f(ccd) + "%", lines, ["文明修正最多 ±0.2 秒"]))
	return out


## 條件式增傷（低血量、斬殺）：只在條件成立時生效，列在明細但不改變格子數字
static func _cond_lines(sources: Array) -> Array:
	var out: Array = []
	for e in sources:
		var k := str(e["stat"])
		if k == "low_hp_direct_pct" or k == "execute_pct":
			var cond := "自身生命 < 50% 時" if k == "low_hp_direct_pct" else "攻擊生命 < 35% 的敵人時"
			out.append({"cat": "cond", "label": "%s（%s）" % [e["label"], cond], "text": _signed(float(e["value"]), "%"), "sign": _sign(float(e["value"]))})
	return out


## 生命（不在宮格內）：{max, base}
static func hp_info(unit_id: String, star: int, sources: Array) -> Dictionary:
	var base := UnitStats.base_stats(unit_id, star)
	var fin := UnitStats.final_stats(unit_id, star, Modifiers.sum_sources(sources))
	var lines: Array = [{"cat": "base", "label": "基礎生命（已含星級）", "text": _f(base["hp"]), "sign": 0}]
	lines.append_array(_src_lines(sources, ["hp_flat"], ""))
	lines.append_array(_src_lines(sources, ["hp_pct"], "%"))
	return {"max": float(fin["hp"]), "base": float(base["hp"]), "sign": _sign(float(fin["hp"]) - float(base["hp"])), "lines": lines}


static func cell_by_key(list: Array, key: String) -> Dictionary:
	for c in list:
		if c["key"] == key:
			return c
	return {}
