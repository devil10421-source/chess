extends SceneTree
## 《六族遠征》自動測試。執行方式（專案根目錄）：
##   godot --headless --path . --script res://tests/run_tests.gd
## 全部通過時結束碼為 0，否則為 1。

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	SaveSystem.path_override = "user://test_save.json"
	var tests := [
		"test_scripts_and_scenes_load",
		"test_data_integrity",
		"test_hex_grid",
		"test_shop_odds",
		"test_shop_pool",
		"test_economy",
		"test_levels",
		"test_buy_sell_and_gold",
		"test_merge",
		"test_board_limit_and_moves",
		"test_synergy_counting",
		"test_modifiers",
		"test_star_stats",
		"test_expedition_loss",
		"test_settlement_order",
		"test_victory_conditions",
		"test_human_free_reroll",
		"test_shop_lock",
		"test_combat_determinism",
		"test_combat_no_overlap",
		"test_all_skills_trigger",
		"test_ranged_vs_melee",
		"test_save_roundtrip",
		"test_defense_formula",
		"test_front_line_protection",
		"test_flank_breakthrough",
		"test_assassin_and_taunt",
		"test_target_lock",
		"test_round1_all_units_win",
		"test_three_star_exclusion",
		"test_auto_fill",
		"test_interest_ui_data",
		"test_oni_skill_dot",
		"test_playback_clock",
		"test_prep_timer",
		"test_stat_breakdown",
		"test_contribution_stats",
		"test_leaderboard_rows",
		"test_trait_detail",
		"test_v01_save_compat",
		"test_race_traits_234",
		"test_equipment_basic",
		"test_equipment_merge_and_sell",
		"test_equipment_passives",
		"test_equipment_rewards",
		"test_save_v2_and_migration",
		"test_otherworld_enemies",
		"test_live_stats_match",
		"test_bench_during_battle",
		"test_penetration",
		"test_wound",
		"test_slow_rules",
		"test_dot_unified",
		"test_archer_retreat",
		"test_no_armor_down_left",
		"test_full_runs",
	]
	for name in tests:
		_current = name
		var before := _failed
		call(name)
		print(("  ✓ " if _failed == before else "  ✗ ") + name)
	SaveSystem.clear()
	print("")
	print("測試結果：%d 項斷言通過，%d 項失敗" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("    [失敗] %s：%s" % [_current, msg])


func eq(a: Variant, b: Variant, msg: String) -> void:
	check(a == b, "%s（實際 %s，預期 %s）" % [msg, str(a), str(b)])


# ------------------------------------------------------------
func test_scripts_and_scenes_load() -> void:
	for dir in ["res://scripts/core", "res://scripts/core/combat", "res://scripts/ui", "res://scripts/autoload"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var path: String = dir + "/" + f
			var s = load(path)
			check(s != null and s is GDScript and s.can_instantiate(), "腳本無法載入或有解析錯誤：" + path)
	for f in DirAccess.get_files_at("res://scenes"):
		if not f.ends_with(".tscn"):
			continue
		var path := "res://scenes/" + f
		var ps = load(path)
		check(ps is PackedScene, "場景無法載入：" + path)
		if ps is PackedScene:
			check(ps.can_instantiate(), "場景無法實例化：" + path)
	check(ResourceLoader.exists(ProjectSettings.get_setting("application/run/main_scene")), "主場景不存在")


func test_data_integrity() -> void:
	eq(GameData.units().size(), 24, "棋子數量")
	var per_race := {}
	var ids := {}
	for u in GameData.units():
		ids[u["id"]] = true
		var key := "%s-%d" % [u["race"], int(u["cost"])]
		per_race[key] = int(per_race.get(key, 0)) + 1
		check(SkillRunner.KINDS.has(u["skill"]["kind"]), "技能種類未實作：" + str(u["id"]))
		check(GameData.cfg("classes").has(u["class"]), "未知職業：" + str(u["id"]))
		check(GameData.traits()["type"].has(u["type"]), "未知類型：" + str(u["id"]))
		check(GameData.traits()["race"].has(u["race"]), "未知種族：" + str(u["id"]))
	eq(ids.size(), 24, "棋子 id 不重複")
	for race in ["elf", "human", "orc", "centaur", "deer", "oni"]:
		for cost in [1, 2, 3, 4]:
			eq(int(per_race.get("%s-%d" % [race, cost], 0)), 1, "%s 的 %d 費棋子數" % [race, cost])
	eq(GameData.civs().size(), 6, "文明數量")
	for c in GameData.civs():
		eq(c["buffs"].size(), 2, "%s Buff 數" % c["id"])
		eq(c["debuffs"].size(), 2, "%s Debuff 數" % c["id"])
	eq(GameData.stages().size(), 24, "關卡數量")
	for r in range(1, 25):
		var st := GameData.stage(r)
		check(not st.is_empty(), "缺少第 %d 關" % r)
		var used := {}
		for e in st.get("units", []):
			var cell := Vector2i(int(e["col"]), int(e["row"]))
			check(HexGrid.is_enemy_cell(cell), "第 %d 關站位超出敵方區域 %s" % [r, str(cell)])
			check(not used.has(cell), "第 %d 關站位重疊 %s" % [r, str(cell)])
			used[cell] = true
			check(GameData.has_unit(str(e["id"])), "第 %d 關未知棋子 %s" % [r, e["id"]])
			check(int(e["star"]) >= 1 and int(e["star"]) <= 3, "第 %d 關星級錯誤" % r)
	for r in [6, 12, 18, 24]:
		check(bool(GameData.stage(r).get("boss", false)), "第 %d 關標示為首領戰" % r)
		check(str(GameData.stage(r).get("faction", "")) != "", "首領關 %d 由異界敵軍擔任" % r)


func test_hex_grid() -> void:
	eq(HexGrid.all_cells().size(), 56, "7×8 格數")
	eq(HexGrid.player_cells().size(), 28, "玩家 28 格")
	eq(HexGrid.distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "同格距離")
	eq(HexGrid.distance(Vector2i(3, 3), Vector2i(3, 4)), 1, "上下相鄰距離 1")
	eq(HexGrid.distance(Vector2i(0, 0), Vector2i(6, 0)), 6, "同排距離")
	eq(HexGrid.distance(Vector2i(0, 0), Vector2i(0, 7)), 7, "直排距離（六角格非曼哈頓）")
	for c in HexGrid.all_cells():
		for n in HexGrid.neighbors(c):
			eq(HexGrid.distance(c, n), 1, "鄰格距離必為 1")
		check(HexGrid.neighbors(c).size() <= 6, "鄰格最多 6 個")
	eq(HexGrid.neighbors(Vector2i(3, 3)).size(), 6, "中間格有 6 鄰格")
	var line := HexGrid.line(Vector2i(0, 7), Vector2i(6, 0))
	eq(line.size(), HexGrid.distance(Vector2i(0, 7), Vector2i(6, 0)) + 1, "直線格數")
	# 像素互轉
	for c in HexGrid.all_cells():
		eq(HexGrid.from_pixel(HexGrid.to_pixel(c, 30.0), 30.0), c, "像素座標互轉")
	# 找路會繞過阻擋
	var blocked := {Vector2i(3, 4): true, Vector2i(2, 4): true, Vector2i(4, 4): true}
	var path := HexGrid.find_path_step(Vector2i(3, 5), {Vector2i(3, 3): true}, blocked)
	check(not path.is_empty(), "可繞路")
	check(not blocked.has(path.get("step", Vector2i(-1, -1))), "第一步不可踩在阻擋格")


func test_shop_odds() -> void:
	for lv in range(1, 11):
		var odds := Shop.odds_for_level(lv)
		eq(odds.size(), 4, "Lv.%d 機率欄數" % lv)
		var total := 0
		for o in odds:
			total += int(o)
		eq(total, 100, "Lv.%d 機率總和" % lv)


func test_shop_pool() -> void:
	for c in GameData.civs():
		var civ := str(c["id"])
		var pool := Shop.full_pool(civ)
		eq(pool.size(), 19, "%s 可抽棋子種類" % civ)
		var fours := Shop.pool_for(civ, 4)
		eq(fours.size(), 1, "%s 只有 1 種 4 費" % civ)
		eq(GameData.unit(fours[0])["race"], c["race"], "%s 的 4 費必為本族" % civ)
		var rng := SeededRng.new(42)
		var seen_four := false
		for i in 3000:
			var id := Shop.roll_slot(rng, 10, civ)
			check(pool.has(id), "抽到池外棋子 " + id)
			if GameData.unit_cost(id) == 4:
				seen_four = true
				check(GameData.unit(id)["race"] == c["race"], "外族 4 費出現在商店")
		check(seen_four, "%s 在 Lv.10 應能抽到本族 4 費" % civ)
		for i in 500:
			eq(GameData.unit_cost(Shop.roll_slot(rng, 1, civ)), 1, "Lv.1 只出 1 費")
		for i in 500:
			check(GameData.unit_cost(Shop.roll_slot(rng, 5, civ)) <= 3, "Lv.5 不出 4 費")
	var run := RunState.create("elf", 1)
	run.begin_round()
	eq(run.shop.size(), 5, "商店 5 格")


func test_economy() -> void:
	eq(Economy.interest(0), 0, "利息 0")
	eq(Economy.interest(9), 0, "利息 9 金")
	eq(Economy.interest(10), 1, "利息 10 金")
	eq(Economy.interest(19), 1, "利息 19 金")
	eq(Economy.interest(20), 2, "利息 20 金")
	eq(Economy.interest(29), 2, "利息 29 金")
	eq(Economy.interest(30), 3, "利息 30 金 +3（V0.2）")
	eq(Economy.interest(99), 3, "利息上限 3（V0.2）")
	eq(Economy.sell_value(3, 1), 3, "1 星出售")
	eq(Economy.sell_value(3, 2), 9, "2 星出售 = 3×cost")
	eq(Economy.sell_value(3, 3), 27, "3 星出售 = 9×cost")


func test_levels() -> void:
	eq(Economy.level_for_xp(0), 1, "0 XP = Lv.1")
	eq(Economy.level_for_xp(1), 1, "1 XP = Lv.1")
	eq(Economy.level_for_xp(2), 2, "2 XP = Lv.2")
	eq(Economy.level_for_xp(6), 3, "6 XP = Lv.3")
	eq(Economy.level_for_xp(46), 7, "23 回合自然 XP 46 = Lv.7")
	eq(Economy.level_for_xp(89), 9, "89 XP = Lv.9")
	eq(Economy.level_for_xp(90), 10, "90 XP = Lv.10")
	eq(Economy.level_for_xp(500), 10, "最高 Lv.10")
	eq(90 - 46, 44, "企劃驗證例：差 44 XP")
	var run := RunState.create("orc", 3)
	run.gold = 100
	for i in 30:
		run.buy_xp()
	eq(run.level(), 10, "買 XP 可到 Lv.10")
	check(run.buy_xp() != "", "滿級不能再買 XP")
	eq(run.board_limit(), 10, "Lv.10 上場上限 10")


func test_buy_sell_and_gold() -> void:
	var run := RunState.create("elf", 5)
	run.shop = ["ORC1", "ELF2", "HUM3", "ELF4", "ONI1"]
	run.gold = 3
	eq(run.buy(3), "金幣不足", "4 費買不起")
	eq(run.gold, 3, "失敗不扣錢")
	eq(run.buy(0), "", "買 1 費")
	eq(run.gold, 2, "扣 1 金")
	eq(run.buy(1), "", "買 2 費")
	eq(run.gold, 0, "扣 2 金")
	check(run.gold >= 0, "金幣不為負")
	eq(run.reroll(), "金幣不足", "沒錢不能刷新")
	eq(run.buy(1), "這格沒有棋子", "已購買的格子不能再買")
	var uid := int(run.bench[0]["uid"])
	eq(run.sell(uid), "", "出售")
	eq(run.gold, 1, "出售回收 1 金")
	check(run.find_unit(uid).is_empty(), "出售後棋子消失")
	# 候補滿時不可買（無法合成）
	var full := RunState.create("elf", 6)
	full.gold = 100
	for i in full.bench.size():
		full.bench[i] = {"uid": 100 + i, "id": "HUM1", "star": 2}
	full.shop = ["ORC1", "ORC1", "ORC1", "ORC1", "ORC1"]
	eq(full.buy(0), "候補區已滿", "候補滿且無法合成時不可購買")


func test_merge() -> void:
	var run := RunState.create("orc", 7)
	run.gold = 100
	run.shop = ["ORC1", "ORC1", "ORC1", "ORC1", "ORC1"]
	run.buy(0)
	run.buy(1)
	eq(run.copies_of("ORC1", 1), 2, "兩隻一星")
	run.buy(2)
	eq(run.copies_of("ORC1", 1), 0, "三合一後一星歸零")
	eq(run.copies_of("ORC1", 2), 1, "得到一隻二星")
	# 九隻 → 三星
	for k in 2:
		run.shop = ["ORC1", "ORC1", "ORC1", "ORC1", "ORC1"]
		run.buy(0)
		run.buy(1)
		run.buy(2)
	eq(run.copies_of("ORC1", 3), 1, "三隻二星 → 三星")
	eq(run.all_units().size(), 1, "合成後只剩一隻")
	# 最高三星：已有三星後不能再買同名棋子（V0.2），也就不會出現四星
	run.shop = ["ORC1", "ORC1", "ORC1", "ORC1", "ORC1"]
	eq(run.buy(0), "已擁有三星，不需要更多", "已有三星時不能再買同名")
	eq(run.copies_of("ORC1", 3), 1, "仍只有一隻三星")
	var r4 := RunState.create("orc", 70)
	for i in 3:
		r4.bench[i] = {"uid": i + 1, "id": "ORC1", "star": 3}
	r4.next_uid = 4
	r4._try_merge("ORC1", 3)
	eq(r4.copies_of("ORC1", 3), 3, "三星不會再往上合成")
	# 場上棋子參與合成，結果保留在場上
	var r2 := RunState.create("orc", 8)
	r2.gold = 100
	r2.xp = 6
	r2.shop = ["CEN1", "CEN1", "CEN1", "", ""]
	r2.buy(0)
	var first := int(r2.bench[0]["uid"])
	eq(r2.move_to_board(first, Vector2i(3, 6)), "", "部署")
	r2.buy(1)
	r2.buy(2)
	eq(r2.board_count(), 1, "合成後仍佔 1 個上場名額")
	eq(int(r2.board[Vector2i(3, 6)]["star"]), 2, "場上那隻升為二星")
	# 候補滿但可合成時允許購買
	var r3 := RunState.create("elf", 9)
	r3.gold = 100
	for i in r3.bench.size():
		r3.bench[i] = {"uid": 100 + i, "id": "HUM1", "star": 2}
	r3.bench[0] = {"uid": 1, "id": "ELF1", "star": 1}
	r3.bench[1] = {"uid": 2, "id": "ELF1", "star": 1}
	r3.next_uid = 200
	r3.shop = ["ELF1", "", "", "", ""]
	eq(r3.buy(0), "", "候補滿但可立即合成時可購買")
	eq(r3.copies_of("ELF1", 2), 1, "立即合成為二星")
	# 不會複製棋子
	var uids := {}
	for u in run.all_units():
		check(not uids.has(u["uid"]), "uid 重複（複製棋子）")
		uids[u["uid"]] = true


func test_board_limit_and_moves() -> void:
	var run := RunState.create("human", 10)
	run.gold = 100
	run.shop = ["ORC1", "ELF1", "HUM1", "", ""]
	run.buy(0)
	run.buy(1)
	run.buy(2)
	eq(run.level(), 1, "Lv.1")
	var a := int(run.bench[0]["uid"])
	var b := int(run.bench[1]["uid"])
	eq(run.move_to_board(a, Vector2i(3, 4)), "", "部署第 1 隻")
	check(run.move_to_board(b, Vector2i(2, 4)) != "", "Lv.1 不能部署第 2 隻")
	eq(run.board_count(), 1, "場上 1 隻")
	check(run.move_to_board(b, Vector2i(3, 2)) != "", "不能部署到敵方區域")
	# 從候補拖到已有棋子的格子 = 互換（人數不變）
	eq(run.move_to_board(b, Vector2i(3, 4)), "", "候補與場上互換")
	eq(int(run.board[Vector2i(3, 4)]["uid"]), b, "互換後場上是 b")
	check(run.find_unit(a)["where"] == "bench", "a 回到候補")
	# 場上移動
	eq(run.move_to_board(b, Vector2i(5, 7)), "", "場上移動")
	check(not run.board.has(Vector2i(3, 4)), "原格清空")
	# 收回候補
	eq(run.move_to_bench(b, 11), "", "收回候補")
	eq(run.board_count(), 0, "場上 0 隻")
	run.xp = 6
	eq(run.board_limit(), 3, "Lv.3 上場 3 隻")


func test_synergy_counting() -> void:
	var c := Synergy.count(["ELF1", "ELF1", "ELF1"])
	eq(int(c["race"]["elf"]), 1, "同名只計 1 種")
	c = Synergy.count(["ELF1", "ELF2"])
	eq(int(c["race"]["elf"]), 2, "兩種精靈")
	eq(Synergy.tier_index("race", "elf", 2), 0, "精靈 2 種 → 第 1 階")
	eq(Synergy.tier_index("race", "elf", 3), 1, "精靈 3 種 → 第 2 階")
	eq(Synergy.tier_index("type", "vanguard", 3), 0, "前衛 3 種仍為 2 階門檻")
	eq(Synergy.tier_index("type", "vanguard", 4), 1, "前衛 4 種")
	eq(Synergy.tier_index("class", "warrior", 1), -1, "1 種不啟動")
	# 候補不算：RunState 只算棋盤
	var run := RunState.create("elf", 11)
	run.bench[0] = {"uid": 1, "id": "ELF1", "star": 1}
	run.bench[1] = {"uid": 2, "id": "ELF2", "star": 1}
	run.next_uid = 3
	eq(run.synergy_counts()["race"].size(), 0, "候補區不計羈絆")
	run.xp = 2
	run.move_to_board(1, Vector2i(3, 4))
	run.move_to_board(2, Vector2i(3, 6))
	eq(int(run.synergy_counts()["race"]["elf"]), 2, "上場兩種精靈")
	var act := Synergy.active(run.synergy_counts())
	var found := false
	for a in act:
		if a["group"] == "race" and a["key"] == "elf":
			found = true
	check(found, "精靈羈絆啟動")


func test_modifiers() -> void:
	# 精靈文明：近戰 HP -10%、遠程普攻 +10%（作用於全部棋子，不論種族）
	var m := Modifiers.for_lineup(["ORC1", "CEN1"], "elf", true)
	eq(float(m[0]["hp_pct"]), -10.0, "精靈：近戰 HP -10%")
	eq(float(m[1]["hp_pct"]), 0.0, "精靈：遠程不扣 HP")
	eq(float(m[1]["ranged_basic_pct"]), 10.0, "精靈：遠程普攻 +10%")
	eq(float(m[0]["melee_basic_pct"]), -8.0, "精靈：近戰普攻 -8%")
	var s0 := UnitStats.final_stats("ORC1", 1, m[0])
	var base := UnitStats.base_stats("ORC1", 1)
	eq(s0["hp"], float(roundi(base["hp"] * 0.9)), "HP 確實下降")
	# 人類：3 種族以上 HP +6%
	var h2 := Modifiers.for_lineup(["ORC1", "ELF1"], "human", true)
	eq(float(h2[0]["hp_pct"]), 0.0, "人類 2 種族無加成")
	var h3 := Modifiers.for_lineup(["ORC1", "ELF1", "HUM1"], "human", true)
	eq(float(h3[0]["hp_pct"]), 6.0, "人類 3 種族 HP +6%")
	eq(float(h3[0]["basic_dmg_pct"]), -5.0, "人類普攻 -5%")
	# 半人馬：機動型普攻 +10%
	var cm := Modifiers.for_lineup(["CEN2", "CEN1"], "centaur", true)
	eq(float(cm[0]["basic_dmg_pct"]), 10.0, "半人馬：機動 +10%")
	eq(float(cm[1]["basic_dmg_pct"]), 0.0, "半人馬：非機動無加成")
	check(float(cm[0]["move_speed_pct"]) >= 15.0, "半人馬：移速 +15%（另加半人馬羈絆）")
	# 羈絆只加成符合標籤者
	var gm := Modifiers.for_lineup(["ELF1", "HUM2", "ORC1"], "", true)
	eq(float(gm[0]["armor_flat"]), 5.0 + 3.0, "守衛 2 種 +5、前衛 3 種 +3")
	eq(float(gm[2]["armor_flat"]), 3.0, "戰士只吃前衛 +3")
	# 敵方（無文明、羈絆關閉）
	var em := Modifiers.for_lineup(["ELF1", "HUM2"], "", false)
	eq(float(em[0]["armor_flat"]), 0.0, "敵方羈絆關閉")
	# 文明效果在戰鬥中確實生效：鬼人技能傷害 +12%
	var dmg_plain := _skill_damage("ORC1", "")
	var dmg_oni := _skill_damage("ORC1", "oni")
	check(dmg_oni > dmg_plain, "鬼人文明讓技能傷害變高（%s > %s）" % [dmg_oni, dmg_plain])


func _skill_damage(unit_id: String, civ: String) -> float:
	var sim := CombatSim.new(1)
	var mods: Dictionary = Modifiers.for_lineup([unit_id], civ, false)[0]
	var u := sim.add_unit(unit_id, 1, Vector2i(3, 4), 0, mods)
	var dummy := sim.add_unit("HUM2", 3, Vector2i(3, 3), 1, Modifiers.empty())
	dummy.hp = 99999
	dummy.max_hp = 99999
	u.mana = u.mana_max
	SkillRunner.cast(sim, u)
	for e in sim.events:
		if e["k"] == "damage":
			return float(e["v"])
	return 0.0


func test_star_stats() -> void:
	var s1 := UnitStats.base_stats("ORC1", 1)
	var s2 := UnitStats.base_stats("ORC1", 2)
	var s3 := UnitStats.base_stats("ORC1", 3)
	eq(s1["hp"], 116.0, "ORC1 一星 HP = 110×1.05 四捨五入")
	eq(s2["hp"], float(roundi(116 * 1.9)), "二星 HP ×1.9")
	eq(s3["hp"], float(roundi(116 * 3.3)), "三星 HP ×3.3")
	eq(s2["armor"], s1["armor"] + 3.0, "二星護甲 +3")
	eq(s3["armor"], s1["armor"] + 7.0, "三星護甲 +7")
	eq(s1["atk_speed"], s3["atk_speed"], "攻速不隨星級成長")
	eq(s1["crit_chance"], s3["crit_chance"], "暴擊率不隨星級成長")
	eq(UnitStats.base_stats("ELF1", 1)["hp"], 154.0, "守衛 HP×1.40")
	eq(UnitStats.skill_amount("ORC1", 1, "dmg"), roundf(24 * 2.2), "技能預算")
	eq(UnitStats.skill_amount("ORC1", 2, "dmg"), roundf(24 * 2.2 * 1.85), "技能二星 ×1.85")
	eq(UnitStats.cc_duration(1.0, 2), 1.1, "控制 2 星 ×1.1")
	eq(UnitStats.cc_duration(2.0, 2), 2.2, "控制 2 星 最多 +0.2")
	eq(UnitStats.cc_duration(2.0, 3), 2.4, "控制 3 星 最多 +0.4")
	eq(UnitStats.cc_duration(3.0, 3), 3.4, "控制 3 星上限")


func test_expedition_loss() -> void:
	eq(Economy.expedition_loss(0, 5), 0, "全清不扣")
	eq(Economy.expedition_loss(3, 1), 3, "第 1 回合 ×1.0")
	eq(Economy.expedition_loss(3, 4), 4, "第 4 回合 3×1.2=3.6→4")
	eq(Economy.expedition_loss(5, 7), 7, "第 7 回合 5×1.4=7（不因浮點誤差變 8）")
	eq(Economy.expedition_loss(9, 24), 10, "上限 10")
	eq(Economy.threat([1, 2, 3]), 1 + 2 + 4, "威脅值 1/2/4")
	eq(Economy.round_multiplier(13), 1.8, "第 13 回合倍率")


func _fake_result(cleared: bool, stars: Array = []) -> Dictionary:
	return {"cleared": cleared, "threat": Economy.threat(stars), "alive_enemies": []}


func test_settlement_order() -> void:
	var run := RunState.create("elf", 12)
	run.begin_round()
	run.gold = 15
	run.start_battle()  # 記錄開戰金幣
	var rep := run.settle(_fake_result(true))
	eq(rep["income_interest"], 1, "利息以開戰瞬間 15 金計")
	eq(run.gold, 15 + 5 + 1 + 2, "固定 +5、利息 +1、全清 +2")
	eq(run.xp, 2, "戰後自然 +2 XP")
	eq(run.round_no, 2, "進入第 2 回合")
	# 未全清：扣血，仍有固定收入與 XP
	run.begin_round()
	run.gold = 0
	run.start_battle()
	rep = run.settle(_fake_result(false, [1, 1]))
	eq(rep["hp_loss"], 2, "2 隻一星存活扣 2")
	eq(run.hp, 38, "遠征生命 38")
	eq(run.gold, 5, "失敗仍有固定收入、沒有全清獎勵、不額外扣金")
	# 鹿角人：第 4 回合後 +1
	var deer := RunState.create("deer", 13)
	deer.hp = 30
	deer.round_no = 4
	deer.start_battle()
	rep = deer.settle(_fake_result(false, [1]))
	eq(rep["hp_loss"], 2, "第 4 回合 1×1.2=1.2→2")
	eq(rep["deer_heal"], 1, "鹿角人回 1")
	eq(deer.hp, 29, "30-2+1")
	deer.round_no = 5
	deer.start_battle()
	rep = deer.settle(_fake_result(true))
	eq(rep["deer_heal"], 0, "第 5 回合不回")
	deer.hp = 40
	deer.round_no = 8
	deer.start_battle()
	deer.settle(_fake_result(true))
	eq(deer.hp, 40, "不超過 40")
	# 死亡後不復活、不發收入
	var dead := RunState.create("deer", 14)
	dead.hp = 2
	dead.round_no = 8
	dead.gold = 0
	dead.start_battle()
	rep = dead.settle(_fake_result(false, [3, 3, 3]))
	eq(dead.hp, 0, "歸零")
	eq(rep["deer_heal"], 0, "死亡不觸發鹿角人恢復")
	eq(dead.outcome, "defeat", "戰敗")
	check(dead.finished, "遠征結束")
	eq(dead.gold, 0, "死亡後不發收入")
	# 非鹿角人第 4 回合不回血
	var elf := RunState.create("elf", 15)
	elf.hp = 30
	elf.round_no = 4
	elf.start_battle()
	elf.settle(_fake_result(true))
	eq(elf.hp, 30, "其他文明不回遠征生命")


func test_victory_conditions() -> void:
	var run := RunState.create("oni", 16)
	run.round_no = 24
	run.start_battle()
	run.settle(_fake_result(true))
	eq(run.outcome, "victory", "第 24 回合全清 → 通關")
	var r2 := RunState.create("oni", 17)
	r2.round_no = 24
	r2.start_battle()
	r2.settle(_fake_result(false, [1]))
	eq(r2.outcome, "incomplete", "第 24 回合未全清 → 遠征未完成")
	check(r2.hp > 0, "仍有生命")
	var r3 := RunState.create("oni", 18)
	r3.round_no = 23
	r3.start_battle()
	r3.settle(_fake_result(true))
	check(not r3.finished, "第 23 回合不結束")


func test_human_free_reroll() -> void:
	var run := RunState.create("human", 19)
	run.begin_round()
	eq(run.free_rerolls, 1, "第 1 回合得到 1 張券")
	run.begin_round()
	eq(run.free_rerolls, 1, "同一回合重複進入不重複發券")
	run.gold = 0
	eq(run.reroll(), "", "用券刷新")
	eq(run.free_rerolls, 0, "券用掉")
	for r in [7, 13, 19]:
		run.round_no = r
		run.begin_round()
	eq(run.free_rerolls, 3, "第 7、13、19 回合各 1 張，可累積")
	var elf := RunState.create("elf", 20)
	elf.begin_round()
	eq(elf.free_rerolls, 0, "其他文明沒有券")


func test_shop_lock() -> void:
	var run := RunState.create("elf", 21)
	run.begin_round()
	var before := run.shop.duplicate()
	run.toggle_lock()
	run.start_battle()
	run.settle(_fake_result(true))
	run.begin_round()
	eq(run.shop, before, "鎖定後下一回合不自動刷新")
	run.toggle_lock()
	run.start_battle()
	run.settle(_fake_result(true))
	run.begin_round()
	check(run.shop.size() == 5, "解鎖後自動刷新")


func _demo_run(seed_value: int) -> RunState:
	var run := RunState.create("orc", seed_value)
	run.xp = 12
	run.board[Vector2i(3, 4)] = {"uid": 1, "id": "ORC1", "star": 2}
	run.board[Vector2i(2, 4)] = {"uid": 2, "id": "HUM2", "star": 1}
	run.board[Vector2i(3, 6)] = {"uid": 3, "id": "CEN1", "star": 2}
	run.board[Vector2i(4, 6)] = {"uid": 4, "id": "ONI2", "star": 1}
	run.round_no = 5
	return run


func test_combat_determinism() -> void:
	var a := _demo_run(77).start_battle()
	var b := _demo_run(77).start_battle()
	eq(a["events"].size(), b["events"].size(), "同種子事件數相同")
	eq(a["cleared"], b["cleared"], "同種子結果相同")
	eq(JSON.stringify(a["events"]), JSON.stringify(b["events"]), "同種子事件完全相同")
	check(a["time"] <= 45.0 + 0.001, "戰鬥不超過 45 秒")
	check(a["events"].size() > 10, "有實際戰鬥事件")
	var kinds := {}
	for e in a["events"]:
		kinds[e["k"]] = true
	for k in ["move", "attack", "damage", "cast", "end"]:
		check(kinds.has(k), "戰鬥包含事件 " + k)
	# 時間到仍有敵軍 → 未全清
	var sim := CombatSim.new(1)
	sim.add_unit("HUM1", 1, Vector2i(3, 7), 0, Modifiers.empty())
	sim.add_unit("HUM1", 1, Vector2i(3, 0), 1, Modifiers.empty())
	var res := sim.run()
	check(res["time"] <= 45.001, "45 秒上限")


func test_combat_no_overlap() -> void:
	var res := BattleSetup.build(_demo_run(5).board_lineup(), "orc", 12, 5).run()
	var occ := {}
	for u in res["units"]:
		occ[u["cell"]] = u["cid"]
	var pos := {}
	for u in res["units"]:
		pos[u["cid"]] = u["cell"]
	var ok := true
	for e in res["events"]:
		match e["k"]:
			"move", "dash", "retreat":
				if occ.has(e["to"]) and occ[e["to"]] != e["cid"]:
					ok = false
				occ.erase(e["from"])
				occ[e["to"]] = e["cid"]
				pos[e["cid"]] = e["to"]
				if e["k"] == "move" or e["k"] == "retreat":
					check(HexGrid.distance(e["from"], e["to"]) == 1, "每次只移動 1 格")
			"death":
				occ.erase(pos[e["cid"]])
	check(ok, "任何時刻兩個單位都不會站在同一格")


## 每一種棋子的技能都必須在戰鬥中真的施放並產生效果
func test_all_skills_trigger() -> void:
	for u in GameData.units():
		var id := str(u["id"])
		var sim := CombatSim.new(3)
		var caster := sim.add_unit(id, 1, Vector2i(3, 5), 0, Modifiers.empty())
		var ally := sim.add_unit("ELF1", 1, Vector2i(2, 5), 0, Modifiers.empty())
		ally.hp = ally.max_hp * 0.5
		caster.hp = caster.max_hp * 0.6
		sim.add_unit("ORC1", 1, Vector2i(3, 4), 1, Modifiers.empty())
		sim.add_unit("CEN1", 1, Vector2i(2, 2), 1, Modifiers.empty())
		sim.add_unit("HUM1", 1, Vector2i(5, 0), 1, Modifiers.empty())
		caster.mana = caster.mana_max
		var before := sim.events.size()
		var ok := SkillRunner.cast(sim, caster)
		check(ok, "%s 技能可施放" % id)
		var effect_kinds := {}
		for i in range(before, sim.events.size()):
			effect_kinds[sim.events[i]["k"]] = true
		check(effect_kinds.has("cast"), "%s 有施放事件" % id)
		check(effect_kinds.has("damage") or effect_kinds.has("heal") or effect_kinds.has("shield") or effect_kinds.has("status"),
			"%s 技能有實際效果（傷害／治療／護盾／狀態）" % id)
		# 在完整戰鬥中也會自然施放
		var sim2 := CombatSim.new(4)
		sim2.add_unit(id, 2, Vector2i(3, 5), 0, Modifiers.empty())
		sim2.add_unit("ELF1", 2, Vector2i(2, 4), 0, Modifiers.empty())
		# 高血量、低傷害的假人，確保施法者活得夠久
		for cell in [Vector2i(3, 3), Vector2i(4, 3)]:
			var dummy := sim2.add_unit("HUM2", 1, cell, 1, Modifiers.empty())
			dummy.max_hp = 4000.0
			dummy.hp = 4000.0
		var r := sim2.run()
		var cast_seen := false
		for e in r["events"]:
			if e["k"] == "cast" and e["cid"] == 1:
				cast_seen = true
				break
		check(cast_seen, "%s 在實戰中會自動施放技能" % id)


func test_ranged_vs_melee() -> void:
	# 遠程站後排可以在射程內開打，近戰需移動
	var sim := CombatSim.new(9)
	sim.add_unit("CEN1", 1, Vector2i(3, 6), 0, Modifiers.empty())
	sim.add_unit("ORC1", 1, Vector2i(3, 2), 1, Modifiers.empty())
	var r := sim.run()
	var first_attack_by := -1
	var enemy_moved := false
	for e in r["events"]:
		if e["k"] == "move" and e["cid"] == 2:
			enemy_moved = true
		if e["k"] == "attack" and first_attack_by < 0:
			first_attack_by = e["cid"]
	check(enemy_moved, "近戰敵人會移動接近")
	eq(first_attack_by, 1, "遠程先出手")
	# 3 星強於 1 星
	var s2 := CombatSim.new(9)
	s2.add_unit("ORC1", 3, Vector2i(3, 4), 0, Modifiers.empty())
	s2.add_unit("ORC1", 1, Vector2i(2, 3), 1, Modifiers.empty())
	s2.add_unit("ORC1", 1, Vector2i(3, 3), 1, Modifiers.empty())
	s2.add_unit("ORC1", 1, Vector2i(4, 3), 1, Modifiers.empty())
	check(s2.run()["cleared"], "三星一隻打贏三隻一星")


func test_save_roundtrip() -> void:
	var run := _demo_run(31)
	run.begin_round()
	run.bench[2] = {"uid": 9, "id": "DEE2", "star": 2}
	run.next_uid = 10
	run.free_rerolls = 2
	run.shop_locked = true
	check(SaveSystem.save_run(run), "存檔成功")
	var loaded := SaveSystem.load_run()
	check(loaded != null, "讀檔成功")
	if loaded == null:
		return
	eq(JSON.stringify(loaded.to_dict()), JSON.stringify(run.to_dict()), "存讀檔內容一致")
	eq(loaded.shop_rng.get_state(), run.shop_rng.get_state(), "RNG 狀態一致")
	eq(Shop.roll(loaded.shop_rng, 5, "orc"), Shop.roll(run.shop_rng, 5, "orc"), "讀檔後刷新結果一致")
	SaveSystem.clear()
	check(not SaveSystem.has_save(), "清除存檔")


func test_full_runs() -> void:
	for c in GameData.civs():
		var r := AutoPlayer.play_full_run(str(c["id"]), 1234)
		var run: RunState = r["run"]
		check(run.finished, "%s 完整一局能結束" % c["id"])
		check(r["outcome"] in ["victory", "defeat", "incomplete"], "%s 結局合法" % c["id"])
		check(run.history.size() >= 4, "%s 至少打過前 4 關（不得前 4 關無解）" % c["id"])
		check(run.gold >= 0, "%s 金幣不為負" % c["id"])
		check(run.board_count() <= run.board_limit(), "%s 上場不超過上限" % c["id"])
		var early_ok := 0
		for i in mini(4, run.history.size()):
			if run.history[i]["cleared"]:
				early_ok += 1
		check(early_ok >= 2, "%s 的 bot 在前 4 關至少清 2 關（實際 %d）" % [c["id"], early_ok])
		print("      %s：%s，打到第 %d 回合，遠征生命 %d" % [c["name"], r["outcome"], run.history.size(), run.hp])


# ================= V0.2 第一批：核心戰鬥 =================
func test_defense_formula() -> void:
	eq(UnitStats.defense_reduction(0), 0.0, "防禦 0 → 減傷 0%")
	check(is_equal_approx(UnitStats.defense_reduction(75), 0.375), "防禦 75 → 0.75×75/150 = 37.5%")
	check(is_equal_approx(UnitStats.defense_reduction(25), 0.75 * 25.0 / 100.0), "防禦 25 → 18.75%")
	eq(UnitStats.defense_reduction(-30), 0.0, "負防禦視為 0")
	check(UnitStats.defense_reduction(100000) < 0.75, "上限趨近但不超過 75%")
	var gain_low := UnitStats.defense_reduction(20) - UnitStats.defense_reduction(10)
	var gain_high := UnitStats.defense_reduction(110) - UnitStats.defense_reduction(100)
	check(gain_low > gain_high, "邊際效益遞減（低防禦每點收益較高）")
	# 戰鬥中實際套用：100 原始物理傷害打 75 護甲 → 63（四捨五入）
	var sim := CombatSim.new(1)
	var a := sim.add_unit("ORC1", 1, Vector2i(3, 4), 0, Modifiers.empty())
	var b := sim.add_unit("HUM2", 1, Vector2i(3, 3), 1, Modifiers.empty())
	b.armor = 75.0
	b.mr = 0.0
	b.max_hp = 99999.0
	b.hp = 99999.0
	eq(sim.deal_damage(a, b, 100.0, "physical", "skill", false), 63.0, "物理技能 100 打 75 護甲 = 63")
	eq(sim.deal_damage(a, b, 100.0, "magic", "skill", false), 100.0, "法術傷害看魔抗（0）")
	b.mr = 75.0
	eq(sim.deal_damage(a, b, 100.0, "magic", "skill", false), 63.0, "魔抗 75 同一公式")
	# 百分比減傷與防禦分開計算
	b.statuses.clear()
	b.statuses.append({"kind": "phys_dr", "value": 50.0, "until": 99.0, "src": -1})
	eq(sim.deal_damage(a, b, 100.0, "physical", "skill", false), 31.0, "75 護甲再加 50% 免傷：100×0.625×0.5≈31")


func _first_targets(sim: CombatSim) -> Dictionary:
	## 回傳每個單位「第一次普攻／技能傷害」打到的對象 cid
	var out := {}
	for e in sim.events:
		if e["k"] == "attack" and not out.has(e["cid"]):
			out[e["cid"]] = e["tgt"]
	return out


func test_front_line_protection() -> void:
	# 我方：前排三坦克，後排三輸出；敵方：三隻一般近戰
	var front := [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)]
	var back := [Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)]
	for seed_value in [1, 2, 3]:
		var sim := CombatSim.new(seed_value)
		var front_cids := {}
		for c in front:
			front_cids[sim.add_unit("HUM2", 1, c, 0, Modifiers.empty()).cid] = true
		for c in back:
			sim.add_unit("ONI1", 1, c, 0, Modifiers.empty())
		var enemy_cids: Array = []
		for c in [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]:
			enemy_cids.append(sim.add_unit("ORC1", 1, c, 1, Modifiers.empty()).cid)
		sim.run()
		var firsts := _first_targets(sim)
		for ec in enemy_cids:
			check(front_cids.has(firsts.get(ec, -1)), "種子 %d：敵方近戰 %d 第一個攻擊對象是前排坦克" % [seed_value, ec])
	# 對照：沒有前排時，同樣的敵人會直接打到後排（證明前排確實改變了接戰）
	var sim2 := CombatSim.new(1)
	var back_cids := {}
	for c in back:
		back_cids[sim2.add_unit("ONI1", 1, c, 0, Modifiers.empty()).cid] = true
	var e2 := sim2.add_unit("ORC1", 1, Vector2i(3, 1), 1, Modifiers.empty())
	sim2.run()
	check(back_cids.has(_first_targets(sim2).get(e2.cid, -1)), "沒有前排時敵人直接攻擊後排")


func test_flank_breakthrough() -> void:
	# 坦克在最右側前排，輸出放在最左側第二排、敵人從左側翼進攻：
	# 走到輸出旁 2 步 + 深度 1×2 = 4，走到坦克旁約 6 步 → 應突破側翼打輸出（前排不是全場嘲諷）
	var sim := CombatSim.new(5)
	var tank := sim.add_unit("HUM2", 1, Vector2i(6, 4), 0, Modifiers.empty())
	var carry := sim.add_unit("CEN1", 1, Vector2i(0, 5), 0, Modifiers.empty())
	var enemy := sim.add_unit("ORC1", 1, Vector2i(0, 2), 1, Modifiers.empty())
	sim.run()
	eq(_first_targets(sim).get(enemy.cid, -1), carry.cid, "側翼明顯較近時，近戰會突破側翼攻擊後排")
	check(tank.alive or true, "")


func test_assassin_and_taunt() -> void:
	# 刺客：技能突入最遠的後排
	var sim := CombatSim.new(7)
	for c in [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)]:
		sim.add_unit("HUM2", 1, c, 0, Modifiers.empty())
	var back := sim.add_unit("CEN1", 1, Vector2i(3, 7), 0, Modifiers.empty())
	var mods := Modifiers.empty()
	mods["start_mana"] = 50.0
	var assassin := sim.add_unit("ONI3", 1, Vector2i(3, 1), 1, mods)
	sim.run()
	var hit_back := false
	for e in sim.events:
		if e["k"] == "damage" and e["src"] == assassin.cid and e["tgt"] == back.cid:
			hit_back = true
			break
	check(hit_back, "刺客技能能越過前排打到最後排")
	# 嘲諷：敵人原本鎖定 X，被嘲諷期間改打嘲諷者，但鎖定目標不被改寫
	var s2 := CombatSim.new(8)
	var x := s2.add_unit("ELF1", 3, Vector2i(2, 4), 0, Modifiers.empty())
	var taunter := s2.add_unit("HUM2", 3, Vector2i(3, 4), 0, Modifiers.empty())
	var foe := s2.add_unit("ORC1", 1, Vector2i(2, 3), 1, Modifiers.empty())
	foe.target_cid = x.cid
	s2.apply_cc(taunter, foe, "taunt", 2.0)
	var info := s2.acquire_target(foe)
	eq(info.get("target").cid, taunter.cid, "被嘲諷時攻擊嘲諷者")
	check(info.get("forced", false), "嘲諷屬於強制目標")
	s2.t = 0.0
	s2._act(foe)
	eq(foe.target_cid, x.cid, "嘲諷不改寫原本鎖定的目標")
	foe.statuses.clear()
	eq(s2.acquire_target(foe).get("target").cid, x.cid, "嘲諷結束後回到原目標")


func test_target_lock() -> void:
	# 正常戰鬥：所有單位都不應因「別人比較近」而換目標
	var total := 0
	for r in [3, 8, 13, 19, 24]:
		var run := _demo_run(40 + r)
		run.round_no = r
		var res := run.start_battle()
		for st in res["stats"]:
			total += int(st["target_switches"])
	check(total <= 2, "5 場戰鬥中非死亡換目標次數極少（實際 %d，只允許防卡死）" % total)
	# 目標暫時離開射程：持續追擊同一目標
	var sim := CombatSim.new(9)
	var hunter := sim.add_unit("ORC1", 1, Vector2i(3, 3), 1, Modifiers.empty())
	var far := sim.add_unit("CEN1", 1, Vector2i(3, 7), 0, Modifiers.empty())
	var near := sim.add_unit("HUM1", 1, Vector2i(0, 6), 0, Modifiers.empty())
	hunter.target_cid = far.cid
	# 讓 near 移到 hunter 旁邊（比 far 更近）
	sim.occupancy.erase(near.cell)
	near.cell = Vector2i(2, 3)
	sim.occupancy[near.cell] = near.cid
	var info := sim.acquire_target(hunter)
	eq(info.get("target").cid, far.cid, "其他敵人走得更近也不換目標")
	check(info.has("step"), "目標在射程外時繼續追擊")
	# 防卡死：鎖定目標完全被包圍、無法接近超過設定秒數才換
	var s3 := CombatSim.new(10)
	var me := s3.add_unit("ORC1", 1, Vector2i(6, 0), 1, Modifiers.empty())
	var boxed := s3.add_unit("HUM1", 1, Vector2i(0, 7), 0, Modifiers.empty())
	var other := s3.add_unit("CEN1", 1, Vector2i(6, 4), 0, Modifiers.empty())
	for n in HexGrid.neighbors(boxed.cell):
		s3.add_unit("ELF1", 1, n, 0, Modifiers.empty())
	me.target_cid = boxed.cid
	s3.t = 0.0
	eq(s3.acquire_target(me).get("target").cid, boxed.cid, "剛卡住時仍保持目標")
	s3.t = 1.0
	eq(s3.acquire_target(me).get("target").cid, boxed.cid, "卡住未滿 1.5 秒仍保持")
	s3.t = 1.6
	check(s3.acquire_target(me).get("target").cid != boxed.cid, "卡住超過 1.5 秒才換成可接近的敵人")
	check(other.alive, "")


func test_round1_all_units_win() -> void:
	var slow: Array = []
	for u in GameData.units():
		var id := str(u["id"])
		var cell := Vector2i(3, 4) if GameData.is_melee(id) else Vector2i(3, 6)
		var res := BattleSetup.build([{"uid": 1, "id": id, "star": 1, "cell": cell}], "", 1, 777).run()
		check(res["cleared"], "%s 一星單獨上場能打贏第一回合" % id)
		check(float(res["time"]) <= 15.0, "%s 在 15 秒內取勝（實際 %.1f 秒）" % [id, res["time"]])
		slow.append(float(res["time"]))
	slow.sort()
	print("      第一回合取勝時間：最快 %.1f 秒、最慢 %.1f 秒" % [slow[0], slow[slow.size() - 1]])
	# 各文明（含 Debuff）也都能過
	for c in GameData.civs():
		for u in GameData.units():
			var id := str(u["id"])
			var cell := Vector2i(3, 4) if GameData.is_melee(id) else Vector2i(3, 6)
			check(BattleSetup.build([{"uid": 1, "id": id, "star": 1, "cell": cell}], str(c["id"]), 1, 3).run()["cleared"],
				"%s 文明下 %s 也能打贏第一回合" % [c["id"], id])
	check(not Shop.full_pool("elf").has("TUT1"), "教學弱敵不會出現在商店")


# ================= V0.2 第二批：規則與經濟 =================
func test_three_star_exclusion() -> void:
	var run := RunState.create("orc", 50)
	run.bench[0] = {"uid": 1, "id": "ORC1", "star": 3}
	run.next_uid = 2
	run.gold = 100
	check(run.three_star_ids().has("ORC1"), "偵測到已擁有三星")
	for i in 40:
		run.reroll()
		check(not run.shop.has("ORC1"), "手動刷新不再出現三星棋子")
	run.prepared_round = 0
	run.round_no = 2
	run.begin_round()
	check(not run.shop.has("ORC1"), "回合自動刷新也排除")
	run.shop[0] = "ORC1"   # 既有欄位仍保留該棋子
	eq(run.can_buy(0), "已擁有三星，不需要更多", "既有欄位的三星棋子不能再買")
	run.sell(1)
	check(not run.three_star_ids().has("ORC1"), "出售三星後解除排除")
	var seen := false
	for i in 200:
		run.gold = 100
		run.reroll()
		if run.shop.has("ORC1"):
			seen = true
			break
	check(seen, "出售後該棋子重新回到抽取池")
	# 稀有度比例不失控：排除一隻 1 費後，Lv.5 抽到 1 費的比例仍約 40%
	var rng := SeededRng.new(9)
	var ones := 0
	var n := 6000
	for i in n:
		if GameData.unit_cost(Shop.roll_slot(rng, 5, "orc", {"ORC1": true})) == 1:
			ones += 1
	var ratio := float(ones) / n
	check(ratio > 0.37 and ratio < 0.43, "排除後 1 費比例仍約 40%%（實際 %.1f%%）" % (ratio * 100.0))
	# 抽取池不足：Lv.1 只出 1 費，若 1 費全部排除，改抽其他稀有度、不當機
	var all_ones := {}
	for id in Shop.pool_for("orc", 1):
		all_ones[id] = true
	var alt := Shop.roll_slot(rng, 1, "orc", all_ones)
	check(alt != "" and not all_ones.has(alt), "1 費全被排除時改抽其他稀有度（%s）" % alt)
	var everything := {}
	for id in Shop.full_pool("orc"):
		everything[id] = true
	eq(Shop.roll(rng, 10, "orc", everything), ["", "", "", "", ""], "全部排除時回傳空格，不會無限迴圈")


func test_auto_fill() -> void:
	var run := RunState.create("human", 51)
	run.xp = 20   # Lv.5
	var kept := {Vector2i(1, 4): 1, Vector2i(5, 5): 2, Vector2i(3, 7): 3}
	for c in kept.keys():
		run.board[c] = {"uid": kept[c], "id": "ORC1", "star": 1}
	run.bench[0] = {"uid": 10, "id": "HUM2", "star": 1}
	run.bench[2] = {"uid": 11, "id": "CEN1", "star": 1}
	run.bench[5] = {"uid": 12, "id": "ELF1", "star": 1}
	run.bench[7] = {"uid": 13, "id": "ONI1", "star": 1}
	run.next_uid = 20
	var placed := run.auto_fill_board()
	eq(placed, [10, 11], "依候補區由左到右補位，補到上限為止")
	eq(run.board_count(), 5, "補到 Lv.5 上限")
	for c in kept.keys():
		check(run.board.has(c) and int(run.board[c]["uid"]) == kept[c], "原本部署的棋子沒有被移動 %s" % str(c))
	check(run.bench[5] != null and run.bench[7] != null, "其餘候補棋子留在原位")
	var uids := {}
	for c in run.board.keys():
		check(HexGrid.is_player_cell(c), "補位只放在己方格子")
		check(not uids.has(run.board[c]["uid"]), "沒有重複棋子")
		uids[run.board[c]["uid"]] = true
	eq(run.all_units().size(), 7, "棋子總數不變（沒有消失或複製）")
	check(run.find_unit(10)["cell"].y == 4, "近戰補在前排")
	check(run.find_unit(11)["cell"].y == 7, "遠程補在後排")
	# start_battle 會先補位再建立戰鬥快照
	var r2 := RunState.create("human", 52)
	r2.bench[3] = {"uid": 5, "id": "ORC1", "star": 1}
	r2.next_uid = 6
	var res := r2.start_battle()
	eq(res["units"].filter(func(x): return x["side"] == 0).size(), 1, "開戰時自動補位後才建立戰鬥")
	# 可關閉
	var board_cfg: Dictionary = GameData.cfg("board")
	board_cfg["auto_fill"] = false
	var r3 := RunState.create("human", 53)
	r3.bench[0] = {"uid": 5, "id": "ORC1", "star": 1}
	eq(r3.auto_fill_board(), [], "設定關閉時不補位")
	board_cfg["auto_fill"] = true


func test_interest_ui_data() -> void:
	eq(Economy.next_interest(0), {"next_gold": 10, "need": 10, "next_interest": 1}, "0 金：差 10 金到 +1")
	eq(Economy.next_interest(25), {"next_gold": 30, "need": 5, "next_interest": 3}, "25 金：差 5 金到 +3")
	eq(Economy.next_interest(30), {}, "30 金已達上限")
	# XP 規劃（考慮溢出）
	var p := Economy.xp_plan(30)   # Lv.6，本級 0/12
	eq(p["level"], 6, "30 XP = Lv.6")
	eq([p["cur"], p["need"], p["missing"]], [0, 12, 12], "Lv.6：0/12，還差 12")
	eq([p["buys"], p["cost"]], [3, 12], "還需購買 3 次、12 金")
	p = Economy.xp_plan(36)        # Lv.6，6/12
	eq([p["cur"], p["need"], p["missing"], p["buys"], p["cost"]], [6, 12, 6, 2, 8], "企劃例：6/12 還差 6 → 2 次 8 金")
	p = Economy.xp_plan(3)         # Lv.2，1/4 → 差 3 → 1 次（溢出 1）
	eq([p["missing"], p["buys"]], [3, 1], "溢出經驗：差 3 只需買 1 次")
	check(Economy.xp_plan(90)["max"], "滿級")


func test_oni_skill_dot() -> void:
	var sim := CombatSim.new(1)
	var oni_mods: Dictionary = Modifiers.for_lineup(["ONI4"], "oni", false)[0]
	var oni := sim.add_unit("ONI4", 3, Vector2i(3, 6), 0, oni_mods)
	var plain := sim.add_unit("ONI4", 3, Vector2i(4, 6), 0, Modifiers.empty())
	var dummy := sim.add_unit("HUM2", 1, Vector2i(3, 1), 1, Modifiers.empty())
	dummy.armor = 0.0
	dummy.mr = 0.0
	dummy.max_hp = 999999.0
	dummy.hp = 999999.0
	eq(sim.damage_bonus_pct(oni, dummy, "magic", "skill", true), 12.0, "鬼人：技能持續傷害 +12%")
	eq(sim.damage_bonus_pct(oni, dummy, "physical", "skill", false), 12.0, "鬼人：物理技能 +12%")
	eq(sim.damage_bonus_pct(oni, dummy, "magic", "skill", false), 12.0, "鬼人：法術技能 +12%")
	eq(sim.damage_bonus_pct(oni, dummy, "physical", "basic", false), 0.0, "鬼人：普攻不加成")
	eq(sim.damage_bonus_pct(oni, dummy, "physical", "item", false), 0.0, "鬼人：裝備獨立傷害不加成（V0.3 預留）")
	# 實際 DOT：每次結算只乘一次 1.12
	var total := UnitStats.skill_amount("ONI4", 3, "dot")
	sim.add_periodic(oni, dummy, "dot", total, 4.0, "magic")
	sim.add_periodic(plain, dummy, "dot", total, 4.0, "magic")
	var tick_amount := total / 8.0
	sim.t = 0.5
	var before := sim.events.size()
	sim._update_statuses()
	var got := {}
	for i in range(before, sim.events.size()):
		var e: Dictionary = sim.events[i]
		if e["k"] == "damage" and e["dot"]:
			got[e["src"]] = e["v"]
	eq(got.get(plain.cid), float(roundi(tick_amount)), "一般 DOT 每跳 = 總量 / 跳數")
	eq(got.get(oni.cid), float(roundi(tick_amount * 1.12)), "鬼人 DOT 每跳只乘一次 1.12")
	# 流血（物理技能 DOT）也適用
	var s2 := CombatSim.new(2)
	var o1 := s2.add_unit("ONI1", 3, Vector2i(3, 4), 0, Modifiers.for_lineup(["ONI1"], "oni", false)[0])
	var d2 := s2.add_unit("HUM2", 1, Vector2i(3, 3), 1, Modifiers.empty())
	d2.armor = 0.0
	d2.max_hp = 999999.0
	d2.hp = 999999.0
	var bleed := UnitStats.skill_amount("ONI1", 3, "dot")
	s2.add_periodic(o1, d2, "dot", bleed, 3.0, "physical")
	s2.t = 0.5
	s2._update_statuses()
	var last: Dictionary = s2.events[s2.events.size() - 1]
	eq(last["v"], float(roundi(bleed / 6.0 * 1.12)), "鬼人流血每跳 +12%")
	eq(last["source"], "skill", "DOT 的傷害來源標示為技能")


func test_playback_clock() -> void:
	check(is_equal_approx(PlaybackClock.sim_from_real(10.0), 10.0), "0–15 秒 1.0×")
	check(is_equal_approx(PlaybackClock.sim_from_real(15.0), 15.0), "15 秒時模擬 15 秒")
	check(is_equal_approx(PlaybackClock.sim_from_real(25.0), 30.0), "15–25 秒 1.5×：25 秒時模擬 30 秒")
	check(is_equal_approx(PlaybackClock.sim_from_real(32.5), 45.0), "25 秒後 2.0×：45 秒戰鬥約 32.5 秒播完")
	check(is_equal_approx(PlaybackClock.real_from_sim(45.0), 32.5), "反向換算 45 → 32.5")
	eq(PlaybackClock.rate_at_real(5.0), 1.0, "5 秒時倍率 1.0")
	eq(PlaybackClock.rate_at_real(20.0), 1.5, "20 秒時倍率 1.5")
	eq(PlaybackClock.rate_at_real(30.0), 2.0, "30 秒時倍率 2.0")
	var prev := -1.0
	var ok := true
	for i in 400:
		var r := i * 0.1
		var sim_t := PlaybackClock.sim_from_real(r)
		if sim_t < prev - 1e-9 or not is_equal_approx(PlaybackClock.real_from_sim(sim_t), r):
			ok = false
		prev = sim_t
	check(ok, "時間軸單調遞增且可逆（事件順序不會改變）")
	# 戰鬥結果與播放速度無關：模擬層完全不讀取播放倍率（實際播放的一致性由冒煙測試檢查）
	var src := FileAccess.get_file_as_string("res://scripts/core/combat/combat_sim.gd")
	check(not src.contains("playback") and not src.contains("battle_speed"), "戰鬥模擬不依賴播放速度")


func test_prep_timer() -> void:
	var tm := PrepTimer.new()
	eq(tm.duration, 30.0, "備戰固定 30 秒（V0.3）")
	check(not tm.tick(1.0), "未開始不計時")
	tm.start()
	check(not tm.tick(19.0), "11 秒前不觸發")
	check(not tm.is_caution(), "剩 11 秒為一般顏色")
	check(not tm.tick(1.0), "")
	check(tm.is_caution() and not tm.is_warning(), "剩 10 秒轉黃色")
	check(not tm.tick(5.0), "")
	check(tm.is_warning(), "剩 5 秒轉紅色")
	tm.paused = true
	check(not tm.tick(100.0), "暫停時不計時")
	tm.paused = false
	check(tm.tick(5.1), "倒數結束時觸發自動開戰")
	check(not tm.tick(1.0), "只觸發一次")
	tm.start()
	eq(tm.seconds_left(), 30, "每回合重新從 30 秒開始")


# ================= V0.2 第三批：資訊透明 =================
func _cell(cells: Array, key: String) -> Dictionary:
	return StatBreakdown.cell_by_key(cells, key)


func test_stat_breakdown() -> void:
	# 3×4 宮格：12 個屬性，順序固定，生命不在宮格內
	var cells := StatBreakdown.cells("ORC1", 1, [])
	eq(cells.map(func(c): return c["key"]), StatBreakdown.ORDER, "12 格屬性與順序")
	check(not cells.any(func(c): return c["key"] == "hp"), "生命不放在宮格內")
	for c in cells:
		check(not str(c["text"]).begins_with("+") and not str(c["text"]).contains(" +"), "格子只顯示最終數字（%s：%s）" % [c["key"], c["text"]])
	# 正常升星不會讓數字變藍：比較基準是目前星級的基礎值
	for u in GameData.units():
		for star in [1, 2, 3]:
			for c in StatBreakdown.cells(str(u["id"]), star, []):
				if c["key"] != "mana":
					eq(int(c["sign"]), 0, "%s %d★ 沒有修正時 %s 為白字" % [u["id"], star, c["key"]])
	var s3 := StatBreakdown.cells("ORC1", 3, [])
	eq(_cell(s3, "atk")["value"], UnitStats.base_stats("ORC1", 3)["atk"], "三星數字是三星基礎值")
	# 文明 Debuff → 紅；羈絆／裝備 Buff → 藍；分類正確
	var elf: Array = Modifiers.sources_for_lineup(["ORC1"], "elf", true)[0]
	eq(int(_cell(StatBreakdown.cells("ORC1", 1, elf), "atk")["sign"]), -1, "精靈文明近戰普攻 -8% → 攻擊紅字")
	eq(int(StatBreakdown.hp_info("ORC1", 1, elf)["sign"]), -1, "精靈文明近戰 HP -10% → 生命紅字")
	var src: Array = Modifiers.sources_for_lineup(["HUM2", "ELF1"], "", true, [["DM_PLATE"], []])[0]
	var arm := _cell(StatBreakdown.cells("HUM2", 2, src), "armor")
	eq(int(arm["sign"]), 1, "羈絆＋裝備物防 → 藍字")
	eq(arm["value"], UnitStats.final_stats("HUM2", 2, Modifiers.sum_sources(src))["armor"], "物防數字＝實際戰鬥數值")
	var cats := {}
	for l in arm["lines"]:
		cats[l["cat"]] = true
	check(cats.has("base") and cats.has("trait") and cats.has("item"), "物防明細區分 基礎／羈絆／裝備")
	check(not cats.has("civ"), "沒有文明修正時不列出文明")
	check(arm["lines"].all(func(l): return l["cat"] == "base" or not str(l["text"]).ends_with("0") or str(l["text"]) != "+0"), "不列零值來源")
	check(arm["extra"][0].contains("減傷率"), "物防明細顯示目前減傷率")
	# 戰鬥中暫時效果：破甲；Buff 與 Debuff 同時存在時以淨值決定顏色
	var mixed := _cell(StatBreakdown.cells("ORC1", 1, [{"stat": "melee_basic_pct", "value": -8.0, "source": "civ", "label": "精靈"}],
		[{"kind": "atk_down", "value": 30.0, "left": 2.0}, {"kind": "atk_up", "value": 20.0, "left": 3.0}]), "atk")
	eq(int(mixed["sign"]), -1, "攻擊 −8%（文明）−30%（弱化）＋20%（增益）→ 淨值為負，紅字")
	check(mixed["lines"].any(func(l): return l["cat"] == "status" and int(l["sign"]) == -1), "明細列出暫時性戰鬥效果（紅字）")
	var up := _cell(StatBreakdown.cells("ORC1", 1, [{"stat": "melee_basic_pct", "value": -8.0, "source": "civ", "label": "精靈"}],
		[{"kind": "atk_up", "value": 40.0, "left": 3.0}]), "atk")
	eq(int(up["sign"]), 1, "攻擊 −8% 與 ＋40% → 淨值為正，藍字")
	# 緩速：攻速 −10%、移速 −25%
	var slowed := StatBreakdown.cells("ORC1", 1, [], [{"kind": "slow", "value": 0.0, "left": 1.0}])
	eq(int(_cell(slowed, "as")["sign"]), -1, "緩速 → 攻速紅字")
	check(is_equal_approx(float(_cell(slowed, "move")["value"]), UnitStats.base_stats("ORC1", 1)["move_speed"] * 0.75), "緩速 → 移速 ×0.75")
	# 穿透格
	var pen := StatBreakdown.cells("ORC1", 1, [{"stat": "phys_pen", "value": 25.0, "source": "item", "label": "裝備"}], [{"kind": "phys_pen", "value": 50.0, "left": 2.0}])
	eq(_cell(pen, "phys_pen")["text"], "60%", "物理穿透 25%＋50% 受上限 60%")
	eq(int(_cell(pen, "phys_pen")["sign"]), 1, "物理穿透 → 藍字")
	eq(_cell(pen, "magic_pen")["text"], "0%", "魔法穿透不受物理穿透影響")
	# 攻速、暴擊（裝備）
	var ring: Array = Modifiers.sources_for_lineup(["CEN1"], "", false, [["DM_RING", "CU_FANG"]])[0]
	var rc := StatBreakdown.cells("CEN1", 1, ring)
	eq(int(_cell(rc, "crit")["sign"]), 1, "暴擊率裝備 → 藍")
	eq(_cell(rc, "crit")["text"], "20%", "暴擊率 5% + 15%")
	eq(_cell(rc, "crit_dmg")["text"], "175%", "暴擊傷害 150% + 25%")
	eq(int(_cell(rc, "as")["sign"]), 1, "攻速裝備 → 藍")
	# 鬼人文明技能傷害、戰鬥中魔力顯示
	var deer: Array = Modifiers.sources_for_lineup(["DEE2"], "deer", true)[0]
	eq(int(_cell(StatBreakdown.cells("DEE2", 1, deer), "skill")["sign"]), 1, "鹿角人治療護盾 +12% → 技能格藍字（收在技能明細）")
	var oni: Array = Modifiers.sources_for_lineup(["ONI2"], "oni", true)[0]
	eq(_cell(StatBreakdown.cells("ONI2", 1, oni), "skill")["text"], "112%", "鬼人技能傷害 112%")
	eq(_cell(StatBreakdown.cells("ONI2", 1, [], [], {"mana": 40.0}), "mana")["text"], "40/60", "戰鬥中魔力顯示 目前／上限")
	eq(_cell(StatBreakdown.cells("TUT1", 1, []), "mana")["text"], "—", "沒有技能的單位")
	# 修正值由來源加總，與實際一致
	var direct := Modifiers.for_lineup(["ELF1", "ELF2", "HUM2"], "human", true)
	var srcs := Modifiers.sources_for_lineup(["ELF1", "ELF2", "HUM2"], "human", true)
	for i in 3:
		eq(Modifiers.sum_sources(srcs[i]), direct[i], "來源加總＝修正值")


func test_contribution_stats() -> void:
	var sim := CombatSim.new(1)
	var a := sim.add_unit("ORC1", 1, Vector2i(3, 4), 0, Modifiers.empty())
	var b := sim.add_unit("HUM2", 1, Vector2i(3, 3), 1, Modifiers.empty())
	b.armor = 0.0
	# 護盾：先給 50 護盾，打 30 → 吸收 30、HP 不變
	sim.add_shield(b, b, 50.0, 10.0)
	sim.deal_damage(a, b, 30.0, "physical", "skill", false)
	eq(b.shield_absorbed, 30.0, "護盾只計實際吸收的 30（未消耗的 20 不算）")
	eq(a.damage_dealt, 0.0, "被護盾吸收的不算有效 HP 傷害")
	eq(b.damage_taken, 0.0, "護盾擋下時沒有承傷")
	# 再打 40：護盾剩 20 吸收，HP 損失 20
	sim.deal_damage(a, b, 40.0, "physical", "skill", false)
	eq(b.shield_absorbed, 50.0, "護盾累計吸收 50")
	eq(a.damage_dealt, 20.0, "有效傷害 20")
	eq(b.damage_taken, 20.0, "承傷 20")
	# 溢出擊殺：剩 HP 少於傷害時只計剩餘 HP
	b.hp = 10.0
	sim.deal_damage(a, b, 100.0, "physical", "skill", false)
	eq(a.damage_dealt, 30.0, "擊殺只計剩餘 10 HP")
	eq(a.overkill, 90.0, "溢出傷害另外記錄（除錯用）")
	# 有效治療：超過最大生命的不算
	var s2 := CombatSim.new(2)
	var healer := s2.add_unit("HUM1", 1, Vector2i(3, 6), 0, Modifiers.empty())
	var hurt := s2.add_unit("ORC1", 1, Vector2i(3, 4), 0, Modifiers.empty())
	hurt.hp = hurt.max_hp - 15.0
	s2.heal(healer, hurt, 50.0)
	eq(healer.healing_done, 15.0, "有效治療只計補到滿血的 15")
	# 同名兩隻分開統計
	var s3 := CombatSim.new(3)
	s3.add_unit("ORC1", 2, Vector2i(2, 4), 0, Modifiers.empty())
	s3.add_unit("ORC1", 2, Vector2i(4, 4), 0, Modifiers.empty())
	s3.add_unit("HUM2", 2, Vector2i(3, 3), 1, Modifiers.empty())
	var res := s3.run()
	var orc_rows: Array = res["stats"].filter(func(x): return x["id"] == "ORC1")
	eq(orc_rows.size(), 2, "同名兩隻各自一列")
	check(orc_rows[0]["cid"] != orc_rows[1]["cid"], "以戰鬥單位 cid 區分")


func test_leaderboard_rows() -> void:
	var stats := [
		{"cid": 1, "side": 0, "id": "ORC1", "star": 2, "damage": 300, "taken": 50, "shielded": 0, "healing": 0},
		{"cid": 2, "side": 0, "id": "ORC1", "star": 1, "damage": 100, "taken": 150, "shielded": 0, "healing": 0},
		{"cid": 3, "side": 0, "id": "HUM1", "star": 1, "damage": 0, "taken": 0, "shielded": 0, "healing": 80},
		{"cid": 9, "side": 1, "id": "ELF1", "star": 1, "damage": 999, "taken": 0, "shielded": 0, "healing": 0},
	]
	var rows := Leaderboard.rows(stats, "damage")
	eq(rows.size(), 3, "只列我方 3 隻")
	eq(rows[0]["cid"], 1, "由高到低排序")
	check(is_equal_approx(rows[0]["pct"], 75.0), "占比 300/400 = 75%")
	check(is_equal_approx(rows[1]["pct"], 25.0), "占比 25%")
	eq(rows[2]["pct"], 0.0, "0 傷害 0%")
	check(is_equal_approx(rows[1]["ratio"], 100.0 / 300.0), "橫條長度相對第一名")
	check(rows[0]["name"] != rows[1]["name"], "同名棋子加上編號區分")
	eq(Leaderboard.rows(stats, "healing")[0]["cid"], 3, "治療排行")
	eq(Leaderboard.rows(stats, "taken")[0]["cid"], 2, "承傷排行")
	var sum := 0.0
	for r in Leaderboard.rows(stats, "taken"):
		sum += float(r["pct"])
	check(is_equal_approx(sum, 100.0), "百分比總和 100%")
	# 實際戰鬥資料：全隊有效傷害總和 ≤ 敵方損失的總 HP
	var res := _demo_run(5).start_battle()
	var dealt := Leaderboard.total(res["stats"], "damage", 0)
	var enemy_taken := Leaderboard.total(res["stats"], "taken", 1)
	check(is_equal_approx(dealt, enemy_taken), "我方有效傷害 = 敵方實際承傷（%d）" % int(dealt))


func test_trait_detail() -> void:
	var d := Synergy.detail("race", "elf", [{"id": "ELF1", "star": 2}, {"id": "ELF1", "star": 1}], [{"id": "ELF2", "star": 1}], "human")
	eq(d["count"], 1, "同名重複上場仍只計 1 種")
	var states := {}
	for m in d["members"]:
		states[m["id"]] = m["state"]
	eq(states["ELF1"], "board", "ELF1 已上場")
	eq(states["ELF2"], "bench", "ELF2 在候補")
	eq(states["ELF3"], "none", "ELF3 尚未持有")
	eq(states["ELF4"], "unavailable", "人類文明無法取得精靈頂尖棋子")
	eq(d["members"].size(), 4, "列出所有精靈棋子")
	var e := Synergy.detail("race", "elf", [], [], "elf")
	for m in e["members"]:
		if m["id"] == "ELF4":
			eq(m["state"], "none", "精靈文明可取得 ELF4")
	var board_stars: Array = d["members"][0]["stars"]
	board_stars.sort()
	eq(board_stars, [1, 2], "列出上場棋子的星級")


## V0.1 存檔（version 1）必須能直接在 V0.2 讀取並繼續遊玩
func test_v01_save_compat() -> void:
	var v01 := {"version": 1, "civ_id": "oni", "round": 7, "hp": 31, "gold": 23, "xp": 14, "run_seed": "123456789",
		"shop_rng_state": "987654321", "shop": ["ORC1", "", "ELF2", "HUM3", "ONI4"], "shop_locked": false, "free_rerolls": 0,
		"bench": [{"uid": 5, "id": "CEN1", "star": 1}, null, null, null, null, null, null, null, null, null, null, null],
		"board": [{"uid": 2, "id": "ONI1", "star": 2, "col": 3, "row": 4}, {"uid": 3, "id": "ONI2", "star": 1, "col": 3, "row": 6}],
		"next_uid": 6, "prepared_round": 7, "finished": false, "outcome": "", "history": []}
	var f := FileAccess.open(SaveSystem._path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(v01))
	f.close()
	var run := SaveSystem.load_run()
	check(run != null, "V0.1 存檔可以讀取")
	if run == null:
		return
	eq([run.civ_id, run.round_no, run.hp, run.gold, run.xp], ["oni", 7, 31, 23, 14], "V0.1 存檔內容正確")
	eq(run.board_count(), 2, "V0.1 存檔的場上棋子")
	eq(run.shop, ["ORC1", "", "ELF2", "HUM3", "ONI4"], "V0.1 存檔的商店內容")
	var res := run.start_battle()
	check(res.has("stats") and res["events"].size() > 0, "讀取後可以直接開戰（V0.2 規則）")
	check(run.board_count() == 3, "V0.2 自動補位對舊存檔也有效")
	SaveSystem.clear()


# ================= V0.3 =================
func test_race_traits_234() -> void:
	eq(Synergy.tier_index("race", "elf", 2), 0, "種族 2 種 → 第 1 階")
	eq(Synergy.tier_index("race", "elf", 3), 1, "種族 3 種 → 第 2 階")
	eq(Synergy.tier_index("race", "elf", 4), 2, "種族 4 種 → 第 3 階")
	eq(Synergy.tier_index("class", "warrior", 4), 1, "職業仍為 2/3")
	var m := Modifiers.for_lineup(["ELF1", "ELF2", "ELF3", "ELF4"], "", true)
	eq(float(m[1]["ranged_basic_pct"]), 12.0, "精靈 4 種：遠程普攻 +12%（取代低階、不累加）")
	eq(float(m[1]["start_mana"]), 15.0, "精靈 4 種：初始魔力 +15")
	var dup := Modifiers.for_lineup(["ELF1", "ELF1", "ELF2", "ELF3"], "", true)
	eq(float(dup[2]["ranged_basic_pct"]), 8.0, "同名重複不增加計數（3 種 → +8%）")
	var oni := Modifiers.for_lineup(["ONI1", "ONI2", "ONI3", "ONI4", "ORC1"], "", true)
	eq(float(oni[0]["skill_dmg_pct"]), 20.0, "鬼人 4 種：技能傷害 +20%（含 DOT）")
	eq(float(oni[4]["skill_dmg_pct"]), 0.0, "鬼人種族羈絆只作用於鬼人")
	var both := Modifiers.for_lineup(["ONI1", "ONI2"], "oni", true)
	eq(float(both[0]["skill_dmg_pct"]), 12.0 + 6.0, "鬼人文明 +12% 與種族 2 種 +6% 分開計算再加總")
	var hum := Modifiers.for_lineup(["HUM1", "HUM2", "HUM3", "HUM4"], "", true)
	eq(float(hum[0]["armor_flat"]), 14.0, "人類 4 種：物防 +14")
	# 四費限制不變：非本文明只能湊到 3 種
	for c in GameData.civs():
		for race in ["elf", "human", "orc", "centaur", "deer", "oni"]:
			var n := 0
			for id in Shop.full_pool(str(c["id"])):
				if GameData.unit(id)["race"] == race:
					n += 1
			eq(n, 4 if race == c["race"] else 3, "%s 文明可取得的 %s 棋子種類" % [c["id"], race])


func _unit_with_items(run: RunState, uid: int) -> Array:
	return RunState.unit_items(run.find_unit(uid)["unit"])


func test_equipment_basic() -> void:
	var run := RunState.create("orc", 300)
	run.bench[0] = {"uid": 1, "id": "ORC1", "star": 1, "items": []}
	run.next_uid = 2
	run.inventory = ["CU_DAGGER", "DM_PLATE", "OG_EYE"]
	eq(run.equip(1, 0), "", "穿上第 1 件")
	eq(run.equip(1, 0), "", "穿上第 2 件")
	eq(_unit_with_items(run, 1), ["CU_DAGGER", "DM_PLATE"], "兩格裝備")
	check(run.equip(1, 0) != "", "裝備欄已滿時不能再裝")
	eq(run.equip(1, 0, 1), "", "指定欄位可直接更換")
	eq(_unit_with_items(run, 1), ["CU_DAGGER", "OG_EYE"], "更換後的裝備")
	eq(run.inventory, ["DM_PLATE"], "被換下的回到背包")
	eq(run.unequip(1, 0), "", "免費卸下")
	eq(run.inventory, ["DM_PLATE", "CU_DAGGER"], "卸下回到背包")
	eq(run.gold, 5, "穿脫裝備不花錢")
	# 屬性套用：熔岩胸甲 生命 +150、物防 +15
	run.equip(1, 0)
	var lineup := [{"uid": 1, "id": "ORC1", "star": 1, "cell": Vector2i(3, 4), "items": _unit_with_items(run, 1)}]
	var mods: Dictionary = Modifiers.for_lineup(["ORC1"], "", false, [lineup[0]["items"]])[0]
	var st := UnitStats.final_stats("ORC1", 1, mods)
	var base := UnitStats.base_stats("ORC1", 1)
	eq(st["hp"], base["hp"] + 150.0, "裝備生命 +150 確實套用")
	eq(st["armor"], base["armor"] + 15.0, "裝備物防 +15 確實套用")
	var src: Array = Modifiers.sources_for_lineup(["ORC1"], "", false, [lineup[0]["items"]])[0]
	check(src.any(func(e): return e["source"] == "item" and str(e["label"]).contains("熔岩胸甲")), "裝備效果列為「裝備」來源")
	var sim := BattleSetup.build(lineup, "", 3, 1)
	eq(sim.units[0].max_hp, st["hp"], "戰鬥中的生命包含裝備")


func test_equipment_merge_and_sell() -> void:
	var run := RunState.create("orc", 301)
	run.gold = 100
	run.bench[0] = {"uid": 1, "id": "ORC1", "star": 1, "items": ["CU_DAGGER", "DM_PLATE"]}
	run.bench[1] = {"uid": 2, "id": "ORC1", "star": 1, "items": ["OG_EYE"]}
	run.next_uid = 3
	var before := run.all_items().size()
	run.shop = ["ORC1", "", "", "", ""]
	run.buy(0)
	eq(run.copies_of("ORC1", 2), 1, "合成二星")
	var star2: Dictionary = run.all_units()[0]
	eq(RunState.unit_items(star2), ["CU_DAGGER", "DM_PLATE"], "合成後保留最多兩件（原棋子優先）")
	eq(run.inventory, ["OG_EYE"], "多出來的回到背包")
	eq(run.all_items().size(), before, "合成後裝備總數不變（不遺失、不複製）")
	run.sell(int(star2["uid"]))
	eq(run.all_items().size(), before, "出售後裝備總數不變")
	eq(run.inventory.size(), 3, "出售時身上裝備回到背包")
	# 三隻二星 → 三星，各自帶裝備
	var r2 := RunState.create("orc", 302)
	for i in 3:
		r2.bench[i] = {"uid": i + 1, "id": "HUM2", "star": 2, "items": ["CU_ROBE"] if i < 2 else ["DM_AXE", "DM_RING"]}
	r2.next_uid = 9
	r2._try_merge("HUM2", 2)
	eq(r2.copies_of("HUM2", 3), 1, "三星合成")
	eq(r2.all_items().size(), 4, "三星合成後 4 件裝備都還在")
	eq(RunState.unit_items(r2.all_units()[0]).size(), 2, "棋子身上最多 2 件")


func test_equipment_passives() -> void:
	# 吸血：造成有效傷害的 15% 治療自己
	var sim := CombatSim.new(1)
	var a := sim.add_unit("ORC1", 1, Vector2i(3, 4), 0, Modifiers.empty(), 0, ["CU_FANG"])
	var b := sim.add_unit("HUM2", 1, Vector2i(3, 3), 1, Modifiers.empty())
	a.hp = 50.0
	b.armor = 0.0
	sim.deal_damage(a, b, 100.0, "physical", "skill", false)
	eq(a.hp, 50.0 + 15.0, "吸血 15%")
	# 流血：普攻後目標身上有來源為裝備的持續傷害
	var s2 := CombatSim.new(2)
	var c := s2.add_unit("ORC1", 1, Vector2i(3, 4), 0, Modifiers.empty(), 0, ["CU_DAGGER"])
	var d := s2.add_unit("HUM2", 1, Vector2i(3, 3), 1, Modifiers.empty())
	s2.basic_attack(c, d)
	check(d.statuses.any(func(x): return x["kind"] == "dot" and x.get("source") == "item"), "獻祭匕首：普攻造成流血（裝備來源）")
	# 裝備傷害不吃鬼人技能加成
	var oni_mods: Dictionary = Modifiers.for_lineup(["ONI1"], "oni", false)[0]
	var o := s2.add_unit("ONI1", 1, Vector2i(5, 4), 0, oni_mods, 0, ["CU_DAGGER"])
	eq(s2.damage_bonus_pct(o, d, "physical", "item", true), 0.0, "裝備流血不吃鬼人技能 +12%")
	# 反甲：受到近戰普攻時反彈法術傷害
	var s3 := CombatSim.new(3)
	var att := s3.add_unit("ORC1", 1, Vector2i(3, 3), 1, Modifiers.empty())
	var tank := s3.add_unit("HUM2", 1, Vector2i(3, 4), 0, Modifiers.empty(), 0, ["DM_PLATE"])
	var hp0 := att.hp
	s3.basic_attack(att, tank)
	check(att.hp < hp0, "熔岩胸甲：近戰普攻者受到反彈傷害")
	# 生命交換：開戰時 -10% 最大生命
	var s4 := CombatSim.new(4)
	var bp := s4.add_unit("ONI2", 1, Vector2i(3, 6), 0, Modifiers.empty(), 0, ["CU_CODEX"])
	s4.add_unit("HUM2", 1, Vector2i(3, 0), 1, Modifiers.empty())
	var full := bp.max_hp
	ItemPassives.on_battle_start(s4, bp)
	eq(bp.hp, full - roundf(full * 0.1), "血祭法典：開戰失去 10% 生命")
	# 施法護盾、施法暈眩
	var s5 := CombatSim.new(5)
	var caster := s5.add_unit("ORC1", 1, Vector2i(3, 4), 0, Modifiers.empty(), 0, ["DM_HEART", "OG_EYE"])
	var foe := s5.add_unit("HUM2", 3, Vector2i(3, 3), 1, Modifiers.empty())
	caster.mana = caster.mana_max
	caster.target_cid = foe.cid
	s5._act(caster)
	check(caster.shield_total() >= 120.0, "炎魔之心：施法後獲得護盾")
	check(foe.has_status("stun"), "虛空之眼：技能主要目標暈眩")
	# 每第 3 次普攻的法術追加
	var s6 := CombatSim.new(6)
	var st := s6.add_unit("CEN1", 1, Vector2i(3, 6), 0, Modifiers.empty(), 0, ["OG_STAFF"])
	var dummy := s6.add_unit("HUM2", 3, Vector2i(3, 3), 1, Modifiers.empty())
	var n_before := s6.events.size()
	for i in 3:
		s6.basic_attack(st, dummy)
	var item_hits := 0
	for i in range(n_before, s6.events.size()):
		if s6.events[i]["k"] == "damage" and s6.events[i]["source"] == "item":
			item_hits += 1
	eq(item_hits, 1, "扭曲法杖：3 次普攻觸發 1 次")
	for it in GameData.items():
		if it.has("passive"):
			check(ItemPassives.KINDS.has(it["passive"]["kind"]), "被動已實作：%s" % it["id"])


func test_equipment_rewards() -> void:
	var run := RunState.create("elf", 303)
	run.round_no = 3
	run.start_battle()
	var rep := run.settle(_fake_result(true))
	check(rep["reward"], "第 3 回合完成後產生裝備獎勵")
	eq(run.pending_reward["choices"].size(), 3, "三選一")
	var ids: Array = run.pending_reward["choices"]
	check(ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2], "三件不重複")
	for id in ids:
		eq(GameData.item(id)["faction"], "cult", "第 3 回合掉落邪教遺物")
		eq(GameData.item(id)["tier"], "normal", "第 3 回合為普通裝備")
	eq(run.claim_reward(1), "", "選擇第 2 件")
	eq(run.inventory, [ids[1]], "加入背包")
	check(run.claim_reward(0) != "", "同一回合不能重複領取")
	check(run.rewards_claimed.has(3), "記錄已領取")
	# 第 12 回合：惡魔進階；第 24 回合：沒有裝備
	run.round_no = 12
	run.start_battle()
	run.settle(_fake_result(false, [1]))
	eq(run.pending_reward.get("tier"), "advanced", "第 12 回合為進階裝備（未全清也算完成）")
	eq(run.pending_reward.get("faction"), "demon", "第 12 回合掉落惡魔兵裝")
	run.claim_reward(0)
	var r24 := RunState.create("elf", 304)
	r24.round_no = 24
	r24.start_battle()
	r24.settle(_fake_result(true))
	check(r24.pending_reward.is_empty(), "第 24 回合沒有裝備掉落")
	var normal := RunState.create("elf", 305)
	normal.round_no = 4
	normal.start_battle()
	normal.settle(_fake_result(true))
	check(normal.pending_reward.is_empty(), "一般回合沒有裝備")
	eq(GameData.reward_rounds().map(func(x): return int(x["round"])), [3, 6, 9, 12, 15, 18, 21], "七個裝備回合")


func test_save_v2_and_migration() -> void:
	var run := RunState.create("deer", 306)
	run.bench[0] = {"uid": 1, "id": "DEE1", "star": 2, "items": ["CU_ROBE"]}
	run.board[Vector2i(3, 6)] = {"uid": 2, "id": "DEE2", "star": 1, "items": ["OG_MASK", "DM_RING"]}
	run.next_uid = 3
	run.inventory = ["CU_DAGGER"]
	run.rewards_claimed = [3, 6]
	run.pending_reward = {"round": 9, "faction": "cult", "tier": "normal", "choices": ["CU_FANG", "CU_AMULET", "CU_CODEX"]}
	check(SaveSystem.save_run(run), "存檔")
	var loaded := SaveSystem.load_run()
	check(loaded != null, "讀檔")
	if loaded != null:
		eq(JSON.stringify(loaded.to_dict()), JSON.stringify(run.to_dict()), "裝備、背包、領取狀態完整保存")
		eq(int(loaded.to_dict()["version"]), 2, "存檔版本 2")
	# V0.1／V0.2 的 version 1 存檔：自動補上空裝備
	var v1 := run.to_dict()
	v1["version"] = 1
	v1.erase("inventory")
	v1.erase("rewards_claimed")
	v1.erase("pending_reward")
	for b in v1["bench"]:
		if b != null:
			b.erase("items")
	for b in v1["board"]:
		b.erase("items")
	var m := RunState.from_dict(v1)
	check(m != null, "version 1 存檔可讀取")
	if m != null:
		eq(m.inventory, [], "舊存檔背包為空")
		eq(m.all_items(), [], "舊存檔棋子沒有裝備")
		eq(m.board_count(), 1, "舊存檔棋子保留")
		check(m.equip(1, 0) != "", "空背包不能裝備（不會當機）")
	SaveSystem.clear()


func test_otherworld_enemies() -> void:
	# 變體沿用基礎棋子並只乘一次階段倍率
	var base := UnitStats.base_stats("ORC1", 1)
	var imp := UnitStats.base_stats("DEMON_IMP", 1)
	eq(imp["hp"], float(roundi(base["hp"] * 1.5)), "惡魔：生命 ×1.5")
	check(is_equal_approx(imp["atk"], snappedf(base["atk"] * 1.35, 0.1)), "惡魔：攻擊 ×1.35")
	var acolyte := UnitStats.base_stats("CULT_ACOLYTE", 2)
	eq(acolyte["hp"], UnitStats.base_stats("ONI1", 2)["hp"], "邪教：倍率 1.0")
	var spawn := UnitStats.base_stats("OG_SPAWN", 1)
	eq(spawn["hp"], float(roundi(UnitStats.base_stats("DEE3", 1)["hp"] * 2.1)), "古神：生命 ×2.1")
	eq(UnitStats.skill("CULT_ACOLYTE")["kind"], UnitStats.skill("ONI1")["kind"], "變體沿用基礎技能")
	eq(UnitStats.base_stats("OG_AVATAR", 1)["hp"], float(GameData.unit("OG_AVATAR")["stats"]["hp"]), "古神化身使用固定屬性（不再乘階段倍率）")
	# 關卡配置
	var expect := {3: "cult", 6: "cult", 9: "cult", 12: "demon", 15: "demon", 18: "demon", 21: "oldgod", 24: "oldgod"}
	for r in range(1, 25):
		var st := GameData.stage(r)
		if expect.has(r):
			eq(str(st.get("faction", "")), expect[r], "第 %d 回合為 %s" % [r, expect[r]])
			for e in st["units"]:
				eq(str(GameData.unit(e["id"]).get("phase", "")), expect[r], "第 %d 回合敵軍屬於該勢力" % r)
		else:
			check(not st.has("faction"), "第 %d 回合為一般六族敵軍" % r)
			for e in st["units"]:
				check(not GameData.unit(e["id"]).has("phase"), "第 %d 回合不含異界敵軍" % r)
	check(GameData.stage(24)["units"].any(func(e): return e["id"] == "OG_AVATAR"), "第 24 回合出現古神化身")
	# 古神化身技能確實施放
	var sim := CombatSim.new(9)
	var avatar := sim.add_unit("OG_AVATAR", 1, Vector2i(3, 0), 1, Modifiers.empty())
	for c in [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 6)]:
		sim.add_unit("HUM2", 1, c, 0, Modifiers.empty())
	avatar.mana = avatar.mana_max
	check(SkillRunner.cast(sim, avatar), "古神化身施放萬眼凝視")
	check(sim.units.filter(func(x): return x.side == 0 and x.has_status("stun")).size() == 3, "全場暈眩")
	# 三階段平均強度遞增（以 生命 × 每秒傷害 的平方根加總估算）
	var power := {}
	for r in expect.keys():
		var p := 0.0
		for e in GameData.stage(r)["units"]:
			var s := UnitStats.base_stats(e["id"], int(e["star"]))
			p += sqrt(s["hp"] * s["atk"] * s["atk_speed"])
		power[r] = p
	var cult: float = (power[3] + power[6] + power[9]) / 3.0
	var demon: float = (power[12] + power[15] + power[18]) / 3.0
	var old: float = (power[21] + power[24]) / 2.0
	check(cult < demon and demon < old, "強度：邪教 %.0f < 惡魔 %.0f < 古神 %.0f" % [cult, demon, old])
	check(not Shop.full_pool("elf").has("DEMON_IMP"), "異界敵軍不會出現在商店")


func test_live_stats_match() -> void:
	# 右側即時排行由事件累加，結束時必須等於戰鬥統計
	for r in [5, 12, 18]:
		var run := _demo_run(500 + r)
		run.round_no = r
		var res := run.start_battle()
		var acc := {}
		for e in res["events"]:
			match e["k"]:
				"damage":
					var a: Dictionary = acc.get(e["src"], {"damage": 0.0, "taken": 0.0, "shielded": 0.0, "healing": 0.0})
					a["damage"] += float(e["hp_dmg"])
					acc[e["src"]] = a
					var t: Dictionary = acc.get(e["tgt"], {"damage": 0.0, "taken": 0.0, "shielded": 0.0, "healing": 0.0})
					t["taken"] += float(e["hp_dmg"])
					acc[e["tgt"]] = t
					for pair in e["absorb_by"]:
						var p: Dictionary = acc.get(int(pair[0]), {"damage": 0.0, "taken": 0.0, "shielded": 0.0, "healing": 0.0})
						p["shielded"] += float(pair[1])
						acc[int(pair[0])] = p
				"heal":
					var h: Dictionary = acc.get(e["src"], {"damage": 0.0, "taken": 0.0, "shielded": 0.0, "healing": 0.0})
					h["healing"] += float(e["v"])
					acc[e["src"]] = h
		var ok := true
		for stt in res["stats"]:
			var a: Dictionary = acc.get(stt["cid"], {"damage": 0.0, "taken": 0.0, "shielded": 0.0, "healing": 0.0})
			for k in ["damage", "taken", "shielded", "healing"]:
				if roundi(a[k]) != int(stt[k]):
					ok = false
		check(ok, "第 %d 回合：事件累加的即時統計＝最終統計" % r)


func test_bench_during_battle() -> void:
	# 戰鬥在開戰時已算完；之後整理候補區不影響本場結果
	var run := _demo_run(600)
	run.bench[0] = {"uid": 50, "id": "CEN1", "star": 1, "items": []}
	run.bench[1] = {"uid": 51, "id": "ELF1", "star": 1, "items": []}
	run.next_uid = 60
	run.xp = 6   # Lv.3（場上已有 4 隻，超過上限也不會補位）
	var res := run.start_battle()
	var snap := JSON.stringify(res["events"])
	run.move_to_bench(50, 7)
	run.move_to_bench(51, 0)
	eq(JSON.stringify(res["events"]), snap, "整理候補區不改變本場戰鬥事件")
	check(run.bench[7] != null and int(run.bench[7]["uid"]) == 50, "候補區排列已更新（影響下一回合）")
	var rep := run.settle(res)
	eq(rep["cleared"], res["cleared"], "結算使用開戰時的結果")


# ------------------------------------------------------------ V0.4 戰鬥術語
func _dummy_sim() -> Array:
	var sim := CombatSim.new(1)
	var a := sim.add_unit("ORC1", 1, Vector2i(3, 4), 0, Modifiers.empty())
	var b := sim.add_unit("HUM2", 1, Vector2i(3, 3), 1, Modifiers.empty())
	b.max_hp = 99999.0
	b.hp = 99999.0
	return [sim, a, b]


func test_penetration() -> void:
	# 規格範例：減傷 40%、物理穿透 25% → 有效減傷 30%，100 原始傷害造成 70
	var d40 := 0.0
	for i in 2000:
		if UnitStats.defense_reduction(i * 0.1) >= 0.4:
			d40 = i * 0.1
			break
	check(absf(CombatSim.reduction_after_pen(d40, 25.0) - 0.30) < 0.002, "減傷 40% × (1 − 25%) = 30%")
	var t := _dummy_sim()
	var sim: CombatSim = t[0]
	var a: CombatUnit = t[1]
	var b: CombatUnit = t[2]
	b.armor = 75.0      # 減傷 37.5%
	b.mr = 75.0
	eq(sim.deal_damage(a, b, 100.0, "physical", "skill", false), 63.0, "沒有穿透：100 打 75 護甲 = 63")
	a.mods["phys_pen"] = 40.0
	eq(sim.deal_damage(a, b, 100.0, "physical", "skill", false), float(roundi(100.0 * (1.0 - 0.375 * 0.6))), "物理穿透 40%：減傷 37.5% → 22.5%")
	eq(sim.deal_damage(a, b, 100.0, "magic", "skill", false), 63.0, "物理穿透不影響魔法傷害")
	a.mods["phys_pen"] = 0.0
	a.mods["magic_pen"] = 40.0
	eq(sim.deal_damage(a, b, 100.0, "physical", "skill", false), 63.0, "魔法穿透不影響物理傷害")
	eq(sim.deal_damage(a, b, 100.0, "magic", "skill", false), float(roundi(100.0 * (1.0 - 0.375 * 0.6))), "魔法穿透 40% 作用於魔法傷害")
	# 上限 60%，不會低於 0
	a.mods["magic_pen"] = 50.0
	sim.add_status(a, "magic_pen", 50.0, 5.0, a.cid, {"tag": "skill"})
	check(is_equal_approx(a.penetration("magic"), 60.0), "同類穿透加總上限 60%")
	check(CombatSim.reduction_after_pen(75.0, 150.0) >= 0.0, "穿透不會讓減傷低於 0")
	# 技能提供的穿透（取代破甲）：同來源重複施放只刷新
	var s2 := CombatSim.new(2)
	var orc3 := s2.add_unit("ORC3", 1, Vector2i(3, 6), 0, Modifiers.empty())
	s2.add_unit("HUM2", 1, Vector2i(3, 3), 1, Modifiers.empty())
	orc3.mana = orc3.mana_max
	SkillRunner.cast(s2, orc3)
	SkillRunner.cast(s2, orc3)
	eq(orc3.statuses.filter(func(x): return x["kind"] == "phys_pen").size(), 1, "戰矛獵手：穿透只有一份（重複施放刷新）")
	check(is_equal_approx(orc3.penetration("physical"), 30.0), "戰矛獵手施法後自身物理穿透 30%")


func test_wound() -> void:
	var t := _dummy_sim()
	var sim: CombatSim = t[0]
	var a: CombatUnit = t[1]
	a.hp = 10.0
	eq(sim.heal(a, a, 100.0), 100.0, "沒有重傷：治療 100")
	a.hp = 10.0
	sim.add_status(a, "wound", 0.0, 3.0, -1)
	sim.add_status(a, "wound", 0.0, 5.0, 99)
	eq(a.statuses.filter(func(x): return x["kind"] == "wound").size(), 1, "多個重傷不疊加（只有一份）")
	eq(sim.heal(a, a, 100.0), 60.0, "重傷：治療固定 −40%")
	sim.add_shield(a, a, 100.0, 3.0)
	eq(a.shield_total(), 100.0, "重傷不降低護盾")
	var w: Dictionary = a.statuses.filter(func(x): return x["kind"] == "wound")[0]
	check(is_equal_approx(float(w["until"]), 5.0), "重傷持續時間取較長者")


func test_slow_rules() -> void:
	var t := _dummy_sim()
	var sim: CombatSim = t[0]
	var b: CombatUnit = t[2]
	var as0 := b.effective_atk_speed()
	var mv0 := b.effective_move_speed()
	sim.apply_cc(t[1], b, "slow", 2.0)
	check(is_equal_approx(b.effective_atk_speed(), as0 * 0.9), "緩速：攻速 −10%")
	check(is_equal_approx(b.effective_move_speed(), mv0 * 0.75), "緩速：移速 −25%")
	sim.add_status(b, "slow", 0.0, 4.0, 77)
	eq(b.statuses.filter(func(x): return x["kind"] == "slow").size(), 1, "不同來源緩速不相加")
	check(is_equal_approx(b.effective_move_speed(), mv0 * 0.75), "兩個緩速仍只有 −25%")
	check(b.effective_atk_speed() > 0.0 and b.effective_move_speed() > 0.0, "緩速不會讓速度變成負值")
	sim.t = 2.5
	sim._update_statuses()
	check(b.has_status("slow"), "時間取較長者：2.5 秒時仍緩速")
	sim.t = 4.1
	sim._update_statuses()
	check(not b.has_status("slow"), "到期後解除")
	# 星紋術士的緩速使用統一規則（不再帶百分比）
	check(not GameData.unit("ELF3")["skill"]["params"].has("pct"), "星紋術士緩速不再自訂百分比")


func test_dot_unified() -> void:
	var t := _dummy_sim()
	var sim: CombatSim = t[0]
	var a: CombatUnit = t[1]
	var b: CombatUnit = t[2]
	sim.add_periodic(a, b, "dot", 60.0, 3.0, "physical", "skill", "skill")
	sim.add_periodic(a, b, "dot", 60.0, 3.0, "physical", "skill", "skill")
	eq(b.statuses.filter(func(x): return x["kind"] == "dot").size(), 1, "同一來源同一效果重複施加只刷新")
	var c := sim.add_unit("ONI1", 1, Vector2i(2, 4), 0, Modifiers.empty())
	sim.add_periodic(c, b, "dot", 60.0, 3.0, "magic", "skill", "skill")
	eq(b.statuses.filter(func(x): return x["kind"] == "dot").size(), 2, "不同施加者的持續傷害各自計算")
	# 名稱統一：資料與介面不再出現流血／燃燒／中毒
	var texts: Array = []
	for u in GameData.units() + GameData.special_units():
		texts.append(str(u.get("skill", {}).get("desc", "")))
	for it in GameData.items():
		texts.append(str(it.get("desc", "")))
	for c2 in GameData.civs():
		for bf in c2["buffs"] + c2["debuffs"]:
			texts.append(str(bf["text"]))
	var bad := texts.filter(func(x): return x.contains("流血") or x.contains("燃燒") or x.contains("中毒") or x.contains("侵蝕"))
	eq(bad.size(), 0, "技能、裝備、文明說明統一稱「持續傷害」")


func test_archer_retreat() -> void:
	# 草原弓手：施法後向後撤一格，拉開與最近敵人的距離
	var sim := CombatSim.new(3)
	var arc := sim.add_unit("CEN1", 1, Vector2i(3, 5), 0, Modifiers.empty())
	var foe := sim.add_unit("ORC1", 1, Vector2i(3, 3), 1, Modifiers.empty())
	foe.max_hp = 9999.0
	foe.hp = 9999.0
	arc.target_cid = foe.cid
	arc.mana = arc.mana_max
	var d0 := HexGrid.distance(arc.cell, foe.cell)
	var before := arc.cell
	check(SkillRunner.cast(sim, arc), "草原弓手施法成功")
	check(arc.cell != before and HexGrid.distance(before, arc.cell) == 1, "施法後移動一格")
	check(HexGrid.distance(arc.cell, foe.cell) > d0, "後撤後與最近敵人的距離增加")
	eq(arc.target_cid, foe.cid, "後撤不取消原本的目標鎖定")
	eq(sim.occupancy.get(arc.cell), arc.cid, "占位同步更新")
	check(not sim.occupancy.has(before), "原格子釋放")
	check(sim.events.any(func(e): return e["k"] == "retreat" and e["cid"] == arc.cid), "產生後撤事件（播放同步）")
	# 沒有合法空格：被包圍時不動、不卡住
	var s2 := CombatSim.new(4)
	var a2 := s2.add_unit("CEN1", 1, Vector2i(3, 6), 0, Modifiers.empty())
	var f2 := s2.add_unit("ORC1", 1, Vector2i(3, 3), 1, Modifiers.empty())
	f2.max_hp = 9999.0
	f2.hp = 9999.0
	for n in HexGrid.neighbors(a2.cell):
		s2.add_unit("ELF1", 1, n, 0, Modifiers.empty())
	a2.target_cid = f2.cid
	a2.mana = a2.mana_max
	check(SkillRunner.cast(s2, a2), "被包圍時仍可施法")
	eq(a2.cell, Vector2i(3, 6), "沒有空格時維持原位")
	# 不會走到更容易被攻擊的位置：所有候選格都更危險時不動
	var s3 := CombatSim.new(5)
	var a3 := s3.add_unit("CEN1", 1, Vector2i(0, 7), 0, Modifiers.empty())
	var f3 := s3.add_unit("ORC1", 1, Vector2i(0, 6), 1, Modifiers.empty())
	f3.max_hp = 9999.0
	f3.hp = 9999.0
	s3.add_unit("CEN1", 1, Vector2i(2, 4), 1, Modifiers.empty())
	a3.target_cid = f3.cid
	a3.mana = a3.mana_max
	var cell3 := a3.cell
	SkillRunner.cast(s3, a3)
	var ev := s3._retreat_eval(a3.cell, s3.enemies_of(a3))
	var ev0 := s3._retreat_eval(cell3, s3.enemies_of(a3))
	check(int(ev["threat"]) <= int(ev0["threat"]), "不移到會被更多敵人攻擊的位置")
	# 整場戰鬥：可重現、不重疊
	var r1 := BattleSetup.build([{"id": "CEN1", "star": 2, "cell": Vector2i(3, 6), "uid": 1, "items": []},
		{"id": "CEN1", "star": 1, "cell": Vector2i(1, 6), "uid": 2, "items": []}], "centaur", 5, 9).run()
	var r2 := BattleSetup.build([{"id": "CEN1", "star": 2, "cell": Vector2i(3, 6), "uid": 1, "items": []},
		{"id": "CEN1", "star": 1, "cell": Vector2i(1, 6), "uid": 2, "items": []}], "centaur", 5, 9).run()
	eq(JSON.stringify(r1["events"]), JSON.stringify(r2["events"]), "含後撤的戰鬥同種子可重現")


func test_no_armor_down_left() -> void:
	# 「破甲」已全面遷移：資料與技能不再對目標降低防禦
	for u in GameData.units() + GameData.special_units():
		var pr: Dictionary = u.get("skill", {}).get("params", {})
		check(not pr.has("armor") or str(u.get("skill", {}).get("kind", "")) in ["rally", "living_bark"], "%s 沒有降低目標防禦的參數" % u["id"])
	for id in ["HUM3", "ORC3", "OG_AVATAR"]:
		check(float(GameData.unit(id)["skill"]["params"].get("pen", 0)) > 0.0, "%s 改為自身穿透" % id)
	var r := BattleSetup.build(_demo_run(11).board_lineup(), "human", 15, 11).run()
	check(not r["events"].any(func(e): return e["k"] == "status" and e["kind"] == "armor_down"), "戰鬥中不再出現破甲狀態")
