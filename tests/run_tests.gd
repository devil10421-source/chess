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
		var has_boss := false
		for e in GameData.stage(r)["units"]:
			if GameData.unit_cost(str(e["id"])) == 4:
				has_boss = true
		check(has_boss, "首領關 %d 應有 4 費棋子" % r)


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
	eq(Economy.interest(99), 2, "利息上限 2")
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
	# 三星不再往上合成
	for k in 3:
		run.shop = ["ORC1", "ORC1", "ORC1", "ORC1", "ORC1"]
		run.buy(0)
		run.buy(1)
		run.buy(2)
	eq(run.copies_of("ORC1", 3), 2, "最高三星：再湊一組只會多一隻三星")
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
			"move", "dash":
				if occ.has(e["to"]) and occ[e["to"]] != e["cid"]:
					ok = false
				occ.erase(e["from"])
				occ[e["to"]] = e["cid"]
				pos[e["cid"]] = e["to"]
				if e["k"] == "move":
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
