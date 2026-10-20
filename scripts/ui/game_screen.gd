extends Control
## 遊戲主畫面：備戰（購物、佈陣）→ 自動戰鬥播放 → 結算 → 下一回合。
## 這裡只負責把玩家操作轉給 RunState，並把狀態畫出來。
## 電腦快捷鍵：D 刷新、F 買經驗、E 出售選取棋子、空白鍵 開始戰鬥。

enum Phase { PREP, BATTLE, RESULT }

@onready var board: BoardView = $BoardView
@onready var battle_player: BattlePlayer = $BoardView/BattlePlayer
@onready var top_bar: PanelContainer = $TopBar
@onready var round_label: Label = $TopBar/HBox/RoundLabel
@onready var hp_label: Label = $TopBar/HBox/HpLabel
@onready var gold_label: Label = $TopBar/HBox/GoldLabel
@onready var level_label: Label = $TopBar/HBox/LevelLabel
@onready var threat_label: Label = $TopBar/HBox/ThreatLabel
@onready var speed_btn: Button = $TopBar/HBox/SpeedButton
@onready var skip_btn: Button = $TopBar/HBox/SkipButton
@onready var debug_btn: Button = $TopBar/HBox/DebugButton
@onready var menu_btn: Button = $TopBar/HBox/MenuBtn
@onready var trait_panel: PanelContainer = $TraitPanel
@onready var trait_title: Label = $TraitPanel/VBox/Header/TraitTitle
@onready var trait_toggle: Button = $TraitPanel/VBox/Header/TraitToggle
@onready var trait_scroll: ScrollContainer = $TraitPanel/VBox/TraitScroll
@onready var trait_text: RichTextLabel = $TraitPanel/VBox/TraitScroll/TraitText
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_title: Label = $InfoPanel/VBox/Header/InfoTitle
@onready var info_text: RichTextLabel = $InfoPanel/VBox/InfoScroll/InfoText
@onready var close_info_btn: Button = $InfoPanel/VBox/Header/CloseInfoButton
@onready var sell_btn: Button = $InfoPanel/VBox/SellButton
@onready var shop_bar: PanelContainer = $ShopBar
@onready var reroll_btn: Button = $ShopBar/HBox/LeftButtons/RerollButton
@onready var xp_btn: Button = $ShopBar/HBox/LeftButtons/XpButton
@onready var lock_btn: Button = $ShopBar/HBox/RightButtons/LockButton
@onready var start_btn: Button = $ShopBar/HBox/RightButtons/StartButton
@onready var result_overlay: Control = $ResultOverlay
@onready var result_title: Label = $ResultOverlay/Panel/VBox/ResultTitle
@onready var result_text: RichTextLabel = $ResultOverlay/Panel/VBox/ResultText
@onready var result_btn: Button = $ResultOverlay/Panel/VBox/ResultButton
@onready var menu_overlay: Control = $MenuOverlay
@onready var debug_panel: PanelContainer = $DebugPanel
@onready var round_spin: SpinBox = $DebugPanel/VBox/RoundRow/RoundSpin
@onready var abandon_confirm: ConfirmationDialog = $AbandonConfirm
@onready var toast: Label = $Toast

var run: RunState
var phase := Phase.PREP
var _shop_buttons: Array[Button] = []
var _last_result: Dictionary = {}
var _enemy_info: Dictionary = {}
var _trait_collapsed := false
var _toast_tween: Tween


func _ready() -> void:
	run = Session.run
	if run == null:
		# 直接在編輯器執行此場景（F6）時，自動建立一局測試用遠征
		run = RunState.create("human", 20240601)
		Session.run = run
	for i in 5:
		_shop_buttons.append(get_node("ShopBar/HBox/ShopSlots/Slot%d" % i))
	_style()
	_connect()
	get_viewport().size_changed.connect(_layout)
	board.is_over_sell_zone = func(p: Vector2) -> bool: return shop_bar.get_global_rect().has_point(p)
	run.changed.connect(_on_run_changed)
	debug_btn.visible = Session.debug_enabled
	_enter_prep()
	await get_tree().process_frame
	_layout()


func _style() -> void:
	for p in [top_bar, trait_panel, info_panel, shop_bar, $ResultOverlay/Panel, $MenuOverlay/Panel, debug_panel]:
		UiStyle.apply_panel(p)
	UiStyle.apply_panel($ResultOverlay/Panel, Color(0.10, 0.12, 0.17, 0.98), UiStyle.GOLD)
	UiStyle.style_button(reroll_btn, Color(0.16, 0.30, 0.52))
	UiStyle.style_button(xp_btn, Color(0.22, 0.40, 0.28))
	UiStyle.style_button(lock_btn, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 15)
	UiStyle.style_button(start_btn, Color(0.62, 0.38, 0.06), UiStyle.GOLD, 21)
	UiStyle.style_button(sell_btn, Color(0.50, 0.20, 0.18))
	UiStyle.style_button(result_btn, Color(0.62, 0.38, 0.06), UiStyle.GOLD, 20)
	for b in [speed_btn, skip_btn, debug_btn, menu_btn, trait_toggle, close_info_btn]:
		UiStyle.style_button(b, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 15)
	for b in $MenuOverlay/Panel/VBox.get_children():
		if b is Button:
			UiStyle.style_button(b, Color(0.18, 0.21, 0.28))
	for b in [$DebugPanel/VBox/RoundRow/JumpButton, $DebugPanel/VBox/Row2/GoldButton, $DebugPanel/VBox/Row2/LevelButton,
			$DebugPanel/VBox/Row3/WinButton, $DebugPanel/VBox/Row3/CloseDebugButton]:
		UiStyle.style_button(b, Color(0.35, 0.22, 0.14), Color(1, 0.6, 0.4, 0.5), 15)
	for l in [round_label, hp_label, gold_label, level_label, threat_label]:
		l.add_theme_font_size_override("font_size", 16)
	hp_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	gold_label.add_theme_color_override("font_color", UiStyle.GOLD)
	level_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	threat_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))


func _connect() -> void:
	for i in _shop_buttons.size():
		var idx := i
		_shop_buttons[i].pressed.connect(func(): _on_buy(idx))
	reroll_btn.pressed.connect(_on_reroll)
	xp_btn.pressed.connect(_on_buy_xp)
	lock_btn.pressed.connect(func(): run.toggle_lock())
	start_btn.pressed.connect(_on_start_battle)
	sell_btn.pressed.connect(_on_sell_selected)
	close_info_btn.pressed.connect(func():
		info_panel.visible = false
		_layout())
	trait_toggle.pressed.connect(_toggle_traits)
	speed_btn.pressed.connect(_cycle_speed)
	skip_btn.pressed.connect(func(): battle_player.skip())
	menu_btn.pressed.connect(func(): _show_menu(true))
	debug_btn.pressed.connect(func(): debug_panel.visible = not debug_panel.visible)
	result_btn.pressed.connect(_on_result_continue)
	$MenuOverlay/Panel/VBox/ResumeButton.pressed.connect(func(): _show_menu(false))
	$MenuOverlay/Panel/VBox/CodexButton.pressed.connect(func():
		SaveSystem.save_run(run)
		Session.open_codex(Session.SCENE_GAME))
	$MenuOverlay/Panel/VBox/SaveQuitButton.pressed.connect(func():
		SaveSystem.save_run(run)
		Session.goto(Session.SCENE_MENU))
	$MenuOverlay/Panel/VBox/AbandonButton.pressed.connect(func(): abandon_confirm.popup_centered())
	abandon_confirm.confirmed.connect(func():
		SaveSystem.clear()
		Session.run = null
		Session.goto(Session.SCENE_MENU))
	board.unit_selected.connect(_on_unit_selected)
	board.enemy_selected.connect(_on_enemy_selected)
	board.move_to_board_requested.connect(func(uid: int, cell: Vector2i): _report(run.move_to_board(uid, cell)))
	board.move_to_bench_requested.connect(func(uid: int, idx: int): _report(run.move_to_bench(uid, idx)))
	board.sell_requested.connect(func(uid: int): _sell(uid))
	battle_player.finished.connect(_on_battle_finished)
	battle_player.threat_changed.connect(func(t: int):
		threat_label.text = "敵方威脅 %d（未全清扣 %d 生命）" % [t, Economy.expedition_loss(t, run.round_no)])
	# 除錯
	$DebugPanel/VBox/RoundRow/JumpButton.pressed.connect(_debug_jump)
	$DebugPanel/VBox/Row2/GoldButton.pressed.connect(func():
		run.gold += 20
		run.changed.emit())
	$DebugPanel/VBox/Row2/LevelButton.pressed.connect(_debug_level)
	$DebugPanel/VBox/Row3/WinButton.pressed.connect(_debug_win)
	$DebugPanel/VBox/Row3/CloseDebugButton.pressed.connect(func(): debug_panel.visible = false)


# ---------- 版面 ----------
func _layout() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var left := trait_panel.get_global_rect().end.x + 8.0
	var right := info_panel.get_global_rect().position.x - 8.0 if info_panel.visible else vp.x - 8.0
	var top := top_bar.get_global_rect().end.y + 6.0
	var bottom := shop_bar.get_global_rect().position.y - 6.0
	board.fit(Rect2(left, top, maxf(100.0, right - left), maxf(100.0, bottom - top)))


func _toggle_traits() -> void:
	_trait_collapsed = not _trait_collapsed
	trait_scroll.visible = not _trait_collapsed
	trait_title.text = "羈絆" if _trait_collapsed else "文明與羈絆"
	trait_toggle.text = "▶" if _trait_collapsed else "◀"
	trait_panel.offset_right = 112.0 if _trait_collapsed else 222.0
	trait_panel.offset_bottom = -470.0 if _trait_collapsed else -132.0
	await get_tree().process_frame
	_layout()


# ---------- 階段 ----------
func _enter_prep() -> void:
	phase = Phase.PREP
	run.begin_round()
	SaveSystem.save_run(run)
	battle_player.clear()
	board.interactive = true
	board.set_prep_visible(true)
	board.show_prep(run)
	result_overlay.visible = false
	speed_btn.visible = false
	skip_btn.visible = false
	menu_btn.visible = true
	_refresh()


func _on_run_changed() -> void:
	if phase != Phase.PREP:
		_refresh_top()
		return
	board.sync_prep()
	_refresh()
	SaveSystem.save_run(run)


func _on_start_battle() -> void:
	if phase != Phase.PREP:
		return
	if run.board_count() == 0:
		_toast("請至少部署 1 隻棋子到下方 4 排")
		return
	phase = Phase.BATTLE
	board.select(-1)
	board.interactive = false
	_last_result = run.start_battle()
	board.set_prep_visible(false)
	battle_player.play(_last_result, board)
	speed_btn.visible = true
	skip_btn.visible = true
	menu_btn.visible = false
	debug_panel.visible = false
	_update_speed_label()
	_refresh()


func _on_battle_finished() -> void:
	if phase != Phase.BATTLE:
		return
	var report := run.settle(_last_result)
	if run.finished:
		SaveSystem.clear()
	else:
		SaveSystem.save_run(run)
	phase = Phase.RESULT
	skip_btn.visible = false
	_show_result(report)
	_refresh()


func _on_result_continue() -> void:
	result_overlay.visible = false
	if run.finished:
		Session.goto(Session.SCENE_END)
	else:
		_enter_prep()


func _show_result(rep: Dictionary) -> void:
	var lines: Array = []
	var cleared: bool = rep["cleared"]
	if rep["outcome"] == "defeat":
		result_title.text = "遠征失敗"
		result_title.add_theme_color_override("font_color", UiStyle.BAD)
	elif rep["outcome"] == "victory":
		result_title.text = "遠征完成！"
		result_title.add_theme_color_override("font_color", UiStyle.GOLD)
	elif rep["outcome"] == "incomplete":
		result_title.text = "遠征未完成"
		result_title.add_theme_color_override("font_color", UiStyle.BAD)
	else:
		result_title.text = "第 %d 回合：%s" % [rep["round"], "全清敵軍" if cleared else "未能全清"]
		result_title.add_theme_color_override("font_color", UiStyle.GOOD if cleared else UiStyle.BAD)
	if cleared:
		lines.append("[color=#6bdc85]敵軍全滅，遠征生命不受損。[/color]")
	else:
		lines.append("剩餘敵軍威脅 [b]%d[/b] × 回合倍率 %.1f → 遠征生命 [color=#f07a70]-%d[/color]" % [
			rep["threat"], Economy.round_multiplier(int(rep["round"])), rep["hp_loss"]])
	if int(rep["deer_heal"]) > 0:
		lines.append("鹿角人文明：遠征生命 +%d" % rep["deer_heal"])
	lines.append("遠征生命：%d → [b]%d[/b] / %d" % [rep["hp_before"], rep.get("hp_after", run.hp), Economy.max_hp()])
	if rep["outcome"] != "defeat":
		var total := int(rep["income_base"]) + int(rep["income_interest"]) + int(rep["income_clear"])
		lines.append("收入 [color=#ffd24d]+%d 金[/color]（固定 %d、利息 %d、全清獎勵 %d）" % [
			total, rep["income_base"], rep["income_interest"], rep["income_clear"]])
		if int(rep["xp_gain"]) > 0:
			lines.append("自然經驗 +%d XP" % rep["xp_gain"] + ("　[color=#8fd0ff]文明升到 Lv.%d！[/color]" % rep["level_after"] if rep["level_after"] != rep["level_before"] else ""))
	# 本場輸出最高的我方棋子
	var best := {}
	for s in _last_result.get("stats", []):
		if int(s["side"]) == 0 and (best.is_empty() or int(s["damage"]) > int(best["damage"])):
			best = s
	if not best.is_empty() and int(best["damage"]) > 0:
		lines.append("[color=#9aa3ad]本場輸出最高：%s %s（%d 傷害）[/color]" % [GameData.unit(best["id"])["name"], UiStyle.stars(int(best["star"])), best["damage"]])
	result_text.text = "\n".join(lines)
	result_btn.text = "查看遠征結算" if run.finished else "進入第 %d 回合備戰" % run.round_no
	result_overlay.visible = true


# ---------- 操作 ----------
func _report(reason: String) -> void:
	if reason != "":
		_toast(reason)


func _on_buy(slot: int) -> void:
	if phase != Phase.PREP:
		return
	_report(run.buy(slot))


func _on_reroll() -> void:
	if phase == Phase.PREP:
		_report(run.reroll())


func _on_buy_xp() -> void:
	if phase == Phase.PREP:
		_report(run.buy_xp())


func _on_sell_selected() -> void:
	var uid := board.selected_uid()
	if uid >= 0:
		_sell(uid)


func _sell(uid: int) -> void:
	if phase != Phase.PREP:
		return
	var f := run.find_unit(uid)
	if f.is_empty():
		return
	var value := UnitStats.sell_value(f["unit"]["id"], int(f["unit"]["star"]))
	if run.sell(uid) == "":
		_toast("出售 %s，+%d 金" % [GameData.unit(f["unit"]["id"])["name"], value])
		board.select(-1)


func _cycle_speed() -> void:
	var speeds := [1.0, 2.0, 4.0]
	var i := speeds.find(Session.battle_speed)
	Session.battle_speed = speeds[(i + 1) % speeds.size()]
	_update_speed_label()


func _update_speed_label() -> void:
	speed_btn.text = "速度 %d×" % int(Session.battle_speed)


func _show_menu(v: bool) -> void:
	if phase == Phase.BATTLE:
		return
	menu_overlay.visible = v
	board.interactive = not v and phase == Phase.PREP


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_D:
			_on_reroll()
		KEY_F:
			_on_buy_xp()
		KEY_E:
			_on_sell_selected()
		KEY_SPACE:
			if phase == Phase.PREP:
				_on_start_battle()
			elif phase == Phase.RESULT:
				_on_result_continue()
		KEY_ESCAPE:
			if phase != Phase.BATTLE:
				_show_menu(not menu_overlay.visible)


func _toast(msg: String) -> void:
	toast.text = msg
	toast.visible = true
	toast.modulate.a = 1.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func(): toast.visible = false)


# ---------- 資訊顯示 ----------
func _on_unit_selected(uid: int) -> void:
	_enemy_info = {}
	if uid >= 0:
		info_panel.visible = true
		_layout()
	_refresh_info()


func _on_enemy_selected(unit_id: String, star: int) -> void:
	board.select(-1)
	_enemy_info = {"id": unit_id, "star": star}
	info_panel.visible = true
	_layout()
	_refresh_info()


func _refresh() -> void:
	_refresh_top()
	_refresh_shop()
	_refresh_traits()
	_refresh_info()


func _refresh_top() -> void:
	var boss := "・首領" if GameData.is_boss_round(run.round_no) else ""
	round_label.text = "回合 %d/%d・第%d章%s" % [run.round_no, GameData.total_rounds(), run.chapter(), boss]
	hp_label.text = "生命 %d/%d" % [run.hp, Economy.max_hp()]
	gold_label.text = "金幣 %d（利息+%d）" % [run.gold, run.current_interest()]
	var prog := Economy.xp_progress(run.xp)
	if run.level() >= Economy.max_level():
		level_label.text = "%s Lv.%d 滿級・上場 %d/%d" % [run.civ_name(), run.level(), run.board_count(), run.board_limit()]
	else:
		level_label.text = "%s Lv.%d（%d/%d）・上場 %d/%d" % [run.civ_name(), run.level(), prog[0], prog[1], run.board_count(), run.board_limit()]
	if phase == Phase.PREP:
		var st := GameData.stage(run.round_no)
		var stars: Array = []
		for e in st.get("units", []):
			stars.append(int(e["star"]))
		threat_label.text = "%s：敵 %d・威脅 %d" % [st.get("name", ""), stars.size(), Economy.threat(stars)]


func _refresh_shop() -> void:
	var prep := phase == Phase.PREP
	for i in _shop_buttons.size():
		var b := _shop_buttons[i]
		var id := str(run.shop[i]) if i < run.shop.size() else ""
		if id == "":
			b.text = "（已招募）"
			b.disabled = true
			UiStyle.style_button(b, Color(0.12, 0.13, 0.17), Color(1, 1, 1, 0.05), 14)
			continue
		var u := GameData.unit(id)
		var cost := int(u["cost"])
		var owned := run.copies_of(id, 1)
		var mark := "　◆合成" if owned >= 2 else ("　◇%d/3" % (owned + 1) if owned == 1 else "")
		b.text = "%s\n%s\n%d 金%s" % [u["name"], UiStyle.unit_line(id), cost, mark]
		var col := GameData.tier_color(cost)
		UiStyle.style_button(b, col.darkened(0.62), col, 15)
		b.disabled = not prep or run.can_buy(i) != ""
		b.tooltip_text = "%s｜%s\n%s" % [u["name"], UnitStats.skill(id).get("name", ""), UnitStats.skill_text(id, 1)]
	if run.free_rerolls > 0:
		reroll_btn.text = "免費刷新（%d）" % run.free_rerolls
		reroll_btn.disabled = not prep
	else:
		reroll_btn.text = "刷新（%d 金）" % Economy.reroll_cost()
		reroll_btn.disabled = not prep or run.gold < Economy.reroll_cost()
	if run.level() >= Economy.max_level():
		xp_btn.text = "文明已滿級"
		xp_btn.disabled = true
	else:
		xp_btn.text = "買經驗 +%d（%d 金）" % [Economy.xp_per_buy(), Economy.xp_cost()]
		xp_btn.disabled = not prep or run.gold < Economy.xp_cost()
	lock_btn.text = "已鎖定（點擊解鎖）" if run.shop_locked else "鎖定商店"
	lock_btn.disabled = not prep
	start_btn.disabled = not prep
	start_btn.text = "開始戰鬥" if prep else "戰鬥中…"


func _refresh_traits() -> void:
	var c := GameData.civ(run.civ_id)
	var lines: Array = []
	lines.append("[b][color=%s]%s 文明[/color][/b]" % [UiStyle.hex_color(GameData.race_color(str(c.get("race", ""))).lightened(0.3)), c.get("name", "")])
	for bf in c.get("buffs", []):
		lines.append("[color=#6bdc85]▲[/color] " + str(bf["text"]))
	for df in c.get("debuffs", []):
		lines.append("[color=#f07a70]▼[/color] " + str(df["text"]))
	lines.append("")
	var summary := Synergy.summary(run.synergy_counts())
	if summary.is_empty():
		lines.append("[color=#9aa3ad]把棋子放上棋盤即可啟動羈絆（不同名稱才計數）。[/color]")
	for s in summary:
		var th: Array = s["thresholds"]
		var parts: Array = []
		for i in th.size():
			parts.append(("[color=#ffd24d]%d[/color]" if int(s["tier"]) >= i else "%d") % th[i])
		var active := int(s["tier"]) >= 0
		var group_name: String = {"race": "種族", "type": "類型", "class": "職業"}[s["group"]]
		var head := "[b]%s[/b] %s %d（%s）" % [s["name"], group_name, s["count"], "/".join(parts)]
		if active:
			lines.append("[color=#ffe9a8]" + head + "[/color]")
			lines.append("　[color=#cfd6e2]" + str(s["texts"][s["tier"]]) + "[/color]")
		else:
			lines.append("[color=#8a90a0]" + head + "[/color]")
	trait_text.text = "\n".join(lines)


func _refresh_info() -> void:
	sell_btn.visible = false
	if not _enemy_info.is_empty():
		var id := str(_enemy_info["id"])
		info_title.text = "敵方：" + str(GameData.unit(id)["name"])
		info_text.text = UiStyle.unit_info_bbcode(id, int(_enemy_info["star"])) + "\n\n[color=#9aa3ad]敵軍沒有文明加成；V0.1 敵方羈絆預設關閉。[/color]"
		return
	var uid := board.selected_uid()
	var f := run.find_unit(uid) if uid >= 0 else {}
	if f.is_empty():
		info_title.text = "棋子資訊"
		info_text.text = "[color=#9aa3ad]點選棋子查看屬性與技能。\n\n• 點選棋子後再點空格＝移動\n• 拖曳棋子＝移動或互換\n• 拖到下方商店列＝出售\n• 點敵方棋子可查看敵軍資訊\n\n電腦快捷鍵：D 刷新、F 買經驗、E 出售、空白鍵 開戰[/color]"
		return
	var u: Dictionary = f["unit"]
	var id := str(u["id"])
	var star := int(u["star"])
	info_title.text = "%s %s" % [GameData.unit(id)["name"], UiStyle.stars(star)]
	var mods := {}
	var note := "[color=#9aa3ad]（候補區：未套用文明與羈絆）[/color]"
	if f["where"] == "board":
		var ids := run.board_unit_ids()
		var all_mods := Modifiers.for_lineup(ids, run.civ_id, true)
		var cells := run.board_lineup()
		for i in cells.size():
			if int(cells[i]["uid"]) == uid:
				mods = all_mods[i]
		note = "[color=#9aa3ad]（已含文明與羈絆修正）[/color]"
	info_text.text = UiStyle.unit_info_bbcode(id, star, mods) + "\n\n" + note
	if phase == Phase.PREP:
		sell_btn.visible = true
		sell_btn.text = "出售　+%d 金" % UnitStats.sell_value(id, star)


# ---------- 除錯 ----------
func _debug_jump() -> void:
	if phase != Phase.PREP:
		return
	run.round_no = int(round_spin.value)
	run.prepared_round = 0
	_enter_prep()
	_toast("已跳到第 %d 回合" % run.round_no)


func _debug_level() -> void:
	var th := Economy.xp_thresholds()
	var lv := run.level()
	if lv < Economy.max_level():
		run.xp = int(th[lv])
	run.changed.emit()


func _debug_win() -> void:
	if phase != Phase.PREP:
		return
	run.gold_at_battle_start = run.gold
	_last_result = {"cleared": true, "threat": 0, "alive_enemies": [], "stats": []}
	var report := run.settle(_last_result)
	if run.finished:
		SaveSystem.clear()
	phase = Phase.RESULT
	_show_result(report)
	_refresh()
