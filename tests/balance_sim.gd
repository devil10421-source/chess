extends SceneTree
## 難度模擬：讓簡單的 bot 用每個文明各打 N 局，輸出每關全清率與最終結果。
## 用法：godot --headless --path . --script res://tests/balance_sim.gd -- --runs=20
## bot 很陽春（不會刻意湊羈絆、站位固定），真人通常會打得比它好；用來找「難度突然暴增」的關卡。


func _initialize() -> void:
	var runs := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
		if a.begins_with("--interest_max="):
			# 比較用：暫時覆寫利息上限（不改檔案）
			GameData.cfg("economy")["interest_max"] = int(a.substr(15))
	print("利息上限：+%d" % Economy.interest_max())
	var interest_sum: Array = []
	interest_sum.resize(GameData.total_rounds() + 1)
	interest_sum.fill(0.0)
	var total_rounds := GameData.total_rounds()
	var clears: Array = []
	var reached: Array = []
	clears.resize(total_rounds + 1)
	clears.fill(0)
	reached.resize(total_rounds + 1)
	reached.fill(0)
	var outcomes := {}
	var per_civ := {}
	var t0 := Time.get_ticks_msec()
	for c in GameData.civs():
		var civ := str(c["id"])
		per_civ[civ] = {"victory": 0, "rounds": 0}
		for i in runs:
			var r := AutoPlayer.play_full_run(civ, 1000 + i * 7919)
			outcomes[r["outcome"]] = int(outcomes.get(r["outcome"], 0)) + 1
			var hist: Array = r["history"]
			per_civ[civ]["rounds"] += hist.size()
			if r["outcome"] == "victory":
				per_civ[civ]["victory"] += 1
			for h in hist:
				interest_sum[int(h["round"])] += float(h.get("income_interest", 0))
				reached[int(h["round"])] += 1
				if h["cleared"]:
					clears[int(h["round"])] += 1
	print("回合 | 抵達 | 全清率")
	for rd in range(1, total_rounds + 1):
		var rate: float = 0.0 if reached[rd] == 0 else 100.0 * clears[rd] / reached[rd]
		print("%2d   | %4d | %5.1f%%  %s" % [rd, reached[rd], rate, GameData.stage(rd).get("name", "")])
	print("")
	var parts: Array = []
	for rd in [4, 8, 12, 16, 20, 24]:
		if reached[rd] > 0:
			parts.append("第%d回合 %.2f" % [rd, interest_sum[rd] / reached[rd]])
	print("平均利息收入：" + "、".join(parts))
	for civ in per_civ.keys():
		print("%s：平均打到第 %.1f 回合，通關 %d/%d" % [GameData.civ(civ)["name"], float(per_civ[civ]["rounds"]) / runs, per_civ[civ]["victory"], runs])
	print("結局統計：", outcomes)
	print("耗時 %.1f 秒" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
