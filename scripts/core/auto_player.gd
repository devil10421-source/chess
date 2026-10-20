class_name AutoPlayer
extends RefCounted
## 簡單的自動玩家：用於自動測試與難度模擬（不會出現在正式遊戲中）。
## 策略：照回合目標升級 → 優先買能合成的棋子 → 買高費棋子 → 依強度部署（近戰前排、遠程後排）。

const TARGET_LEVEL := [1, 2, 2, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 8, 8, 8, 8, 9, 9]


static func power(id: String, star: int) -> float:
	var mult := [1.0, 3.5, 11.0]
	return float(GameData.unit_cost(id)) * mult[clampi(star, 1, 3) - 1]


static func play_prep(run: RunState) -> void:
	run.begin_round()
	var target: int = TARGET_LEVEL[clampi(run.round_no - 1, 0, TARGET_LEVEL.size() - 1)]
	var keep := 0 if run.round_no <= 3 else mini(20, run.round_no * 2)
	# 升級
	while run.level() < target and run.gold >= Economy.xp_cost():
		if run.buy_xp() != "":
			break
	# 購買
	var safety := 0
	while safety < 30:
		safety += 1
		var bought := _buy_best(run, keep)
		if not bought:
			if run.gold - Economy.reroll_cost() >= keep + 4 and run.round_no >= 4:
				run.reroll()
				continue
			break
	_sell_extras(run)
	arrange(run)


static func _buy_best(run: RunState, keep: int) -> bool:
	var best := -1
	var best_score := -1.0
	for i in run.shop.size():
		var id := str(run.shop[i])
		if id == "" or run.can_buy(i) != "":
			continue
		var cost := GameData.unit_cost(id)
		var owned := run.copies_of(id, 1) + run.copies_of(id, 2) * 3
		var score := float(cost) + owned * 2.5
		if run.gold - cost < keep and owned == 0:
			continue
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		return false
	return run.buy(best) == ""


static func _sell_extras(run: RunState) -> void:
	# 候補區快滿時，賣掉最弱且沒有同名的棋子
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
		run.sell(int(run.bench[worst]["uid"]))
		filled -= 1


## 依強度挑出上場棋子並站位：近戰在第 4~5 排，遠程在第 6~7 排
static func arrange(run: RunState) -> void:
	var all := run.all_units()
	all.sort_custom(func(a, b) -> bool:
		var pa := power(a["id"], int(a["star"]))
		var pb := power(b["id"], int(b["star"]))
		if pa != pb:
			return pa > pb
		return int(a["uid"]) < int(b["uid"]))
	var chosen: Array = all.slice(0, run.board_limit())
	# 先全部收回候補（候補空間不足時保留原位）
	for c in run.board.keys():
		var u: Dictionary = run.board[c]
		var idx := run.bench_free_index()
		if idx >= 0:
			run.move_to_bench(int(u["uid"]), idx)
	var front := [Vector2i(3, 4), Vector2i(2, 4), Vector2i(4, 4), Vector2i(1, 4), Vector2i(5, 4), Vector2i(0, 4), Vector2i(6, 4),
		Vector2i(3, 5), Vector2i(2, 5), Vector2i(4, 5)]
	var back := [Vector2i(3, 6), Vector2i(2, 6), Vector2i(4, 6), Vector2i(3, 7), Vector2i(2, 7), Vector2i(4, 7), Vector2i(1, 6),
		Vector2i(5, 6), Vector2i(1, 7), Vector2i(5, 7)]
	for u in chosen:
		var cells: Array = front if GameData.is_melee(u["id"]) else back
		for c in cells:
			if not run.board.has(c):
				if run.move_to_board(int(u["uid"]), c) == "":
					break


## 跑完整局，回傳 {"round": 最後回合, "outcome", "hp"}
static func play_full_run(civ_id: String, seed_value: int) -> Dictionary:
	var run := RunState.create(civ_id, seed_value)
	var guard := 0
	while not run.finished and guard < 40:
		guard += 1
		play_prep(run)
		var result := run.start_battle()
		run.settle(result)
	return {"round": run.round_no, "outcome": run.outcome, "hp": run.hp, "history": run.history, "run": run}
