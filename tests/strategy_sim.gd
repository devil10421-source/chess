extends SceneTree
## V0.4 策略與經濟模擬（固定種子，可重複執行）。
## 用法：godot --headless --path . --script res://tests/strategy_sim.gd -- --runs=6 --out=docs/V0.4_模擬報告.md
## 兩部分，結果分開呈現：
##   A. 純抽卡模擬（不含戰鬥）：只用商店機率與有限卡池，估算各等級找到指定 4 費的刷新次數。
##   B. 策略 bot 完整對局（含真實戰鬥模擬）：三種策略 × 六文明 × N 局，記錄升級時間、金幣收支、4 費取得、二星／三星與通關率。
## bot 不會刻意湊羈絆、站位固定、裝備直接穿給最強棋子；通關率只代表「這個 bot」的表現，不等於真人難度。

const Bot := preload("res://tests/strategy_bot.gd")
const STRATEGIES := ["level", "midcarry", "lowroll"]
const STRAT_NAMES := {"level": "優先升級", "midcarry": "中費主力二星", "lowroll": "低費三星"}

var lines: Array = []


func out(s: String = "") -> void:
	print(s)
	lines.append(s)


func _initialize() -> void:
	var runs := 6
	var path := ""
	var draw_samples := 15
	var strategies: Array = STRATEGIES
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--draw="):
			draw_samples = int(a.substr(7))
		if a.begins_with("--only="):
			strategies = Array(a.substr(7).split(","))
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
		if a.begins_with("--out="):
			path = a.substr(6)
	var t0 := Time.get_ticks_msec()
	out("# 《六族遠征》V0.4 策略與經濟模擬報告")
	out("")
	out("由 `tests/strategy_sim.gd` 產生（固定種子，可重複執行：`godot --headless --path . --script res://tests/strategy_sim.gd -- --runs=%d`）。" % runs)
	out("")
	if draw_samples > 0:
		_draw_sim(draw_samples)
	_strategy_sim(runs, strategies)
	out("")
	out("耗時 %.0f 秒。" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if path != "":
		var f := FileAccess.open("res://" + path, FileAccess.WRITE)
		if f:
			f.store_string("\n".join(lines) + "\n")
			f.close()
	quit(0)


# ---------------- A. 純抽卡 ----------------
## 在等級 lv、卡池全滿（沒有被其他人拿走，PVE 只有自己）時，每次刷新 5 格，
## 直到「看到」指定 4 費 n 張（看到即買下，買下後從卡池扣除）需要的刷新次數。
func _rolls_to_collect(civ: String, lv: int, need: int, seed_value: int) -> int:
	var rng := SeededRng.new(seed_value)
	var pool := Shop.initial_pool(civ)
	var target := Bot.own_four(civ)
	var got := 0
	var rolls := 0
	var shop: Array = []
	while got < need and rolls < 5000:
		for id in shop:
			if str(id) != "":
				pool[str(id)] = int(pool[str(id)]) + 1   # 沒買的放回卡池
		shop = Shop.roll(rng, lv, civ, {}, pool)
		rolls += 1
		for i in shop.size():
			if str(shop[i]) == target and got < need:
				got += 1
				shop[i] = ""   # 買下（不放回）
	return rolls


func _draw_sim(samples: int) -> void:
	out("## A. 純抽卡模擬（不含戰鬥、不含金幣限制）")
	out("")
	out("條件：卡池全滿、只追「本族專屬 4 費」、每次刷新 5 格、看到就買。各等級 6 文明 × %d 次的平均刷新次數（每次刷新 2 金）。" % samples)
	out("")
	out("| 等級 | 4 費機率 | 看到第 1 張 | 湊滿 3 張（二星） | 湊滿 9 張（三星） |")
	out("|---|---:|---:|---:|---:|")
	for lv in [7, 8, 9, 10]:
		var sums := [0.0, 0.0, 0.0]
		var n := 0
		for c in GameData.civs():
			for k in samples:
				var sd: int = 9000 + int(lv) * 101 + k * 7 + n
				sums[0] += _rolls_to_collect(str(c["id"]), lv, 1, sd)
				sums[1] += _rolls_to_collect(str(c["id"]), lv, 3, sd + 1)
				sums[2] += _rolls_to_collect(str(c["id"]), lv, 9, sd + 2)
				n += 1
		out("| Lv.%d | %d%% | %.1f 次（%.0f 金） | %.1f 次（%.0f 金） | %.1f 次（%.0f 金） |" % [lv, int(Shop.odds_for_level(lv)[3]),
			sums[0] / n, sums[0] / n * 2, sums[1] / n, sums[1] / n * 2, sums[2] / n, sums[2] / n * 2])
	out("")
	out("說明：4 費共 6 種（本族 1＋中立 5），每種 10 張；所以抽到 4 費時，指定那一種的機率約 1/6。")
	out("")


# ---------------- B. 策略 bot ----------------
func _strategy_sim(runs: int, strategies: Array) -> void:
	out("## B. 策略 bot 完整對局（含真實戰鬥模擬）")
	out("")
	out("每種策略 × 6 文明 × %d 局（固定種子）。**通關率是 bot 的結果，不是真人難度**：bot 不湊羈絆、站位固定。" % runs)
	out("")
	var all := {}
	for strat in strategies:
		var rs: Array = []
		for c in GameData.civs():
			for i in runs:
				var r := Bot.play_full_run(str(c["id"]), 2000 + i * 7919, strat)
				r["civ"] = str(c["id"])
				rs.append(r)
		all[strat] = rs
	# B1 摘要
	out("### B1. 策略摘要")
	out("")
	out("| 指標 | " + " | ".join(strategies.map(func(s): return STRAT_NAMES[s])) + " |")
	out("|---|" + "---:|".repeat(strategies.size()))
	var rows := [
		["平均打到回合", func(rs): return "%.1f" % _avg(rs.map(func(r): return float(r["history"].size())))],
		["第 24 回合通關率", func(rs): return _pct(rs.filter(func(r): return r["outcome"] == "victory").size(), rs.size())],
		["抵達第 24 回合", func(rs): return _pct(rs.filter(func(r): return r["history"].size() >= 24).size(), rs.size())],
		["Lv.6 平均回合", func(rs): return _lv_round(rs, 6)],
		["Lv.7 平均回合", func(rs): return _lv_round(rs, 7)],
		["Lv.8 平均回合", func(rs): return _lv_round(rs, 8)],
		["Lv.9 平均回合", func(rs): return _lv_round(rs, 9)],
		["Lv.10 達成率／平均回合", func(rs): return _lv_round(rs, 10)],
		["總收入（金）", func(rs): return "%.0f" % _avg(rs.map(func(r): return float(r["stats"]["income"])))],
		["花在升級", func(rs): return "%.0f" % _avg(rs.map(func(r): return float(r["stats"]["spent_xp"])))],
		["花在刷新（次數）", func(rs): return "%.0f（%.0f 次）" % [_avg(rs.map(func(r): return float(r["stats"]["spent_reroll"]))), _avg(rs.map(func(r): return float(r["stats"]["rerolls"])))]],
		["花在買棋子", func(rs): return "%.0f" % _avg(rs.map(func(r): return float(r["stats"]["spent_units"])))],
		["出售回收", func(rs): return "%.0f" % _avg(rs.map(func(r): return float(r["stats"]["sold"])))],
		["首隻 4 費：取得率／平均回合", func(rs): return _first(rs, "first_four_round")],
		["本族 4 費二星：機率／平均回合", func(rs): return _first(rs, "own4_star2_round")],
		["4 費三星出現頻率", func(rs): return _pct(rs.filter(func(r): return r["stats"]["four_star3"]).size(), rs.size())],
		["低費（1～2 費）三星：機率／平均回合", func(rs): return _first(rs, "low_three_star_round")],
		["卡池守恆檢查", func(rs): return "全部通過" if rs.all(func(r): return r["pool_ok"]) else "有錯誤"],
	]
	for row in rows:
		var cells: Array = []
		for strat in strategies:
			cells.append(str((row[1] as Callable).call(all[strat])))
		out("| %s | %s |" % [row[0], " | ".join(cells)])
	out("")
	# B2 文明
	out("### B2. 各文明相對表現（三種策略合計）")
	out("")
	out("| 文明 | 平均打到回合 | 第 24 回合通關率 | 本族 4 費二星機率 |")
	out("|---|---:|---:|---:|")
	for c in GameData.civs():
		var rs: Array = []
		for strat in strategies:
			rs.append_array(all[strat].filter(func(r): return r["civ"] == str(c["id"])))
		out("| %s | %.1f | %s | %s |" % [c["name"], _avg(rs.map(func(r): return float(r["history"].size()))),
			_pct(rs.filter(func(r): return r["outcome"] == "victory").size(), rs.size()),
			_pct(rs.filter(func(r): return int(r["stats"]["own4_star2_round"]) > 0).size(), rs.size())])
	out("")
	# B3 每回合全清率
	out("### B3. 每回合全清率（三種策略合計）")
	out("")
	out("| 回合 | 敵軍 | 抵達 | 全清率 |")
	out("|---:|---|---:|---:|")
	for rd in range(1, GameData.total_rounds() + 1):
		var reached := 0
		var cleared := 0
		for strat in strategies:
			for r in all[strat]:
				for h in r["history"]:
					if int(h["round"]) == rd:
						reached += 1
						if h["cleared"]:
							cleared += 1
		out("| %d | %s | %d | %s |" % [rd, GameData.stage(rd).get("name", ""), reached, _pct(cleared, reached)])


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for x in a:
		t += float(x)
	return t / a.size()


func _pct(n: int, d: int) -> String:
	return "—" if d == 0 else "%.0f%%" % (100.0 * n / d)


func _lv_round(rs: Array, lv: int) -> String:
	var hit: Array = []
	for r in rs:
		if r["stats"]["level_round"].has(lv):
			hit.append(float(r["stats"]["level_round"][lv]))
	if hit.is_empty():
		return "未達成"
	var s := "%.1f" % _avg(hit)
	if hit.size() < rs.size():
		s = "%s／%s" % [_pct(hit.size(), rs.size()), s]
	return s


func _first(rs: Array, key: String) -> String:
	var hit: Array = []
	for r in rs:
		if int(r["stats"][key]) > 0:
			hit.append(float(r["stats"][key]))
	if hit.is_empty():
		return "0%"
	return "%s／第 %.1f 回合" % [_pct(hit.size(), rs.size()), _avg(hit)]
