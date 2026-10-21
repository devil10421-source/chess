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
	# ── 第 1 回合 PvP ──
	await _finish_round(g, m, "r1")
	check(m.round_no == 2, "進入第 2 回合")
	# ── 第 2 回合：合作 PvE＋交易 ──
	var a := m.assignment(m.human_seat)
	check(m.round_kind == "pve" and str(a.get("kind", "")) in ["coop", "solo"], "第 2 回合為合作 PvE（%s）" % str(a))
	check(g.bar_left.text.contains("PvE"), "上方顯示 PvE 與隊友")
	if str(a.get("kind", "")) == "coop":
		g.prep_timer.remaining = 0.2
		await wait(0.5)
		check(g.phase == 3 and g.trade_overlay.visible, "備戰結束 → 交易畫面")
		check(g.trade_title.text.contains("隊友"), "交易畫面顯示隊友")
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
	await _finish_round(g, m, "r2")
	check(m.pool.audit().is_empty(), "交易與 PvE 後棋池守恆")
	# ── 快轉到第 8 回合：國家制度 ──
	var guard := 0
	while m.round_no < ClashGovernment.system_round() and guard < 12:
		guard += 1
		await _finish_round(g, m, "")
	check(m.round_no == ClashGovernment.system_round() and g.phase == 0, "到第 %d 回合備戰" % ClashGovernment.system_round())
	check(g.gov_overlay.visible and g.gov_cards.get_child_count() == 3, "第 8 回合顯示三種國家制度")
	check(g.prep_timer.running and not g.prep_timer.paused, "選擇制度時倒數不暫停")
	await shot("clash_government")
	var pick: Button = g.gov_cards.get_child(2).find_children("*", "Button", true, false)[0]
	pick.pressed.emit()
	await wait(0.2)
	check(m.human().government == "commune", "選擇偉大公社並保存")
	check(not g.gov_overlay.visible and not g.gov_reopen.visible, "選完關閉")
	check(g.civ_btn.find_children("*", "Label", true, false).any(func(l): return (l as Label).text.contains("偉大公社")), "左側國家列顯示制度")
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
