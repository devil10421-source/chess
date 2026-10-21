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


func hover(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	get_tree().root.push_input(mv, true)
	await get_tree().process_frame
	await get_tree().process_frame


## 棋盤（含候補區、上方狀態條空間）在畫面上的範圍
func board_screen_rect(board: BoardView) -> Rect2:
	var t := board.total_size()
	var tl := screen_pos(board, Vector2((board.board_size().x - t.x) * 0.5, -board.top_pad()))
	return Rect2(tl, t * board.get_global_transform_with_canvas().get_scale())


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
	check(g.prep_timer.running and g.prep_timer.duration == 45.0, "第 1 回合 45 秒備戰倒數開始")
	check(g._gold_label.text == "5" and g._lv_label.text == "Lv.1" and g._hp_label.text == "40/40" and g._pop_label.text == "0/1", "底部顯示 金幣｜Lv｜生命｜人口")
	check(g.xp_left.text.strip_edges() == "0/2 XP" and g._xp_cost_label.text == "4" and g._xp_word.text == "升級", "XP 條：0/2 XP、4 金升級")
	# 文明升級圖示：商店左側、文明代表色徽章；點擊＝購買 4 XP、花 4 金
	check(g.civup_btn.get_parent().name == "LeftButtons" and g.civup_btn.visible, "文明升級按鈕在商店左側")
	check(g._btn_labels[g.civup_btn]["icon"].kind == "civ_elf", "文明升級使用精靈徽章圖示")
	var lv_xp_before := run.xp
	await click_at(g.civup_btn.get_global_rect().get_center())
	check(run.gold == 1 and run.xp == lv_xp_before + 4, "點文明圖示：+4 XP、−4 金")
	check(g._gold_label.text == "1" and g._lv_label.text == "Lv.%d" % run.level(), "金幣與等級即時更新")
	var plan := Economy.xp_plan(run.xp)
	check(g.xp_left.text.strip_edges() == "%d/%d XP" % [plan["cur"], plan["need"]] and g._xp_cost_label.text == str(plan["cost"]), "XP 條即時更新")
	check(g.civup_btn.disabled, "金幣不足時停用")
	var xp_w: float = g.xp_bar.get_global_rect().size.x
	var slots_w: float = g.shop_slots.get_global_rect().size.x
	check(absf(xp_w - slots_w) <= 2.0, "XP 條與五格商店等寬（%.0f vs %.0f）" % [xp_w, slots_w])
	var top_rect: Rect2 = g.top_bar.get_global_rect()
	var bottom_rect: Rect2 = g.bottom_bar.get_global_rect()
	check(top_rect.end.y < bottom_rect.position.y, "上方列與下方操作區不重疊")
	check(g.get_node("LeftPanel/Scroll/List").get_child(0) == g.civ_btn, "文明固定在羈絆清單第一項")
	check(g.left_panel.get_global_rect().size.x <= 170.0, "羈絆清單寬度受限（%.0f）" % g.left_panel.get_global_rect().size.x)
	check(not g.is_popover_open(), "文明效果平常不顯示長文字")
	var board_pos0: Vector2 = board.position
	var hex0: float = board.hex_size
	await hover(g.civ_btn.get_global_rect().get_center())
	check(g.is_popover_open() and g.popover_key() == "civ", "滑鼠懸停文明 → 浮動說明")
	check(g.popover_bbcode().count("▲") == 2 and g.popover_bbcode().count("▼") == 2, "說明列出 2 Buff＋2 Debuff")
	check(board.position == board_pos0 and board.hex_size == hex0, "浮動說明不推動棋盤")
	await hover(screen_pos(board, board.cell_center(Vector2i(3, 2))))
	check(not g.is_popover_open(), "滑鼠移開 → 說明消失")
	await click_at(g.civ_btn.get_global_rect().get_center())
	check(g.is_popover_open() and g._pop_pinned, "點擊文明（手機）→ 固定顯示說明")
	await shot("civ_popover")
	await click_at(screen_pos(board, board.cell_center(Vector2i(3, 2))))
	check(not g.is_popover_open(), "點空白處關閉說明")
	var vs: Vector2 = g.get_viewport_rect().size
	var br := board_screen_rect(board)
	check(br.position.y >= g.top_bar.get_global_rect().end.y - 0.5 and br.end.y <= g.bottom_bar.get_global_rect().position.y + 0.5, "棋盤與上下兩條不重疊（%s／上 %s／下 %s）" % [str(br), str(g.top_bar.get_global_rect()), str(g.bottom_bar.get_global_rect())])
	check(br.position.x >= g.left_panel.get_global_rect().end.x - 0.5, "棋盤不被羈絆清單遮住")
	check(absf(br.get_center().x - vs.x * 0.5) <= 2.0, "棋盤固定置中")
	if vs.y == 720.0:
		check(board.hex_size >= 36.5, "棋盤放大（格子 %.1f，V0.3 為 34.0）" % board.hex_size)
	await shot("prep_layout")

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
	var tk0: UnitToken = board._prep_tokens.get(uid)
	var hl: Dictionary = tk0.head_layout()
	check(hl["mark"].x < (hl["bar"] as Rect2).position.x and tk0.star == 1, "星級標記在 HP／MP 條左側（一星一點）")
	check((hl["items"] as Array).is_empty(), "沒有裝備的棋子不畫裝備格")
	var bp0: Vector2 = board.position
	await click_at(screen_pos(board, board.bench_center(bidx)))
	check(g._info_mode == "unit" and g.detail_box.visible, "點棋子 → 右側顯示資訊卡")
	await get_tree().process_frame
	check(board.position == bp0, "資訊卡浮在右側，不推動棋盤")
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

	# ── 裝備（V0.4）：點空欄位 → 右側背包 → 點裝備直接穿上 ──
	run.inventory = ["DM_PLATE", "CU_DAGGER", "OG_EYE"]
	run.changed.emit()
	await get_tree().process_frame
	var white_armor := card.cell_color("armor")
	var bpos: Vector2 = board.position
	card.slot_button(0).pressed.emit()
	await get_tree().process_frame
	check(g.is_bag_open(), "點空裝備欄 → 右側打開背包")
	check(board.position == bpos, "背包浮在右側，不推動棋盤")
	var row0: Button = g.bag_row_button(0)
	if row0 == null:
		check(false, "背包列出裝備")
		get_tree().quit(1)
		return
	row0.pressed.emit()
	await wait(0.2)
	check(RunState.unit_items(run.find_unit(uid)["unit"]) == ["DM_PLATE"], "點裝備 → 穿到這隻棋子")
	check(not g.is_bag_open(), "裝上後背包關閉、回到棋子資訊")
	check(card.cell_color("armor") != white_armor and card.cell_color("armor").b > card.cell_color("armor").r, "裝備物防 → 物防數字變藍")
	check(run.inventory == ["CU_DAGGER", "OG_EYE"], "背包少一件")
	check((board._prep_tokens[uid].head_layout()["items"] as Array).size() == 1, "穿 1 件裝備：棋子下方只畫 1 個圖示")
	await shot("card_equipped")
	# 鎖定：已裝備的欄位只能用卸除器取下
	card.slot_button(0).pressed.emit()
	await get_tree().process_frame
	var rm_btn: Button = null
	for bb in g.item_buttons.get_children():
		if (bb as Button).text.begins_with("使用卸除器"):
			rm_btn = bb
	check(rm_btn != null and rm_btn.disabled, "沒有卸除器時不能取下（按鈕停用）")
	check(not g.item_buttons.get_children().any(func(x): return (x as Button).text == "卸下" or (x as Button).text == "更換"), "沒有免費卸下或更換")
	g.item_overlay.visible = false
	run.removers = 1
	card.slot_button(0).pressed.emit()
	await get_tree().process_frame
	for bb in g.item_buttons.get_children():
		if (bb as Button).text.begins_with("使用卸除器"):
			rm_btn = bb
	rm_btn.pressed.emit()
	await wait(0.1)
	check(RunState.unit_items(run.find_unit(uid)["unit"]).is_empty() and run.inventory.size() == 3 and run.removers == 0, "使用卸除器：裝備回背包、卸除器 −1")
	# 拖曳：從背包把裝備拖到棋子上
	g.bag_btn.pressed.emit()
	await wait(0.1)
	check(g.is_bag_open(), "按背包按鈕打開背包")
	await shot("bag")
	var drag_row: Button = g.bag_row_button(0)
	var drag_id: String = run.inventory[0]
	var tok_pos := screen_pos(board, board._prep_tokens[uid].position)
	var from_pos := drag_row.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from_pos
	down.global_position = from_pos
	get_tree().root.push_input(down, true)
	await get_tree().process_frame
	for i in range(1, 9):
		var mv := InputEventMouseMotion.new()
		mv.position = from_pos.lerp(tok_pos, i / 8.0)
		mv.global_position = mv.position
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_tree().root.push_input(mv, true)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = tok_pos
	up.global_position = tok_pos
	get_tree().root.push_input(up, true)
	await wait(0.15)
	check(RunState.unit_items(run.find_unit(uid)["unit"]) == [drag_id], "拖曳裝備到棋子 → 穿上")
	# 點裝備再點棋子（手機替代操作）
	g.bag_btn.pressed.emit()
	await wait(0.1)
	var tap_id: String = run.inventory[0]
	g.bag_row_button(0).pressed.emit()
	await get_tree().process_frame
	check(g._pending_item == 0, "點一下裝備 → 進入選擇棋子")
	await click_at(screen_pos(board, board.bench_center(bidx)))
	check(RunState.unit_items(run.find_unit(uid)["unit"]) == [drag_id, tap_id], "再點棋子 → 穿上")
	g.bag_btn.pressed.emit()
	await wait(0.1)
	g.bag_row_button(0).pressed.emit()
	await get_tree().process_frame
	await click_at(screen_pos(board, board.bench_center(bidx)))
	check(RunState.unit_items(run.find_unit(uid)["unit"]).size() == 2 and run.inventory.size() == 1, "兩格已滿時不能再穿、不覆蓋")
	g._close_bag()

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
	check(not g.has_node("BottomBar/VBox/RowB/RightButtons/StartButton"), "沒有開始戰鬥按鈕（倒數歸零自動開戰）")

	# ── V0.5：戰鬥中經營商店與即時裝備 ──
	var bpl: BattlePlayer = g.battle_player
	# 第 1 回合的稻草兵太脆，讓它耐打一點，確保以下檢查都在戰鬥進行中完成（只改這場測試的模擬）
	for eu in bpl.sim().units:
		if eu.side == 1:
			eu.max_hp = 2500.0
			eu.hp = 2500.0
	run.gold = 40
	run.changed.emit()
	var gold_r := run.gold
	g.reroll_btn.pressed.emit()
	await get_tree().process_frame
	check(run.gold == gold_r - Economy.reroll_cost(), "戰鬥中可以刷新商店")
	var bench_n := run.all_units().size()
	for i in run.shop.size():
		if run.can_buy(i) == "":
			(g.get_node("BottomBar/VBox/RowB/ShopSlots/Slot%d" % i) as Button).pressed.emit()
			break
	await get_tree().process_frame
	check(run.all_units().size() >= bench_n, "戰鬥中可以購買棋子")
	var fight_uid := int(run.board_lineup()[0]["uid"])
	RunState.unit_items(run.find_unit(fight_uid)["unit"]).clear()   # 確保有空裝備欄（之前測試穿過的裝備直接清掉）
	run._sync_live_items(fight_uid)
	await wait(0.2)
	var live_cu: CombatUnit = bpl.sim().units.filter(func(x): return x.uid == fight_uid)[0]
	var atk_live0 := live_cu.atk
	run.inventory.append("DM_GREATAXE")
	run.changed.emit()
	g._open_bag(fight_uid)
	await get_tree().process_frame
	var axe_i := run.inventory.find("DM_GREATAXE")
	g.bag_row_button(axe_i).pressed.emit()
	await wait(0.3)
	check(is_equal_approx(live_cu.atk, atk_live0 + 22.0), "戰鬥中替場上棋子穿裝備：攻擊力立即 +22（%.1f → %.1f）" % [atk_live0, live_cu.atk])
	check(bpl.token(live_cu.cid).items.has("DM_GREATAXE"), "棋盤上的棋子裝備圖示即時更新")
	check(run.sell(fight_uid) != "", "戰鬥中的場上棋子不能出售")

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
		check(run.board_count() == g.battle_player.sim().snapshots().filter(func(x): return x["side"] == 0).size(), "整理候補不會把棋子加入戰場")
	await wait(0.8)
	var my_cid := -1
	var foe_cid := -1
	for snap in bp.player_lineup():
		my_cid = int(snap["cid"])
	for cid in bp._units.keys():
		if int(bp._units[cid]["side"]) == 1:
			foe_cid = int(cid)
	await click_at(screen_pos(board, bp.token(my_cid).position))
	check(g._info_mode == "battle" and card.visible, "戰鬥中點己方棋子顯示資訊卡（%s, %s, phase %d）" % [g._info_mode, str(card.visible), g.phase])
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
	g.skip_btn.pressed.emit()   # 略過動畫（直接算完，結果與正常播放相同）
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

	# ── 收合：右側排行浮在戰場上，開關不推動棋盤 ──
	g.prep_timer.remaining = 999.0
	var pos_open: Vector2 = board.position
	var hex_open: float = board.hex_size
	g.leader._toggle.pressed.emit()
	await wait(0.3)
	check(g.right_panel.get_global_rect().size.x < 80 and g.right_panel.get_global_rect().size.y < 80, "右側貢獻面板收合成小圖示")
	check(board.position == pos_open and board.hex_size == hex_open, "收合排行：棋盤位置與大小不變")
	await shot("collapsed")
	g.leader._toggle.pressed.emit()
	await wait(0.3)
	check(board.position == pos_open and board.hex_size == hex_open, "展開排行：棋盤位置與大小不變")

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
