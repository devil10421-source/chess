extends RefCounted
## V0.4 策略模擬用的自動玩家（只在測試／模擬使用，不會打包進遊戲）。
## 三種策略：
##   level    ＝優先升文明等級（早升 Lv.7～10，不刻意刷新）
##   midcarry ＝優先把中費（3 費）主力升到二星：一般升級節奏，到 Lv.6～7 後用多餘金幣刷新找 3 費
##   lowroll  ＝優先追求低費三星：前中期停在低等級，把金幣拿去刷新 1～2 費，之後才升級
## 同時記錄經濟與抽卡指標（stats），給 strategy_sim.gd 彙整。

const LEVEL_PLAN := {
	"level":    [1, 2, 3, 3, 4, 5, 5, 6, 6, 7, 7, 7, 8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10],
	"midcarry": [1, 2, 2, 3, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 7, 7, 8, 8, 8, 8, 9, 9, 9, 9],
	"lowroll":  [1, 2, 2, 3, 3, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 7, 7, 8, 8, 8, 9, 9, 9, 9],
}


static func new_stats() -> Dictionary:
	return {"income": 0, "spent_xp": 0, "spent_reroll": 0, "spent_units": 0, "sold": 0, "rerolls": 0,
		"level_round": {}, "first_four_round": -1, "own4_star2_round": -1, "four_star3": false,
		"low_three_stars": 0, "low_three_star_round": -1, "items_equipped": 0}


static func power(id: String, star: int) -> float:
	var mult := [1.0, 3.2, 9.0]
	return float(GameData.unit_cost(id)) * mult[clampi(star, 1, 3) - 1]


static func own_four(civ_id: String) -> String:
	for id in Shop.pool_for(civ_id, 4):
		if not GameData.is_neutral(id):
			return id
	return ""


## 一回合的備戰（strategy 見上）
static func play_prep(run: RunState, strategy: String, st: Dictionary) -> void:
	if run.has_pending_reward():
		run.claim_reward(0)
	run.begin_round()
	var plan: Array = LEVEL_PLAN.get(strategy, LEVEL_PLAN["level"])
	var target: int = plan[clampi(run.round_no - 1, 0, plan.size() - 1)]
	var rd := run.round_no
	# 利息門檻：前期保留 10、中期 20～30（滿利息 +3）
	var keep := 0 if rd <= 3 else (10 if rd <= 6 else 30)
	if strategy == "lowroll" and rd >= 5 and rd <= 14:
		keep = 10
	if strategy == "midcarry" and run.level() >= 6 and rd >= 10:
		keep = 20
	if rd >= 20:
		keep = 0   # 後期不再存錢
	# 升級
	while run.level() < target and run.gold - Economy.xp_cost() >= mini(keep, 10):
		if run.buy_xp() != "":
			break
		st["spent_xp"] += Economy.xp_cost()
	_buy_loop(run, strategy, keep, st)
	# 刷新：lowroll 找低費同名、midcarry 找 3 費同名
	var roll_ok := (strategy == "lowroll" and rd >= 5 and rd <= 14) or (strategy == "midcarry" and run.level() >= 6) or rd >= 20
	var guard := 0
	while roll_ok and guard < 40 and run.gold - Economy.reroll_cost() >= keep and _wants_roll(run, strategy):
		guard += 1
		var g := run.gold
		if run.reroll() != "":
			break
		st["spent_reroll"] += g - run.gold
		st["rerolls"] += 1
		_buy_loop(run, strategy, keep, st)
	_sell_extras(run, st)
	arrange(run)
	_equip_items(run, st)
	_track(run, st)


static func _wants_roll(run: RunState, strategy: String) -> bool:
	# 還有可以追的目標（已擁有、尚未三星的低費／中費）
	for u in run.all_units():
		var c := GameData.unit_cost(str(u["id"]))
		if int(u["star"]) < 3 and ((strategy == "lowroll" and c <= 2) or (strategy == "midcarry" and c == 3) or strategy == "level"):
			return true
	return strategy != "lowroll"


static func _buy_loop(run: RunState, strategy: String, keep: int, st: Dictionary) -> void:
	var safety := 0
	while safety < 30:
		safety += 1
		var best := -1
		var best_score := -1.0
		for i in run.shop.size():
			var id := str(run.shop[i])
			if id == "" or run.can_buy(i) != "":
				continue
			var cost := GameData.unit_cost(id)
			var owned := run.copies_of(id, 1) + run.copies_of(id, 2) * 3
			var score := float(cost) + owned * 2.5
			match strategy:
				"lowroll":
					if cost <= 2:
						score += 3.0 + owned * 3.0
					elif run.round_no <= 14 and owned == 0:
						score -= 4.0
				"midcarry":
					if cost == 3:
						score += 3.0 + owned * 2.0
			if id == own_four(run.civ_id):
				score += 3.0
			if run.gold - cost < keep and owned == 0:
				continue
			if score > best_score:
				best_score = score
				best = i
		if best < 0:
			return
		var id2 := str(run.shop[best])
		if run.buy(best) != "":
			return
		st["spent_units"] += GameData.unit_cost(id2)


static func _sell_extras(run: RunState, st: Dictionary) -> void:
	var filled := 0
	for b in run.bench:
		if b != null:
			filled += 1
	while filled > run.bench.size() - 3:
		var worst := -1
		var worst_p := INF
		for i in run.bench.size():
			var b = run.bench[i]
			if b == null:
				continue
			var p := power(b["id"], int(b["star"]))
			if run.copies_of(b["id"], int(b["star"])) >= 2:
				p += 100.0
			if p < worst_p:
				worst_p = p
				worst = i
		if worst < 0:
			break
		var u: Dictionary = run.bench[worst]
		st["sold"] += UnitStats.sell_value(str(u["id"]), int(u["star"]))
		run.sell(int(u["uid"]))
		filled -= 1


static func arrange(run: RunState) -> void:
	AutoPlayer.arrange(run)


static func _equip_items(run: RunState, st: Dictionary) -> void:
	var lineup := run.board_lineup()
	lineup.sort_custom(func(a, b) -> bool: return power(a["id"], int(a["star"])) > power(b["id"], int(b["star"])))
	for p in lineup:
		while not run.inventory.is_empty() and RunState.unit_items(run.find_unit(int(p["uid"]))["unit"]).size() < GameData.item_slots():
			if run.equip(int(p["uid"]), 0) != "":
				break
			st["items_equipped"] += 1


static func _track(run: RunState, st: Dictionary) -> void:
	var lv := run.level()
	for l in range(2, lv + 1):
		if not st["level_round"].has(l):
			st["level_round"][l] = run.round_no
	var own4 := own_four(run.civ_id)
	for u in run.all_units():
		var c := GameData.unit_cost(str(u["id"]))
		if c == 4 and int(st["first_four_round"]) < 0:
			st["first_four_round"] = run.round_no
		if str(u["id"]) == own4 and int(u["star"]) >= 2 and int(st["own4_star2_round"]) < 0:
			st["own4_star2_round"] = run.round_no
		if c == 4 and int(u["star"]) >= 3:
			st["four_star3"] = true
		if c <= 2 and int(u["star"]) >= 3 and int(st["low_three_star_round"]) < 0:
			st["low_three_star_round"] = run.round_no


static func play_full_run(civ_id: String, seed_value: int, strategy: String) -> Dictionary:
	var run := RunState.create(civ_id, seed_value)
	var st := new_stats()
	var guard := 0
	while not run.finished and guard < 40:
		guard += 1
		play_prep(run, strategy, st)
		var result := run.start_battle()
		var rep := run.settle(result)
		st["income"] += int(rep.get("income_base", 0)) + int(rep.get("income_interest", 0)) + int(rep.get("income_clear", 0))
	var three := 0
	for u in run.all_units():
		if GameData.unit_cost(str(u["id"])) <= 2 and int(u["star"]) >= 3:
			three += 1
	st["low_three_stars"] = three
	return {"outcome": run.outcome, "round": run.round_no, "history": run.history, "stats": st, "hp": run.hp,
		"pool_ok": _pool_check(run)}


static func _pool_check(run: RunState) -> bool:
	var rem := run.pool_remaining()
	var used := run.pool_used()
	for id in rem.keys():
		if int(rem[id]) < 0 or int(rem[id]) + int(used.get(id, 0)) != Shop.supply(GameData.unit_cost(id)):
			return false
	return true
