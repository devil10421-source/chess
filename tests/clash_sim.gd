extends SceneTree
## 《氏族爭霸》10 人 AI 對局模擬報告（固定種子，可重複執行）。
##   godot --headless --path . --script res://tests/clash_sim.gd -- --runs=20 --out=docs/氏族爭霸_V0.1_模擬報告.md
## A. 一場完整十人對局的逐回合紀錄  B. 多場統計（回合數、淘汰節奏、PvE、交易、援軍、國家制度）
## C. 普通 AI 對簡單 AI（確認 AI 不是亂買）  D. 棋子費用分布

var lines: Array = []


func out(s: String = "") -> void:
	print(s)
	lines.append(s)


func _initialize() -> void:
	var runs := 20
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
		if a.begins_with("--out="):
			path = a.substr(6)
	var t0 := Time.get_ticks_msec()
	out("# 《氏族爭霸》10 人 PvPvE 原型 V0.1 模擬報告")
	out("")
	out("由 `tests/clash_sim.gd` 產生（固定種子，可重複：`godot --headless --path . --script res://tests/clash_sim.gd -- --runs=%d`）。十名玩家全部由 AI 操作（普通難度，C 節除外）；數值為 `data/clash_config.json` 的第一輪測試值。" % runs)
	out("")
	_detailed_match(20261022)
	_stats(runs)
	_easy_vs_normal(maxi(6, runs / 2))
	_unit_distribution()
	out("")
	out("（模擬耗時 %.0f 秒）" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if path != "":
		var f := FileAccess.open("res://" + path, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	quit()


## 跑一回合並收集戰鬥細節（與 ClashMatch.auto_round 相同的流程）
func _round(m: ClashMatch, st: Dictionary) -> Dictionary:
	var next := m.lock_in()
	if next == "trade":
		m.end_trades()
	for t in m.trades:
		st["trades_total"] = int(st.get("trades_total", 0)) + 1
		if str(t["status"]) == "done":
			st["trades_done"] = int(st.get("trades_done", 0)) + 1
	m.run_battles(false)
	for bt in m.battles:
		var b: ClashBattle = bt
		if b.kind == "coop":
			var held := [(b.sims[0] as CombatSim).events.any(func(e): return e["k"] == "hold"), (b.sims[1] as CombatSim).events.any(func(e): return e["k"] == "hold")]
			var spawned := [(b.sims[0] as CombatSim).events.any(func(e): return e["k"] == "spawn"), (b.sims[1] as CombatSim).events.any(func(e): return e["k"] == "spawn")]
			var ok := bool(b.outcome()["success"])
			_inc(st, "coop_n")
			if ok:
				_inc(st, "coop_ok")
			if spawned[0] or spawned[1]:
				_inc(st, "reinforce")
			if (held[0] and spawned[0]) or (held[1] and spawned[1]):
				_inc(st, "rescue_try")
				if ok:
					_inc(st, "rescue_ok")
			var key := "pve%d" % b.pve_index
			_inc(st, key + "_n")
			if ok:
				_inc(st, key + "_ok")
		elif b.kind == "solo":
			_inc(st, "solo_n")
			if bool(b.outcome()["success"]):
				_inc(st, "solo_ok")
		elif b.kind == "ghost":
			_inc(st, "ghost_n")
		else:
			_inc(st, "pvp_n")
			if str(b.outcome()["winner"]) == "draw":
				_inc(st, "pvp_draw")
	var rep := m.settle_round()
	for s in rep["per_seat"].keys():
		var d := int(rep["per_seat"][s].get("damage", 0))
		st["dmg_" + str(rep["kind"])] = int(st.get("dmg_" + str(rep["kind"]), 0)) + d
	if not m.finished:
		m.begin_round()
	return rep


func _inc(st: Dictionary, k: String, v: int = 1) -> void:
	st[k] = int(st.get(k, 0)) + v


# ---------- A ----------
func _detailed_match(seed_value: int) -> void:
	out("## A. 一場完整十人對局（種子 %d）" % seed_value)
	out("")
	var m := ClashMatch.create("AI", "AI", seed_value, "normal", false)
	var st := {}
	out("| 回合 | 類型 | 存活 | 摘要 | 淘汰 |")
	out("|---:|---|---:|---|---|")
	var guard := 0
	while not m.finished and guard < 80:
		guard += 1
		var alive := m.alive_count()
		var trades_before := m.event_log.filter(func(l): return str(l).contains("交易：")).size()
		var rep := _round(m, st)
		var summary: Array = []
		if rep["kind"] == "pve":
			var ok := (rep["lines"] as Array).filter(func(l): return str(l).ends_with("成功")).size()
			summary.append("PvE 成功 %d／%d 組" % [ok, (rep["lines"] as Array).size()])
			var tr := m.event_log.filter(func(l): return str(l).contains("交易：")).size() - trades_before
			summary.append("成交 %d 筆" % tr)
		else:
			var draws := (rep["lines"] as Array).filter(func(l): return str(l).ends_with("平手")).size()
			summary.append("%d 場 PvP%s" % [(rep["lines"] as Array).size(), "（平手 %d）" % draws if draws > 0 else ""])
		var gov_notes := m.event_log.filter(func(l): return str(l).begins_with("R%d " % int(rep["round"])) and (str(l).contains("成為") or str(l).contains("推行"))).size()
		if gov_notes > 0:
			summary.append("%d 次制度／政策選擇" % gov_notes)
		var dmg: Array = []
		for s in rep["per_seat"].keys():
			dmg.append(int(rep["per_seat"][s]["damage"]))
		dmg.sort()
		summary.append("最大扣血 %d" % (dmg[-1] if not dmg.is_empty() else 0))
		var elim: Array = (rep["eliminated"] as Array).map(func(s): return "%s（第 %d 名）" % [(m.players[s] as ClashPlayer).country, (m.players[s] as ClashPlayer).placement])
		out("| %d | %s | %d | %s | %s |" % [int(rep["round"]), "合作 PvE" if rep["kind"] == "pve" else "PvP", alive, "；".join(summary), "、".join(elim) if not elim.is_empty() else ""])
	out("")
	out("**最終名次**")
	out("")
	out("| 名次 | 國家 | 制度／政策 | 淘汰回合 | 等級 | 戰績 | 最後陣容 |")
	out("|---:|---|---|---:|---:|---|---|")
	for p in m.standings():
		var cp: ClashPlayer = p
		var comp: Array = []
		for u in cp.run.board_lineup():
			comp.append("%s%s" % [GameData.unit(str(u["id"]))["name"], "★".repeat(int(u["star"]))])
		out("| %d | %s | %s／%s | %s | %d | %d 勝 %d 敗 | %s |" % [cp.placement, cp.country, cp.government_name(), cp.policy_name(),
			"存活（生命 %d）" % cp.hp if cp.alive else str(cp.eliminated_round), cp.run.level(), cp.wins, cp.losses, "、".join(comp)])
	out("")
	out("交易紀錄：")
	for l in m.event_log.filter(func(x): return str(x).contains("交易：")).slice(0, 12):
		out("- %s" % l)
	out("")


# ---------- B ----------
func _stats(runs: int) -> void:
	out("## B. 多場統計（%d 場，普通 AI）" % runs)
	out("")
	var st := {}
	var rounds: Array = []
	var first_elim: Array = []
	var gov_place := {}
	var pol_place := {}
	var champ_gov := {}
	var champ_pol := {}
	var final_level: Array = []
	var three_stars: Array = []
	var pool_ok := true
	for i in runs:
		var m := ClashMatch.create("AI", "AI", 7000 + i * 131, "normal", false)
		var guard := 0
		while not m.finished and guard < 80:
			guard += 1
			_round(m, st)
			if not m.pool.audit().is_empty():
				pool_ok = false
		rounds.append(m.round_no)
		var fe := 999
		for p in m.players:
			var cp: ClashPlayer = p
			if cp.eliminated_round > 0:
				fe = mini(fe, cp.eliminated_round)
			_acc(gov_place, cp.government_name(), cp.placement)
			if cp.policy != "":
				_acc(pol_place, cp.policy_name(), cp.placement)
			if cp.placement == 1:
				champ_gov[cp.government_name()] = int(champ_gov.get(cp.government_name(), 0)) + 1
				champ_pol[cp.policy_name()] = int(champ_pol.get(cp.policy_name(), 0)) + 1
				final_level.append(cp.run.level())
				three_stars.append(cp.run.all_units().filter(func(u): return int(u["star"]) >= 3).size())
		first_elim.append(fe)
	out("| 指標 | 數值 |")
	out("|---|---|")
	out("| 對局回合數（平均／最短／最長） | %.1f／%d／%d |" % [_avg(rounds), rounds.min(), rounds.max()])
	out("| 第一位淘汰的回合（平均） | %.1f |" % _avg(first_elim))
	out("| 冠軍最後等級（平均） | %.1f |" % _avg(final_level))
	out("| 冠軍持有三星棋子（平均） | %.1f |" % _avg(three_stars))
	out("| PvP 場數／平手率 | %d／%s |" % [int(st.get("pvp_n", 0)), _pct(int(st.get("pvp_draw", 0)), int(st.get("pvp_n", 0)))])
	out("| 幽靈戰場數 | %d |" % int(st.get("ghost_n", 0)))
	out("| PvP 造成的總扣血／PvE 造成的總扣血 | %d／%d |" % [int(st.get("dmg_pvp", 0)), int(st.get("dmg_pve", 0))])
	out("| 合作 PvE 成功率 | %s（%d 組） |" % [_pct(int(st.get("coop_ok", 0)), int(st.get("coop_n", 0))), int(st.get("coop_n", 0))])
	out("| 單人 PvE 成功率 | %s（%d 次） |" % [_pct(int(st.get("solo_ok", 0)), int(st.get("solo_n", 0))), int(st.get("solo_n", 0))])
	out("| 有援軍出動的合作組 | %d |" % int(st.get("reinforce", 0)))
	out("| 一方全滅後被救回的嘗試／成功 | %d／%d |" % [int(st.get("rescue_try", 0)), int(st.get("rescue_ok", 0))])
	out("| 交易成交率（AI 對 AI） | %s（%d 組中 %d 筆） |" % [_pct(int(st.get("trades_done", 0)), int(st.get("trades_total", 0))), int(st.get("trades_total", 0)), int(st.get("trades_done", 0))])
	out("| 棋池守恆（每回合檢查） | %s |" % ("全部通過" if pool_ok else "有錯誤"))
	out("")
	out("**各次 PvE 的合作成功率**")
	out("")
	out("| 第 n 次 PvE | 敵軍（《六族遠征》關卡 × 重複加強；另乘 duo_scale %.2f） | 組數 | 成功率 |" % float(GameData.clash_cfg("pve").get("duo_scale", 1.0)))
	out("|---:|---|---:|---:|")
	for n in range(1, 9):
		var tot := int(st.get("pve%d_n" % n, 0))
		if tot == 0:
			continue
		var stg := ClashBattle.pve_stage(n)
		out("| %d | %s ×%.2f | %d | %s |" % [n, GameData.stage(int(stg["round"])).get("name", ""), float(stg["scale"]), tot, _pct(int(st.get("pve%d_ok" % n, 0)), tot)])
	out("")
	out("**國家制度與政策（AI 隨機傾向選擇；平均名次越小越好）**")
	out("")
	out("| 制度 | 選擇次數 | 平均名次 | 冠軍次數 |")
	out("|---|---:|---:|---:|")
	for k in gov_place.keys():
		var arr: Array = gov_place[k]
		out("| %s | %d | %.2f | %d |" % [k if k != "" else "（未選擇即淘汰）", arr.size(), _avg(arr), int(champ_gov.get(k, 0))])
	out("")
	out("| 政策 | 選擇次數 | 平均名次 | 冠軍次數 |")
	out("|---|---:|---:|---:|")
	for k in pol_place.keys():
		var arr: Array = pol_place[k]
		out("| %s | %d | %.2f | %d |" % [k, arr.size(), _avg(arr), int(champ_pol.get(k, 0))])
	out("")


func _acc(d: Dictionary, k: String, v: int) -> void:
	var arr: Array = d.get(k, [])
	arr.append(v)
	d[k] = arr


# ---------- C ----------
func _easy_vs_normal(runs: int) -> void:
	out("## C. 普通 AI 對簡單 AI（%d 場，座位 0～4 普通、5～9 簡單）" % runs)
	out("")
	var normal: Array = []
	var easy: Array = []
	for i in runs:
		var m := ClashMatch.create("AI", "AI", 9100 + i * 17, "normal", false)
		for s in range(5, 10):
			(m.players[s] as ClashPlayer).ai_level = "easy"
		m.play_to_end()
		for p in m.players:
			if (p as ClashPlayer).index < 5:
				normal.append((p as ClashPlayer).placement)
			else:
				easy.append((p as ClashPlayer).placement)
	out("| AI | 平均名次 | 進前四 |")
	out("|---|---:|---:|")
	out("| 普通 | %.2f | %s |" % [_avg(normal), _pct(normal.filter(func(x): return int(x) <= 4).size(), normal.size())])
	out("| 簡單 | %.2f | %s |" % [_avg(easy), _pct(easy.filter(func(x): return int(x) <= 4).size(), easy.size())])
	out("")
	out("（註：第一場 AI 的開局在第 1 回合前已備戰，難度在之後的回合才生效。）")
	out("")


# ---------- D ----------
func _unit_distribution() -> void:
	out("## D. 棋子費用與氏族分布（34 隻，費用與技能未調整）")
	out("")
	var by_cost := {}
	var by_race := {}
	for u in GameData.units():
		var c := int(u["cost"])
		by_cost[c] = int(by_cost.get(c, 0)) + 1
		var r := GameData.race_name(str(u["race"]))
		by_race[r] = int(by_race.get(r, 0)) + 1
	out("| 費用 | 種類 | 每種份數 | 該費用總份數 |")
	out("|---:|---:|---:|---:|")
	for c in [1, 2, 3, 4]:
		out("| %d | %d | %d | %d |" % [c, int(by_cost.get(c, 0)), SharedPool.supply(c), int(by_cost.get(c, 0)) * SharedPool.supply(c)])
	out("")
	out("| 氏族（含中立測試分配） | 棋子數 |")
	out("|---|---:|")
	for r in by_race.keys():
		out("| %s | %d |" % [r, by_race[r]])
	out("")


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for x in a:
		t += float(x)
	return t / a.size()


func _pct(n: int, d: int) -> String:
	return "—" if d == 0 else "%.0f%%" % (100.0 * n / d)
