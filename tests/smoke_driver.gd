extends Node
## 實機冒煙測試：真的開啟各場景、模擬滑鼠／觸控輸入、打幾回合、開圖鑑、走到結算畫面。
## 由 tests/smoke_test.tscn 啟動。可加 -- --shots=<資料夾> 存截圖（需有顯示環境）。

var failures: Array = []
var shots_dir := ""
var shot_index := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		printerr("  [失敗] " + msg)
	else:
		print("  ✓ " + msg)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func scene() -> Node:
	return get_tree().current_scene


func shot(name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	shot_index += 1
	img.save_png("%s/%02d_%s.png" % [shots_dir, shot_index, name])


func press(path: String) -> void:
	var b: Button = scene().get_node(path)
	b.pressed.emit()


func click_at(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	get_tree().root.push_input(down, true)
	await get_tree().process_frame
	var up := down.duplicate()
	up.pressed = false
	get_tree().root.push_input(up, true)
	await get_tree().process_frame
	await get_tree().process_frame


func drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	get_tree().root.push_input(down, true)
	await get_tree().process_frame
	for i in range(1, 9):
		var mv := InputEventMouseMotion.new()
		var p := from.lerp(to, i / 8.0)
		mv.position = p
		mv.global_position = p
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_tree().root.push_input(mv, true)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	get_tree().root.push_input(up, true)
	await get_tree().process_frame
	await get_tree().process_frame


func screen_pos(board: BoardView, local: Vector2) -> Vector2:
	return board.get_global_transform_with_canvas() * local


func _bar_color(g: Node) -> Color:
	var sb: StyleBoxFlat = (g.bar as ProgressBar).get_theme_stylebox("fill")
	return sb.bg_color


func _run() -> void:
	SaveSystem.clear()
	Session.goto(Session.SCENE_MENU)
	await wait(0.6)
	check(scene().name == "MainMenu", "主選單開啟")
	press("Center/Box/NewGameButton")
	await wait(0.5)
	check(scene().name == "CivSelect", "進入文明選擇")
	(scene().get_node("Margin/VBox/CivGrid").get_child(0) as Button).pressed.emit()   # 精靈
	await wait(0.2)
	press("Margin/VBox/Buttons/StartButton")
	await wait(0.8)
	check(scene().name == "Game", "進入遊戲畫面")
	var run: RunState = Session.run
	var g := scene()
	var board: BoardView = g.get_node("BoardView")
	check(run.civ_id == "elf", "精靈文明")

	# ── 版面 ──
	check(g.round_label.text == "1/24", "上方顯示回合 1/24")
	check(GameData.reward_rounds().size() == 7, "七個裝備節點")
	check(g.prep_timer.running and g.prep_timer.duration == 30.0, "30 秒備戰倒數開始")
	check(g._gold_label.text == "5" and g._lv_label.text == "Lv.1" and g._hp_label.text == "40/40" and g._pop_label.text == "0/1", "底部顯示 金幣｜Lv｜生命｜人口")
	check(g.xp_left.text.strip_edges() == "0/2 XP" and g._xp_cost_label.text == "4" and g._xp_word.text == "升級", "XP 條：0/2 XP、4 金升級")
	var xp_w: float = g.xp_bar.get_global_rect().size.x
	var slots_w: float = g.shop_slots.get_global_rect().size.x
	check(absf(xp_w - slots_w) <= 2.0, "XP 條與五格商店等寬（%.0f vs %.0f）" % [xp_w, slots_w])
	var top_rect: Rect2 = g.top_bar.get_global_rect()
	var bottom_rect: Rect2 = g.bottom_bar.get_global_rect()
	check(top_rect.end.y < bottom_rect.position.y, "上方列與下方操作區不重疊")
	check(g.get_node("LeftPanel/VBox/Scroll/List").get_child(0) == g.civ_btn, "文明是羈絆清單的第一項")
	check(not g.civ_detail.visible, "文明效果平常不展開")
	g.civ_btn.pressed.emit()
	await get_tree().process_frame
	check(g.civ_detail.visible and g.civ_detail.text.count("▲") == 2 and g.civ_detail.text.count("▼") == 2, "點文明展開 2 Buff＋2 Debuff")
	await shot("prep_layout")
	g.civ_btn.pressed.emit()

	# ── 棋子資訊卡：九宮格（3×4）──
	g.prep_timer.remaining = 999.0
	run.gold = 20
	run.changed.emit()
	(g.get_node("BottomBar/VBox/RowB/ShopSlots/Slot0") as Button).pressed.emit()
	await get_tree().process_frame
	var uid := -1
	var bidx := -1
	for i in run.bench.size():
		if run.bench[i] != null:
			uid = int(run.bench[i]["uid"])
			bidx = i
			break
	await click_at(screen_pos(board, board.bench_center(bidx)))
	check(g._info_mode == "unit" and g.detail_box.visible, "點棋子 → 右側顯示資訊卡")
	var card: UnitCard = g.card
	check(card._cells.size() == 12, "3×4 共 12 個屬性格")
	var plus := false
	for k in card._cells.keys():
		if card.cell_text(k).contains("+"):
			plus = true
	check(not plus, "屬性格沒有 +X／−X 常駐標示")
	check(not card.is_detail_open(), "平常不顯示計算明細")
	card.cell_button("armor").pressed.emit()
	await get_tree().process_frame
	check(card.is_detail_open() and card.detail_text().contains("物理防禦"), "點物防格 → 顯示物防明細")
	check(card.detail_text().contains("減傷率"), "明細顯示目前減傷率")
	await shot("card_detail")
	# 點卡片上明細以外的地方（不會取消選取棋子）
	await click_at(card._hp_label.get_global_rect().get_center())
	check(not card.is_detail_open(), "點其他地方關閉明細，回到簡潔宮格")
	check(g._info_mode == "unit", "關閉明細不會取消選取")

	# ── 裝備：點空欄位 → 從背包穿上 ──
	run.inventory = ["DM_PLATE", "CU_DAGGER"]
	run.changed.emit()
	await get_tree().process_frame
	var white_armor := card.cell_color("armor")
	card.slot_button(0).pressed.emit()
	await get_tree().process_frame
	check(g.item_overlay.visible, "點空裝備欄 → 打開背包選擇")
	var wear: Button = null
	for c in g.item_body.get_children():
		for b in c.find_children("*", "Button", true, false):
			if (b as Button).text == "穿上":
				wear = b
				break
		if wear:
			break
	if wear == null:
		check(false, "背包選擇畫面有「穿上」按鈕")
		get_tree().quit(1)
		return
	wear.pressed.emit()
	await wait(0.2)
	check(RunState.unit_items(run.find_unit(uid)["unit"]) == ["DM_PLATE"], "穿上熔岩胸甲")
	check(card.cell_color("armor") != white_armor and card.cell_color("armor").b > card.cell_color("armor").r, "裝備物防 → 物防數字變藍")
	check(run.inventory == ["CU_DAGGER"], "背包少一件")
	await shot("card_equipped")
	card.slot_button(0).pressed.emit()
	await get_tree().process_frame
	var unequip: Button = null
	for b in g.item_buttons.get_children():
		if (b as Button).text == "卸下":
			unequip = b
	if unequip == null:
		check(false, "裝備資訊有「卸下」按鈕")
		get_tree().quit(1)
		return
	unequip.pressed.emit()
	await wait(0.1)
	check(RunState.unit_items(run.find_unit(uid)["unit"]).is_empty() and run.inventory.size() == 2, "卸下回到背包")
	run.equip(uid, 0)

	# ── 倒數顏色 ──
	g.prep_timer.remaining = 15.0
	await wait(0.15)
	var c_normal := _bar_color(g)
	g.prep_timer.remaining = 9.0
	await wait(0.15)
	var c_yellow := _bar_color(g)
	g.prep_timer.remaining = 4.0
	await wait(0.15)
	var c_red := _bar_color(g)
	check(c_yellow.r > 0.8 and c_yellow.g > 0.6 and c_yellow.b < 0.4, "10～6 秒黃色")
	check(c_red.r > 0.8 and c_red.g < 0.45, "5～0 秒紅色")
	check(c_normal.b > c_normal.r, "30～11 秒一般顏色")
	await shot("countdown_red")

	# ── 倒數歸零 → 自動補位並開戰 ──
	(g.get_node("BottomBar/VBox/RowB/ShopSlots/Slot1") as Button).pressed.emit()
	await get_tree().process_frame
	g.prep_timer.remaining = 0.3
	await wait(0.6)
	check(g.phase == 1, "倒數歸零自動開戰")
	check(run.board_count() >= 1, "自動補位")
	check(g.bar_left.text.contains("戰鬥中"), "開戰後倒數條改為戰鬥狀態")

	# ── 戰鬥中：整理候補、查看雙方、即時貢獻 ──
	var bp: BattlePlayer = g.battle_player
	var bench_before := []
	for i in run.bench.size():
		if run.bench[i] != null:
			bench_before.append(i)
	if not bench_before.is_empty():
		var from_i: int = bench_before[0]
		var to_i := 11
		var moved_uid := int(run.bench[from_i]["uid"])
		await drag(screen_pos(board, board.bench_center(from_i)), screen_pos(board, board.bench_center(to_i)))
		check(run.bench[to_i] != null and int(run.bench[to_i]["uid"]) == moved_uid, "戰鬥中可以整理候補區")
		check(run.board_count() == g._last_result["units"].filter(func(x): return x["side"] == 0).size(), "整理候補不會把棋子加入戰場")
	await wait(0.8)
	var my_cid := -1
	var foe_cid := -1
	for snap in bp.player_lineup():
		my_cid = int(snap["cid"])
	for cid in bp._units.keys():
		if int(bp._units[cid]["side"]) == 1:
			foe_cid = int(cid)
	await click_at(screen_pos(board, bp.token(my_cid).position))
	check(g._info_mode == "battle" and card.visible, "戰鬥中點己方棋子顯示資訊卡")
	check(card._hp_label.text.begins_with("生命"), "資訊卡顯示即時生命")
	card.cell_button("atk").pressed.emit()
	await get_tree().process_frame
	check(card.is_detail_open(), "戰鬥中也能點屬性看明細")
	await shot("battle_card")
	if bp.is_alive(foe_cid):
		await click_at(screen_pos(board, bp.token(foe_cid).position))
		check(g.detail_title.text.contains("敵方"), "戰鬥中點敵方棋子")
	g._close_detail()
	await wait(0.6)
	check(g.leader.row_count() > 0, "右側貢獻面板即時顯示")
	await shot("battle_leader")

	# ── 戰後：沒有結算視窗、自動回到備戰 ──
	Session.battle_speed = 4.0
	var t1 := 0.0
	while g.phase == 1 and t1 < 40.0:
		await wait(0.2)
		t1 += 0.2
	var final_hp := {}
	for e in g._last_result["events"]:
		if e["k"] in ["damage", "heal", "item"]:
			final_hp[e.get("tgt", e.get("cid"))] = float(e["hp"])
	var ok_hp := true
	for cid in final_hp.keys():
		var tk := bp.token(cid)
		if tk and absf(tk.hp - float(final_hp[cid])) > 0.01:
			ok_hp = false
	check(ok_hp, "播放後血量與模擬結果一致（加速不改變結果）")
	check(g.toast_texts().any(func(t): return t.contains("金")), "戰後以提示顯示收入（不彈出結算畫面）")
	check(not g.has_node("ResultOverlay"), "沒有每回合結算畫面")
	await wait(1.4)
	check(g.phase == 0 and run.round_no == 2, "自動進入第 2 回合備戰")
	check(g.leader.row_count() > 0, "戰後保留上一場統計")
	Session.battle_speed = 1.0

	# ── 裝備回合：三選一（不計備戰時間）──
	g.prep_timer.remaining = 999.0
	if Session.debug_enabled:
		(g.get_node("DebugPanel/VBox/RoundRow/RoundSpin") as SpinBox).value = 3
		press("DebugPanel/VBox/RoundRow/JumpButton")
		await wait(0.3)
		check(g.bar_left.text.contains("邪教"), "第 3 回合為邪教敵軍")
		var inv_before := run.inventory.size()
		press("DebugPanel/VBox/Row3/WinButton")
		await wait(0.8)
		check(g.reward_overlay.visible, "裝備回合完成 → 三選一")
		check(g.reward_cards.get_child_count() == 3, "三件裝備可查看")
		check(not g.prep_timer.running, "選擇裝備時不計備戰時間")
		await shot("reward")
		var pick: Button = g.reward_cards.get_child(0).find_children("*", "Button", true, false)[0]
		pick.pressed.emit()
		await wait(0.3)
		check(run.inventory.size() == inv_before + 1, "選擇後加入背包")
		check(run.rewards_claimed.has(3), "第 3 回合已領取")
		check(g.phase == 0 and g.prep_timer.running, "選完才開始第 4 回合倒數")
		check(g.reward_dots.claimed.has(3), "裝備節點點亮")

	# ── 收合 ──
	g.prep_timer.remaining = 999.0
	g.leader._toggle.pressed.emit()
	await wait(0.3)
	check(g.right_panel.get_global_rect().size.x < 80, "右側貢獻面板可收合")
	g.left_toggle.pressed.emit()
	await wait(0.3)
	check(g.left_panel.get_global_rect().size.x < 80, "左側面板可收合")
	await shot("collapsed")
	g.leader._toggle.pressed.emit()
	g.left_toggle.pressed.emit()
	await wait(0.2)

	# ── 存檔續玩（含裝備）──
	var items_before := run.all_items().size()
	press("TopBar/HBox/MenuBtn")
	await wait(0.2)
	press("MenuOverlay/Panel/VBox/SaveQuitButton")
	await wait(0.6)
	press("Center/Box/ContinueButton")
	await wait(0.8)
	check(scene().name == "Game" and Session.run.all_items().size() == items_before, "繼續遠征：裝備完整保留")
	g = scene()

	# ── 圖鑑 ──
	press("TopBar/HBox/MenuBtn")
	await wait(0.2)
	press("MenuOverlay/Panel/VBox/CodexButton")
	await wait(0.8)
	check(scene().name == "Codex", "開啟圖鑑")
	press("Margin/VBox/Header/BackButton")
	await wait(0.8)
	g = scene()

	# ── 第 24 回合：古神化身，通關 ──
	if Session.debug_enabled:
		g.prep_timer.remaining = 999.0
		(g.get_node("DebugPanel/VBox/RoundRow/RoundSpin") as SpinBox).value = 24
		press("DebugPanel/VBox/RoundRow/JumpButton")
		await wait(0.4)
		check(g.bar_left.text.contains("古神化身"), "第 24 回合為古神化身")
		await shot("round24")
		press("DebugPanel/VBox/Row3/WinButton")
		await wait(1.0)
		check(scene().name == "EndScreen", "通關後顯示最終結算畫面")
		await shot("end")

	print("")
	print("冒煙測試：%s（失敗 %d 項）" % ["通過" if failures.is_empty() else "未通過", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
