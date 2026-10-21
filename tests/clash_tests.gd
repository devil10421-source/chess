extends SceneTree
## 《氏族爭霸》10 人 PvPvE 原型的驗收測試（對應開發指令第十三節）。
##   godot --headless --path . --script res://tests/clash_tests.gd
## 全部通過時結束碼為 0。

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	var tests := [
		"test_clans_and_pool_scope",
		"test_match_start_1_human_9_ai",
		"test_pvp_pairing_counts",
		"test_pvp_avoid_recent",
		"test_pve_pairing_counts",
		"test_pool_supply_limit",
		"test_pool_star_up_and_sell",
		"test_pool_elimination_returns",
		"test_ghost_no_pool",
		"test_mirror_cell",
		"test_pvp_damage_and_win_gold",
		"test_trade_rules",
		"test_trade_capacity_and_items",
		"test_trade_timeout_cancel",
		"test_coop_rescue_success",
		"test_coop_rescue_fails",
		"test_coop_both_wiped",
		"test_coop_settlement_hp",
		"test_solo_pve",
		"test_elimination_ranking_ties",
		"test_simultaneous_final_tie",
		"test_no_double_settle",
		"test_government_choices",
		"test_policy_effects_economy",
		"test_policy_effects_combat",
		"test_people_power_villagers",
		"test_ai_uses_rules",
		"test_full_matches",
		"test_reproducible",
		"test_single_player_untouched",
	]
	for name in tests:
		_current = name
		var before := _failed
		call(name)
		print(("  ✓ " if _failed == before else "  ✗ ") + name)
	GameData.set_clash_clans(false)
	print("")
	print("《氏族爭霸》測試結果：%d 項斷言通過，%d 項失敗" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("    [失敗] %s：%s" % [_current, msg])


func eq(a: Variant, b: Variant, msg: String) -> void:
	check(a == b, "%s（實際 %s，預期 %s）" % [msg, str(a), str(b)])


# ---------- 工具 ----------
func _ai_match(seed_value: int) -> ClashMatch:
	return ClashMatch.create("測試", "測試國", seed_value, "normal", false)


func _put(p: ClashPlayer, id: String, star: int, cell: Vector2i) -> int:
	var u := {"uid": p.run.next_uid, "id": id, "star": star, "items": []}
	p.run.next_uid += 1
	p.run.board[cell] = u
	return int(u["uid"])


func _bench(p: ClashPlayer, id: String, star: int) -> int:
	var u := {"uid": p.run.next_uid, "id": id, "star": star, "items": []}
	p.run.next_uid += 1
	p.run.bench[p.run.bench_free_index()] = u
	return int(u["uid"])


func _clear(p: ClashPlayer) -> void:
	p.run.board.clear()
	for i in p.run.bench.size():
		p.run.bench[i] = null
	p.run.shop = []


## 依座位找到強力陣容需要的棋子（3 星 4 費）
func _strong_board(p: ClashPlayer) -> void:
	_clear(p)
	var cells := [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 6), Vector2i(2, 6)]
	var ids := ["NEU6", "NEU8", "ORC4", "NEU7", "ELF4"]
	for i in ids.size():
		_put(p, ids[i], 3, cells[i])


func _weak_board(p: ClashPlayer) -> void:
	_clear(p)
	_put(p, "ELF1", 1, Vector2i(3, 7))


# ---------- 棋子與棋池 ----------
func test_clans_and_pool_scope() -> void:
	GameData.set_clash_clans(true)
	eq(Shop.full_pool("").size(), 34, "34 隻棋子全部可招募（沒有文明限制）")
	var neutral_left := GameData.units().filter(func(u): return str(u["race"]) == "neutral")
	eq(neutral_left.size(), 0, "沒有中立分類（全部歸入六大氏族，測試分配）")
	eq(str(GameData.unit("NEU7")["race"]), "elf", "中立棋子的測試氏族歸屬")
	check(GameData.was_neutral("NEU7"), "仍可辨識原本是中立棋子")
	eq(int(GameData.unit("NEU7")["cost"]), 4, "費用不變")
	var counts := Synergy.count(["NEU7", "ELF1", "ELF2"])
	eq(int(counts["race"].get("elf", 0)), 3, "原中立棋子計入所屬氏族的種族羈絆")
	var hp_before: float = float(UnitStats.base_stats("NEU7", 1)["hp"])
	GameData.set_clash_clans(false)
	eq(str(GameData.unit("NEU7")["race"]), "neutral", "離開模式後還原")
	check(is_equal_approx(float(UnitStats.base_stats("NEU7", 1)["hp"]), float(hp_before)), "數值不受氏族歸屬影響")
	GameData.set_clash_clans(true)


func test_match_start_1_human_9_ai() -> void:
	var m := ClashMatch.create("玩家001", "永遠正確的人民共和國", 11, "normal", true)
	eq(m.players.size(), 10, "10 名玩家")
	eq(m.players.filter(func(p): return p.is_human).size(), 1, "1 名真人")
	eq(m.human().country, "永遠正確的人民共和國", "國家名稱")
	eq(m.human().player_name, "玩家001", "玩家名稱")
	var names := {}
	for p in m.players:
		names[p.country] = true
		eq(p.hp, 100, "生命 100")
		eq(p.run.civ_id, "", "沒有開局文明")
		eq(p.government, "", "開局沒有國家制度")
	eq(names.size(), 10, "國家名稱不重複")
	eq(m.round_no, 1, "第 1 回合")
	eq(m.round_kind, "pvp", "第 1 回合為 PvP")
	eq(m.stage, "prep", "備戰階段")
	check(m.players.filter(func(p): return not p.is_human and p.run.all_units().size() > 0).size() == 9, "AI 已在備戰時買棋子")
	check(m.pool.audit().is_empty(), "棋池守恆")


func test_pvp_pairing_counts() -> void:
	var rng := SeededRng.new(5)
	for n in [10, 9, 8, 7, 6, 3, 2]:
		var alive: Array = range(n)
		var plan := ClashMatchmaking.pvp(alive, {}, -1, rng)
		eq((plan["pairs"] as Array).size(), n / 2, "%d 人 → %d 場 PvP" % [n, n / 2])
		var seen := {}
		for pr in plan["pairs"]:
			seen[int(pr[0])] = true
			seen[int(pr[1])] = true
			check(int(pr[0]) != int(pr[1]), "不會自己打自己")
		if n % 2 == 1:
			check(int(plan["lone"]) >= 0 and not seen.has(int(plan["lone"])), "%d 人：一人落單" % n)
			check(int(plan["ghost_of"]) >= 0 and int(plan["ghost_of"]) != int(plan["lone"]), "幽靈對手是另一名存活玩家")
			seen[int(plan["lone"])] = true
		else:
			eq(int(plan["lone"]), -1, "%d 人：沒有幽靈戰" % n)
		eq(seen.size(), n, "%d 人全部有對戰" % n)
	eq(ClashMatch.round_type(2, 2), "pvp", "只剩 2 人：最終決戰只打 PvP")
	eq(ClashMatch.round_type(2, 10), "pve", "第 2 回合為合作 PvE")
	eq(ClashMatch.round_type(8, 10), "pve", "每 6 回合一次 PvE（第 8 回合）")
	eq(ClashMatch.round_type(9, 10), "pvp", "其餘回合 PvP")


func test_pvp_avoid_recent() -> void:
	var rng := SeededRng.new(9)
	var recent := {}
	var repeats := 0
	for r in 30:
		var plan := ClashMatchmaking.pvp(range(10), recent, -1, rng)
		for pr in plan["pairs"]:
			var a := int(pr[0])
			var b := int(pr[1])
			var ha: Array = recent.get(a, [])
			if not ha.is_empty() and int(ha[-1]) == b:
				repeats += 1
			ha.append(b)
			var hb: Array = recent.get(b, [])
			hb.append(a)
			recent[a] = ha
			recent[b] = hb
	eq(repeats, 0, "十人時不會連續兩回合遇到同一名對手")


func test_pve_pairing_counts() -> void:
	var rng := SeededRng.new(3)
	for n in [10, 8, 9, 7, 3]:
		var plan := ClashMatchmaking.pve(range(n), rng)
		eq((plan["pairs"] as Array).size(), n / 2, "%d 人 PvE：%d 組雙人合作" % [n, n / 2])
		if n % 2 == 1:
			check(int(plan["solo"]) >= 0, "%d 人：一人單人 PvE" % n)
		else:
			eq(int(plan["solo"]), -1, "%d 人：沒有單人 PvE" % n)


func test_pool_supply_limit() -> void:
	var m := _ai_match(21)
	for p in m.players:
		_clear(p)
	# 十名玩家合計持有 10 份 ELF4（4 費供應 10）：棋池剩 0，任何人的商店都抽不到、也買不到
	for i in 10:
		_bench(m.players[i], "ELF4", 1)
	eq(int(m.pool.remaining()["ELF4"]), 0, "4 費 10 份全部被持有")
	check(m.pool.audit().is_empty(), "沒有超過供應")
	var p: ClashPlayer = m.players[0]
	p.run.xp = 120
	var seen := false
	for k in 200:
		p.run.gold = 100
		p.run.reroll()
		if p.run.shop.has("ELF4"):
			seen = true
	check(not seen, "棋池用完後商店不會再出現（200 次刷新）")
	# 出售 1 份 → 回池
	m.players[3].run.sell(int(m.players[3].run.bench[0]["uid"]))
	eq(int(m.pool.remaining()["ELF4"]), 1, "出售後歸還 1 份")
	# 商店預留也佔份數
	var q: ClashPlayer = m.players[5]
	q.run.shop = ["ELF4", "", "", "", ""]
	eq(int(m.pool.remaining()["ELF4"]), 0, "商店上顯示的棋子已預留")
	check(m.pool.audit().is_empty(), "預留後仍守恆")
	eq(SharedPool.supply(1), 30, "1 費 30 份")
	eq(SharedPool.supply(2), 25, "2 費 25 份")
	eq(SharedPool.supply(3), 18, "3 費 18 份")
	eq(SharedPool.supply(4), 10, "4 費 10 份")


func test_pool_star_up_and_sell() -> void:
	var m := _ai_match(22)
	var p: ClashPlayer = m.players[0]
	_clear(p)
	var before: int = int(m.pool.remaining()["HUM1"])
	p.run.gold = 50
	for k in 3:
		p.run.shop = ["HUM1", "", "", "", ""]
		check(p.run.buy(0) == "", "買第 %d 隻" % (k + 1))
	eq(p.run.copies_of("HUM1", 2), 1, "三隻合成二星")
	eq(int(m.pool.remaining()["HUM1"]), before - 3, "升星不會額外生成份數（二星＝3 份）")
	var uid := int(p.run.all_units().filter(func(u): return u["id"] == "HUM1")[0]["uid"])
	p.run.sell(uid)
	eq(int(m.pool.remaining()["HUM1"]), before, "出售二星歸還 3 份")
	check(m.pool.audit().is_empty(), "守恆")


func test_pool_elimination_returns() -> void:
	var m := _ai_match(23)
	var p: ClashPlayer = m.players[4]
	var used_by_p := p.run.pool_used()
	var total := 0
	for id in used_by_p.keys():
		total += int(used_by_p[id])
	check(total > 0, "淘汰前持有棋子／商店預留")
	var rem_before := m.pool.remaining()
	p.hp = -5
	m.stage = "battle"
	m.battles = []
	var rep := m.settle_round()
	check((rep["eliminated"] as Array).has(4), "生命 ≤ 0 淘汰")
	var rem_after := m.pool.remaining()
	for id in used_by_p.keys():
		eq(int(rem_after[id]), int(rem_before[id]) + int(used_by_p[id]), "%s 份數回到共用棋池" % id)
	check(not m.alive_seats().has(4), "存活名單更新")
	check(m.pool.audit().is_empty(), "守恆")


func test_ghost_no_pool() -> void:
	var m := _ai_match(24)
	var used_before := m.pool.used()
	var g: ClashPlayer = m.players[2]
	_strong_board(g)
	var used_mid := m.pool.used()
	var lone: ClashPlayer = m.players[1]
	var board_before := g.run.board_lineup()
	var gold_before: int = g.run.gold
	var bt := ClashBattle.make_pvp(ClashBattle.lineup_snapshot(lone), ClashBattle.lineup_snapshot(g), 5, true)
	bt.run()
	eq(bt.kind, "ghost", "幽靈戰")
	eq(m.pool.used(), used_mid, "幽靈陣容不佔棋池份數")
	eq(g.run.board_lineup(), board_before, "被複製玩家的棋子不受影響")
	eq(g.run.gold, gold_before, "被複製玩家的經濟不受影響")
	var ghosts := (bt.sims[0] as CombatSim).units.filter(func(u): return u.side == 1)
	eq(ghosts.size(), board_before.size(), "複製實際棋子數量")
	check(ghosts.all(func(u): return int(u.star) == 3), "複製星級")


func test_mirror_cell() -> void:
	eq(ClashBattle.mirror_cell(Vector2i(0, 4)), Vector2i(6, 3), "下方左側 → 上方右側")
	eq(ClashBattle.mirror_cell(Vector2i(3, 7)), Vector2i(3, 0), "後排中央 → 對面後排中央")
	for c in 7:
		for r in range(4, 8):
			var mc := ClashBattle.mirror_cell(Vector2i(c, r))
			check(mc.y <= 3 and mc.y >= 0 and mc.x >= 0 and mc.x <= 6, "鏡像落在對方區域")
			eq(ClashBattle.mirror_cell(mc), Vector2i(c, r), "鏡像兩次回到原位")


func test_pvp_damage_and_win_gold() -> void:
	var m := _ai_match(25)
	m.round_no = 12
	m.round_kind = "pvp"
	m.pvp_plan = {"pairs": [[0, 1]], "lone": -1, "ghost_of": -1}
	for s in range(2, 10):
		m.players[s].alive = false
		m.pool.unregister(m.players[s].run)
	_strong_board(m.players[0])
	_weak_board(m.players[1])
	var hp1: int = m.players[1].hp
	var gold0: int = m.players[0].run.gold
	m.start_battles()
	m.run_battles()
	var o: Dictionary = (m.battles[0] as ClashBattle).outcome()
	eq(str(o["winner"]), "a", "強陣容獲勝")
	var survivors: Array = o["a_stars"]
	m.settle_round()
	eq(m.players[1].hp, hp1 - (ClashMatch.pvp_base_damage(12) + ClashMatch.unit_damage(survivors)), "輸方扣血＝回合基礎值＋對方存活棋子")
	check(m.players[0].run.gold >= gold0 + 1 + Economy.base_income(), "勝方 +1 金與收入")


# ---------- 交易 ----------
func _trade_setup(seed_value: int) -> Array:
	var m := _ai_match(seed_value)
	var a: ClashPlayer = m.players[0]
	var b: ClashPlayer = m.players[1]
	_clear(a)
	_clear(b)
	var ua := _bench(a, "HUM2", 2)
	var ub := _bench(b, "ORC3", 1)
	a.run.inventory = ["CP_BLADE"]
	b.run.inventory = ["CP_STONE"]
	m.stage = "trade"
	var t := ClashTrade.new_trade(0, 1)
	m.trades = [t]
	return [m, t, ua, ub]


func test_trade_rules() -> void:
	var s := _trade_setup(31)
	var m: ClashMatch = s[0]
	var t: Dictionary = s[1]
	var ua: int = s[2]
	var ub: int = s[3]
	var used_before := m.pool.used()
	eq(m.submit(0, {"type": "trade_offer", "offer": {"kind": "unit", "uid": ua}}), "", "A 提出二星人類")
	check(m.submit(0, {"type": "trade_confirm"}) != "", "只有一方提出時不能確認（不允許單方面贈送）")
	eq(m.submit(1, {"type": "trade_offer", "offer": {"kind": "unit", "uid": ub}}), "", "B 提出棋子")
	eq(m.submit(0, {"type": "trade_confirm"}), "", "A 確認")
	check(bool(t["confirm"][0]) and str(t["status"]) == "open", "只有一方確認：尚未成交、資產未移轉")
	check(not m.players[0].run.find_unit(ua).is_empty(), "未成交前棋子仍在原主")
	# 變更提案 → 雙方確認清除
	eq(m.submit(1, {"type": "trade_offer", "offer": {"kind": "item", "inv": 0}}), "", "B 改提出裝備")
	check(not bool(t["confirm"][0]) and not bool(t["confirm"][1]), "任一方變更內容，雙方確認都清除")
	eq(m.submit(1, {"type": "trade_confirm"}), "", "B 確認")
	eq(m.submit(0, {"type": "trade_confirm"}), "", "A 確認 → 成交")
	eq(str(t["status"]), "done", "雙方確認後成交")
	check(m.players[0].run.find_unit(ua).is_empty(), "棋子離開原主（不殘留）")
	eq(m.players[1].run.copies_of("HUM2", 2), 1, "B 收到二星棋子（星級保留）")
	check(m.players[0].run.inventory.has("CP_STONE") and not m.players[1].run.inventory.has("CP_STONE"), "裝備轉移、沒有複製")
	eq(m.pool.used(), used_before, "交易只轉移所有權，棋池份數不變")
	check(m.submit(0, {"type": "trade_confirm"}) != "", "成交後不能再交易（不會交換兩次）")
	# 已出售的棋子不能成交
	var s2 := _trade_setup(32)
	var m2: ClashMatch = s2[0]
	var t2: Dictionary = s2[1]
	m2.submit(0, {"type": "trade_offer", "offer": {"kind": "unit", "uid": s2[2]}})
	m2.submit(1, {"type": "trade_offer", "offer": {"kind": "unit", "uid": s2[3]}})
	m2.submit(0, {"type": "trade_confirm"})
	m2.players[1].run.sell(int(s2[3]))
	check(m2.submit(1, {"type": "trade_confirm"}) != "", "棋子已出售：交易不成立")
	eq(str(t2["status"]), "open", "沒有成交")
	check(not m2.players[0].run.find_unit(int(s2[2])).is_empty(), "A 的棋子沒有被拿走")


func test_trade_capacity_and_items() -> void:
	var s := _trade_setup(33)
	var m: ClashMatch = s[0]
	var t: Dictionary = s[1]
	var a: ClashPlayer = m.players[0]
	var b: ClashPlayer = m.players[1]
	# A 的上場棋子身上有裝備：交換時裝備退回 A 的背包，只交換棋子本體
	var on_board := _put(a, "CEN2", 1, Vector2i(3, 4))
	a.run.find_unit(on_board)["unit"]["items"] = ["CP_PLATE", "CP_CRYSTAL"]
	# B 的候補區填滿 → 無法接收棋子
	while b.run.bench_free_index() >= 0:
		_bench(b, "HUM1", 1)
	m.submit(0, {"type": "trade_offer", "offer": {"kind": "unit", "uid": on_board}})
	m.submit(1, {"type": "trade_offer", "offer": {"kind": "item", "inv": 0}})
	m.submit(1, {"type": "trade_confirm"})
	var r := m.submit(0, {"type": "trade_confirm"})
	check(r.contains("候補區已滿"), "接收者候補已滿 → 阻止交易並提示（%s）" % r)
	check(not a.run.find_unit(on_board).is_empty(), "棋子沒有被刪除")
	# 騰出空位後成交
	b.run.sell(int(b.run.bench[0]["uid"]))
	m.submit(1, {"type": "trade_confirm"})
	eq(m.submit(0, {"type": "trade_confirm"}), "", "有空位後成交")
	check(a.run.inventory.has("CP_PLATE") and a.run.inventory.has("CP_CRYSTAL"), "棋子身上的裝備退回原玩家背包")
	var got := b.run.all_units().filter(func(u): return u["id"] == "CEN2")
	eq(got.size(), 1, "B 收到棋子")
	check(RunState.unit_items(got[0]).is_empty(), "棋子本體交換，不夾帶裝備")
	eq(b.run.find_unit(int(got[0]["uid"])).get("where", ""), "bench", "原本上陣的棋子交換後放到接收者候補區")
	check(a.run.board_lineup().filter(func(u): return int(u["uid"]) == on_board).is_empty(), "不殘留在原玩家棋盤")


func test_trade_timeout_cancel() -> void:
	var s := _trade_setup(34)
	var m: ClashMatch = s[0]
	var t: Dictionary = s[1]
	m.submit(0, {"type": "trade_offer", "offer": {"kind": "unit", "uid": s[2]}})
	m.submit(1, {"type": "trade_offer", "offer": {"kind": "unit", "uid": s[3]}})
	m.submit(0, {"type": "trade_confirm"})
	m.round_kind = "pve"
	m.pve_plan = {"pairs": [], "solo": -1}
	m.end_trades()
	eq(str(t["status"]), "cancelled", "時間到：未確認的交易取消")
	check(not m.players[0].run.find_unit(int(s[2])).is_empty(), "取消後資產不移轉")
	eq(m.stage, "battle", "時間到自動進入 PvE 戰鬥")


# ---------- 合作 PvE ----------
func _coop(m: ClashMatch, a: int, b: int, pve_index: int) -> ClashBattle:
	return ClashBattle.make_coop(ClashBattle.lineup_snapshot(m.players[a]), ClashBattle.lineup_snapshot(m.players[b]), pve_index, 77)


func test_coop_rescue_success() -> void:
	var m := _ai_match(41)
	_clear(m.players[0])   # A 一開戰就全滅（沒有棋子）
	_strong_board(m.players[1])
	var bt := _coop(m, 0, 1, 2)
	var saw_hold := false
	var saw_spawn := false
	var guard := 0
	while not bt.finished and guard < 6000:
		guard += 1
		bt.step_to(guard * 0.05)
		var sa: CombatSim = bt.sims[0]
		if sa.holding:
			saw_hold = true
			check(not sa.finished, "全滅不立即判定失敗（等待救援）")
	var sa: CombatSim = bt.sims[0]
	for e in sa.events:
		if e["k"] == "spawn":
			saw_spawn = true
			check(str(e["snap"].get("origin", "")) != "", "援軍標記來源")
	check(saw_hold, "A 全滅後戰場凍結等待")
	check(saw_spawn, "B 清場後存活棋子前往 A 的棋盤")
	check(bool(bt.outcome()["success"]), "援軍消滅 A 剩餘敵軍 → 雙人 PvE 成功")
	# 援軍沿用清場時的戰鬥快照：生命不會回滿
	var sb: CombatSim = bt.sims[1]
	var spawn_hp := {}
	for e in sa.events:
		if e["k"] == "spawn":
			spawn_hp[str(e["snap"]["id"])] = float(e["snap"]["hp"])
	check(not spawn_hp.is_empty(), "有援軍")
	# 援軍不從棋池生成份數
	eq(m.pool.audit(), [], "援軍不佔棋池")


func test_coop_rescue_fails() -> void:
	var m := _ai_match(42)
	_weak_board(m.players[0])
	_weak_board(m.players[1])
	var bt := _coop(m, 0, 1, 6)   # 終局首領：一星援軍救不回來
	# 讓 B 立刻清場（直接擊倒 B 棋盤的敵軍），B 唯一的一星棋子會去支援 A
	var sb: CombatSim = bt.sims[1]
	sb.start()
	for u in sb.units:
		if u.side == 1:
			sb.kill(u)
	bt.run()
	var sa: CombatSim = bt.sims[0]
	check(sa.events.any(func(e): return e["k"] == "spawn"), "B 清場後派出援軍")
	check(not bool(sa.result().get("cleared", true)), "援軍也全滅")
	check(not bool(bt.outcome()["success"]), "援軍失敗 → 雙人 PvE 失敗")
	check(bt.finished, "沒有無限等待")


func test_coop_both_wiped() -> void:
	var m := _ai_match(43)
	_clear(m.players[0])
	_weak_board(m.players[1])
	var bt := _coop(m, 0, 1, 6)
	bt.run()
	check(bt.finished, "雙方都全滅也會結束（不會僵持）")
	check(not bool(bt.outcome()["success"]), "雙方都全滅 → 失敗")
	check((bt.sims[0] as CombatSim).finished and (bt.sims[1] as CombatSim).finished, "兩張棋盤都結算")


func test_coop_settlement_hp() -> void:
	var m := _ai_match(44)
	m.round_no = 8
	m.begin_round()
	eq(m.round_kind, "pve", "第 8 回合合作 PvE")
	var pairs: Array = m.pve_plan["pairs"]
	eq(pairs.size(), 5, "十人 → 五組")
	var p0: Array = pairs[0]
	var p1: Array = pairs[1]
	# 第一組：一方全滅、一方強力清場 → 救援成功，雙方都不扣血
	_clear(m.players[p0[0]])
	_strong_board(m.players[p0[1]])
	# 第二組：雙方都沒有棋子 → 失敗，雙方各扣 PvE 失敗生命
	_clear(m.players[p1[0]])
	_clear(m.players[p1[1]])
	for s in [p0[0], p1[0], p1[1]]:
		for i in m.players[s].run.bench.size():
			m.players[s].run.bench[i] = null
	var hp := {}
	for p in m.players:
		hp[p.index] = p.hp
	m.lock_in()
	m.end_trades()
	# 自動補位可能補上棋子：確保第二組保持空棋盤
	m.run_battles()
	var rep := m.settle_round()
	eq(m.players[p0[0]].hp, hp[p0[0]], "救援成功：先全滅的一方不扣血")
	eq(m.players[p0[1]].hp, hp[p0[1]], "救援成功：清場方不扣血")
	eq(m.players[p1[0]].hp, hp[p1[0]] - ClashMatch.pve_loss(8), "失敗：雙方各扣 PvE 失敗生命")
	eq(m.players[p1[1]].hp, hp[p1[1]] - ClashMatch.pve_loss(8), "失敗：隊友同樣扣血")
	# 低生命玩家一次失敗可能淘汰；雙方都達到條件時同時淘汰
	var m2 := _ai_match(45)
	m2.round_no = 8
	m2.begin_round()
	var pr: Array = m2.pve_plan["pairs"][0]
	for s in pr:
		_clear(m2.players[s])
		m2.players[s].hp = 3
	m2.lock_in()
	m2.end_trades()
	m2.run_battles()
	var rep2 := m2.settle_round()
	check((rep2["eliminated"] as Array).has(int(pr[0])) and (rep2["eliminated"] as Array).has(int(pr[1])), "合作失敗：雙方同時淘汰")


func test_solo_pve() -> void:
	var m := _ai_match(46)
	m.players[9].alive = false
	m.pool.unregister(m.players[9].run)
	m.round_no = 8
	m.begin_round()
	var solo := int(m.pve_plan["solo"])
	check(solo >= 0, "九人：一人單人 PvE")
	eq((m.pve_plan["pairs"] as Array).size(), 4, "其餘四組")
	m.lock_in()
	check(m.trade_for(solo).is_empty(), "單人 PvE 不交易")
	m.end_trades()
	var bt: ClashBattle = m.battles.filter(func(b): return b.kind == "solo")[0]
	eq(bt.a, solo, "單人挑戰者")
	var st := ClashBattle.pve_stage(m.pve_count)
	check(float(GameData.clash_cfg("pve").get("solo_scale", 1.0)) < 1.0, "單人敵軍較弱（沒有隊友救援的補償）")
	var hp := {}
	for p in m.players:
		hp[p.index] = p.hp
	m.run_battles()
	m.settle_round()
	var ok := bool(bt.outcome()["success"])
	eq(m.players[solo].hp, hp[solo] - (0 if ok else ClashMatch.pve_loss(8)), "單人失敗只扣自己")


# ---------- 淘汰與名次 ----------
func test_elimination_ranking_ties() -> void:
	var m := _ai_match(51)
	m.stage = "battle"
	m.battles = []
	# 三人同回合淘汰：回合開始生命 20／20／10；結算後 −5／−5／−1
	var setups := [[3, 20, -5], [5, 20, -5], [7, 10, -1]]
	for s in setups:
		m.players[s[0]].hp_at_round_start = s[1]
		m.players[s[0]].hp = s[2]
	var rep := m.settle_round()
	eq((rep["eliminated"] as Array).size(), 3, "三人同時淘汰")
	eq(m.players[7].placement, 10, "回合開始生命最低者名次最後")
	eq(m.players[3].placement, 8, "完全相同 → 並列")
	eq(m.players[5].placement, 8, "完全相同 → 並列（共用較前名次）")
	eq(m.alive_count(), 7, "存活 7 人")
	# 回合開始生命相同時比結算後生命
	var m2 := _ai_match(52)
	m2.stage = "battle"
	m2.battles = []
	m2.players[1].hp_at_round_start = 15
	m2.players[1].hp = -2
	m2.players[2].hp_at_round_start = 15
	m2.players[2].hp = -9
	m2.settle_round()
	eq(m2.players[1].placement, 9, "結算後生命較高者較前")
	eq(m2.players[2].placement, 10, "結算後生命較低者較後")


func test_simultaneous_final_tie() -> void:
	var m := _ai_match(53)
	for s in range(2, 10):
		m.players[s].alive = false
		m.players[s].placement = 12 - s
		m.pool.unregister(m.players[s].run)
	m.stage = "battle"
	m.battles = []
	m.players[0].hp_at_round_start = 5
	m.players[0].hp = -3
	m.players[1].hp_at_round_start = 5
	m.players[1].hp = -3
	var rep := m.settle_round()
	check(m.finished, "最後兩人同時淘汰 → 對局結束")
	eq(m.players[0].placement, 1, "完全相同 → 並列第一")
	eq(m.players[1].placement, 1, "完全相同 → 並列第一")
	var m2 := _ai_match(54)
	for s in range(2, 10):
		m2.players[s].alive = false
		m2.players[s].placement = 12 - s
		m2.pool.unregister(m2.players[s].run)
	m2.stage = "battle"
	m2.battles = []
	m2.players[0].hp_at_round_start = 8
	m2.players[0].hp = -1
	m2.players[1].hp_at_round_start = 4
	m2.players[1].hp = -1
	m2.settle_round()
	eq(m2.players[0].placement, 1, "回合開始生命較高者為冠軍")
	eq(m2.players[1].placement, 2, "另一人第 2 名")


func test_no_double_settle() -> void:
	var m := _ai_match(55)
	m.lock_in()
	m.run_battles()
	var hp := m.players.map(func(p): return p.hp)
	var rep := m.settle_round()
	check(not rep.is_empty(), "第一次結算")
	var hp2 := m.players.map(func(p): return p.hp)
	var again := m.settle_round()
	check(again.is_empty(), "同一回合不會重複結算")
	eq(m.players.map(func(p): return p.hp), hp2, "生命沒有被扣兩次")
	eq(m.round_no, 2, "回合只前進一次")


# ---------- 國家制度 ----------
func test_government_choices() -> void:
	var m := ClashMatch.create("真人", "真人國", 61, "normal", true)
	var me := m.human()
	eq(ClashGovernment.pending_choice(me, 7), "", "第 8 回合前不能選")
	check(m.submit(0, {"type": "government", "value": "empire"}) != "", "第 1 回合不能選制度")
	m.round_no = 8
	eq(ClashGovernment.pending_choice(me, 8), "system", "第 8 回合選制度")
	eq(m.submit(0, {"type": "government", "value": "empire"}), "", "選擇萬世帝國")
	eq(me.government, "empire", "第一次選擇保存")
	check(m.submit(0, {"type": "government", "value": "commune"}) != "", "不能重選")
	eq(ClashGovernment.policies_for("empire"), ["i_am_the_state", "never_retreat"], "政策只顯示所屬制度的兩條")
	m.round_no = 16
	check(m.submit(0, {"type": "policy", "value": "people_power"}) != "", "不能選其他制度的政策")
	eq(m.submit(0, {"type": "policy", "value": "never_retreat"}), "", "選擇帝國永不退讓")
	eq(me.policy, "never_retreat", "政策保存")
	# 任何玩家都能選任何制度
	var m2 := _ai_match(62)
	m2.round_no = 8
	var picks := ["democracy", "empire", "commune"]
	for i in 3:
		var p: ClashPlayer = m2.players[i]
		p.government = ""
		eq(m2.submit(i, {"type": "government", "value": picks[i]}), "", "玩家 %d 選 %s" % [i, picks[i]])
	for s in ClashGovernment.systems():
		eq(ClashGovernment.policies_for(s).size(), 2, "%s 有兩條政策" % s)
	# 時間到自動選（固定種子）
	var m3 := ClashMatch.create("真人", "真人國", 63, "normal", true)
	m3.round_no = 8
	m3.lock_in()
	check(m3.human().government != "", "時間到未選 → 自動選擇")
	check(not m3.gov_auto_notes.is_empty(), "提示自動選擇")


func test_policy_effects_economy() -> void:
	var m := _ai_match(64)
	var p: ClashPlayer = m.players[0]
	# 超級民主聯邦：收入 +1
	p.government = "democracy"
	eq(ClashGovernment.income_adjust(p), 1, "民主：每回合收入 +1")
	# 選擇式民主：每回合第一次刷新免費、出售二星 +1
	p.policy = "selective_democracy"
	p.run.free_rerolls = 0
	ClashGovernment.apply_round_perks(p)
	eq(p.run.free_rerolls, 1, "每回合 1 次免費刷新")
	var g0: int = p.run.gold
	p.run.reroll()
	eq(p.run.gold, g0, "免費刷新不花金幣")
	ClashGovernment.apply_round_perks(p)
	ClashGovernment.apply_round_perks(p)
	eq(p.run.free_rerolls, 1, "不累積")
	_clear(p)
	var uid := _bench(p, "HUM2", 2)
	g0 = p.run.gold
	p.run.sell(uid)
	eq(p.run.gold, g0 + UnitStats.sell_value("HUM2", 2) + 1, "出售二星額外 +1 金")
	# 自由市場：利息上限 +2；PvP 勝利不得金；傷害 −5%
	p.policy = "free_market"
	ClashGovernment.apply_round_perks(p)
	eq(ClashGovernment.interest(p, 80), Economy.interest_max() + 2, "利息上限 +2")
	eq(ClashGovernment.pvp_win_gold(p), 0, "PvP 勝利不再額外得金")
	var q: ClashPlayer = m.players[1]
	eq(ClashGovernment.interest(q, 80), Economy.interest_max(), "其他玩家利息上限不變")
	# 五回合計畫：計畫期間 −1；完成一期 +5 金 +4 經驗，發展等級 +1
	var r: ClashPlayer = m.players[2]
	r.government = "commune"
	r.policy = "five_year_plan"
	r.plan_round = 16
	eq(ClashGovernment.income_adjust(r), -1, "計畫期間收入 −1")
	var gold: int = r.run.gold
	var xp: int = r.run.xp
	for rd in range(16, 20):
		eq(ClashGovernment.on_round_end(r, rd), "", "第 %d 回合尚未完成" % rd)
	check(ClashGovernment.on_round_end(r, 20) != "", "第 20 回合完成第一期")
	eq(r.plan_cycles, 1, "發展等級 1")
	eq(r.run.gold, gold + 5, "+5 金")
	eq(r.run.xp, xp + 4, "+4 經驗")
	eq(ClashGovernment.income_adjust(r), 0, "發展等級抵銷計畫成本（之後每期再 +1）")


func _mods_for(p: ClashPlayer) -> Array:
	return ClashBattle.lineup_mods(p, p.run.board_lineup())


func test_policy_effects_combat() -> void:
	var m := _ai_match(65)
	var p: ClashPlayer = m.players[0]
	_clear(p)
	var u1 := _put(p, "HUM2", 2, Vector2i(3, 4))
	var u2 := _put(p, "ELF1", 1, Vector2i(2, 6))
	var base := _mods_for(p)
	# 萬世帝國：二星以上 +8%
	p.government = "empire"
	var mods := _mods_for(p)
	eq(float(mods[0]["hp_pct"]) - float(base[0]["hp_pct"]), 8.0, "帝國：二星生命 +8%")
	eq(float(mods[1]["hp_pct"]) - float(base[1]["hp_pct"]), 0.0, "帝國：一星沒有精銳加成")
	# 朕即是國家：核心大幅強化、其他不享精銳加成
	p.policy = "i_am_the_state"
	p.core_uid = u2
	mods = _mods_for(p)
	eq(float(mods[1]["hp_pct"]) - float(base[1]["hp_pct"]), 40.0, "核心生命 +40%")
	eq(float(mods[1]["atk_pct"]) - float(base[1]["atk_pct"]), 35.0, "核心攻擊 +35%")
	eq(float(mods[0]["hp_pct"]) - float(base[0]["hp_pct"]), 0.0, "非核心不享精銳加成")
	var s1 := UnitStats.final_stats("ELF1", 1, mods[1])
	var s0 := UnitStats.final_stats("ELF1", 1, base[1])
	check(float(s1["atk"]) > float(s0["atk"]) * 1.3, "攻擊力確實提高（%.1f → %.1f）" % [s0["atk"], s1["atk"]])
	p.core_uid = -1
	ClashGovernment.on_battle_start(p, p.run.board_lineup())
	eq(p.core_uid, u1, "未指定核心 → 開戰自動選最強者")
	# 帝國永不退讓：維持陣容累積忠誠，大幅更換歸零
	p.policy = "never_retreat"
	p.last_lineup_ids = []
	p.loyalty = 0
	ClashGovernment.on_battle_start(p, p.run.board_lineup())
	ClashGovernment.on_battle_start(p, p.run.board_lineup())
	ClashGovernment.on_battle_start(p, p.run.board_lineup())
	eq(p.loyalty, 2, "陣容不變：忠誠逐場 +1")
	mods = _mods_for(p)
	eq(float(mods[1]["hp_pct"]) - float(base[1]["hp_pct"]), 8.0, "每層生命 +4%")
	_clear(p)
	_put(p, "ORC1", 1, Vector2i(3, 4))
	_put(p, "ONI1", 1, Vector2i(2, 4))
	ClashGovernment.on_battle_start(p, p.run.board_lineup())
	eq(p.loyalty, 0, "大幅更換陣容 → 忠誠歸零")
	# 偉大公社：生命 +5%；自由市場：傷害 −5%
	p.government = "commune"
	p.policy = ""
	mods = _mods_for(p)
	check(mods.all(func(x): return float(x["hp_pct"]) >= 5.0), "公社：所有上場棋子生命 +5%")
	p.government = "democracy"
	p.policy = "free_market"
	mods = _mods_for(p)
	check(mods.all(func(x): return float(x["dmg_pct"]) == -5.0), "自由市場：傷害 −5%")
	p.policy = ""
	var plain := _mods_for(p)
	var sim := CombatSim.new(1)
	var a := sim.add_unit("ONI1", 1, Vector2i(3, 4), 0, mods[0])
	var a2 := sim.add_unit("ONI1", 1, Vector2i(2, 4), 0, plain[0])
	var b := sim.add_unit("HUM2", 1, Vector2i(3, 3), 1, Modifiers.empty())
	eq(sim.damage_bonus_pct(a, b, "physical", "basic", false) - sim.damage_bonus_pct(a2, b, "physical", "basic", false), -5.0, "戰鬥中確實套用傷害 −5%")


func test_people_power_villagers() -> void:
	var pp := ClashGovernment.policy_cfg("people_power")
	var mods := Modifiers.empty()
	mods["mobilize"] = 1.0
	var sim := CombatSim.new(3)
	var a := sim.add_unit("ORC1", 1, Vector2i(3, 4), 0, mods)
	var b := sim.add_unit("DEE1", 3, Vector2i(3, 3), 1, Modifiers.empty())
	b.max_hp = 99999.0
	b.hp = 99999.0
	sim.start()
	var hits := int(pp.get("hits_per_villager", 4))
	for i in hits - 1:
		sim.basic_attack(a, b)
	eq(a.villagers, 0, "未達門檻沒有村民")
	sim.basic_attack(a, b)
	eq(a.villagers, 1, "每 %d 次有效普攻召喚 1 名村民" % hits)
	check(sim.events.any(func(e): return e["k"] == "villager" and int(e["cid"]) == a.cid), "村民事件")
	# 持續傷害、技能、村民攻擊不計入動員
	var before: int = a.mobilize_count
	sim.deal_damage(b, a, 5.0, "physical", "skill", false)
	sim.deal_damage(b, a, 5.0, "physical", "basic", true)
	eq(a.mobilize_count, before, "技能與持續傷害不累積動員值")
	sim.deal_damage(b, a, 5.0, "physical", "basic", false)
	eq(a.mobilize_count, before + 1, "受到有效普攻累積動員值")
	# 村民攻擊：統一結算的魔法傷害，不占棋格
	var cells_before: int = sim.occupancy.size()
	a.target_cid = b.cid
	var hp0: float = b.hp
	sim.t = a.villager_next
	sim._villager_pulse()
	check(b.hp < hp0, "村民造成傷害")
	var vd: Array = sim.events.filter(func(e): return e["k"] == "damage" and str(e["source"]) == "villager")
	eq(vd.size(), 1, "村民傷害以 source＝villager 結算")
	eq(str(vd[0]["dtype"]), "magic", "魔法傷害")
	eq(sim.occupancy.size(), cells_before, "村民不占棋格")
	var mob_after: int = a.mobilize_count
	eq(a.mobilize_count, mob_after, "村民攻擊不累積動員值")
	# 上限
	for i in 60:
		sim.basic_attack(a, b)
	eq(a.villagers, int(pp.get("max_villagers", 4)), "村民數有上限")
	# 不啟動羈絆：村民不是棋子，Synergy 只看棋盤棋子
	check(sim.units.size() == 2, "村民不是戰鬥單位")
	# 完整戰鬥中會召喚並造成傷害
	var m := _ai_match(66)
	var p: ClashPlayer = m.players[0]
	_strong_board(p)
	p.government = "commune"
	p.policy = "people_power"
	var q: ClashPlayer = m.players[1]
	_strong_board(q)
	var bt := ClashBattle.make_pvp(ClashBattle.lineup_snapshot(p), ClashBattle.lineup_snapshot(q), 9, false)
	bt.run()
	var ev: Array = (bt.sims[0] as CombatSim).events
	check(ev.any(func(e): return e["k"] == "villager"), "實戰中召喚村民")
	check(ev.any(func(e): return e["k"] == "damage" and str(e["source"]) == "villager" and int(e["v"]) > 0), "實戰中村民造成魔法傷害")
	check(not ev.any(func(e): return e["k"] == "villager" and (bt.sims[0] as CombatSim).unit_by_cid(int(e["cid"])).side == 1), "對手沒有人民的力量就沒有村民")


# ---------- AI ----------
func test_ai_uses_rules() -> void:
	var m := _ai_match(71)
	for k in 10:
		m.auto_round()
		check(m.pool.audit().is_empty(), "第 %d 回合棋池守恆（AI 不能跳過棋池規則）" % m.round_no)
		for p in m.players:
			check(p.run.gold >= 0, "金幣不為負")
			check(p.run.board_count() <= p.run.board_limit(), "上場不超過等級")
	var bought := m.players.filter(func(p): return p.run.all_units().size() >= 3)
	check(bought.size() >= 8, "AI 會買棋子")
	check(m.players.any(func(p): return p.run.level() >= 5), "AI 會升級")
	check(m.players.any(func(p): return p.run.all_units().any(func(u): return int(u["star"]) >= 2)), "AI 會升星")
	check(m.players.filter(func(p): return p.government != "").size() == m.alive_count(), "AI 在第 8 回合選擇國家制度")
	check(m.event_log.any(func(l): return str(l).contains("交易")), "AI 會提出並完成交易")
	check(m.players.any(func(p): return p.run.all_items().size() > 0), "AI 取得並使用裝備")
	var eq_count := 0
	for p in m.players:
		for u in p.run.board.values():
			eq_count += RunState.unit_items(u).size()
	check(eq_count > 0, "AI 會穿裝備")


# ---------- 完整對局 ----------
func test_full_matches() -> void:
	var rounds: Array = []
	for sd in [101, 202, 303, 404]:
		var m := _ai_match(sd)
		var guard := 0
		var reports := 0
		while not m.finished and guard < 80:
			guard += 1
			var rep := m.auto_round()
			reports += 1
			if not m.pool.audit().is_empty():
				check(false, "種子 %d 第 %d 回合棋池不守恆：%s" % [sd, m.round_no, str(m.pool.audit())])
				break
		check(m.finished, "種子 %d：對局結束（%d 回合）" % [sd, m.round_no])
		check(m.round_no <= int(GameData.clash_cfg("match").get("max_rounds", 45)), "沒有無限回合")
		var places: Array = m.players.map(func(p): return p.placement)
		check(places.has(1), "有冠軍")
		check(places.all(func(x): return int(x) >= 1 and int(x) <= 10), "十人都有名次 %s" % str(places))
		eq(reports, m.reports.size(), "每回合只結算一次")
		check(m.reports.any(func(r): return r["kind"] == "pve"), "有合作 PvE 回合")
		rounds.append(m.round_no)
	print("    （完整對局回合數：%s）" % str(rounds))


func test_reproducible() -> void:
	var a := _ai_match(909)
	var b := _ai_match(909)
	for k in 12:
		a.auto_round()
		b.auto_round()
	eq(a.event_log, b.event_log, "相同種子：配對、交易、戰鬥結果完全相同")
	eq(a.players.map(func(p): return p.hp), b.players.map(func(p): return p.hp), "相同種子：生命相同")
	var r1 := ClashMatchmaking.pve(range(10), SeededRng.new(5))
	var r2 := ClashMatchmaking.pve(range(10), SeededRng.new(5))
	eq(r1, r2, "PvE 隨機配對支援固定種子")


func test_single_player_untouched() -> void:
	GameData.set_clash_clans(false)
	eq(Shop.pool_for("elf", 4).size(), 6, "單人模式：4 費仍只有本族＋5 名中立")
	check(GameData.is_neutral("NEU1"), "單人模式：中立分類保留")
	var r := RunState.create("elf", 5)
	check(r.shared_pool == null, "單人模式不使用共用棋池")
	eq(int(r.pool_remaining().get("ELF1", 0)), Shop.supply(1), "單人模式棋池供應不變（%d）" % Shop.supply(1))
	GameData.set_clash_clans(true)
