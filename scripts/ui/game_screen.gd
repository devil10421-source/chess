extends Control
## 遊戲主畫面：備戰（15 秒倒數，可提前開戰）→ 自動戰鬥播放 → 結算與貢獻排行 → 下一回合。
## 這裡只負責把玩家操作轉給 RunState，並把狀態畫出來；規則都在 scripts/core。
## 電腦快捷鍵：D 刷新、F 買經驗、E 出售選取棋子、空白鍵 開始戰鬥／繼續、Esc 選單。

enum Phase { PREP, BATTLE, RESULT }

const CIV_W := 170.0
const TRAIT_W := 190.0
const COLLAPSED_W := 52.0
const COLOR_UP := "#5aa9ff"
const COLOR_DOWN := "#ff6b6b"
const STATE_MARK := {
	"board": "[color=#6bdc85]● 已上場[/color]",
	"bench": "[color=#ffd24d]◐ 候補區[/color]",
	"none": "[color=#9aa3ad]○ 尚未持有[/color]",
	"unavailable": "[color=#7a6f73]✕ 本文明商店無法取得[/color]",
}

@onready var board: BoardView = $BoardView
@onready var battle_player: BattlePlayer = $BoardView/BattlePlayer
@onready var top_bar: PanelContainer = $TopBar
@onready var round_label: Label = $TopBar/HBox/RoundLabel
@onready var hp_label: Label = $TopBar/HBox/HpLabel
@onready var gold_label: Label = $TopBar/HBox/GoldLabel
@onready var threat_label: Label = $TopBar/HBox/ThreatLabel
@onready var timer_label: Label = $TopBar/HBox/TimerLabel
@onready var report_btn: Button = $TopBar/HBox/ReportButton
@onready var speed_btn: Button = $TopBar/HBox/SpeedButton
@onready var skip_btn: Button = $TopBar/HBox/SkipButton
@onready var debug_btn: Button = $TopBar/HBox/DebugButton
@onready var menu_btn: Button = $TopBar/HBox/MenuBtn
@onready var civ_panel: PanelContainer = $CivPanel
@onready var civ_title: Label = $CivPanel/VBox/Header/CivTitle
@onready var civ_toggle: Button = $CivPanel/VBox/Header/CivToggle
@onready var civ_scroll: ScrollContainer = $CivPanel/VBox/CivScroll
@onready var civ_text: RichTextLabel = $CivPanel/VBox/CivScroll/CivText
@onready var trait_panel: PanelContainer = $TraitPanel
@onready var trait_title: Label = $TraitPanel/VBox/Header/TraitTitle
@onready var trait_toggle: Button = $TraitPanel/VBox/Header/TraitToggle
@onready var trait_scroll: ScrollContainer = $TraitPanel/VBox/TraitScroll
@onready var trait_list: VBoxContainer = $TraitPanel/VBox/TraitScroll/TraitList
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_title: Label = $InfoPanel/VBox/Header/InfoTitle
@onready var info_body: VBoxContainer = $InfoPanel/VBox/InfoScroll/InfoBody
@onready var close_info_btn: Button = $InfoPanel/VBox/Header/CloseInfoButton
@onready var sell_btn: Button = $InfoPanel/VBox/SellButton
@onready var shop_bar: PanelContainer = $ShopBar
@onready var level_label: Label = $ShopBar/HBox/LevelBox/LevelRow/LevelLabel
@onready var pop_label: Label = $ShopBar/HBox/LevelBox/LevelRow/PopLabel
@onready var xp_bar: ProgressBar = $ShopBar/HBox/LevelBox/XpBar
@onready var xp_text: Label = $ShopBar/HBox/LevelBox/XpText
@onready var reroll_btn: Button = $ShopBar/HBox/LeftButtons/RerollButton
@onready var xp_btn: Button = $ShopBar/HBox/LeftButtons/XpButton
@onready var lock_btn: Button = $ShopBar/HBox/RightButtons/LockButton
@onready var start_btn: Button = $ShopBar/HBox/RightButtons/StartButton
@onready var big_countdown: Label = $BigCountdown
@onready var result_overlay: Control = $ResultOverlay
@onready var result_title: Label = $ResultOverlay/Panel/VBox/ResultTitle
@onready var result_text: RichTextLabel = $ResultOverlay/Panel/VBox/ResultText
@onready var leader_list: VBoxContainer = $ResultOverlay/Panel/VBox/LeaderList
@onready var result_btn: Button = $ResultOverlay/Panel/VBox/ResultButton
@onready var menu_overlay: Control = $MenuOverlay
@onready var debug_panel: PanelContainer = $DebugPanel
@onready var round_spin: SpinBox = $DebugPanel/VBox/RoundRow/RoundSpin
@onready var abandon_confirm: ConfirmationDialog = $AbandonConfirm
@onready var toast: Label = $Toast

var run: RunState
var phase := Phase.PREP
var prep_timer := PrepTimer.new()
var _shop_buttons: Array[Button] = []
var _leader_tabs: Array[Button] = []
var _last_result: Dictionary = {}
var _last_report: Dictionary = {}
var _result_view_only := false
var _leader_metric := "damage"
var _civ_collapsed := false
var _trait_collapsed := false
var _toast_tween: Tween
var _info: InfoView
## 資訊面板目前顯示的對象：none / unit（備戰棋子 uid）/ enemy（敵方預覽）/ battle（戰鬥中 cid）/ trait（羈絆名單）
var _info_mode := "none"
var _info_ref: Variant = null
var _info_refresh := 0.0
var _last_seconds := -1


func _ready() -> void:
	run = Session.run
	if run == null:
		# 直接在編輯器執行此場景（F6）時，自動建立一局測試用遠征
		run = RunState.create("human", 20240601)
		Session.run = run
	_info = InfoView.new(info_body)
	for i in 5:
		_shop_buttons.append(get_node("ShopBar/HBox/ShopSlots/Slot%d" % i))
	for i in 4:
		_leader_tabs.append(get_node("ResultOverlay/Panel/VBox/LeaderTabs/Tab%d" % i))
	_style()
	_connect()
	get_viewport().size_changed.connect(_layout)
	board.is_over_sell_zone = func(p: Vector2) -> bool: return shop_bar.get_global_rect().has_point(p)
	run.changed.connect(_on_run_changed)
	debug_btn.visible = Session.debug_enabled
	_apply_side_layout()
	_enter_prep()
	await get_tree().process_frame
	_layout()


func _style() -> void:
	for p in [top_bar, civ_panel, trait_panel, info_panel, shop_bar, $MenuOverlay/Panel, debug_panel]:
		UiStyle.apply_panel(p)
	UiStyle.apply_panel(civ_panel, Color(0.10, 0.13, 0.20, 0.95), Color(0.35, 0.5, 0.8, 0.6))
	UiStyle.apply_panel($ResultOverlay/Panel, Color(0.10, 0.12, 0.17, 0.98), UiStyle.GOLD)
	UiStyle.style_button(reroll_btn, Color(0.16, 0.30, 0.52))
	UiStyle.style_button(xp_btn, Color(0.22, 0.40, 0.28))
	UiStyle.style_button(lock_btn, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 15)
	UiStyle.style_button(start_btn, Color(0.62, 0.38, 0.06), UiStyle.GOLD, 19)
	UiStyle.style_button(sell_btn, Color(0.50, 0.20, 0.18))
	UiStyle.style_button(result_btn, Color(0.62, 0.38, 0.06), UiStyle.GOLD, 19)
	for b in [report_btn, speed_btn, skip_btn, debug_btn, menu_btn, civ_toggle, trait_toggle, close_info_btn]:
		UiStyle.style_button(b, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 14)
	for b in $MenuOverlay/Panel/VBox.get_children():
		if b is Button:
			UiStyle.style_button(b, Color(0.18, 0.21, 0.28))
	for b in [$DebugPanel/VBox/RoundRow/JumpButton, $DebugPanel/VBox/Row2/GoldButton, $DebugPanel/VBox/Row2/LevelButton,
			$DebugPanel/VBox/Row3/WinButton, $DebugPanel/VBox/Row3/CloseDebugButton]:
		UiStyle.style_button(b, Color(0.35, 0.22, 0.14), Color(1, 0.6, 0.4, 0.5), 15)
	for l in [round_label, hp_label, gold_label, threat_label, timer_label]:
		l.add_theme_font_size_override("font_size", 16)
	hp_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	gold_label.add_theme_color_override("font_color", UiStyle.GOLD)
	threat_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.40, 0.70, 1.0)
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.10)
	bg.set_corner_radius_all(4)
	xp_bar.add_theme_stylebox_override("fill", fill)
	xp_bar.add_theme_stylebox_override("background", bg)


func _connect() -> void:
	for i in _shop_buttons.size():
		var idx := i
		_shop_buttons[i].pressed.connect(func(): _on_buy(idx))
	for i in _leader_tabs.size():
		var metric: String = Leaderboard.ORDER[i]
		_leader_tabs[i].pressed.connect(func(): _set_leader_metric(metric))
	reroll_btn.pressed.connect(_on_reroll)
	xp_btn.pressed.connect(_on_buy_xp)
	lock_btn.pressed.connect(func(): run.toggle_lock())
	start_btn.pressed.connect(func(): _on_start_battle(false))
	sell_btn.pressed.connect(_on_sell_selected)
	close_info_btn.pressed.connect(func():
		info_panel.visible = false
		_layout())
	civ_toggle.pressed.connect(func():
		_civ_collapsed = not _civ_collapsed
		_apply_side_layout())
	trait_toggle.pressed.connect(func():
		_trait_collapsed = not _trait_collapsed
		_apply_side_layout())
	report_btn.pressed.connect(func():
		if not _last_report.is_empty():
			_show_result(_last_report, true))
	speed_btn.pressed.connect(_cycle_speed)
	skip_btn.pressed.connect(func(): battle_player.skip())
	menu_btn.pressed.connect(func(): _show_menu(true))
	debug_btn.pressed.connect(func(): debug_panel.visible = not debug_panel.visible)
	result_btn.pressed.connect(_on_result_continue)
	$MenuOverlay/Panel/VBox/ResumeButton.pressed.connect(func(): _show_menu(false))
	$MenuOverlay/Panel/VBox/CodexButton.pressed.connect(func():
		Session.prep_time_left = prep_timer.remaining
		Session.prep_time_round = run.round_no
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
	board.battle_unit_selected.connect(_on_battle_unit_selected)
	board.move_to_board_requested.connect(func(uid: int, cell: Vector2i): _report(run.move_to_board(uid, cell)))
	board.move_to_bench_requested.connect(func(uid: int, idx: int): _report(run.move_to_bench(uid, idx)))
	board.sell_requested.connect(func(uid: int): _sell(uid))
	battle_player.finished.connect(_on_battle_finished)
	battle_player.threat_changed.connect(func(t: int):
		threat_label.text = "敵方威脅 %d（未全清扣 %d 生命）" % [t, Economy.expedition_loss(t, run.round_no)])
	$DebugPanel/VBox/RoundRow/JumpButton.pressed.connect(_debug_jump)
	$DebugPanel/VBox/Row2/GoldButton.pressed.connect(func():
		run.gold += 20
		run.changed.emit())
	$DebugPanel/VBox/Row2/LevelButton.pressed.connect(_debug_level)
	$DebugPanel/VBox/Row3/WinButton.pressed.connect(_debug_win)
	$DebugPanel/VBox/Row3/CloseDebugButton.pressed.connect(func(): debug_panel.visible = false)


# ---------- 版面 ----------
## 文明面板固定在羈絆面板左側；兩者都可收合成窄條（仍維持左右相對位置）
func _apply_side_layout() -> void:
	var civ_w := COLLAPSED_W if _civ_collapsed else CIV_W
	var trait_w := COLLAPSED_W if _trait_collapsed else TRAIT_W
	civ_panel.offset_left = 6.0
	civ_panel.offset_right = 6.0 + civ_w
	trait_panel.offset_left = civ_panel.offset_right + 6.0
	trait_panel.offset_right = trait_panel.offset_left + trait_w
	civ_scroll.visible = not _civ_collapsed
	trait_scroll.visible = not _trait_collapsed
	civ_title.visible = not _civ_collapsed
	trait_title.visible = not _trait_collapsed
	civ_toggle.text = "文▶" if _civ_collapsed else "◀"
	trait_toggle.text = "羈▶" if _trait_collapsed else "◀"
	civ_toggle.custom_minimum_size = Vector2(40 if _civ_collapsed else 34, 32)
	trait_toggle.custom_minimum_size = Vector2(40 if _trait_collapsed else 34, 32)
	# 面板不能小於內容最小寬度：等一個畫面後，依文明面板「實際」右緣擺放羈絆面板，避免重疊
	await get_tree().process_frame
	trait_panel.offset_left = civ_panel.get_global_rect().end.x + 6.0
	trait_panel.offset_right = trait_panel.offset_left + trait_w
	_layout_deferred()


func _layout_deferred() -> void:
	await get_tree().process_frame
	_layout()


func _layout() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var left := trait_panel.get_global_rect().end.x + 8.0
	var right := info_panel.get_global_rect().position.x - 8.0 if info_panel.visible else vp.x - 8.0
	var top := top_bar.get_global_rect().end.y + 6.0
	var bottom := shop_bar.get_global_rect().position.y - 6.0
	board.fit(Rect2(left, top, maxf(100.0, right - left), maxf(100.0, bottom - top)))
	big_countdown.position.y = top + (bottom - top) * 0.35


# ---------- 階段 ----------
func _enter_prep() -> void:
	phase = Phase.PREP
	run.begin_round()
	SaveSystem.save_run(run)
	battle_player.clear()
	board.battle_mode = false
	board.interactive = true
	board.set_prep_visible(true)
	board.show_prep(run)
	result_overlay.visible = false
	speed_btn.visible = false
	skip_btn.visible = false
	menu_btn.visible = true
	report_btn.visible = not _last_report.is_empty()
	_set_info("none", null)
	_refresh()
	# 商店與棋盤初始化完成後才開始 15 秒倒數（從圖鑑返回同一回合時接續剩餘秒數）
	prep_timer.start()
	if Session.prep_time_round == run.round_no and Session.prep_time_left > 0.0:
		prep_timer.remaining = Session.prep_time_left
	Session.prep_time_round = -1
	_last_seconds = -1
	_update_timer_ui()


func _process(delta: float) -> void:
	if phase == Phase.PREP:
		prep_timer.paused = menu_overlay.visible or debug_panel.visible or abandon_confirm.visible
		if prep_timer.tick(delta):
			_on_start_battle(true)
			return
		_update_timer_ui()
	elif phase == Phase.BATTLE:
		timer_label.text = "戰鬥 %.1f 秒・播放 %.1f×" % [battle_player.sim_time(), Session.playback_rate]
		_info_refresh -= delta
		if _info_mode == "battle" and _info_refresh <= 0.0:
			_info_refresh = 0.2
			_refresh_info()


func _update_timer_ui() -> void:
	var secs := prep_timer.seconds_left()
	var warn := prep_timer.is_warning()
	big_countdown.visible = warn and not prep_timer.paused
	if warn:
		var pulse := 1.0 + 0.12 * absf(sin(Time.get_ticks_msec() / 150.0))
		big_countdown.scale = Vector2(pulse, pulse)
		big_countdown.pivot_offset = big_countdown.size * 0.5
	if secs == _last_seconds:
		return
	_last_seconds = secs
	var paused := "（暫停）" if prep_timer.paused else ""
	timer_label.text = "備戰 %d 秒%s" % [secs, paused]
	timer_label.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if warn else Color(0.75, 0.9, 1.0))
	big_countdown.text = str(secs)
	start_btn.text = "開始戰鬥（%d）" % secs


func _on_run_changed() -> void:
	if phase != Phase.PREP:
		_refresh_top()
		return
	board.sync_prep()
	_refresh()
	SaveSystem.save_run(run)


## auto = 倒數結束自動開戰
func _on_start_battle(auto: bool) -> void:
	if phase != Phase.PREP:
		return
	board.cancel_drag()
	# 人口不足時從候補區最左側自動補位（補位完成後才建立戰鬥快照）
	var placed := run.auto_fill_board()
	if run.board_count() == 0 and not auto:
		_toast("場上與候補區都沒有棋子，請先招募")
		return
	prep_timer.stop()
	big_countdown.visible = false
	phase = Phase.BATTLE
	board.select(-1)
	board.interactive = false
	_last_result = run.start_battle()
	board.set_prep_visible(false)
	board.battle_mode = true
	battle_player.play(_last_result, board)
	speed_btn.visible = true
	skip_btn.visible = true
	menu_btn.visible = false
	report_btn.visible = false
	debug_panel.visible = false
	_update_speed_label()
	_set_info("none", null)
	_refresh()
	if not placed.is_empty():
		_toast("人口未滿：已從候補區自動補上 %d 隻" % placed.size())
	elif auto:
		_toast("備戰時間到，自動開戰")


func _on_battle_finished() -> void:
	if phase != Phase.BATTLE:
		return
	var report := run.settle(_last_result)
	report["stats"] = _last_result.get("stats", [])
	_last_report = report
	if run.finished:
		SaveSystem.clear()
	else:
		SaveSystem.save_run(run)
	phase = Phase.RESULT
	skip_btn.visible = false
	_show_result(report, false)
	_refresh()


func _on_result_continue() -> void:
	result_overlay.visible = false
	if _result_view_only:
		_result_view_only = false
		return
	board.battle_mode = false
	if run.finished:
		Session.goto(Session.SCENE_END)
	else:
		_enter_prep()


func _show_result(rep: Dictionary, view_only: bool) -> void:
	_result_view_only = view_only
	var lines: Array = []
	var cleared: bool = rep["cleared"]
	if view_only:
		result_title.text = "第 %d 回合戰報" % rep["round"]
		result_title.add_theme_color_override("font_color", UiStyle.GOLD)
	elif rep["outcome"] == "defeat":
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
		lines.append("剩餘敵軍威脅 [b]%d[/b] × 回合倍率 %.1f → 遠征生命 [color=#ff6b6b]-%d[/color]" % [
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
	result_text.text = "\n".join(lines)
	_leader_metric = "damage"
	_set_leader_metric(_leader_metric)
	if view_only:
		result_btn.text = "關閉"
	else:
		result_btn.text = "查看遠征結算" if run.finished else "進入第 %d 回合備戰" % run.round_no
	result_overlay.visible = true


func _set_leader_metric(metric: String) -> void:
	_leader_metric = metric
	for i in _leader_tabs.size():
		var active: bool = Leaderboard.ORDER[i] == metric
		UiStyle.style_button(_leader_tabs[i], Color(0.55, 0.36, 0.08) if active else Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 14)
	var stats: Array = _last_report.get("stats", _last_result.get("stats", []))
	LeaderboardView.build(leader_list, stats, metric)


# ---------- 操作 ----------
func _report(reason: String) -> void:
	if reason != "":
		_toast(reason)


func _on_buy(slot: int) -> void:
	if phase == Phase.PREP:
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
				_on_start_battle(false)
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


# ---------- 選取 ----------
func _set_info(mode: String, ref: Variant) -> void:
	var changed: bool = mode != _info_mode or ref != _info_ref
	_info_mode = mode
	_info_ref = ref
	if mode != "none" and not info_panel.visible:
		info_panel.visible = true
		_layout_deferred()
	if changed:
		_info.clear()
	_refresh_info()


func _on_unit_selected(uid: int) -> void:
	_set_info("unit" if uid >= 0 else "none", uid if uid >= 0 else null)


func _on_enemy_selected(unit_id: String, star: int) -> void:
	_set_info("enemy", {"id": unit_id, "star": star})


func _on_battle_unit_selected(cid: int) -> void:
	_set_info("battle" if cid >= 0 else "none", cid if cid >= 0 else null)


# ---------- 畫面更新 ----------
func _refresh() -> void:
	_refresh_top()
	_refresh_level()
	_refresh_shop()
	_refresh_civ()
	_refresh_traits()
	_refresh_info()


func _refresh_top() -> void:
	var boss := "・首領" if GameData.is_boss_round(run.round_no) else ""
	round_label.text = "回合 %d/%d・第%d章%s" % [run.round_no, GameData.total_rounds(), run.chapter(), boss]
	hp_label.text = "生命 %d/%d" % [run.hp, Economy.max_hp()]
	var nxt := Economy.next_interest(run.gold)
	if nxt.is_empty():
		gold_label.text = "金幣 %d（利息 +%d・已達上限）" % [run.gold, run.current_interest()]
	else:
		gold_label.text = "金幣 %d（利息 +%d・再 %d 金 → +%d）" % [run.gold, run.current_interest(), nxt["need"], nxt["next_interest"]]
	if phase == Phase.PREP:
		var st := GameData.stage(run.round_no)
		var stars: Array = []
		for e in st.get("units", []):
			stars.append(int(e["star"]))
		threat_label.text = "%s：敵 %d・威脅 %d" % [st.get("name", ""), stars.size(), Economy.threat(stars)]


## 文明等級與經驗：顯示在商店旁（小而清楚）
func _refresh_level() -> void:
	var plan := Economy.xp_plan(run.xp)
	level_label.text = "Lv.%d" % run.level()
	pop_label.text = "上場 %d/%d" % [run.board_count(), run.board_limit()]
	if plan["max"]:
		xp_bar.max_value = 1
		xp_bar.value = 1
		xp_text.text = "已達最高等級"
		return
	xp_bar.max_value = plan["need"]
	xp_bar.value = plan["cur"]
	xp_text.text = "經驗 %d/%d・還差 %d XP\n購買 +%d XP／%d 金：再 %d 次（%d 金）" % [
		plan["cur"], plan["need"], plan["missing"], Economy.xp_per_buy(), Economy.xp_cost(), plan["buys"], plan["cost"]]


func _refresh_shop() -> void:
	var prep := phase == Phase.PREP
	var three := run.three_star_ids()
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
		var mark := " ◆合成" if owned >= 2 else (" ◇%d/3" % (owned + 1) if owned == 1 else "")
		if three.has(id):
			mark = " 已三星"
		b.text = "%s\n%s・%s\n%s・%d 金%s" % [u["name"], GameData.race_name(u["race"]), GameData.type_name(u["type"]),
			GameData.class_name_of(u["class"]), cost, mark]
		var col := GameData.tier_color(cost)
		UiStyle.style_button(b, col.darkened(0.62), col, 14)
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
	if not prep:
		start_btn.text = "戰鬥中…"


## 文明面板：常駐顯示 2 Buff（藍）與 2 Debuff（紅）
func _refresh_civ() -> void:
	var c := GameData.civ(run.civ_id)
	var lines: Array = []
	lines.append("[b][color=%s]%s[/color][/b]" % [UiStyle.hex_color(GameData.race_color(str(c.get("race", ""))).lightened(0.3)), c.get("name", "")])
	for bf in c.get("buffs", []):
		lines.append("[color=%s]▲ %s[/color]" % [COLOR_UP, bf["text"]])
	for df in c.get("debuffs", []):
		lines.append("[color=%s]▼ %s[/color]" % [COLOR_DOWN, df["text"]])
	civ_text.text = "\n".join(lines)


## 羈絆面板：每個羈絆是一個按鈕，點擊後在右側顯示完整名單
func _refresh_traits() -> void:
	for c in trait_list.get_children():
		trait_list.remove_child(c)
		c.queue_free()
	var summary := Synergy.summary(run.synergy_counts())
	if summary.is_empty():
		var l := InfoView.make_rich("[color=#9aa3ad]把棋子放上棋盤即可啟動羈絆（同名只計 1 種）。[/color]", 13)
		trait_list.add_child(l)
	for s in summary:
		var th: Array = s["thresholds"]
		var active := int(s["tier"]) >= 0
		var next := ""
		for t in th:
			if int(s["count"]) < int(t):
				next = "/%d" % int(t)
				break
		var group_name: String = {"race": "種族", "type": "類型", "class": "職業"}[s["group"]]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 34)
		b.clip_text = true
		b.text = "%s %s・%d%s" % [s["name"], group_name, s["count"], next if next != "" else "（滿）"]
		b.tooltip_text = "點擊查看完整名單"
		if active:
			UiStyle.style_button(b, Color(0.45, 0.32, 0.08), UiStyle.GOLD, 14)
		else:
			UiStyle.style_button(b, Color(0.15, 0.17, 0.22), Color(1, 1, 1, 0.08), 14)
			b.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
		var g: String = s["group"]
		var k: String = s["key"]
		b.pressed.connect(func(): _set_info("trait", {"group": g, "key": k}))
		trait_list.add_child(b)
	var tip := InfoView.make_rich("[color=#8a90a0]點羈絆可看所有成員與取得狀態[/color]", 12)
	trait_list.add_child(tip)


func _refresh_info() -> void:
	sell_btn.visible = false
	match _info_mode:
		"unit":
			_info_prep_unit(int(_info_ref))
		"enemy":
			_info_enemy(_info_ref)
		"battle":
			_info_battle(int(_info_ref))
		"trait":
			_info_trait(_info_ref)
		_:
			info_title.text = "棋子資訊"
			_info.show_text("[color=#9aa3ad]點選棋子查看屬性、數值來源與技能。\n\n• 點棋子＝選取；點另一隻＝切換\n• 選取後點空格＝移動\n• 拖曳＝移動或互換\n• 拖到下方商店列＝出售\n• 點棋盤外空白處＝取消選取\n• 戰鬥中也可點雙方棋子查看即時數值\n• 點左側羈絆可看完整名單\n\n電腦快捷鍵：D 刷新、F 買經驗、E 出售、空白鍵 開戰[/color]")


func _unit_header(id: String, star: int, note: String) -> String:
	var u := GameData.unit(id)
	var cost := int(u["cost"])
	var lines: Array = []
	if not GameData.is_special(id):
		lines.append("[color=%s]%s %d 費[/color]　[color=#ffe873]%s[/color]" % [UiStyle.hex_color(GameData.tier_color(cost)), GameData.tier_name(cost), cost, UiStyle.stars(star)])
		lines.append(UiStyle.unit_line(id))
	else:
		lines.append("[color=#9aa3ad]教學用弱敵（固定屬性、無主動技能）[/color]")
	if note != "":
		lines.append(note)
	return "\n".join(lines)


func _skill_footer(id: String, star: int) -> String:
	var sk := UnitStats.skill(id)
	var lines: Array = []
	lines.append("")
	lines.append("[color=#ffd34d]技能｜%s[/color]" % str(sk.get("name", "")))
	lines.append(UnitStats.skill_text(id, star))
	lines.append("")
	lines.append("[color=#8a90a0]裝備欄（V0.3 開放）：［ 空 ］［ 空 ］[/color]")
	return "\n".join(lines)


func _info_prep_unit(uid: int) -> void:
	var f := run.find_unit(uid)
	if f.is_empty():
		_set_info("none", null)
		return
	var u: Dictionary = f["unit"]
	var id := str(u["id"])
	var star := int(u["star"])
	info_title.text = "%s %s" % [GameData.unit(id)["name"], UiStyle.stars(star)]
	var sources: Array = []
	var note := "[color=#9aa3ad]候補區：尚未套用文明與羈絆[/color]"
	if f["where"] == "board":
		var lineup := run.board_lineup()
		var ids: Array = []
		for p in lineup:
			ids.append(p["id"])
		var all_sources := Modifiers.sources_for_lineup(ids, run.civ_id, true)
		for i in lineup.size():
			if int(lineup[i]["uid"]) == uid:
				sources = all_sources[i]
		note = "[color=#9aa3ad]場上：已含文明與羈絆修正[/color]"
	_info.update_stats(_unit_header(id, star, note), StatBreakdown.build(id, star, sources), _skill_footer(id, star))
	if phase == Phase.PREP:
		sell_btn.visible = true
		sell_btn.text = "出售　+%d 金" % UnitStats.sell_value(id, star)


func _info_enemy(ref: Dictionary) -> void:
	var id := str(ref["id"])
	var star := int(ref["star"])
	info_title.text = "敵方：%s %s" % [GameData.unit(id)["name"], UiStyle.stars(star)]
	var note := "[color=#9aa3ad]敵軍沒有文明加成；V0.1 起敵方羈絆預設關閉。[/color]"
	_info.update_stats(_unit_header(id, star, note), StatBreakdown.build(id, star, []), _skill_footer(id, star))


## 戰鬥中查看：以 cid 讀取戰鬥單位的即時狀態（唯讀，不影響戰鬥）
func _info_battle(cid: int) -> void:
	var snap := battle_player.unit_snapshot(cid)
	if snap.is_empty():
		_set_info("none", null)
		return
	var id := str(snap["id"])
	var star := int(snap["star"])
	var side := int(snap["side"])
	info_title.text = "%s%s %s" % ["敵方：" if side == 1 else "", GameData.unit(id)["name"], UiStyle.stars(star)]
	var sources: Array = []
	if side == 0:
		var lineup := battle_player.player_lineup()
		var ids: Array = []
		for p in lineup:
			ids.append(p["id"])
		var all_sources := Modifiers.sources_for_lineup(ids, run.civ_id, true)
		for i in lineup.size():
			if int(lineup[i]["cid"]) == cid:
				sources = all_sources[i]
	var statuses := battle_player.live_statuses(cid)
	var tk := battle_player.token(cid)
	var alive := battle_player.is_alive(cid)
	var live: Array = []
	if tk:
		if alive:
			live.append("生命 [b]%d[/b] / %d　護盾 %d" % [roundi(tk.hp), roundi(tk.max_hp), roundi(tk.shield)])
			live.append("魔力 %d / %d" % [roundi(tk.mana), roundi(tk.mana_max)])
		else:
			live.append("[color=#ff6b6b]已陣亡[/color]")
	if statuses.is_empty():
		live.append("[color=#8a90a0]目前沒有增益或負面狀態[/color]")
	for st in statuses:
		var kind := str(st["kind"])
		var neg := kind in UnitToken.NEGATIVE
		var nm := str(StatBreakdown.STATUS_NAMES.get(kind, kind))
		var val := ""
		if float(st["value"]) != 0.0:
			val = " %s%s" % ["-" if neg else "+", StatBreakdown._f(absf(float(st["value"])))]
			if kind in ["atk_up", "atk_down", "slow", "dmg_up", "phys_dr", "mark", "as_up"]:
				val += "%"
		live.append("[color=%s]%s %s%s（剩 %.1f 秒）[/color]" % [COLOR_DOWN if neg else COLOR_UP, "▼" if neg else "▲", nm, val, float(st["left"])])
	live.append("[color=#8a90a0]戰鬥中只能查看，不能移動或出售[/color]")
	var header := _unit_header(id, star, "\n".join(live))
	_info.update_stats(header, StatBreakdown.build(id, star, sources, statuses), _skill_footer(id, star))


## 羈絆完整名單：已上場／候補／未持有／本文明無法取得
func _info_trait(ref: Dictionary) -> void:
	var board_units: Array = []
	for p in run.board_lineup():
		board_units.append({"id": p["id"], "star": p["star"]})
	var bench_units: Array = []
	for b in run.bench:
		if b != null:
			bench_units.append({"id": b["id"], "star": b["star"]})
	var d := Synergy.detail(str(ref["group"]), str(ref["key"]), board_units, bench_units, run.civ_id)
	var group_name: String = {"race": "種族", "type": "類型", "class": "職業"}[d["group"]]
	info_title.text = "羈絆：%s（%s）" % [d["name"], group_name]
	var lines: Array = []
	var tier := int(d["tier"])
	if tier >= 0:
		lines.append("[color=#ffd24d]已啟動第 %d 階（上場 %d 種）[/color]" % [tier + 1, d["count"]])
	else:
		lines.append("[color=#9aa3ad]未啟動（上場 %d 種）[/color]" % d["count"])
	var th: Array = d["thresholds"]
	var next_need := -1
	for t in th:
		if int(d["count"]) < int(t):
			next_need = int(t)
			break
	if next_need > 0:
		lines.append("下一階：需要 %d 種，還差 %d 種" % [next_need, next_need - int(d["count"])])
	else:
		lines.append("已達最高階")
	lines.append("")
	for i in th.size():
		var on := i == tier
		lines.append("%s[b]%d 種[/b]：%s%s" % ["[color=#ffd24d]" if on else "[color=#9aa3ad]", th[i], d["texts"][i], "[/color]"])
	lines.append("")
	lines.append("[b]成員[/b]　[color=#8a90a0]（只計已上場且不同名稱）[/color]")
	for m in d["members"]:
		var stars := ""
		if not m["stars"].is_empty():
			var parts: Array = []
			for s in m["stars"]:
				parts.append("★".repeat(int(s)))
			stars = "　" + "、".join(parts)
		var name := "[s]%s[/s]" % m["name"] if m["state"] == "unavailable" else str(m["name"])
		lines.append("%s　%s %d 費%s" % [STATE_MARK[m["state"]], name, m["cost"], stars])
	_info.show_text("\n".join(lines))


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
	prep_timer.stop()
	run.gold_at_battle_start = run.gold
	_last_result = {"cleared": true, "threat": 0, "alive_enemies": [], "stats": []}
	var report := run.settle(_last_result)
	report["stats"] = []
	_last_report = report
	if run.finished:
		SaveSystem.clear()
	phase = Phase.RESULT
	_show_result(report, false)
	_refresh()
