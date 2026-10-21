class_name ClashGovernment
extends RefCounted
## 《氏族爭霸》國家制度與深化政策。第 8 回合選制度、第 16 回合選該制度的兩條政策之一（clash_config.json → government）。
## 這裡只放規則計算（純函式＋對 ClashPlayer 狀態的更新），選擇動作由 ClashMatch.submit() 統一受理。


static func cfg() -> Dictionary:
	return GameData.clash_cfg("government")


static func systems() -> Array:
	return ["democracy", "empire", "commune"]


static func system_cfg(sys: String) -> Dictionary:
	return cfg().get("systems", {}).get(sys, {})


static func policy_cfg(pol: String) -> Dictionary:
	return cfg().get("policies", {}).get(pol, {})


static func policies_for(sys: String) -> Array:
	return system_cfg(sys).get("policies", [])


static func system_round() -> int:
	return int(GameData.clash_cfg("rounds").get("government_round", 8))


static func policy_round() -> int:
	return int(GameData.clash_cfg("rounds").get("policy_round", 16))


## 這名玩家現在是否需要選制度／政策（""＝不需要）
static func pending_choice(p: ClashPlayer, round_no: int) -> String:
	if not p.alive:
		return ""
	if p.government == "" and round_no >= system_round():
		return "system"
	if p.government != "" and p.policy == "" and round_no >= policy_round():
		return "policy"
	return ""


static func choose_system(p: ClashPlayer, sys: String, round_no: int) -> String:
	if pending_choice(p, round_no) != "system":
		return "現在不能選擇國家制度"
	if not systems().has(sys):
		return "沒有這個制度"
	p.government = sys
	return ""


static func choose_policy(p: ClashPlayer, pol: String, round_no: int) -> String:
	if pending_choice(p, round_no) != "policy":
		return "現在不能選擇深化政策"
	if not policies_for(p.government).has(pol):
		return "只能選擇所屬制度的政策"
	p.policy = pol
	if pol == "five_year_plan":
		p.plan_round = round_no
		p.plan_cycles = 0
	return ""


# ---------- 經濟效果 ----------
## 回合開始：選擇式民主每回合第一次刷新免費（不累積）；出售加成寫入 RunState.perks
static func apply_round_perks(p: ClashPlayer) -> void:
	p.run.perks = {}
	if p.policy == "selective_democracy":
		var pc := policy_cfg(p.policy)
		p.run.free_rerolls = maxi(p.run.free_rerolls, int(pc.get("free_rerolls_per_round", 1)))
		p.run.perks["sell_bonus_2star"] = int(pc.get("sell_bonus_2star", 1))


## 每回合收入的增減（制度基礎＋五回合計畫）
static func income_adjust(p: ClashPlayer) -> int:
	var v := 0
	if p.government == "democracy":
		v += int(system_cfg("democracy").get("income_bonus", 1))
	if p.policy == "five_year_plan":
		var pc := policy_cfg(p.policy)
		v += p.plan_cycles * int(pc.get("income_per_level", 1)) - int(pc.get("income_penalty", 1))
	return v


static func interest_max(p: ClashPlayer) -> int:
	var m := Economy.interest_max()
	if p.policy == "free_market":
		m += int(policy_cfg("free_market").get("interest_max_bonus", 2))
	return m


static func interest(p: ClashPlayer, gold: int) -> int:
	return clampi(int(floor(float(maxi(gold, 0)) / float(Economy.interest_step()))), 0, interest_max(p))


static func pvp_win_gold(p: ClashPlayer) -> int:
	if p.policy == "free_market":
		return int(policy_cfg("free_market").get("pvp_win_gold", 0))
	return int(GameData.clash_cfg("pvp").get("win_gold", 1))


## 回合結束：五回合計畫週期結算。回傳說明文字（沒有事件為 ""）
static func on_round_end(p: ClashPlayer, round_no: int) -> String:
	if p.policy != "five_year_plan" or p.plan_round <= 0:
		return ""
	var pc := policy_cfg(p.policy)
	var done := round_no - p.plan_round + 1
	var cycle := int(pc.get("cycle_rounds", 5))
	if done > 0 and done % cycle == 0:
		p.plan_cycles += 1
		p.run.gold += int(pc.get("cycle_gold", 5))
		if p.run.level() < Economy.max_level():
			p.run.xp += int(pc.get("cycle_xp", 4))
		return "五回合計畫完成第 %d 期：+%d 金、+%d 經驗，發展等級 %d" % [p.plan_cycles, int(pc.get("cycle_gold", 5)), int(pc.get("cycle_xp", 4)), p.plan_cycles]
	return ""


# ---------- 戰鬥效果 ----------
## 開戰時更新：帝國永不退讓的忠誠層數、朕即是國家的核心（未指定或核心不在場上時自動選最強者）
static func on_battle_start(p: ClashPlayer, lineup: Array) -> void:
	var ids: Array = []
	for u in lineup:
		ids.append(str(u["id"]))
	if p.policy == "never_retreat":
		var pc := policy_cfg(p.policy)
		var ratio := keep_ratio(p.last_lineup_ids, ids)
		if p.last_lineup_ids.is_empty():
			pass
		elif ratio >= float(pc.get("keep_ratio_stack", 0.75)) - 0.0001:
			p.loyalty = mini(int(pc.get("max_stacks", 5)), p.loyalty + 1)
		elif ratio < float(pc.get("keep_ratio_reset", 0.5)) - 0.0001:
			p.loyalty = 0
	if p.policy == "i_am_the_state":
		var on_board := false
		for u in lineup:
			if int(u["uid"]) == p.core_uid:
				on_board = true
		if not on_board:
			p.core_uid = strongest_uid(lineup)
	p.last_lineup_ids = ids


## 陣容保留比例：上一場的棋子（依 id，可重複）有多少比例仍在這一場
static func keep_ratio(prev: Array, cur: Array) -> float:
	if prev.is_empty():
		return 1.0
	var left := cur.duplicate()
	var kept := 0
	for id in prev:
		var i := left.find(id)
		if i >= 0:
			kept += 1
			left.remove_at(i)
	return float(kept) / float(prev.size())


static func strongest_uid(lineup: Array) -> int:
	var best := -1
	var best_p := -1.0
	for u in lineup:
		var pw: float = float(GameData.unit_cost(str(u["id"]))) * float([1.0, 3.0, 9.0][clampi(int(u["star"]), 1, 3) - 1])
		if pw > best_p or (is_equal_approx(pw, best_p) and int(u["uid"]) < best):
			best_p = pw
			best = int(u["uid"])
	return best


## 每隻上場棋子的制度／政策修正來源（與羈絆、裝備同格式，UI 明細與戰鬥都用這份）
static func sources_for(p: ClashPlayer, lineup: Array) -> Array:
	var out: Array = []
	for u in lineup:
		var list: Array = []
		var star := int(u["star"])
		var is_core := p.policy == "i_am_the_state" and int(u["uid"]) == p.core_uid
		match p.government:
			"empire":
				var sc := system_cfg("empire")
				var elite := star >= int(sc.get("elite_min_star", 2))
				if elite and (p.policy != "i_am_the_state" or is_core):
					list.append(_src("hp_pct", float(sc.get("elite_hp_pct", 8)), "萬世帝國：精銳"))
					list.append(_src("atk_pct", float(sc.get("elite_atk_pct", 8)), "萬世帝國：精銳"))
			"commune":
				list.append(_src("hp_pct", float(system_cfg("commune").get("all_hp_pct", 5)), "偉大公社：集體"))
		match p.policy:
			"i_am_the_state":
				if is_core:
					var pc := policy_cfg(p.policy)
					list.append(_src("hp_pct", float(pc.get("core_hp_pct", 40)), "朕即是國家：核心"))
					list.append(_src("atk_pct", float(pc.get("core_atk_pct", 35)), "朕即是國家：核心"))
					list.append(_src("start_mana", float(pc.get("core_start_mana", 20)), "朕即是國家：核心"))
			"never_retreat":
				if p.loyalty > 0:
					var pc := policy_cfg(p.policy)
					list.append(_src("hp_pct", float(pc.get("hp_pct_per_stack", 4)) * p.loyalty, "帝國永不退讓：忠誠 %d" % p.loyalty))
					list.append(_src("atk_pct", float(pc.get("atk_pct_per_stack", 4)) * p.loyalty, "帝國永不退讓：忠誠 %d" % p.loyalty))
			"people_power":
				list.append(_src("mobilize", 1.0, "人民的力量：動員村民"))
			"free_market":
				list.append(_src("dmg_pct", float(policy_cfg("free_market").get("damage_pct", -5)), "自由市場：戰鬥收益較弱"))
		out.append(list)
	return out


static func _src(stat: String, value: float, label: String) -> Dictionary:
	return {"stat": stat, "value": value, "source": "gov", "label": label}


## 給玩家看的一行說明
static func summary(p: ClashPlayer) -> String:
	if p.government == "":
		return "尚未選擇國家制度（第 %d 回合）" % system_round()
	var s := "%s：%s" % [p.government_name(), system_cfg(p.government).get("base_text", "")]
	if p.policy != "":
		s += "\n%s：%s" % [p.policy_name(), policy_cfg(p.policy).get("text", "")]
		match p.policy:
			"never_retreat":
				s += "（目前忠誠 %d 層）" % p.loyalty
			"five_year_plan":
				s += "（發展等級 %d）" % p.plan_cycles
	return s
