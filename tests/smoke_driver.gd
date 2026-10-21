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


func _run() -> void:
	SaveSystem.clear()
	Session.goto(Session.SCENE_MENU)
	await wait(0.6)
	check(scene().name == "MainMenu", "主選單開啟")
	check(scene().get_node("Center/Box/ContinueButton").disabled, "無存檔時「繼續」停用")
	await shot("menu")

	press("Center/Box/NewGameButton")
	await wait(0.5)
	check(scene().name == "CivSelect", "進入文明選擇")
	var grid: GridContainer = scene().get_node("Margin/VBox/CivGrid")
	check(grid.get_child_count() == 6, "六個文明卡")
	(grid.get_child(1) as Button).pressed.emit()   # 人類
	await wait(0.2)
	press("Margin/VBox/Buttons/StartButton")
	await wait(0.8)
	check(scene().name == "Game", "進入遊戲畫面")
	var run: RunState = Session.run
	var g := scene()
	var board: BoardView = g.get_node("BoardView")
	check(run != null and run.civ_id == "human", "建立人類文明遠征")
	check(run.round_no == 1 and run.gold == 5 and run.hp == 40 and run.level() == 1, "第 1 回合：5 金、Lv.1、生命 40")
	check(SaveSystem.has_save(), "進入備戰後自動存檔")
	check(g.prep_timer.running and g.prep_timer.seconds_left() >= 14, "備戰 15 秒倒數已開始")

	# 版面：文明面板在羈絆面板左側
	var civ_rect: Rect2 = g.get_node("CivPanel").get_global_rect()
	var trait_rect: Rect2 = g.get_node("TraitPanel").get_global_rect()
	check(civ_rect.end.x <= trait_rect.position.x + 0.5, "文明面板位於羈絆面板左側")
	check(str(g.get_node("CivPanel/VBox/CivScroll/CivText").text).contains("▲") and str(g.get_node("CivPanel/VBox/CivScroll/CivText").text).contains("▼"), "文明面板常駐顯示 Buff 與 Debuff")
	check(str(g.get_node("ShopBar/HBox/LevelBox/LevelRow/LevelLabel").text) == "Lv.1", "商店旁顯示文明等級")
	check(str(g.get_node("ShopBar/HBox/LevelBox/XpText").text).contains("還差"), "顯示還差多少經驗與購買次數")
	check(str(g.get_node("TopBar/HBox/GoldLabel").text).contains("再"), "顯示下一個利息門檻")

	# 第一回合：買一隻、不部署，等 15 秒倒數 → 自動補位並自動開戰
	var b0: Button = g.get_node("ShopBar/HBox/ShopSlots/Slot0")
	b0.pressed.emit()
	await get_tree().process_frame
	check(run.board_count() == 0 and run.all_units().size() == 1, "買了 1 隻放在候補區")
	await shot("prep_round1")
	var t0 := Time.get_ticks_msec()
	while g.phase == 0 and Time.get_ticks_msec() - t0 < 17000:
		if g.prep_timer.is_warning() and not g.big_countdown.visible:
			pass
		await wait(0.1)
	var waited := (Time.get_ticks_msec() - t0) / 1000.0
	check(g.phase == 1, "倒數結束後自動開戰（等了 %.1f 秒）" % waited)
	check(waited > 13.5 and waited < 16.5, "倒數約 15 秒（%.1f）" % waited)
	check(run.board_count() == 1, "人口未滿時自動從候補區補位")

	# 戰鬥中點選雙方棋子查看（唯讀，不影響戰鬥）
	await wait(0.6)
	var bp: BattlePlayer = g.battle_player
	var my_cid := -1
	var foe_cid := -1
	for s in bp.player_lineup():
		my_cid = int(s["cid"])
	for cid in bp._units.keys():
		if int(bp._units[cid]["side"]) == 1:
			foe_cid = int(cid)
	var clock_before := bp.sim_time()
	await click_at(screen_pos(board, bp.token(my_cid).position))
	check(g._info_mode == "battle" and int(g._info_ref) == my_cid, "戰鬥中點己方棋子 → 以 cid 顯示資料")
	check(not g.get_node("InfoPanel/VBox/SellButton").visible, "戰鬥中不能出售")
	await shot("battle_inspect_own")
	if bp.is_alive(foe_cid):
		await click_at(screen_pos(board, bp.token(foe_cid).position))
		check(str(g.get_node("InfoPanel/VBox/Header/InfoTitle").text).begins_with("敵方"), "戰鬥中點敵方棋子顯示敵軍資料")
		var info_txt := ""
		for c in g.info_body.get_children():
			if c is RichTextLabel:
				info_txt += c.text
		check(info_txt.contains("生命") and info_txt.contains("魔力"), "顯示即時生命、護盾與魔力")
	await wait(0.3)
	check(g.phase != 0 and (bp.sim_time() > clock_before or not bp.is_playing()), "查看資料不會暫停戰鬥")

	# 播放結束後，畫面上的血量必須和模擬結果一致（加速不改變結果）
	var t1 := 0.0
	while not g.get_node("ResultOverlay").visible and t1 < 40.0:
		await wait(0.25)
		t1 += 0.25
	check(g.get_node("ResultOverlay").visible, "戰鬥播放完畢並顯示結算")
	var final_hp := {}
	for e in g._last_result["events"]:
		if e["k"] in ["damage", "heal"]:
			final_hp[e["tgt"]] = float(e["hp"])
	var hp_ok := true
	for cid in final_hp.keys():
		var tk := bp.token(cid)
		if tk and absf(tk.hp - float(final_hp[cid])) > 0.01:
			hp_ok = false
	check(hp_ok, "播放後每隻棋子的血量與戰鬥模擬結果完全一致")
	check(g.leader_list.get_child_count() > 0, "結算顯示戰鬥貢獻排行")
	for i in 4:
		(g.get_node("ResultOverlay/Panel/VBox/LeaderTabs/Tab%d" % i) as Button).pressed.emit()
		await get_tree().process_frame
		check(g._leader_metric == Leaderboard.ORDER[i], "切換排行：%s" % Leaderboard.METRICS[Leaderboard.ORDER[i]])
	(g.get_node("ResultOverlay/Panel/VBox/LeaderTabs/Tab0") as Button).pressed.emit()
	await shot("result_leaderboard")
	press("ResultOverlay/Panel/VBox/ResultButton")
	await wait(0.4)
	check(g.phase == 0, "回到備戰")
	check(g.get_node("TopBar/HBox/ReportButton").visible, "備戰時可重新查看上一場戰報")

	# 選取與拖曳判定（倒數期間讓計時先停在很大，避免測試途中自動開戰）
	g.prep_timer.remaining = 999.0
	run.gold = 30
	run.changed.emit()
	for i in 5:
		var b: Button = g.get_node("ShopBar/HBox/ShopSlots/Slot%d" % i)
		if not b.disabled:
			b.pressed.emit()
			await get_tree().process_frame
	var bench_idx: Array = []
	for i in run.bench.size():
		if run.bench[i] != null:
			bench_idx.append(i)
	if bench_idx.size() >= 2:
		var ua := int(run.bench[bench_idx[0]]["uid"])
		var ub := int(run.bench[bench_idx[1]]["uid"])
		var gold_before := run.gold
		await click_at(screen_pos(board, board.bench_center(bench_idx[0])))
		check(board.selected_uid() == ua, "點選棋子 A")
		check(run.gold == gold_before and not run.find_unit(ua).is_empty(), "單純點擊不會誤判為出售")
		await click_at(screen_pos(board, board.bench_center(bench_idx[1])))
		check(board.selected_uid() == ub, "點另一隻棋子正確切換選取")
		await shot("selection")
		var info_btn: Button = null
		for c in g.info_body.get_children():
			if c is Button:
				info_btn = c
				break
		if info_btn:
			info_btn.pressed.emit()
			await get_tree().process_frame
			check(info_btn.text.begins_with("▾"), "點屬性展開數值來源")
			await shot("stat_expanded")
		var empty_spot := screen_pos(board, Vector2(-30, board.board_size().y * 0.5))
		await click_at(empty_spot)
		check(board.selected_uid() == -1, "點棋盤外空白處取消選取")

	# 羈絆名單
	AutoPlayer.arrange(run)
	await wait(0.2)
	var trait_btn: Button = null
	for c in g.trait_list.get_children():
		if c is Button:
			trait_btn = c
			break
	check(trait_btn != null, "羈絆面板是可點選的清單")
	if trait_btn:
		trait_btn.pressed.emit()
		await wait(0.2)
		check(str(g.get_node("InfoPanel/VBox/Header/InfoTitle").text).begins_with("羈絆："), "點羈絆顯示完整名單")
		await shot("trait_detail")

	# 收合側邊面板仍保持文明在羈絆左側
	press("CivPanel/VBox/Header/CivToggle")
	press("TraitPanel/VBox/Header/TraitToggle")
	await wait(0.3)
	civ_rect = g.get_node("CivPanel").get_global_rect()
	trait_rect = g.get_node("TraitPanel").get_global_rect()
	check(civ_rect.end.x <= trait_rect.position.x + 0.5 and trait_rect.size.x < 80, "收合後仍維持文明在羈絆左側")
	await shot("panels_collapsed")
	press("CivPanel/VBox/Header/CivToggle")
	press("TraitPanel/VBox/Header/TraitToggle")
	await wait(0.2)

	# 倒數最後 5 秒的警示
	g.prep_timer.remaining = 4.5
	await wait(0.3)
	check(g.big_countdown.visible, "倒數最後 5 秒顯示大字警示")
	await shot("countdown_warning")
	g.prep_timer.remaining = 999.0

	# 用 bot 操作連打幾回合（略過動畫）
	for r in 3:
		AutoPlayer.play_prep(run)
		await wait(0.2)
		press("ShopBar/HBox/RightButtons/StartButton")
		await wait(0.3)
		g.battle_player.skip()
		await wait(0.3)
		check(g.get_node("ResultOverlay").visible, "第 %d 回合結算顯示" % (run.round_no - 1))
		if run.finished:
			break
		press("ResultOverlay/Panel/VBox/ResultButton")
		await wait(0.3)
		g.prep_timer.remaining = 999.0
	check(run.history.size() >= 4, "連續完成多個回合（%d）" % run.history.size())

	# 存檔續玩
	var round_before := run.round_no
	press("TopBar/HBox/MenuBtn")
	await wait(0.2)
	check(g.prep_timer.paused, "開選單時暫停倒數")
	press("MenuOverlay/Panel/VBox/SaveQuitButton")
	await wait(0.6)
	check(scene().name == "MainMenu", "存檔並回主選單")
	press("Center/Box/ContinueButton")
	await wait(0.8)
	check(scene().name == "Game" and Session.run.round_no == round_before, "繼續遠征回到同一回合")
	run = Session.run
	g = scene()

	# 圖鑑
	press("TopBar/HBox/MenuBtn")
	await wait(0.2)
	press("MenuOverlay/Panel/VBox/CodexButton")
	await wait(0.8)
	check(scene().name == "Codex", "開啟圖鑑")
	(scene().get_node("Margin/VBox/Tabs") as TabContainer).current_tab = 1
	await wait(0.3)
	check(scene().get_node("Margin/VBox/Tabs/Units/UnitGrid").get_child_count() == 24, "圖鑑列出 24 隻棋子（不含教學弱敵）")
	press("Margin/VBox/Header/BackButton")
	await wait(0.8)
	check(scene().name == "Game", "從圖鑑返回遊戲")
	g = scene()

	# 除錯：跳到第 24 回合並直接過關 → 通關畫面
	if Session.debug_enabled:
		g.prep_timer.remaining = 999.0
		(g.get_node("DebugPanel/VBox/RoundRow/RoundSpin") as SpinBox).value = 24
		press("DebugPanel/VBox/RoundRow/JumpButton")
		await wait(0.4)
		check(Session.run.round_no == 24, "除錯選關到第 24 回合")
		press("DebugPanel/VBox/Row3/WinButton")
		await wait(0.3)
		check(Session.run.outcome == "victory", "第 24 回合全清 → 通關")
		press("ResultOverlay/Panel/VBox/ResultButton")
		await wait(0.8)
		check(scene().name == "EndScreen", "顯示遠征結算畫面")
		await shot("end_screen")
		check(not SaveSystem.has_save(), "遠征結束後清除存檔")

	print("")
	print("冒煙測試：%s（失敗 %d 項）" % ["通過" if failures.is_empty() else "未通過", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
