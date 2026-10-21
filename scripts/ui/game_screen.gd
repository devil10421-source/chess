extends Control
## 遊戲主畫面（V0.4，手機橫向優先）。
## 上：回合 X/24＋七個裝備節點、30 秒備戰倒數條。左：精簡羈絆清單（文明置頂；滑鼠懸停或點擊才顯示浮動說明）。
## 右：浮在戰場上的戰鬥貢獻面板（收合時只剩圖示）；選取棋子時改顯示棋子資訊卡。下：資源列、XP 條（與商店同寬）、商店。
## 棋盤的位置與大小只由上下兩條與左側清單的固定寬度決定，右側面板開關不會推動棋盤。
## 每回合不再彈出結算畫面：戰後以不擋操作的提示顯示收入、生命與升級；裝備回合結束後先三選一再進入備戰。
## 電腦快捷鍵：D 刷新、F 買經驗、E 出售、空白鍵 開戰、Esc 選單。

enum Phase { PREP, BATTLE, AFTER, REWARD }

const RIGHT_W := 280.0
const COLLAPSED_W := 64.0
const COLLAPSED_H := 54.0
const POPOVER_W := 330.0
const COLOR_UP := "#5aa9ff"
const COLOR_DOWN := "#ff6b6b"
const STATE_MARK := {
	"board": "[color=#6bdc85]● 已上場[/color]",
	"bench": "[color=#ffd24d]◐ 候補區[/color]",
	"none": "[color=#9aa3ad]○ 尚未持有[/color]",
	"unavailable": "[color=#7a6f73]× 本文明無法招募[/color]",
}

@onready var board: BoardView = $BoardView
@onready var battle_player: BattlePlayer = $BoardView/BattlePlayer
@onready var top_bar: PanelContainer = $TopBar
@onready var round_label: Label = $TopBar/HBox/RoundBox/RoundLabel
@onready var reward_dots: RewardDots = $TopBar/HBox/RoundBox/RewardDots
@onready var bar: ProgressBar = $TopBar/HBox/Countdown/Bar
@onready var bar_left: Label = $TopBar/HBox/Countdown/BarText/BarLeft
@onready var bar_right: Label = $TopBar/HBox/Countdown/BarText/BarRight
@onready var speed_btn: Button = $TopBar/HBox/SpeedButton
@onready var skip_btn: Button = $TopBar/HBox/SkipButton
@onready var debug_btn: Button = $TopBar/HBox/DebugButton
@onready var menu_btn: Button = $TopBar/HBox/MenuBtn
@onready var left_panel: PanelContainer = $LeftPanel
@onready var left_scroll: ScrollContainer = $LeftPanel/Scroll
@onready var civ_btn: Button = $LeftPanel/Scroll/List/CivButton
@onready var trait_list: VBoxContainer = $LeftPanel/Scroll/List/TraitList
@onready var popover: PanelContainer = $TraitPopover
@onready var popover_scroll: ScrollContainer = $TraitPopover/Scroll
@onready var popover_text: RichTextLabel = $TraitPopover/Scroll/Text
@onready var right_panel: PanelContainer = $RightPanel
@onready var leader_host: VBoxContainer = $RightPanel/Stack/LeaderHost
@onready var detail_box: VBoxContainer = $RightPanel/Stack/DetailBox
@onready var detail_title: Label = $RightPanel/Stack/DetailBox/Header/DetailTitle
@onready var close_detail_btn: Button = $RightPanel/Stack/DetailBox/Header/CloseDetail
@onready var detail_body: VBoxContainer = $RightPanel/Stack/DetailBox/Scroll/Body
@onready var sell_btn: Button = $RightPanel/Stack/DetailBox/SellButton
@onready var bag_box: VBoxContainer = $RightPanel/Stack/BagBox
@onready var bag_title: Label = $RightPanel/Stack/BagBox/Header/BagTitle
@onready var bag_hint: Label = $RightPanel/Stack/BagBox/BagHint
@onready var bag_list: VBoxContainer = $RightPanel/Stack/BagBox/Scroll/List
@onready var bottom_bar: PanelContainer = $BottomBar
@onready var res_box: HBoxContainer = $BottomBar/VBox/RowA/ResBox
@onready var xp_bar: ProgressBar = $BottomBar/VBox/RowA/XpBox/XpBar
@onready var xp_left: Label = $BottomBar/VBox/RowA/XpBox/XpText/XpLeft
@onready var xp_right: HBoxContainer = $BottomBar/VBox/RowA/XpBox/XpText/XpRight
@onready var bag_btn: Button = $BottomBar/VBox/RowA/BagButton
@onready var reroll_btn: Button = $BottomBar/VBox/RowB/LeftButtons/RerollButton
@onready var civup_btn: Button = $BottomBar/VBox/RowB/LeftButtons/CivUpButton
@onready var shop_slots: HBoxContainer = $BottomBar/VBox/RowB/ShopSlots
@onready var lock_btn: Button = $BottomBar/VBox/RowB/RightButtons/LockButton
@onready var big_countdown: Label = $BigCountdown
@onready var reward_overlay: Control = $RewardOverlay
@onready var reward_title: Label = $RewardOverlay/Panel/VBox/RewardTitle
@onready var reward_cards: HBoxContainer = $RewardOverlay/Panel/VBox/Cards
@onready var item_overlay: Control = $ItemOverlay
@onready var item_title: Label = $ItemOverlay/Panel/VBox/ItemTitle
@onready var item_body: VBoxContainer = $ItemOverlay/Panel/VBox/ItemScroll/ItemBody
@onready var item_buttons: HBoxContainer = $ItemOverlay/Panel/VBox/ItemButtons
@onready var menu_overlay: Control = $MenuOverlay
@onready var debug_panel: PanelContainer = $DebugPanel
@onready var round_spin: SpinBox = $DebugPanel/VBox/RoundRow/RoundSpin
@onready var abandon_confirm: ConfirmationDialog = $AbandonConfirm
@onready var toasts: VBoxContainer = $Toasts

var run: RunState
var phase := Phase.PREP
var prep_timer := PrepTimer.new()
var leader: LeaderPanel
var card: UnitCard
var _detail_text: RichTextLabel
var _shop_buttons: Array[Button] = []
var _last_result: Dictionary = {}
## 浮動說明（羈絆／文明）：key＝"civ" 或 "group:key"；pinned＝點擊固定（手機點擊、電腦點擊），否則為滑鼠懸停
var _pop_key := ""
var _pop_pinned := false
var _pop_anchor_y := 0.0
## 版面初始位移（套用手機安全區時以此為基準）
var _base_offsets: Dictionary = {}
## 右側詳細資訊目前顯示的對象：none / unit（備戰棋子 uid）/ enemy（敵方預覽）/ battle（戰鬥中 cid）
var _info_mode := "none"
var _info_ref: Variant = null
var _info_refresh := 0.0
var _leader_refresh := 0.0
var _after_time := 0.0
var _last_seconds := -1
# 底部資源列與按鈕上的文字
var _gold_label: Label
var _interest_label: Label
var _lv_label: Label
var _civ_badge: UiIcon
var _hp_label: Label
var _pop_label: Label
var _xp_cost_label: Label
var _xp_coin: UiIcon
var _xp_word: Label
var _btn_labels: Dictionary = {}


func _ready() -> void:
	run = Session.run
	if run == null:
		# 直接在編輯器執行此場景（F6）時，自動建立一局測試用遠征
		run = RunState.create("human", 20240601)
		Session.run = run
	for i in 5:
		_shop_buttons.append(get_node("BottomBar/VBox/RowB/ShopSlots/Slot%d" % i))
	leader = LeaderPanel.new()
	leader_host.add_child(leader)
	card = UnitCard.new()
	detail_body.add_child(card)
	_detail_text = InfoView.make_rich("", 14)
	detail_body.add_child(_detail_text)
	for c in [top_bar, left_panel, right_panel, bottom_bar]:
		_base_offsets[c] = [c.offset_left, c.offset_top, c.offset_right, c.offset_bottom]
	_build_bottom()
	_build_civ_row()
	_style()
	_connect()
	get_viewport().size_changed.connect(_layout)
	board.is_over_sell_zone = func(p: Vector2) -> bool: return bottom_bar.get_global_rect().has_point(p) and _shop_open()
	run.changed.connect(_on_run_changed)
	debug_btn.visible = Session.debug_enabled
	_apply_side_layout()
	_enter_prep()
	await get_tree().process_frame
	_layout()


# ---------- 建立底部資源列與圖示按鈕 ----------
func _build_bottom() -> void:
	var civ_col := _civ_color()
	_gold_label = _res_item("coin", UiStyle.GOLD, "0")
	_interest_label = Label.new()
	_interest_label.add_theme_font_size_override("font_size", 12)
	_interest_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_interest_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5, 0.85))
	res_box.add_child(_interest_label)
	_sep()
	_civ_badge = UiIcon.make(_civ_icon(), civ_col, 20)
	res_box.add_child(_civ_badge)
	_lv_label = Label.new()
	_lv_label.add_theme_font_size_override("font_size", 17)
	_lv_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	res_box.add_child(_lv_label)
	_sep()
	_hp_label = _res_item("heart", Color(1.0, 0.45, 0.45), "40/40")
	_sep()
	_pop_label = _res_item("people", Color(0.75, 0.85, 1.0), "0/1")
	_xp_cost_label = Label.new()
	_xp_coin = UiIcon.make("coin", UiStyle.GOLD, 16)
	_xp_word = Label.new()
	for l in [_xp_cost_label, _xp_word]:
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_right.add_child(_xp_cost_label)
	xp_right.add_child(_xp_coin)
	xp_right.add_child(_xp_word)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(6, 0)
	xp_right.add_child(pad)
	_decorate(reroll_btn, "refresh", Color(0.85, 0.92, 1.0), "刷新 2")
	_decorate(civup_btn, _civ_icon(), civ_col, "+4 XP", 28)
	_decorate(lock_btn, "unlock", Color(0.85, 0.88, 0.95), "鎖定")
	_decorate(bag_btn, "bag", Color(0.85, 0.75, 0.55), "背包 0")


func _res_item(kind: String, tint: Color, text: String) -> Label:
	var ic := UiIcon.make(kind, tint, 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	res_box.add_child(ic)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	res_box.add_child(l)
	return l


func _sep() -> void:
	var l := Label.new()
	l.text = "｜"
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	res_box.add_child(l)


## 在按鈕中放「圖示＋文字」（文字之後由 _btn_text 更新）
func _decorate(b: Button, kind: String, tint: Color, text: String, icon_size: float = 22.0) -> void:
	b.text = ""
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var ic := UiIcon.make(kind, tint, icon_size)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(ic)
	h.add_child(l)
	b.add_child(h)
	_btn_labels[b] = {"label": l, "icon": ic}


func _btn_text(b: Button, text: String, icon_kind: String = "") -> void:
	var it: Dictionary = _btn_labels.get(b, {})
	if it.is_empty():
		b.text = text
		return
	(it["label"] as Label).text = text
	if icon_kind != "":
		(it["icon"] as UiIcon).set_icon(icon_kind, (it["icon"] as UiIcon).tint)


func btn_label(b: Button) -> String:
	var it: Dictionary = _btn_labels.get(b, {})
	return (it["label"] as Label).text if not it.is_empty() else b.text


## 文明徽章圖示（精靈葉、人類王冠、半獸人獠牙、半人馬馬蹄、鹿角人鹿角、鬼人鬼角）
func _civ_icon() -> String:
	return "civ_" + run.civ_id


## 羈絆清單第一列：文明（圖示＋名稱；說明改用浮動視窗）
func _build_civ_row() -> void:
	civ_btn.text = ""
	_row_content(civ_btn, _civ_icon(), _civ_color(), "", "%s文明" % GameData.civ(run.civ_id).get("name", ""), Color.WHITE)
	civ_btn.mouse_entered.connect(func(): _hover_pop("civ", civ_btn, true))
	civ_btn.mouse_exited.connect(func(): _hover_pop("civ", civ_btn, false))
	civ_btn.pressed.connect(func(): _press_pop("civ", civ_btn))


## 羈絆列的內容：[圖示] 進度 名稱
func _row_content(b: Button, icon: String, tint: Color, progress: String, name_text: String, text_col: Color) -> void:
	for c in b.get_children():
		b.remove_child(c)
		c.queue_free()
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -4
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 5)
	var ic := UiIcon.make(icon, tint, 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	if progress != "":
		var pl := Label.new()
		pl.text = progress
		pl.add_theme_font_size_override("font_size", 14)
		pl.add_theme_color_override("font_color", text_col)
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(pl)
	var nl := Label.new()
	nl.text = name_text
	nl.clip_text = true
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.add_theme_font_size_override("font_size", 14)
	nl.add_theme_color_override("font_color", text_col)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(nl)
	b.add_child(h)


func _civ_color() -> Color:
	return Color(str(GameData.civ(run.civ_id).get("color", "#888888")))


func _style() -> void:
	for p in [left_panel, right_panel, $MenuOverlay/Panel, debug_panel, $ItemOverlay/Panel]:
		UiStyle.apply_panel(p)
	for p in [top_bar, bottom_bar]:
		var sb := UiStyle.panel_box()
		sb.content_margin_top = 4 if p == top_bar else 6
		sb.content_margin_bottom = 4 if p == top_bar else 6
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		p.add_theme_stylebox_override("panel", sb)
	var lp := UiStyle.panel_box(Color(0.10, 0.12, 0.16, 0.82))
	lp.content_margin_left = 4
	lp.content_margin_right = 4
	lp.content_margin_top = 4
	lp.content_margin_bottom = 4
	left_panel.add_theme_stylebox_override("panel", lp)
	UiStyle.apply_panel(popover, Color(0.08, 0.10, 0.14, 0.97), UiStyle.GOLD)
	UiStyle.apply_panel($RewardOverlay/Panel, Color(0.10, 0.12, 0.17, 0.98), UiStyle.GOLD)
	UiStyle.style_button(reroll_btn, Color(0.16, 0.30, 0.52))
	UiStyle.style_button(civup_btn, _civ_color().darkened(0.55), _civ_color())
	UiStyle.style_button(lock_btn, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 15)
	UiStyle.style_button(sell_btn, Color(0.50, 0.20, 0.18))
	UiStyle.style_button(bag_btn, Color(0.22, 0.19, 0.14), Color(0.85, 0.75, 0.55, 0.6), 15)
	UiStyle.style_button(civ_btn, _civ_color().darkened(0.6), _civ_color(), 15)
	for b in [speed_btn, skip_btn, debug_btn, menu_btn, close_detail_btn, $RightPanel/Stack/BagBox/Header/CloseBag]:
		UiStyle.style_button(b, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 14)
	for b in $MenuOverlay/Panel/VBox.get_children():
		if b is Button:
			UiStyle.style_button(b, Color(0.18, 0.21, 0.28))
	for b in [$DebugPanel/VBox/RoundRow/JumpButton, $DebugPanel/VBox/Row2/GoldButton, $DebugPanel/VBox/Row2/LevelButton,
			$DebugPanel/VBox/Row3/WinButton, $DebugPanel/VBox/Row3/ItemButton, $DebugPanel/VBox/CloseDebugButton]:
		UiStyle.style_button(b, Color(0.35, 0.22, 0.14), Color(1, 0.6, 0.4, 0.5), 15)
	var xfill := StyleBoxFlat.new()
	xfill.bg_color = Color(0.30, 0.55, 0.95)
	xfill.set_corner_radius_all(6)
	var xbg := StyleBoxFlat.new()
	xbg.bg_color = Color(1, 1, 1, 0.08)
	xbg.set_corner_radius_all(6)
	xp_bar.add_theme_stylebox_override("fill", xfill)
	xp_bar.add_theme_stylebox_override("background", xbg)
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = Color(1, 1, 1, 0.07)
	bbg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bbg)
	_set_bar_color(Color(0.35, 0.6, 0.95))


func _set_bar_color(c: Color) -> void:
	var f := StyleBoxFlat.new()
	f.bg_color = c
	f.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", f)


func _connect() -> void:
	for i in _shop_buttons.size():
		var idx := i
		_shop_buttons[i].pressed.connect(func(): _on_buy(idx))
	reroll_btn.pressed.connect(_on_reroll)
	civup_btn.pressed.connect(_on_buy_xp)
	lock_btn.pressed.connect(func():
		if _shop_open():
			run.toggle_lock())
	sell_btn.pressed.connect(_on_sell_selected)
	bag_btn.pressed.connect(_show_bag)
	close_detail_btn.pressed.connect(_close_detail)
	$RightPanel/Stack/BagBox/Header/CloseBag.pressed.connect(_close_bag)
	board.tap_interceptor = _intercept_unit_tap
	leader.collapse_toggled.connect(func(_c: bool): _apply_side_layout())
	reward_dots.dot_pressed.connect(func(_r: int, text: String): _toast(text))
	speed_btn.pressed.connect(_cycle_speed)
	skip_btn.pressed.connect(func(): battle_player.skip())
	menu_btn.pressed.connect(func(): _show_menu(true))
	debug_btn.pressed.connect(func(): debug_panel.visible = not debug_panel.visible)
	card.equip_slot_pressed.connect(_on_equip_slot)
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
	board.unit_selected.connect(func(uid: int): _set_info("unit" if uid >= 0 else "none", uid if uid >= 0 else null))
	board.enemy_selected.connect(func(id: String, star: int): _set_info("enemy", {"id": id, "star": star}))
	board.battle_unit_selected.connect(func(cid: int): _set_info("battle" if cid >= 0 else "none", cid if cid >= 0 else null))
	board.move_to_board_requested.connect(func(uid: int, cell: Vector2i):
		if phase == Phase.PREP:
			_report(run.move_to_board(uid, cell)))
	board.move_to_bench_requested.connect(func(uid: int, idx: int):
		# 戰鬥中也能整理候補區（只影響下一回合）；場上棋子由 RunState 擋下
		_report(run.move_to_bench(uid, idx)))
	board.sell_requested.connect(func(uid: int): _sell(uid))
	battle_player.finished.connect(_on_battle_finished)
	$DebugPanel/VBox/RoundRow/JumpButton.pressed.connect(_debug_jump)
	$DebugPanel/VBox/Row2/GoldButton.pressed.connect(func():
		run.gold += 20
		run.changed.emit())
	$DebugPanel/VBox/Row2/LevelButton.pressed.connect(_debug_level)
	$DebugPanel/VBox/Row3/ItemButton.pressed.connect(func():
		var all := GameData.items()
		run.inventory.append(str(all[randi() % all.size()]["id"]))
		run.changed.emit())
	$DebugPanel/VBox/Row3/WinButton.pressed.connect(_debug_win)
	$DebugPanel/VBox/CloseDebugButton.pressed.connect(func(): debug_panel.visible = false)


# ---------- 版面 ----------
## 右側面板浮在戰場上方：收合時只剩右上角一個圖示；開關都不會影響棋盤
func _apply_side_layout() -> void:
	var bag := bag_box.visible
	var detail := detail_box.visible and not bag
	detail_box.visible = detail_box.visible and not bag
	var small := leader.collapsed and not detail and not bag
	var ins := _safe_insets()
	var base: Array = _base_offsets.get(right_panel, [right_panel.offset_left, right_panel.offset_top, right_panel.offset_right, right_panel.offset_bottom])
	right_panel.offset_right = float(base[2]) - ins.z
	right_panel.offset_left = right_panel.offset_right - (COLLAPSED_W if small else RIGHT_W)
	right_panel.offset_top = float(base[1]) + ins.y
	if small:
		right_panel.anchor_bottom = 0.0
		right_panel.offset_bottom = right_panel.offset_top + COLLAPSED_H
	else:
		right_panel.anchor_bottom = 1.0
		right_panel.offset_bottom = float(base[3]) - ins.w
	leader_host.visible = not detail and not bag


func _layout_deferred() -> void:
	await get_tree().process_frame
	_layout()


## 手機安全區（瀏海、圓角、手勢列）：回傳 (左, 上, 右, 下) 需要內縮的距離（畫面座標）
func _safe_insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return Vector4.ZERO
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var k := get_viewport_rect().size / win
	return Vector4(maxf(0.0, safe.position.x) * k.x, maxf(0.0, safe.position.y) * k.y,
		maxf(0.0, win.x - safe.end.x) * k.x, maxf(0.0, win.y - safe.end.y) * k.y)


func _apply_safe_area() -> void:
	var ins := _safe_insets()
	for c in [top_bar, left_panel, bottom_bar]:
		var o: Array = _base_offsets[c]
		c.offset_left = float(o[0]) + ins.x
		c.offset_top = float(o[1]) + (-ins.w if c == bottom_bar else ins.y)
		c.offset_right = float(o[2]) + (ins.x if c == left_panel else -ins.z)
		c.offset_bottom = float(o[3]) + (ins.y if c == top_bar else -ins.w)
	_apply_side_layout()


## 棋盤可用區：上下兩條之間；左右以左側清單寬度對稱保留，使棋盤固定置中（右側面板不參與）
func board_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var left := left_panel.offset_right + 8.0
	var right := vs.x - left
	# 用實際範圍（面板內容可能比設定的位移高）
	var top := maxf(top_bar.offset_bottom, top_bar.get_global_rect().end.y) + 4.0
	var bottom := minf(vs.y + bottom_bar.offset_top, bottom_bar.get_global_rect().position.y) - 4.0
	return Rect2(left, top, maxf(100.0, right - left), maxf(100.0, bottom - top))


func _layout() -> void:
	if not is_inside_tree():
		return
	_apply_safe_area()
	_sync_bottom_columns()
	var r := board_rect()
	board.fit(r)
	big_countdown.position.y = r.position.y + r.size.y * 0.35
	if popover.visible:
		_place_popover()


## 底部兩列使用相同的左右欄寬，讓 XP 條與五格商店完全等寬
func _sync_bottom_columns() -> void:
	var left_btns: Control = $BottomBar/VBox/RowB/LeftButtons
	var right_btns: Control = $BottomBar/VBox/RowB/RightButtons
	res_box.custom_minimum_size.x = 0
	left_btns.custom_minimum_size.x = 0
	var lw := maxf(maxf(res_box.get_combined_minimum_size().x, left_btns.get_combined_minimum_size().x), 220.0)
	res_box.custom_minimum_size.x = lw
	left_btns.custom_minimum_size.x = lw
	var rw := maxf(maxf(bag_btn.get_combined_minimum_size().x, right_btns.get_combined_minimum_size().x), 150.0)
	bag_btn.custom_minimum_size.x = rw
	right_btns.custom_minimum_size.x = rw


# ---------- 階段 ----------
func _enter_prep() -> void:
	# 先處理上一回合的裝備三選一（選擇時不計入 30 秒）
	if run.has_pending_reward():
		_show_reward()
		return
	phase = Phase.PREP
	reward_overlay.visible = false
	run.begin_round()
	SaveSystem.save_run(run)
	battle_player.clear()
	board.battle_mode = false
	board.interactive = true
	board.set_prep_visible(true)
	board.show_prep(run)
	speed_btn.visible = false
	skip_btn.visible = false
	menu_btn.visible = true
	_set_info("none", null)
	_refresh()
	# 介面與棋盤初始化完成、上一場戰鬥結束後才開始倒數（秒數依回合設定；從圖鑑返回同一回合時接續剩餘秒數）
	prep_timer.start_round(run.round_no)
	if Session.prep_time_round == run.round_no and Session.prep_time_left > 0.0:
		prep_timer.remaining = Session.prep_time_left
	Session.prep_time_round = -1
	_last_seconds = -1
	_update_bar()


func _process(delta: float) -> void:
	match phase:
		Phase.PREP:
			# V0.5：裝備資訊、合成確認、三選一都不暫停倒數；只有選單、除錯、放棄確認會暫停
			prep_timer.paused = menu_overlay.visible or debug_panel.visible or abandon_confirm.visible
			if prep_timer.tick(delta):
				_on_start_battle(true)
				return
			_update_bar()
		Phase.BATTLE:
			_update_bar()
			_info_refresh -= delta
			if _info_mode == "battle" and _info_refresh <= 0.0:
				_info_refresh = 0.2
				_refresh_info()
			_leader_refresh -= delta
			if _leader_refresh <= 0.0:
				_leader_refresh = 0.5
				leader.set_stats(battle_player.live_stats())
		Phase.AFTER:
			_after_time -= delta
			if _after_time <= 0.0:
				if run.finished:
					Session.goto(Session.SCENE_END)
					phase = Phase.REWARD
				else:
					_enter_prep()


func _stage_text() -> String:
	var st := GameData.stage(run.round_no)
	var fac := str(st.get("faction", ""))
	var tag := ""
	if fac != "":
		tag = "（%s）" % GameData.phase(fac).get("name", fac)
	return "%s%s" % [st.get("name", ""), tag]


func _update_bar() -> void:
	match phase:
		Phase.PREP:
			bar.max_value = prep_timer.duration
			bar.value = prep_timer.remaining
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
			_set_bar_color(Color(0.92, 0.3, 0.28) if warn else (Color(0.95, 0.78, 0.2) if prep_timer.is_caution() else Color(0.35, 0.6, 0.95)))
			bar_left.text = " " + _stage_text()
			bar_right.text = ("%d 秒（暫停）" % secs) if prep_timer.paused else ("%d 秒" % secs)
			big_countdown.text = str(secs)
		Phase.BATTLE:
			bar.max_value = 1.0
			bar.value = 1.0
			bar_left.text = " 戰鬥中・" + _stage_text()
			bar_right.text = "%.1f 秒 ×%.1f " % [battle_player.sim_time(), Session.playback_rate]
		_:
			bar.max_value = 1.0
			bar.value = 1.0
			bar_right.text = ""


func _set_bar_neutral() -> void:
	_set_bar_color(Color(0.30, 0.34, 0.42))


func _on_run_changed() -> void:
	board.sync_prep()
	_refresh_bag()
	if phase == Phase.PREP:
		_refresh()
		SaveSystem.save_run(run)
	else:
		_refresh_bottom()
		_refresh_shop()
		_refresh_info()


## 倒數結束自動開戰（V0.5 沒有開始戰鬥按鈕）
func _on_start_battle(auto: bool) -> void:
	if phase != Phase.PREP:
		return
	board.cancel_drag()
	_pending_item = -1
	_bag_target_uid = -1
	_refresh_bag()
	var placed := run.auto_fill_board()
	prep_timer.stop()
	big_countdown.visible = false
	phase = Phase.BATTLE
	_set_bar_neutral()
	board.select(-1)
	board.interactive = false
	_last_result = {}
	var sim := run.create_battle()
	board.set_prep_visible(false)
	board.battle_mode = true
	battle_player.play_live(sim, board)
	leader.set_stats(battle_player.live_stats())
	speed_btn.visible = true
	skip_btn.visible = true
	menu_btn.visible = false
	debug_panel.visible = false
	_update_speed_label()
	_set_info("none", null)
	_refresh()
	if not placed.is_empty():
		_toast("人口未滿：已從候補區自動補上 %d 隻" % placed.size())
	else:
		_toast("備戰時間到，開戰！")


func _on_battle_finished() -> void:
	if phase != Phase.BATTLE:
		return
	_last_result = battle_player.sim().result()
	var rep := run.settle(_last_result)
	leader.set_stats(_last_result.get("stats", []))   # 保留上一場統計，直到下一場開始
	if run.finished:
		SaveSystem.clear()
	else:
		SaveSystem.save_run(run)
	_toast_report(rep)
	board.battle_mode = false
	skip_btn.visible = false
	phase = Phase.AFTER
	_after_time = 2.5 if run.finished else 1.0
	_refresh()


## 不擋操作的戰後提示：收入、生命變化、升級
func _toast_report(rep: Dictionary) -> void:
	if rep["outcome"] == "defeat":
		_toast("遠征生命歸零……", Color(1, 0.5, 0.5))
		return
	if rep["cleared"]:
		_toast("全清敵軍", Color(0.55, 0.95, 0.6))
	else:
		_toast("未全清：遠征生命 −%d（剩 %d）" % [rep["hp_loss"], rep["hp_after"]], Color(1, 0.6, 0.55))
	var total := int(rep["income_base"]) + int(rep["income_interest"]) + int(rep["income_clear"])
	_toast("+%d 金（固定 %d・利息 %d・全清 %d）" % [total, rep["income_base"], rep["income_interest"], rep["income_clear"]], UiStyle.GOLD)
	if int(rep["deer_heal"]) > 0:
		_toast("鹿角人：遠征生命 +%d" % rep["deer_heal"], Color(0.55, 0.95, 0.6))
	if rep["level_after"] != rep["level_before"]:
		_toast("文明升到 Lv.%d！" % rep["level_after"], Color(0.6, 0.85, 1.0))
	if bool(rep.get("remover", false)):
		_toast("獲得 1 個%s（現有 %d 個）" % [GameData.remover_name(), run.removers], UiStyle.GOLD)
	if rep["outcome"] == "victory":
		_toast("遠征完成！", UiStyle.GOLD)
	elif rep["outcome"] == "incomplete":
		_toast("第 24 回合未能全清，遠征未完成", Color(1, 0.6, 0.55))


# ---------- 裝備三選一 ----------
func _show_reward() -> void:
	phase = Phase.REWARD
	prep_timer.stop()
	big_countdown.visible = false
	_set_bar_neutral()
	bar_left.text = " 選擇裝備獎勵（不計備戰時間）"
	bar_right.text = ""
	for c in reward_cards.get_children():
		reward_cards.remove_child(c)
		c.queue_free()
	var pr := run.pending_reward
	var fac := str(GameData.equipment().get("factions", {}).get(pr["faction"], {}).get("name", ""))
	reward_title.text = "第 %d 回合獎勵：%s" % [int(pr["round"]), fac]
	var choices: Array = pr["choices"]
	for i in choices.size():
		reward_cards.add_child(_item_card(str(choices[i]), "選擇", func(): _claim(i)))
	reward_overlay.visible = true
	_refresh_top()


func _claim(i: int) -> void:
	var id := str(run.pending_reward["choices"][i])
	if run.claim_reward(i) == "":
		reward_overlay.visible = false
		_toast("獲得裝備：%s（已放入背包）" % GameData.item(id)["name"], UiStyle.GOLD)
		SaveSystem.save_run(run)
		_enter_prep()


## 裝備卡片（固定格式）：名稱／基礎屬性／唯一特性・名稱：一句話描述
func _item_card(id: String, action: String, on_press: Callable) -> Control:
	var it := GameData.item(id)
	var col := Color(str(Equipment.type_info(id).get("color", "#fff")))
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.apply_panel(p, Color(0.12, 0.14, 0.19), col.darkened(0.2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var h := HBoxContainer.new()
	h.add_child(UiIcon.make(str(it.get("type", "weapon")), col, 30))
	var nm := Label.new()
	nm.text = str(it.get("name", id))
	nm.add_theme_font_size_override("font_size", 18)
	h.add_child(nm)
	v.add_child(h)
	v.add_child(InfoView.make_rich(_item_text(id), 13))
	if action != "":
		var b := Button.new()
		b.text = action
		b.custom_minimum_size = Vector2(0, 44)
		UiStyle.style_button(b, Color(0.55, 0.36, 0.08), UiStyle.GOLD, 16)
		b.pressed.connect(on_press)
		v.add_child(b)
	p.add_child(v)
	return p


func _item_text(id: String) -> String:
	var lines: Array = ["[color=%s]%s[/color]" % [COLOR_UP, Equipment.stat_text(id)]]
	var u := Equipment.unique_of(id)
	if not u.is_empty():
		lines.append("[b][color=#ffd34d]唯一特性・%s[/color][/b]：%s" % [u.get("name", ""), u.get("desc", "")])
	return "\n".join(lines)


# ---------- 裝備欄與背包 ----------
## 背包開啟中、正在選裝備目標（點裝備後再點棋子）的背包索引；-1＝沒有
var _pending_item := -1
## 從棋子的空裝備欄打開背包時，直接裝到這隻棋子（-1＝一般背包）
var _bag_target_uid := -1
## 拖曳裝備：按下的背包索引、起點、是否已開始拖曳、拖曳圖示
var _drag_item := -1
var _drag_from := Vector2.ZERO
var _dragging_item := false
var _drag_consumed := false
var _ghost: Control


## 商店、候補區、背包在備戰與戰鬥中都可以操作（V0.5）；戰鬥中的場上棋子由 RunState 限制
func _shop_open() -> bool:
	return phase == Phase.PREP or phase == Phase.BATTLE or phase == Phase.AFTER


func _equip_allowed() -> bool:
	return _shop_open()


func _on_equip_slot(slot: int) -> void:
	var items: Array = _current_items()
	var uid_now := _info_uid()
	var editable := _equip_allowed() and uid_now >= 0
	if slot < items.size():
		_show_item_info(str(items[slot]), slot, editable)
	elif not editable:
		_toast("只能替自己的棋子裝備")
	elif run.inventory.is_empty():
		_toast("背包沒有裝備（裝備回合完成後可三選一）")
	else:
		_open_bag(int(_info_ref))


## 目前資訊卡顯示的是哪一隻自己的棋子（備戰選取或戰鬥中點選我方）；不是自己的棋子回傳 -1
func _info_uid() -> int:
	match _info_mode:
		"unit":
			return int(_info_ref)
		"battle":
			var snap := battle_player.unit_snapshot(int(_info_ref))
			if not snap.is_empty() and int(snap["side"]) == 0:
				return int(snap.get("uid", -1))
	return -1


func _current_items() -> Array:
	match _info_mode:
		"unit":
			var f := run.find_unit(int(_info_ref))
			return RunState.unit_items(f["unit"]) if not f.is_empty() else []
		"battle":
			var uid := _info_uid()
			if uid >= 0 and not run.find_unit(uid).is_empty():
				return RunState.unit_items(run.find_unit(uid)["unit"])
			return battle_player.unit_snapshot(int(_info_ref)).get("items", [])
	return []


func _open_item_overlay(title: String) -> void:
	item_title.text = title
	for c in item_body.get_children():
		item_body.remove_child(c)
		c.queue_free()
	for c in item_buttons.get_children():
		item_buttons.remove_child(c)
		c.queue_free()
	item_overlay.visible = true


func _overlay_button(text: String, cb: Callable, primary: bool = false, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 44)
	UiStyle.style_button(b, Color(0.55, 0.36, 0.08) if primary else Color(0.18, 0.21, 0.28), UiStyle.GOLD if primary else Color(1, 1, 1, 0.15), 15)
	b.disabled = disabled
	b.pressed.connect(cb)
	item_buttons.add_child(b)
	return b


## 已裝備的裝備：顯示資訊；裝上後鎖定，只能用「裝備卸除器」取下回背包
func _show_item_info(id: String, slot: int, editable: bool) -> void:
	_open_item_overlay(str(GameData.item(id).get("name", id)))
	item_body.add_child(_item_card(id, "", Callable()))
	if editable:
		var uid := _info_uid()
		var hint := InfoView.make_rich("[color=#9aa3ad]裝備裝上後會鎖定。使用 1 個%s可取下這件並放回背包（星級與位置不變）。目前持有 %d 個。[/color]" % [GameData.remover_name(), run.removers], 13)
		item_body.add_child(hint)
		_overlay_button("使用卸除器（剩 %d）" % run.removers, func():
			var r := run.use_remover(uid, slot)
			if r == "":
				_toast("已取下 %s，放回背包" % GameData.item(id).get("name", id))
			_report(r)
			item_overlay.visible = false, false, run.removers <= 0)
	_overlay_button("關閉", func(): item_overlay.visible = false, true)


## 背包（右側浮動面板，不擋棋盤）：拖曳裝備到棋子，或點裝備再點棋子
func _show_bag() -> void:
	if bag_box.visible:
		_close_bag()
	else:
		_open_bag(-1)


func _open_bag(target_uid: int) -> void:
	_bag_target_uid = target_uid
	_pending_item = -1
	bag_box.visible = true
	_apply_side_layout()
	_refresh_bag()


func _close_bag() -> void:
	bag_box.visible = false
	detail_box.visible = _info_mode != "none"
	_pending_item = -1
	_bag_target_uid = -1
	_apply_side_layout()


func is_bag_open() -> bool:
	return bag_box.visible


func _refresh_bag() -> void:
	if not bag_box.visible:
		return
	bag_title.text = "背包（%d 件）　卸除器 ×%d" % [run.inventory.size(), run.removers]
	if _bag_target_uid >= 0:
		var f := run.find_unit(_bag_target_uid)
		var nm := str(GameData.unit(str(f["unit"]["id"])).get("name", "")) if not f.is_empty() else ""
		bag_hint.text = "點一件裝備，直接裝到「%s」。" % nm
	elif not _equip_allowed():
		bag_hint.text = "戰鬥中只能查看；備戰時才能裝備。"
	elif _pending_item >= 0:
		bag_hint.text = "已選取：點棋盤或候補區上的棋子即可裝備（再點一次裝備取消）。"
	else:
		bag_hint.text = "把裝備拖到棋子上；或先點裝備、再點棋子。裝上後鎖定，需要卸除器才能取下。"
	for c in bag_list.get_children():
		bag_list.remove_child(c)
		c.queue_free()
	if run.inventory.is_empty():
		var l := Label.new()
		l.text = "目前沒有裝備。完成第 3、6、9、12、15、18、21 回合後可三選一。"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		bag_list.add_child(l)
	for i in run.inventory.size():
		bag_list.add_child(_bag_row(i))


func _bag_row(i: int) -> Button:
	var id := str(run.inventory[i])
	var it := GameData.item(id)
	var col := Color(str(Equipment.type_info(id).get("color", "#fff")))
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 58)
	b.clip_text = true
	var sel := i == _pending_item
	UiStyle.style_button(b, Color(0.45, 0.32, 0.08) if sel else Color(0.13, 0.15, 0.20), UiStyle.GOLD if sel else col.darkened(0.3), 14)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_right = -6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 8)
	var ic := UiIcon.make(str(it.get("type", "weapon")), col, 28)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := Label.new()
	n.text = str(it.get("name", id))
	n.add_theme_font_size_override("font_size", 15)
	n.clip_text = true
	var s := Label.new()
	s.text = Equipment.stat_text(id)
	s.add_theme_font_size_override("font_size", 12)
	s.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	s.clip_text = true
	var u := Label.new()
	u.text = "唯一・" + str(Equipment.unique_of(id).get("name", ""))
	u.add_theme_font_size_override("font_size", 12)
	u.add_theme_color_override("font_color", Color(1.0, 0.83, 0.3))
	u.clip_text = true
	for l in [n, s, u]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	h.add_child(v)
	b.add_child(h)
	b.tooltip_text = "%s\n%s\n%s" % [it.get("name", id), Equipment.stat_text(id), Equipment.unique_line(id)]
	b.button_down.connect(func(): _bag_press(i))
	b.pressed.connect(func(): _bag_click(i))
	b.set_meta("inv_index", i)
	return b


func bag_row_button(i: int) -> Button:
	for c in bag_list.get_children():
		if c is Button and int(c.get_meta("inv_index", -1)) == i:
			return c
	return null


func _bag_press(i: int) -> void:
	_drag_item = i
	_drag_from = get_viewport().get_mouse_position()
	_dragging_item = false
	_drag_consumed = false


## 點一下背包裝備：從空裝備欄打開時直接裝上；否則選取／取消選取，等待點棋子
func _bag_click(i: int) -> void:
	if _drag_consumed:
		_drag_consumed = false
		return
	if not _equip_allowed():
		_toast("戰鬥中不能更換裝備")
		return
	if _bag_target_uid >= 0:
		var target := _bag_target_uid
		if _try_equip(target, i):
			_close_bag()
			board.select(target)
		return
	_pending_item = -1 if _pending_item == i else i
	_refresh_bag()


## 「點裝備再點棋子」：正在選目標時，點到的棋子直接裝備（回傳 true 代表攔截這次點擊）
func _intercept_unit_tap(uid: int) -> bool:
	if _pending_item < 0 or not bag_box.visible or not _equip_allowed():
		return false
	var idx := _pending_item
	_pending_item = -1
	if _try_equip(uid, idx):
		_close_bag()
	else:
		_refresh_bag()
	return true


func _try_equip(uid: int, inv_index: int) -> bool:
	if inv_index < 0 or inv_index >= run.inventory.size():
		return false
	var id := str(run.inventory[inv_index])
	var f := run.find_unit(uid)
	var r := run.equip(uid, inv_index)
	if r != "":
		_toast(r)
		return false
	_toast("%s 裝備了 %s" % [GameData.unit(str(f["unit"]["id"])).get("name", ""), GameData.item(id).get("name", id)], UiStyle.GOLD)
	return true


## 拖曳裝備的過程（_input 中處理，經過其他面板也不會中斷）
func _drag_input(event: InputEvent) -> bool:
	if _drag_item < 0:
		return false
	if event is InputEventMouseMotion:
		if not _dragging_item and event.position.distance_to(_drag_from) > 12.0 and _equip_allowed():
			_dragging_item = true
			_make_ghost(_drag_item)
		if _dragging_item and _ghost:
			_ghost.position = event.position - _ghost.size * 0.5
			var uid := board.unit_at_screen(event.position)
			board.select_hover_unit(uid)
		return _dragging_item
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var was := _dragging_item
		var idx := _drag_item
		_drag_item = -1
		_dragging_item = false
		board.select_hover_unit(-1)
		if _ghost:
			_ghost.queue_free()
			_ghost = null
		if was:
			# 放開位置若剛好還在原本那一列上，按鈕會再發出 pressed：標記略過這一次
			var row := bag_row_button(idx)
			_drag_consumed = row != null and row.get_global_rect().has_point(event.position)
			var uid := board.unit_at_screen(event.position)
			if uid >= 0:
				if _try_equip(uid, idx):
					_close_bag()
					board.select(uid)
			else:
				_toast("把裝備放到棋盤或候補區的棋子上")
			get_viewport().set_input_as_handled()
			return true
	return false


func _make_ghost(i: int) -> void:
	var id := str(run.inventory[i])
	var col := Color(str(Equipment.type_info(id).get("color", "#fff")))
	var p := PanelContainer.new()
	UiStyle.apply_panel(p, Color(0.1, 0.12, 0.16, 0.9), UiStyle.GOLD)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UiIcon.make(str(GameData.item(id).get("type", "weapon")), col, 34))
	p.z_index = 100
	add_child(p)
	p.reset_size()
	_ghost = p


# ---------- 操作 ----------
func _report(reason: String) -> void:
	if reason != "":
		_toast(reason)


func _on_buy(slot: int) -> void:
	if _shop_open():
		_report(run.buy(slot, board.selected_uid()))


func _on_reroll() -> void:
	if _shop_open():
		_report(run.reroll())


func _on_buy_xp() -> void:
	if _shop_open():
		_report(run.buy_xp())


func _on_sell_selected() -> void:
	var uid := board.selected_uid()
	if uid >= 0:
		_sell(uid)


func _sell(uid: int) -> void:
	if not _shop_open():
		return
	if run.is_fighting(uid):
		_toast("戰鬥中的場上棋子不能出售")
		return
	var f := run.find_unit(uid)
	if f.is_empty():
		return
	var value := UnitStats.sell_value(f["unit"]["id"], int(f["unit"]["star"]))
	var n_items := RunState.unit_items(f["unit"]).size()
	if run.sell(uid) == "":
		_toast("出售 %s，+%d 金%s" % [GameData.unit(f["unit"]["id"])["name"], value, "（裝備已回到背包）" if n_items > 0 else ""])
		board.select(-1)


func _cycle_speed() -> void:
	var speeds := [1.0, 2.0, 4.0]
	var i := speeds.find(Session.battle_speed)
	Session.battle_speed = speeds[(i + 1) % speeds.size()]
	_update_speed_label()


func _update_speed_label() -> void:
	speed_btn.text = "%d×" % int(Session.battle_speed)


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
		KEY_ESCAPE:
			if item_overlay.visible:
				item_overlay.visible = false
			elif phase != Phase.BATTLE:
				_show_menu(not menu_overlay.visible)


## 不擋操作的短暫提示（可堆疊）
func _toast(msg: String, color: Color = Color(1, 0.95, 0.75)) -> void:
	var l := Label.new()
	l.text = msg
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(l)
	while toasts.get_child_count() > 4:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func last_toast() -> String:
	var n := toasts.get_child_count()
	return (toasts.get_child(n - 1) as Label).text if n > 0 else ""


func toast_texts() -> Array:
	var out: Array = []
	for c in toasts.get_children():
		out.append((c as Label).text)
	return out


# ---------- 右側詳細資訊 ----------
func _set_info(mode: String, ref: Variant) -> void:
	_info_mode = mode
	_info_ref = ref
	if mode != "none" and bag_box.visible and _pending_item < 0 and _bag_target_uid < 0:
		bag_box.visible = false   # 背包開著時點棋子：改看棋子資訊
	var show := mode != "none"
	if show != detail_box.visible:
		detail_box.visible = show
		_apply_side_layout()
	_refresh_info()


func _close_detail() -> void:
	board.select(-1)
	board.select_battle(-1)
	board.select_enemy_cell(HexGrid.INVALID)
	_set_info("none", null)


func _refresh_info() -> void:
	sell_btn.visible = false
	card.visible = false
	_detail_text.visible = false
	match _info_mode:
		"unit":
			_info_prep_unit(int(_info_ref))
		"enemy":
			_info_enemy(_info_ref)
		"battle":
			_info_battle(int(_info_ref))


func _info_prep_unit(uid: int) -> void:
	var f := run.find_unit(uid)
	if f.is_empty():
		_set_info("none", null)
		return
	var u: Dictionary = f["unit"]
	var id := str(u["id"])
	var items: Array = RunState.unit_items(u)
	var sources: Array = []
	var note := ""
	if f["where"] == "board":
		var lineup := run.board_lineup()
		var ids: Array = []
		var its: Array = []
		for p in lineup:
			ids.append(p["id"])
			its.append(p["items"])
		var all_sources := Modifiers.sources_for_lineup(ids, run.civ_id, true, its)
		for i in lineup.size():
			if int(lineup[i]["uid"]) == uid:
				sources = all_sources[i]
		note = "場上：已含文明、羈絆與裝備"
	else:
		sources = Modifiers.sources_for_lineup([id], "", false, [items])[0]
		note = "候補區：只計裝備（上場後才套用文明與羈絆）"
	if run.is_fighting(uid):
		note += "。戰鬥中：可以穿裝備（立即生效），不能出售或移動"
	detail_title.text = "棋子資訊"
	card.visible = true
	card.show_unit({"ref": "u%d" % uid, "id": id, "star": int(u["star"]), "side": 0, "sources": sources, "items": items, "note": note})
	if _shop_open() and not run.is_fighting(uid):
		sell_btn.visible = true
		sell_btn.text = "出售　+%d 金" % UnitStats.sell_value(id, int(u["star"]))


func _info_enemy(ref: Dictionary) -> void:
	detail_title.text = "敵方資訊"
	card.visible = true
	card.show_unit({"ref": "e%s" % str(ref), "id": str(ref["id"]), "star": int(ref["star"]), "side": 1, "sources": [], "items": [],
		"note": "敵軍沒有文明加成；敵方羈絆預設關閉"})


## 戰鬥中查看：以 cid 讀取戰鬥單位的即時狀態（唯讀，不影響戰鬥）
func _info_battle(cid: int) -> void:
	var snap := battle_player.unit_snapshot(cid)
	if snap.is_empty():
		_set_info("none", null)
		return
	var side := int(snap["side"])
	var sources: Array = []
	if side == 0:
		var lineup := battle_player.player_lineup()
		var ids: Array = []
		var its: Array = []
		for p in lineup:
			ids.append(p["id"])
			its.append(p.get("items", []))
		var all_sources := Modifiers.sources_for_lineup(ids, run.civ_id, true, its)
		for i in lineup.size():
			if int(lineup[i]["cid"]) == cid:
				sources = all_sources[i]
	var tk := battle_player.token(cid)
	var live := {"hp": tk.hp if tk else 0.0, "max_hp": tk.max_hp if tk else 1.0, "shield": tk.shield if tk else 0.0, "mana": tk.mana if tk else 0.0}
	if not battle_player.is_alive(cid):
		live["hp"] = 0.0
	var st_names: Array = []
	for st in battle_player.live_statuses(cid):
		st_names.append("%s %.1f 秒" % [StatBreakdown.STATUS_NAMES.get(st["kind"], st["kind"]), float(st["left"])])
	detail_title.text = "敵方（戰鬥中）" if side == 1 else "我方（戰鬥中）"
	card.visible = true
	card.show_unit({"ref": "c%d" % cid, "id": str(snap["id"]), "star": int(snap["star"]), "side": side, "sources": sources,
		"statuses": battle_player.live_statuses(cid), "live": live, "items": snap.get("items", []),
		"note": ("已陣亡。" if not battle_player.is_alive(cid) else "") + ("狀態：" + "、".join(st_names) if not st_names.is_empty() else "目前沒有增益或負面狀態")})


# ---------- 畫面更新 ----------
func _refresh() -> void:
	_refresh_top()
	_refresh_bottom()
	_refresh_shop()
	_refresh_civ()
	_refresh_traits()
	_refresh_info()


func _refresh_top() -> void:
	round_label.text = "%d/%d" % [run.round_no, GameData.total_rounds()]
	reward_dots.set_state(run.round_no, run.rewards_claimed)


## 底部：金幣｜Lv｜生命｜人口，XP 條（右側顯示升到下一級至少要花的金幣）
func _refresh_bottom() -> void:
	_gold_label.text = str(run.gold)
	var nxt := Economy.next_interest(run.gold)
	_interest_label.text = "+%d" % run.current_interest()
	_interest_label.tooltip_text = "利息 +%d" % run.current_interest() + ("（已達上限）" if nxt.is_empty() else "；再 %d 金 → +%d" % [int(nxt["need"]), int(nxt["next_interest"])])
	_lv_label.text = "Lv.%d" % run.level()
	_hp_label.text = "%d/%d" % [run.hp, Economy.max_hp()]
	_pop_label.text = "%d/%d" % [run.board_count(), run.board_limit()]
	var plan := Economy.xp_plan(run.xp)
	if plan["max"]:
		xp_bar.max_value = 1
		xp_bar.value = 1
		xp_left.text = " Lv.%d" % run.level()
		_xp_cost_label.text = ""
		_xp_coin.visible = false
		_xp_word.text = "MAX"
	else:
		xp_bar.max_value = plan["need"]
		xp_bar.value = plan["cur"]
		xp_left.text = " %d/%d XP" % [plan["cur"], plan["need"]]
		_xp_cost_label.text = str(plan["cost"])
		_xp_coin.visible = true
		_xp_word.text = "升級"
	_btn_text(bag_btn, "背包 %d" % run.inventory.size())


func _refresh_shop() -> void:
	var prep := _shop_open()
	var three := run.three_star_ids()
	for i in _shop_buttons.size():
		var b := _shop_buttons[i]
		var id := str(run.shop[i]) if i < run.shop.size() else ""
		if id == "":
			b.text = "（已招募）"
			b.disabled = true
			UiStyle.style_button(b, Color(0.12, 0.13, 0.17), Color(1, 1, 1, 0.05), 13)
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
		UiStyle.style_button(b, col.darkened(0.62), col, 13)
		b.disabled = not prep or run.can_buy(i) != ""
	var cost_text := "免費 ×%d" % run.free_rerolls if run.free_rerolls > 0 else "刷新 %d" % Economy.reroll_cost()
	_btn_text(reroll_btn, cost_text)
	reroll_btn.disabled = not prep or (run.free_rerolls <= 0 and run.gold < Economy.reroll_cost())
	if run.level() >= Economy.max_level():
		_btn_text(civup_btn, "MAX")
		civup_btn.disabled = true
	else:
		_btn_text(civup_btn, "+%d XP・%d 金" % [Economy.xp_per_buy(), Economy.xp_cost()])
		civup_btn.disabled = not prep or run.gold < Economy.xp_cost()
	_btn_text(lock_btn, "已鎖定" if run.shop_locked else "鎖定", "lock" if run.shop_locked else "unlock")
	lock_btn.disabled = not prep


## 文明列不再常駐顯示 Buff／Debuff（改由浮動說明顯示）
func _refresh_civ() -> void:
	if popover.visible:
		popover_text.text = _pop_text(_pop_key)


## 精簡羈絆清單：[圖示] 目前/下一門檻 名稱；已啟動高亮、未啟動降低對比
func _refresh_traits() -> void:
	for c in trait_list.get_children():
		trait_list.remove_child(c)
		c.queue_free()
	var summary := Synergy.summary(run.synergy_counts())
	if summary.is_empty():
		var l := Label.new()
		l.text = "放棋子上場\n啟動羈絆"
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		trait_list.add_child(l)
	for s in summary:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 34)
		b.clip_text = true
		var active := int(s["tier"]) >= 0
		var g: String = s["group"]
		var k: String = s["key"]
		var key := "%s:%s" % [g, k]
		var col := Color.WHITE if active else Color(0.6, 0.63, 0.7)
		var icon_col := UiStyle.GOLD if active else Color(0.55, 0.58, 0.65)
		if g == "race":
			icon_col = GameData.race_color(k) if active else GameData.race_color(k).darkened(0.35)
		_row_content(b, UiIcon.trait_kind(g, k), icon_col, trait_progress(s), str(s["name"]), col)
		if active:
			UiStyle.style_button(b, Color(0.36, 0.26, 0.07), UiStyle.GOLD, 14)
		else:
			UiStyle.style_button(b, Color(0.12, 0.14, 0.18, 0.9), Color(1, 1, 1, 0.06), 14)
		b.mouse_entered.connect(func(): _hover_pop(key, b, true))
		b.mouse_exited.connect(func(): _hover_pop(key, b, false))
		b.pressed.connect(func(): _press_pop(key, b))
		b.set_meta("pop_key", key)
		trait_list.add_child(b)
	if popover.visible and _pop_key != "civ":
		popover_text.text = _pop_text(_pop_key)


## 羈絆進度文字：目前種數／下一個門檻（已達最高階時顯示目前／最高門檻）
static func trait_progress(s: Dictionary) -> String:
	var th: Array = s["thresholds"]
	var n := int(s["count"])
	for t in th:
		if n < int(t):
			return "%d/%d" % [n, int(t)]
	return "%d/%d" % [n, int(th[th.size() - 1])]


func trait_row(key: String) -> Button:
	if key == "civ":
		return civ_btn
	for c in trait_list.get_children():
		if c is Button and str(c.get_meta("pop_key", "")) == key:
			return c
	return null


# ---------- 羈絆／文明浮動說明 ----------
func _hover_pop(key: String, row: Control, entering: bool) -> void:
	if _pop_pinned:
		return
	if entering:
		_open_pop(key, row, false)
	elif _pop_key == key:
		_close_pop()


func _press_pop(key: String, row: Control) -> void:
	if popover.visible and _pop_key == key and _pop_pinned:
		_close_pop()
		return
	_open_pop(key, row, true)


func _open_pop(key: String, row: Control, pinned: bool) -> void:
	_pop_key = key
	_pop_pinned = pinned
	_pop_anchor_y = row.get_global_rect().position.y
	popover_text.text = _pop_text(key)
	popover.visible = true
	_place_popover()
	_place_popover_deferred()


func _close_pop() -> void:
	popover.visible = false
	_pop_key = ""
	_pop_pinned = false


func is_popover_open() -> bool:
	return popover.visible


func popover_key() -> String:
	return _pop_key if popover.visible else ""


func popover_bbcode() -> String:
	return popover_text.text if popover.visible else ""


func _place_popover_deferred() -> void:
	await get_tree().process_frame
	if popover.visible:
		_place_popover()


## 浮動說明放在羈絆清單右側，貼齊被點的那一列；高度超過可用空間時可捲動
func _place_popover() -> void:
	var r := board_rect()
	var avail := r.size.y - 8.0
	var h := minf(popover_text.get_content_height() + 2.0, avail)
	popover_scroll.custom_minimum_size = Vector2(POPOVER_W, maxf(40.0, h))
	popover.reset_size()
	var x := left_panel.get_global_rect().end.x + 6.0
	var y := clampf(_pop_anchor_y, r.position.y, maxf(r.position.y, r.end.y - popover.size.y))
	popover.position = Vector2(x, y)


func _pop_text(key: String) -> String:
	if key == "civ":
		var c := GameData.civ(run.civ_id)
		var lines: Array = ["[b][color=%s]%s文明[/color][/b]　[color=#9aa3ad]全軍效果（含中立棋子）[/color]" % [UiStyle.hex_color(_civ_color()), c.get("name", "")]]
		for bf in c.get("buffs", []):
			lines.append("[color=%s]▲ %s[/color]" % [COLOR_UP, bf["text"]])
		for df in c.get("debuffs", []):
			lines.append("[color=%s]▼ %s[/color]" % [COLOR_DOWN, df["text"]])
		for u in GameData.units():
			if int(u["cost"]) == 4 and str(u["race"]) == str(c.get("race", run.civ_id)):
				lines.append("[color=#9aa3ad]專屬 4 費：%s[/color]" % u.get("name", ""))
		return "\n".join(lines)
	var parts := key.split(":")
	if parts.size() != 2:
		return ""
	return _trait_text(parts[0], parts[1])


func _trait_text(group: String, key: String) -> String:
	var board_units: Array = []
	for p in run.board_lineup():
		board_units.append({"id": p["id"], "star": p["star"]})
	var bench_units: Array = []
	for b in run.bench:
		if b != null:
			bench_units.append({"id": b["id"], "star": b["star"]})
	var d := Synergy.detail(group, key, board_units, bench_units, run.civ_id)
	var group_name: String = {"race": "種族", "type": "類型", "class": "職業"}[d["group"]]
	var lines: Array = ["[b]%s[/b]　[color=#9aa3ad]%s羈絆[/color]" % [d["name"], group_name]]
	var tier := int(d["tier"])
	lines.append("[color=#ffd24d]已啟動第 %d 階（上場 %d 種）[/color]" % [tier + 1, d["count"]] if tier >= 0 else "[color=#9aa3ad]未啟動（上場 %d 種）[/color]" % d["count"])
	var th: Array = d["thresholds"]
	for i in th.size():
		lines.append("%s[b]%d[/b]　%s[/color]" % ["[color=#ffd24d]" if i == tier else "[color=#9aa3ad]", th[i], d["texts"][i]])
	lines.append("[b]成員[/b] [color=#8a90a0]（只計已上場且不同名稱）[/color]")
	for m in d["members"]:
		var stars := ""
		if not m["stars"].is_empty():
			stars = " " + "、".join(m["stars"].map(func(s): return "★".repeat(int(s))))
		var nm := "[s]%s[/s]" % m["name"] if m["state"] == "unavailable" else str(m["name"])
		lines.append("%s %s %d 費%s" % [STATE_MARK[m["state"]], nm, m["cost"], stars])
	return "\n".join(lines)


func _input(event: InputEvent) -> void:
	if _drag_input(event):
		return
	# 點擊浮動說明與羈絆清單以外的地方：關閉說明（不攔截事件）
	if popover.visible and event is InputEventMouseButton and event.pressed:
		var p: Vector2 = event.position
		if not popover.get_global_rect().has_point(p) and not left_panel.get_global_rect().has_point(p):
			_close_pop()


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
	var rep := run.settle(_last_result)
	if run.finished:
		SaveSystem.clear()
	else:
		SaveSystem.save_run(run)
	_toast_report(rep)
	phase = Phase.AFTER
	_after_time = 0.3
	_refresh()
