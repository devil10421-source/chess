extends "res://tests/smoke_driver.gd"
## 《氏族爭霸》實機冒煙測試：主選單 → 開局設定 → 十人對局畫面；備戰、PvP、合作 PvE 交易、國家制度、淘汰、觀戰、最終結算。


func _run() -> void:
	SaveSystem.path_override = "user://clash_smoke_save.json"
	Session.goto(Session.SCENE_MENU)
	await wait(0.6)
	check(scene().name == "MainMenu", "主選單開啟")
	var cb: Button = scene().get_node("Center/Box/ClashButton")
	check(cb != null, "主選單有《氏族爭霸》入口，單人模式保留")
	check(scene().get_node("Center/Box/NewGameButton").visible, "單人《六族遠征》入口仍在")
	cb.pressed.emit()
	await wait(0.6)
	check(scene().name == "ClashSetup", "進入開局設定")
	scene().country_edit.text = "永遠正確的人民共和國"
	scene().name_edit.text = "玩家001"
	scene().seed_edit.text = "4242"
	await shot("clash_setup")
	scene().start_btn.pressed.emit()
	await wait(1.0)
	var g = scene()
	check(g.name == "ClashGame", "進入十人對局畫面")
	Session.battle_speed = 4.0
	var m: ClashMatch = Session.clash
	check(m != null and m.players.size() == 10, "10 名玩家（1 真人＋9 AI）")
	check(m.human().country == "永遠正確的人民共和國" and m.human().player_name == "玩家001", "國家名稱與統治者名稱")
	check(m.players.filter(func(p): return not p.is_human).size() == 9, "9 名 AI")
	check(GameData.civ(Session.run.civ_id).is_empty(), "沒有開局文明（取消文明選擇）")
	var board: BoardView = g.board
	check(board.hex_size >= 36.0, "棋盤沒有因十人列表縮小（格子 %.1f）" % board.hex_size)
	await wait(0.2)
	check(g.players_panel.visible and g.players_list.get_child_count() == 10, "十人生命／名次列表")
	var br: Rect2 = Rect2(board.get_global_transform_with_canvas() * Vector2.ZERO, board.board_size() * board.get_global_transform_with_canvas().get_scale())
	check(not g.players_panel.get_global_rect().intersects(br.grow(-board.hex_size * 0.6)), "十人列表不遮擋六角棋盤（列表 %s／棋盤 %s）" % [str(g.players_panel.get_global_rect()), str(br)])
	check(g.bar_left.text.contains("PvP 對手") or g.bar_left.text.contains("幽靈"), "上方顯示回合類型與對手（%s）" % g.bar_left.text)
	check(g.round_label.text == "第 1 回合", "回合標籤")
	check(is_equal_approx(g.prep_timer.duration, ClashMatch.prep_seconds(1)), "第 1 回合備戰秒數依設定")
	await shot("clash_prep")
	# 收合／展開列表
	g.players_toggle.pressed.emit()
	await wait(0.1)
	check(not g.players_list.visible, "十人列表可以收合")
	g.players_toggle.pressed.emit()
	await wait(0.1)
	# 買一隻棋子
	var gold0: int = Session.run.gold
	for i in 5:
		if Session.run.can_buy(i) == "":
			(g.get_node("BottomBar/VBox/RowB/ShopSlots/Slot%d" % i) as Button).pressed.emit()
			break
	await wait(0.1)
	check(Session.run.gold < gold0, "可以從共用棋池購買")
	check(m.pool.audit().is_empty(), "棋池守恆")
	# ── 觀看其他玩家的棋盤（備戰中） ──
	var other_seat := _some_other_seat(m)
	var op: ClashPlayer = m.players[other_seat]
	var my_gold: int = Session.run.gold
	var their_units := op.run.all_units().size()
	await click_at(_row_center(g, other_seat))
	await wait(0.2)
	check(g.view_seat == other_seat and g.view_board.visible and not g.board.visible, "點擊其他玩家 → 切換到他的棋盤")
	check(g.view_banner.visible and g.view_label.text.contains(op.country) and g.view_label.text.contains(op.player_name), "顯示國家與玩家名稱")
	check(g.view_label.text.contains("生命 %d" % op.hp) and g.view_label.text.contains("Lv.%d" % op.run.level()), "顯示生命與等級")
	eq_check(g.view_board._prep_tokens.size(), their_units, "顯示對方的棋子（含候補）")
	var pos_ok := true
	var star_ok := true
	var items_ok := true
	for cell in op.run.board.keys():
		var u: Dictionary = op.run.board[cell]
		var tk = g.view_board._prep_tokens.get(int(u["uid"]))
		if tk == null or tk.position.distance_to(g.view_board.cell_center(cell)) > 1.0:
			pos_ok = false
		if tk == null or tk.star != int(u["star"]):
			star_ok = false
		if tk == null or tk.items != RunState.unit_items(u):
			items_ok = false
	check(pos_ok, "棋子站位正確")
	check(star_ok, "星級正確")
	check(items_ok, "裝備正確")
	await shot("clash_view_prep")
	# 唯讀：點對方棋子不會選取或移動，不會動到任何人的資源
	if not op.run.board.is_empty():
		var c0: Vector2i = op.run.board.keys()[0]
		var before := op.run.board_lineup()
		await drag(screen_pos(g.view_board, g.view_board.cell_center(c0)), screen_pos(g.view_board, g.view_board.cell_center(Vector2i(0, 7))))
		check(op.run.board_lineup() == before, "不能操作對方的棋子")
		check(g.view_board.selected_uid() == -1 and g.board.selected_uid() == -1, "觀看時點擊不會選取")
	check(Session.run.gold == my_gold and m.human_seat == 0 and Session.run == m.human().run, "操作權限仍是自己（local 與 viewed 分開）")
	await click_at(_row_center(g, m.human_seat))
	await wait(0.2)
	check(g.view_seat == -1 and g.board.visible and not g.view_board.visible and not g.view_banner.visible, "點擊自己 → 返回自己的棋盤")
	# ── 第 1 回合 PvP：不按略過，戰鬥自然結束後自動進入第 2 回合；戰鬥中觀看其他玩家 ──
	g.prep_timer.remaining = 0.2
	await wait(0.5)
	check(g.phase == 1, "第 1 回合進入戰鬥")
	var watch_seat := _some_other_seat(m)
	await click_at(_row_center(g, watch_seat))
	await wait(0.3)
	check(g.view_board.battle_player.is_watching(), "戰鬥中觀看：播放對方那一場戰鬥")
	check(g.view_board.battle_player._tokens.size() > 0, "對方戰場有棋子")
	var my_clock0: float = g.battle_player.sim_time()
	var idx0: int = g.view_board.battle_player._index
	var tok0: Dictionary = g.view_board.battle_player._tokens.duplicate()
	await wait(0.8)
	await shot("clash_view_battle")
	check(g.battle_player.sim_time() > my_clock0 or g._my_battle_done, "觀看時自己的戰鬥繼續進行")
	check(g.view_board.battle_player._index >= idx0, "對方戰鬥事件持續往前播放")
	check(tok0.keys().all(func(k): return g.view_board.battle_player._tokens.has(k) and g.view_board.battle_player._tokens[k] == tok0[k]), "切換觀看不會重新生成單位")
	await click_at(_row_center(g, m.human_seat))
	await wait(0.2)
	check(g.board.visible and not g.view_board.visible, "戰鬥中可切回自己的棋盤")
	var ok1 := await _natural_round(g, m)
	check(ok1 and m.round_no == 2, "第 1 回合戰鬥自然結束後自動進入第 2 回合（未按略過）")
	# 羈絆精簡圖示欄
	_check_traits(g)
	await shot("clash_traits")
	# ── 第 2 回合：合作 PvE＋交易 ──
	var a := m.assignment(m.human_seat)
	check(m.round_kind == "pve" and str(a.get("kind", "")) in ["coop", "solo"], "第 2 回合為合作 PvE（%s）" % str(a))
	check(g.bar_left.text.contains("PvE"), "上方顯示 PvE 與隊友")
	if str(a.get("kind", "")) == "coop":
		g.prep_timer.remaining = 0.2
		await wait(0.5)
		check(g.phase == 3 and g.trade_overlay.visible, "備戰結束 → 交易畫面")
		check(g.trade_title.text.contains("隊友"), "交易畫面顯示隊友")
		check(g._do({"type": "buy", "slot": 0}) == "交易中不能購買", "真人動作經由對局管理器的同一個規則接口（交易中不能購買）")
		await shot("clash_trade")
		var t: Dictionary = m.trade_for(m.human_seat)
		var other := ClashTrade.partner(t, m.human_seat)
		# 選第一個可提出的項目（不提出以外的第一顆按鈕）
		var choices: Array = g.trade_choices.get_children()
		check(choices.size() >= 2, "可以從自己的棋子／裝備中選擇提案")
		(choices[1] as Button).pressed.emit()
		await wait(0.1)
		check(not (t["offer"][m.human_seat] as Dictionary).is_empty(), "提出一項資源")
		check(g.trade_mine.text != "" and not g.trade_mine.text.contains("尚未提出"), "顯示自己的提案")
		check(g.trade_status.text.contains("未確認"), "顯示雙方確認狀態")
		g.trade_confirm_btn.pressed.emit()
		await wait(1.2)
		var st := str(t["status"])
		check(st in ["open", "done"], "確認後等待或完成交易（%s）" % st)
		if st == "open":
			check(bool(t["confirm"][m.human_seat]) or str(t["note"]) != "", "已確認或顯示無法成交的原因")
			# 改變提案 → 雙方確認清除
			(g.trade_choices.get_children()[0] as Button).pressed.emit()
			await wait(0.05)
			check(not bool(t["confirm"][m.human_seat]) and not bool(t["confirm"][other]), "變更提案後雙方確認清除")
			g.trade_end_btn.pressed.emit()
			await wait(0.3)
		check(g.phase == 1, "交易結束後開戰")
		check(g.coop_panel.visible, "隊友戰況與援軍狀態")
		await wait(0.8)
		await shot("clash_coop_battle")
	var ok2 := await _natural_round(g, m)
	check(ok2 and m.round_no == 3, "第 2 回合 PvE（含援軍／救援）結束後自動進入第 3 回合")
	check(m.pool.audit().is_empty(), "交易與 PvE 後棋池守恆")
	# ── 快轉到第 8 回合：國家制度 ──
	var guard := 0
	var natural_ok := true
	while m.round_no < ClashGovernment.system_round() and guard < 12:
		guard += 1
		var r0 := m.round_no
		if not await _natural_round(g, m) or m.round_no != r0 + 1:
			natural_ok = false
	check(natural_ok, "第 3～7 回合不按略過也能連續推進")
	check(m.round_no == ClashGovernment.system_round() and g.phase == 0, "到第 %d 回合備戰" % ClashGovernment.system_round())
	check(g.gov_overlay.visible and g.gov_cards.get_child_count() == 3, "第 8 回合顯示三種國家制度")
	check(g.prep_timer.running and not g.prep_timer.paused, "選擇制度時倒數不暫停")
	await shot("clash_government")
	var pick: Button = g.gov_cards.get_child(2).find_children("*", "Button", true, false)[0]
	pick.pressed.emit()
	await wait(0.2)
	check(m.human().government == "commune", "選擇偉大公社並保存")
	check(not g.gov_overlay.visible and not g.gov_reopen.visible, "選完關閉")
	check(g.civ_btn.tooltip_text.contains("偉大公社"), "左側國家列顯示制度")
	# 第 8～10 回合同樣自然推進（PvE 與 PvP 都有）→ 至少連續 10 回合沒有卡住
	for k in 3:
		var r1 := m.round_no
		var okk := await _natural_round(g, m)
		check(okk and m.round_no == r1 + 1, "第 %d 回合自然結束並進入下一回合" % r1)
	check(m.round_no >= 11, "連續完成 10 回合以上（目前第 %d 回合）" % m.round_no)
	check(m.state_log.any(func(l): return str(l).contains("結算：")) and m.state_log.any(func(l): return str(l).contains("回合開始")), "回合狀態與結算日誌")
	# ── 淘汰 → 觀戰 → 最終結算 ──
	m.human().hp = 0
	await _finish_round(g, m, "")
	await wait(0.5)
	check(not m.human().alive and g.is_end_open(), "真人淘汰 → 顯示名次")
	check(g.end_title.text.contains("淘汰") and m.human().placement > 0, "淘汰畫面顯示名次（第 %d 名）" % m.human().placement)
	await shot("clash_eliminated")
	check(m.pool.audit().is_empty(), "淘汰後棋子回到共用棋池")
	var fast: Button = g.end_buttons.get_children().filter(func(b): return (b as Button).text == "快轉到結束")[0]
	fast.pressed.emit()
	var t2 := 0.0
	while not m.finished and t2 < 120.0:
		await wait(0.25)
		t2 += 0.25
	await wait(0.5)
	check(m.finished, "觀戰快轉到對局結束（第 %d 回合）" % m.round_no)
	check(g.is_end_open() and g.end_title.text.contains("冠軍"), "最終結算顯示冠軍")
	var places: Array = m.players.map(func(p): return p.placement)
	check(places.has(1) and places.all(func(x): return int(x) >= 1 and int(x) <= 10), "十人都有名次")
	await shot("clash_final")
	var menu_b: Button = g.end_buttons.get_children().filter(func(b): return (b as Button).text == "回主選單")[0]
	menu_b.pressed.emit()
	await wait(0.6)
	check(scene().name == "MainMenu" and Session.clash == null and not GameData.clash_clans_active(), "回主選單並還原中立棋子設定")
	print("")
	print("《氏族爭霸》冒煙測試：%s（失敗 %d 項）" % ["通過" if failures.is_empty() else "未通過", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func eq_check(a: Variant, b: Variant, msg: String) -> void:
	check(a == b, "%s（實際 %s，預期 %s）" % [msg, str(a), str(b)])


func _some_other_seat(m: ClashMatch) -> int:
	for s in m.alive_seats():
		if int(s) != m.human_seat and not (m.players[s] as ClashPlayer).run.board.is_empty():
			return int(s)
	for s in m.alive_seats():
		if int(s) != m.human_seat:
			return int(s)
	return -1


func _row_center(g, seat: int) -> Vector2:
	var row: Control = g.players_list.get_node("Row%d" % seat)
	return row.get_global_rect().get_center()


## 不按略過：備戰 → （交易時間到）→ 戰鬥自然播完 → 等其他戰鬥 → 結算 → 下一回合備戰。成功回傳 true
func _natural_round(g, m: ClashMatch) -> bool:
	var r0 := m.round_no
	if g.phase == 0:
		g.prep_timer.remaining = 0.2
		await wait(0.4)
	if g.phase == 3 and g.trade_overlay.visible:
		g._trade_left = 0.3   # 交易倒數直接走到尾聲（不是略過戰鬥）
	var t := 0.0
	while t < 90.0 and not g.is_end_open() and not (m.round_no > r0 and g.phase == 0):
		await wait(0.25)
		t += 0.25
	return m.round_no > r0 or g.is_end_open()


## 羈絆：精簡圖示＋進度、沒有「啟動中／上場」等狀態文字、加大間距、點擊才顯示效果、不縮小棋盤
func _check_traits(g) -> void:
	var labels: Array = g.left_panel.find_children("*", "Label", true, false)
	check(not labels.any(func(l): return (l as Label).text.contains("啟動") or (l as Label).text.contains("上場")), "左側羈絆區沒有「啟動中」「上場」文字")
	check(g.left_panel.get_theme_stylebox("panel") is StyleBoxEmpty, "不再顯示大型羈絆面板（透明背景）")
	check(g.left_panel.get_global_rect().size.x <= 112.0, "羈絆欄精簡（寬 %.0f）" % g.left_panel.get_global_rect().size.x)
	var rows: Array = g.trait_list.get_children().filter(func(c): return c is Button)
	check(not rows.is_empty(), "有羈絆圖示")
	check(rows.all(func(b): return b.find_child("Badge", true, false) != null), "每個羈絆是圖示＋進度")
	check(rows.all(func(b): return b.find_children("*", "Label", true, false).all(func(l): return (l as Label).text.contains("/"))), "文字只顯示進度（例如 2/4）")
	check(g.trait_list.get_theme_constant("separation") >= 12, "圖示之間的垂直間距（%d px）" % g.trait_list.get_theme_constant("separation"))
	if rows.size() >= 2:
		var gap: float = (rows[1] as Control).get_global_rect().position.y - (rows[0] as Control).get_global_rect().end.y
		check(gap >= 12.0, "相鄰圖示實際間距 %.0f px" % gap)
	var badge: Control = rows[0].find_child("Badge", true, false)
	check(badge.get_global_rect().size.x >= 28.0, "圖示大小 %.0f px（手機上仍清楚）" % badge.get_global_rect().size.x)
	(rows[0] as Button).pressed.emit()
	check(g.is_popover_open(), "點擊羈絆圖示 → 顯示效果")
	g._close_pop()
	check(not g.is_popover_open(), "效果說明可關閉，不長期占據棋盤")
	check(g.board.hex_size >= 36.0, "棋盤沒有縮小（格子 %.1f）" % g.board.hex_size)


## 備戰 → （交易）→ 戰鬥（略過動畫）→ 戰後 → 下一回合備戰
func _finish_round(g, m: ClashMatch, label: String) -> void:
	if g.phase == 0:
		g.prep_timer.remaining = 0.2
		await wait(0.4)
	if g.phase == 3 and not g._spectating:
		if g.trade_overlay.visible:
			g.trade_end_btn.pressed.emit()
		await wait(0.3)
	if g.phase == 1:
		if label != "":
			await wait(0.6)
			await shot("clash_battle_" + label)
		g.skip_btn.pressed.emit()
	var t := 0.0
	while g.phase != 0 and t < 30.0 and not g.is_end_open():
		await wait(0.2)
		t += 0.2
