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
	await shot("civ_select")
	var grid: GridContainer = scene().get_node("Margin/VBox/CivGrid")
	check(grid.get_child_count() == 6, "六個文明卡")
	(grid.get_child(1) as Button).pressed.emit()   # 人類
	await wait(0.2)
	await shot("civ_selected")
	press("Margin/VBox/Buttons/StartButton")
	await wait(0.8)
	check(scene().name == "Game", "進入遊戲畫面")
	var run: RunState = Session.run
	check(run != null and run.civ_id == "human", "建立人類文明遠征")
	check(run.round_no == 1 and run.gold == 5 and run.hp == 40 and run.level() == 1, "第 1 回合：5 金、Lv.1、生命 40")
	check(run.shop.size() == 5, "商店 5 格")
	check(SaveSystem.has_save(), "進入備戰後自動存檔")

	# 用畫面按鈕買棋子
	var g := scene()
	var board: BoardView = g.get_node("BoardView")
	for i in 5:
		var b: Button = g.get_node("ShopBar/HBox/ShopSlots/Slot%d" % i)
		if not b.disabled:
			b.pressed.emit()
			await get_tree().process_frame
	var owned := run.all_units().size()
	check(owned >= 3, "透過商店按鈕購買棋子（%d 隻）" % owned)
	check(run.gold >= 0, "金幣不為負")
	await shot("prep_bought")

	# 模擬點選：點候補第 1 格 → 點棋盤 (3,5)
	var first_uid := int(run.bench[0]["uid"]) if run.bench[0] != null else -1
	await click_at(screen_pos(board, board.bench_center(0)))
	check(board.selected_uid() == first_uid, "點選候補棋子（觸控／滑鼠點擊）")
	await click_at(screen_pos(board, board.cell_center(Vector2i(3, 5))))
	check(run.board.has(Vector2i(3, 5)), "再點空格把棋子部署到棋盤")
	# 拖曳：候補第 2 隻拖到 (2,4) → 應因人數上限失敗
	var second_idx := -1
	for i in run.bench.size():
		if run.bench[i] != null:
			second_idx = i
			break
	if second_idx >= 0:
		await drag(screen_pos(board, board.bench_center(second_idx)), screen_pos(board, board.cell_center(Vector2i(2, 4))))
		check(run.board_count() == 1, "Lv.1 時拖曳第 2 隻上場會被拒絕")
	# 拖曳場上棋子到另一格
	await drag(screen_pos(board, board.cell_center(Vector2i(3, 5))), screen_pos(board, board.cell_center(Vector2i(3, 4))))
	check(run.board.has(Vector2i(3, 4)) and not run.board.has(Vector2i(3, 5)), "拖曳移動場上棋子")
	# 拖到商店列出售
	if second_idx >= 0 and run.bench[second_idx] != null:
		var gold_before := run.gold
		var shop_bar: Control = g.get_node("ShopBar")
		await drag(screen_pos(board, board.bench_center(second_idx)), shop_bar.get_global_rect().get_center())
		check(run.gold > gold_before, "拖到商店列出售")
	await shot("prep_deployed")

	# 開戰
	press("ShopBar/HBox/RightButtons/StartButton")
	await wait(1.6)
	check(g.phase == 1, "進入戰鬥階段")
	await shot("battle")
	Session.battle_speed = 4.0
	var t := 0.0
	while not g.get_node("ResultOverlay").visible and t < 30.0:
		await wait(0.25)
		t += 0.25
	check(g.get_node("ResultOverlay").visible, "戰鬥播放完畢並顯示結算")
	await shot("result")
	check(run.round_no == 2 or run.finished, "結算後進入第 2 回合")
	check(run.history.size() == 1, "有 1 筆回合紀錄")
	press("ResultOverlay/Panel/VBox/ResultButton")
	await wait(0.4)
	check(g.phase == 0, "回到備戰")

	# 用 bot 操作 RunState，畫面跟著更新，連打幾回合
	for r in 4:
		AutoPlayer.play_prep(run)
		await wait(0.2)
		if r == 3:
			await shot("prep_round%d" % run.round_no)
		press("ShopBar/HBox/RightButtons/StartButton")
		await wait(0.3)
		g.battle_player.skip()
		await wait(0.3)
		check(g.get_node("ResultOverlay").visible, "第 %d 回合結算顯示" % (run.round_no - 1))
		if run.finished:
			break
		press("ResultOverlay/Panel/VBox/ResultButton")
		await wait(0.3)
	check(run.history.size() >= 4, "連續完成多個回合（%d）" % run.history.size())

	# 點選場上棋子 → 資訊面板
	if not run.board.is_empty():
		var cell: Vector2i = run.board.keys()[0]
		await click_at(screen_pos(board, board.cell_center(cell)))
		check(g.get_node("InfoPanel/VBox/SellButton").visible, "點選棋子顯示資訊與出售按鈕")
		await shot("unit_info")
	# 點敵方棋子
	var e: Array = BattleSetup.stage_units(run.round_no)
	if not e.is_empty():
		await click_at(screen_pos(board, board.cell_center(e[0]["cell"])))
		check(str(g.get_node("InfoPanel/VBox/Header/InfoTitle").text).begins_with("敵方"), "點敵方棋子顯示敵軍資訊")

	# 收合羈絆面板
	press("TraitPanel/VBox/Header/TraitToggle")
	await wait(0.2)
	await shot("traits_collapsed")
	press("TraitPanel/VBox/Header/TraitToggle")
	await wait(0.2)

	# 存檔續玩：回主選單 → 繼續
	var round_before := run.round_no
	press("TopBar/HBox/MenuBtn")
	await wait(0.2)
	press("MenuOverlay/Panel/VBox/SaveQuitButton")
	await wait(0.6)
	check(scene().name == "MainMenu", "存檔並回主選單")
	check(not scene().get_node("Center/Box/ContinueButton").disabled, "有存檔時「繼續」可用")
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
	await shot("codex_rules")
	(scene().get_node("Margin/VBox/Tabs") as TabContainer).current_tab = 1
	await wait(0.3)
	check(scene().get_node("Margin/VBox/Tabs/Units/UnitGrid").get_child_count() == 24, "圖鑑列出 24 隻棋子")
	await shot("codex_units")
	press("Margin/VBox/Header/BackButton")
	await wait(0.8)
	check(scene().name == "Game", "從圖鑑返回遊戲")
	g = scene()

	# 除錯：跳到第 24 回合並直接過關 → 通關畫面
	if Session.debug_enabled:
		(g.get_node("DebugPanel/VBox/RoundRow/RoundSpin") as SpinBox).value = 24
		press("DebugPanel/VBox/RoundRow/JumpButton")
		await wait(0.4)
		check(Session.run.round_no == 24, "除錯選關到第 24 回合")
		await shot("round24")
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
