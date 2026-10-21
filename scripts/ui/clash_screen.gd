extends "res://scripts/ui/game_screen.gd"
## 《氏族爭霸》對局畫面：沿用單人模式的棋盤、商店、候補、背包、資訊卡與戰鬥播放（GameScreen），
## 另外加上：十人生命／名次列表（可收合）、本回合對手或隊友、PvE 交易畫面、隊友戰況與援軍狀態、
## 國家制度與政策選擇、淘汰／觀戰／最終勝利畫面。規則全部交給 ClashMatch（本地權威對局管理器）。
## 階段對應：PREP＝備戰、REWARD（沿用列舉值）＝PvE 交易、BATTLE＝戰鬥、AFTER＝戰後提示。

const PLAYERS_W := 214.0

var m: ClashMatch
var me: ClashPlayer

var players_panel: PanelContainer
var players_list: VBoxContainer
var players_toggle: Button
var _players_open := true

var trade_overlay: Control
var trade_title: Label
var trade_timer_label: Label
var trade_mine: RichTextLabel
var trade_theirs: RichTextLabel
var trade_status: Label
var trade_choices: VBoxContainer
var trade_confirm_btn: Button
var trade_end_btn: Button
var _trade_left := 0.0
var _trade_version := -1
var _ai_reply_at := -1.0
var _trade_clock := 0.0

var gov_overlay: Control
var gov_title: Label
var gov_cards: HBoxContainer
var gov_hint: Label
var gov_reopen: Button

var coop_panel: PanelContainer
var coop_label: RichTextLabel

var end_overlay: Control
var end_title: Label
var end_body: RichTextLabel
var end_buttons: HBoxContainer
var _end_shown_for := ""

var core_btn: Button
## 真人已淘汰或對局結束：不再有自己的備戰／交易／戰鬥流程（只剩結算畫面或觀戰）
var _ended := false
var _spectating := false
var _spec_left := 0.0
var _spec_fast := false


func _ready() -> void:
	m = Session.clash
	if m == null:
		# 直接在編輯器執行此場景時，自動建立一局測試對局
		Session.new_clash("玩家001", "測試共和國", "normal", 20261022)
		m = Session.clash
	me = m.human()
	Session.run = me.run
	_build_clash_ui()
	board.enemy_preview_provider = _preview_units
	super._ready()
	debug_btn.visible = false
	leader.set_collapsed(true)
	reward_dots.visible = false
	m.changed.connect(_on_match_changed)
	_apply_side_layout()
	_layout()


# ---------- 建立介面 ----------
func _overlay_index() -> int:
	return get_node("ItemOverlay").get_index()


func _build_clash_ui() -> void:
	# 十人列表（右上，可收合；浮在戰場上，不影響棋盤大小）
	players_panel = PanelContainer.new()
	players_panel.name = "PlayersPanel"
	UiStyle.apply_panel(players_panel, Color(0.08, 0.10, 0.14, 0.9))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	players_panel.add_child(pv)
	players_toggle = Button.new()
	players_toggle.name = "Toggle"
	players_toggle.text = "十人排名 ▼"
	players_toggle.custom_minimum_size = Vector2(0, 30)
	UiStyle.style_button(players_toggle, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 13)
	players_toggle.pressed.connect(func():
		_players_open = not _players_open
		_refresh_players())
	pv.add_child(players_toggle)
	players_list = VBoxContainer.new()
	players_list.name = "List"
	players_list.add_theme_constant_override("separation", 1)
	pv.add_child(players_list)
	add_child(players_panel)
	move_child(players_panel, _overlay_index())

	# 合作 PvE：隊友戰況
	coop_panel = PanelContainer.new()
	coop_panel.name = "CoopPanel"
	coop_panel.visible = false
	coop_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_panel(coop_panel, Color(0.06, 0.12, 0.14, 0.9), Color(0.45, 0.9, 1.0, 0.6))
	coop_label = InfoView.make_rich("", 13)
	coop_label.custom_minimum_size = Vector2(380, 0)
	coop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coop_panel.add_child(coop_label)
	add_child(coop_panel)
	move_child(coop_panel, _overlay_index())

	_build_trade_overlay()
	_build_gov_overlay()
	_build_end_overlay()

	# 朕即是國家：在棋子資訊卡上指定核心
	core_btn = Button.new()
	core_btn.name = "CoreButton"
	core_btn.text = "指定為核心（朕即是國家）"
	core_btn.custom_minimum_size = Vector2(0, 40)
	core_btn.visible = false
	UiStyle.style_button(core_btn, Color(0.45, 0.32, 0.06), UiStyle.GOLD, 14)
	core_btn.pressed.connect(func():
		var uid := _info_uid()
		var r := m.submit(me.index, {"type": "core", "uid": uid})
		if r == "":
			_toast("已指定核心：%s" % GameData.unit(str(me.run.find_unit(uid)["unit"]["id"])).get("name", ""), UiStyle.GOLD)
			_mark_core_tokens()
		else:
			_toast(r)
		_refresh_info())
	sell_btn.get_parent().add_child(core_btn)
	sell_btn.get_parent().move_child(core_btn, sell_btn.get_index())


func _panel_vbox(parent: Control, width: float, border: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(width, 0)
	UiStyle.apply_panel(panel, Color(0.10, 0.12, 0.17, 0.98), border)
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.name = "VBox"
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	return v


func _full_rect_layer(node_name: String) -> Control:
	var c := CenterContainer.new()
	c.name = node_name
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	add_child(c)
	move_child(c, _overlay_index())
	return c


func _build_trade_overlay() -> void:
	trade_overlay = _full_rect_layer("TradeOverlay")
	var v := _panel_vbox(trade_overlay, 760, Color(0.45, 0.9, 1.0))
	var head := HBoxContainer.new()
	trade_title = Label.new()
	trade_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_title.add_theme_font_size_override("font_size", 19)
	trade_title.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	head.add_child(trade_title)
	trade_timer_label = Label.new()
	trade_timer_label.name = "TradeTimer"
	trade_timer_label.add_theme_font_size_override("font_size", 19)
	head.add_child(trade_timer_label)
	v.add_child(head)
	var hint := Label.new()
	hint.text = "每人最多提出一項（棋子或背包裡的裝備）。雙方都確認才交換；任一方變更提案，雙方確認都會清除。棋子身上的裝備會退回原主背包，只交換棋子本體。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	v.add_child(hint)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lt := Label.new()
	lt.text = "我的提案"
	lt.add_theme_color_override("font_color", UiStyle.GOLD)
	left.add_child(lt)
	trade_mine = InfoView.make_rich("", 14)
	trade_mine.name = "Mine"
	trade_mine.custom_minimum_size = Vector2(0, 70)
	left.add_child(trade_mine)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 170)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	trade_choices = VBoxContainer.new()
	trade_choices.name = "Choices"
	trade_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_choices.add_theme_constant_override("separation", 3)
	sc.add_child(trade_choices)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rt := Label.new()
	rt.text = "隊友的提案"
	rt.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	right.add_child(rt)
	trade_theirs = InfoView.make_rich("", 14)
	trade_theirs.name = "Theirs"
	trade_theirs.custom_minimum_size = Vector2(0, 70)
	right.add_child(trade_theirs)
	trade_status = Label.new()
	trade_status.name = "Status"
	trade_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trade_status.add_theme_font_size_override("font_size", 15)
	right.add_child(trade_status)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	v.add_child(btns)
	trade_confirm_btn = Button.new()
	trade_confirm_btn.name = "ConfirmTrade"
	trade_confirm_btn.custom_minimum_size = Vector2(0, 46)
	trade_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_confirm_btn.pressed.connect(_on_trade_confirm)
	btns.add_child(trade_confirm_btn)
	trade_end_btn = Button.new()
	trade_end_btn.name = "EndTrade"
	trade_end_btn.text = "不交易，直接開戰"
	trade_end_btn.custom_minimum_size = Vector2(200, 46)
	UiStyle.style_button(trade_end_btn, Color(0.18, 0.21, 0.28))
	trade_end_btn.pressed.connect(_end_trade)
	btns.add_child(trade_end_btn)


func _build_gov_overlay() -> void:
	gov_overlay = _full_rect_layer("GovOverlay")
	var v := _panel_vbox(gov_overlay, 820, UiStyle.GOLD)
	gov_title = Label.new()
	gov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gov_title.add_theme_font_size_override("font_size", 21)
	gov_title.add_theme_color_override("font_color", UiStyle.GOLD)
	v.add_child(gov_title)
	gov_cards = HBoxContainer.new()
	gov_cards.name = "Cards"
	gov_cards.add_theme_constant_override("separation", 10)
	v.add_child(gov_cards)
	gov_hint = Label.new()
	gov_hint.name = "Hint"
	gov_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gov_hint.add_theme_font_size_override("font_size", 13)
	v.add_child(gov_hint)
	var later := Button.new()
	later.name = "Later"
	later.text = "先收起（稍後再選）"
	later.custom_minimum_size = Vector2(0, 38)
	UiStyle.style_button(later, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 14)
	later.pressed.connect(func(): gov_overlay.visible = false)
	v.add_child(later)
	gov_reopen = Button.new()
	gov_reopen.name = "GovReopen"
	gov_reopen.visible = false
	gov_reopen.custom_minimum_size = Vector2(240, 40)
	UiStyle.style_button(gov_reopen, Color(0.55, 0.36, 0.08), UiStyle.GOLD, 15)
	gov_reopen.pressed.connect(_show_gov)
	add_child(gov_reopen)
	move_child(gov_reopen, _overlay_index())


func _build_end_overlay() -> void:
	end_overlay = _full_rect_layer("EndOverlay")
	end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := _panel_vbox(end_overlay, 640, UiStyle.GOLD)
	end_title = Label.new()
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", 28)
	end_title.add_theme_color_override("font_color", UiStyle.GOLD)
	v.add_child(end_title)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 330)
	v.add_child(sc)
	end_body = InfoView.make_rich("", 14)
	end_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(end_body)
	end_buttons = HBoxContainer.new()
	end_buttons.add_theme_constant_override("separation", 10)
	v.add_child(end_buttons)


# ---------- 覆寫：文明列 → 國家 ----------
func _civ_icon() -> String:
	match me.government if me != null else "":
		"democracy":
			return "coin"
		"empire":
			return "civ_human"
		"commune":
			return "people"
	return "civ"


func _civ_color() -> Color:
	match me.government if me != null else "":
		"democracy":
			return Color(0.45, 0.7, 1.0)
		"empire":
			return Color(1.0, 0.78, 0.3)
		"commune":
			return Color(1.0, 0.45, 0.4)
	return Color(0.75, 0.75, 0.8)


func _civ_row_text() -> String:
	var g := me.government_name()
	return "%s%s" % [me.country, ("・" + g) if g != "" else ""]


func _build_civ_row() -> void:
	civ_btn.text = ""
	_row_content(civ_btn, _civ_icon(), _civ_color(), "", _civ_row_text(), Color.WHITE)
	civ_btn.mouse_entered.connect(func(): _hover_pop("civ", civ_btn, true))
	civ_btn.mouse_exited.connect(func(): _hover_pop("civ", civ_btn, false))
	civ_btn.pressed.connect(func(): _press_pop("civ", civ_btn))


func _refresh_civ() -> void:
	_row_content(civ_btn, _civ_icon(), _civ_color(), "", _civ_row_text(), Color.WHITE)
	UiStyle.style_button(civ_btn, _civ_color().darkened(0.6), _civ_color(), 15)
	if popover.visible:
		popover_text.text = _pop_text(_pop_key)


func _pop_text(key: String) -> String:
	if key != "civ":
		return super._pop_text(key)
	var lines: Array = ["[b][color=#ffd24d]%s[/color][/b]　[color=#9aa3ad]統治者：%s[/color]" % [me.country, me.player_name]]
	lines.append("生命 %d・Lv.%d・目前第 %d 名" % [maxi(0, me.hp), me.run.level(), m.current_rank(me.index)])
	lines.append("")
	lines.append(ClashGovernment.summary(me).replace("\n", "\n"))
	lines.append("")
	lines.append("[color=#9aa3ad]沒有開局的氏族 Buff／Debuff；所有玩家都能購買六大氏族的棋子。第 %d 回合選擇國家制度，第 %d 回合選擇深化政策。[/color]" % [ClashGovernment.system_round(), ClashGovernment.policy_round()])
	return "\n".join(lines)


func _lineup_sources(lineup: Array, ids: Array, its: Array) -> Array:
	return ClashBattle.lineup_sources(me, lineup)


func _board_note() -> String:
	return "場上：已含羈絆、裝備與國家制度"


func _info_enemy(ref: Dictionary) -> void:
	detail_title.text = "對手／敵軍資訊"
	card.visible = true
	card.show_unit({"ref": "e%s" % str(ref), "id": str(ref["id"]), "star": int(ref["star"]), "side": 1, "sources": [], "items": [],
		"note": "備戰預覽：只顯示基礎數值；開戰後可點選查看即時狀態"})


func _refresh_info() -> void:
	super._refresh_info()
	if core_btn == null:
		return
	var uid := _info_uid()
	core_btn.visible = me.policy == "i_am_the_state" and uid >= 0 and phase == Phase.PREP and uid != me.core_uid


# ---------- 覆寫：上方與底部 ----------
func _refresh_top() -> void:
	round_label.text = "第 %d 回合" % m.round_no
	reward_dots.visible = false


func _refresh_bottom() -> void:
	super._refresh_bottom()
	_hp_label.text = str(maxi(0, me.hp))
	var it := ClashGovernment.interest(me, run.gold)
	_interest_label.text = "+%d" % it
	_interest_label.tooltip_text = "利息 +%d（上限 %d）" % [it, ClashGovernment.interest_max(me)]


func _stage_text() -> String:
	var a := m.assignment(me.index)
	var kind := str(a.get("kind", ""))
	var other := int(a.get("other", -1))
	match kind:
		"pvp":
			return "PvP 對手：%s" % _who(other)
		"ghost":
			return "幽靈戰：對抗 %s 的陣容鏡像" % _who(other)
		"coop":
			return "合作 PvE（%s）隊友：%s" % [_pve_name(), _who(other)]
		"solo":
			return "單人 PvE（%s）" % _pve_name()
	return "觀戰中" if not me.alive else ""


func _who(seat: int) -> String:
	if seat < 0:
		return "—"
	var p: ClashPlayer = m.players[seat]
	return "%s（%s・生命 %d）" % [p.country, p.player_name, maxi(0, p.hp)]


func _pve_name() -> String:
	var st := ClashBattle.pve_stage(m.pve_count)
	return str(GameData.stage(int(st["round"])).get("name", "PvE"))


## 備戰時棋盤上方的預覽：PvP＝對手目前的陣容（翻轉）；PvE＝本次 PvE 敵軍
func _preview_units(_r: RunState) -> Array:
	if m == null or not me.alive:
		return []
	var a := m.assignment(me.index)
	var out: Array = []
	match str(a.get("kind", "")):
		"pvp", "ghost":
			var other := int(a.get("other", -1))
			if other >= 0:
				for u in (m.players[other] as ClashPlayer).run.board_lineup():
					out.append({"id": u["id"], "star": u["star"], "cell": ClashBattle.mirror_cell(u["cell"])})
		"coop", "solo":
			out = BattleSetup.stage_units(int(ClashBattle.pve_stage(m.pve_count)["round"]))
	return out


# ---------- 覆寫：階段流程 ----------
func _enter_prep() -> void:
	if not me.alive or m.finished:
		_show_end()
		return
	phase = Phase.PREP
	battle_player.clear()
	board.battle_mode = false
	board.interactive = true
	board.set_prep_visible(true)
	board.show_prep(run)
	speed_btn.visible = false
	skip_btn.visible = false
	menu_btn.visible = true
	coop_panel.visible = false
	trade_overlay.visible = false
	_set_info("none", null)
	_refresh()
	_refresh_players()
	prep_timer.duration = ClashMatch.prep_seconds(m.round_no)
	prep_timer.start()
	if Session.prep_time_round == m.round_no and Session.prep_time_left > 0.0:
		prep_timer.remaining = Session.prep_time_left
	Session.prep_time_round = -1
	_last_seconds = -1
	_update_bar()
	_mark_core_tokens()
	var a := m.assignment(me.index)
	_toast("第 %d 回合：%s" % [m.round_no, _stage_text()], Color(0.85, 0.9, 1.0))
	if ClashGovernment.pending_choice(me, m.round_no) != "":
		_show_gov()
	else:
		gov_overlay.visible = false
		gov_reopen.visible = false


func _process(delta: float) -> void:
	if _players_dirty:
		_players_dirty = false
		_refresh_players()
		_refresh_civ()
	if _spectating:
		_spec_process(delta)
		return
	if _ended:
		return
	match phase:
		Phase.PREP:
			prep_timer.paused = menu_overlay.visible or abandon_confirm.visible
			if prep_timer.tick(delta):
				_on_start_battle(true)
				return
			_update_bar()
			_update_gov_countdown()
		Phase.REWARD:
			_trade_process(delta)
		Phase.BATTLE:
			_update_bar()
			_update_coop_panel()
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
				_after_done()


func _update_bar() -> void:
	if phase == Phase.REWARD:
		bar.max_value = ClashMatch.trade_seconds()
		bar.value = _trade_left
		_set_bar_color(Color(0.3, 0.75, 0.85))
		bar_left.text = " 交易階段・" + _stage_text()
		bar_right.text = "%d 秒" % int(ceil(_trade_left))
		return
	super._update_bar()


func _on_run_changed() -> void:
	board.sync_prep()
	_mark_core_tokens()
	_refresh_bag()
	if phase == Phase.PREP:
		_refresh()
	else:
		_refresh_bottom()
		_refresh_shop()
		_refresh_info()
	if trade_overlay != null and trade_overlay.visible:
		_refresh_trade()


## 對局狀態改變（AI 行動也會觸發，一回合可能上百次）：標記待更新，每幀最多重建一次列表
var _players_dirty := false


func _on_match_changed() -> void:
	_players_dirty = true


func _on_start_battle(_auto: bool) -> void:
	if phase != Phase.PREP:
		return
	board.cancel_drag()
	_pending_item = -1
	_bag_target_uid = -1
	_refresh_bag()
	prep_timer.stop()
	big_countdown.visible = false
	gov_overlay.visible = false
	gov_reopen.visible = false
	_close_bag()
	item_overlay.visible = false
	var placed_before := run.board_count()
	var next := m.lock_in()
	for note in m.gov_auto_notes:
		_toast(note, UiStyle.GOLD)
	if run.board_count() > placed_before:
		_toast("人口未滿：已從候補區自動補上 %d 隻" % (run.board_count() - placed_before))
	board.sync_prep()
	if next == "trade":
		_enter_trade()
	else:
		_begin_battle_view()


# ---------- 交易 ----------
func _enter_trade() -> void:
	var t := m.trade_for(me.index)
	if t.is_empty():
		# 自己落單（單人 PvE）：其他組的 AI 交易已談完，直接開戰
		m.end_trades()
		_begin_battle_view()
		return
	phase = Phase.REWARD
	_trade_left = ClashMatch.trade_seconds()
	_trade_clock = 0.0
	_ai_reply_at = 0.6   # 隊友（AI）看到提案後的反應時間
	board.interactive = true
	board.select(-1)
	_set_bar_neutral()
	trade_overlay.visible = true
	var other: ClashPlayer = m.players[ClashTrade.partner(t, me.index)]
	trade_title.text = "合作 PvE 交易：隊友 %s（%s）" % [other.country, other.player_name]
	_trade_version = -1
	_refresh_trade()
	_refresh()


func _trade_process(delta: float) -> void:
	if not menu_overlay.visible:
		_trade_left = maxf(0.0, _trade_left - delta)
		_trade_clock += delta
	var t := m.trade_for(me.index)
	if _ai_reply_at >= 0.0 and _trade_clock >= _ai_reply_at and not t.is_empty() and str(t["status"]) == "open":
		_ai_reply_at = -1.0
		var other := ClashTrade.partner(t, me.index)
		ClashAI.respond_trade(m, t, other)
		_refresh_trade()
		if str(t["status"]) == "done":
			_toast("交易完成！", Color(0.6, 0.95, 1.0))
	trade_timer_label.text = "%d 秒" % int(ceil(_trade_left))
	trade_timer_label.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if _trade_left <= 5.0 else Color.WHITE)
	_update_bar()
	if _trade_left <= 0.0 or m.human_trade_done():
		if not t.is_empty() and str(t["status"]) == "open":
			_toast("時間到，交易取消")
		_end_trade()


func _refresh_trade() -> void:
	var t := m.trade_for(me.index)
	if t.is_empty():
		return
	var other := ClashTrade.partner(t, me.index)
	trade_mine.text = _offer_text(m, me.index, t["offer"][me.index])
	trade_theirs.text = _offer_text(m, other, t["offer"][other])
	var mine_ok := bool(t["confirm"][me.index])
	var theirs_ok := bool(t["confirm"][other])
	var st := str(t["status"])
	if st == "done":
		trade_status.text = "✓ 交易已完成"
	elif st == "cancelled":
		trade_status.text = "交易已取消"
	else:
		trade_status.text = "我：%s　隊友：%s%s" % ["已確認 ✓" if mine_ok else "未確認", "已確認 ✓" if theirs_ok else "未確認",
			("\n" + str(t["note"])) if str(t["note"]) != "" else ""]
	trade_confirm_btn.text = "取消確認" if mine_ok else "確認交易"
	UiStyle.style_button(trade_confirm_btn, Color(0.18, 0.4, 0.45) if not mine_ok else Color(0.3, 0.3, 0.3), Color(0.5, 0.95, 1.0), 17)
	trade_confirm_btn.disabled = st != "open"
	if _trade_version == int(t["version"]) and trade_choices.get_child_count() > 0:
		return
	_trade_version = int(t["version"])
	for c in trade_choices.get_children():
		trade_choices.remove_child(c)
		c.queue_free()
	var none := _choice_button("不提出任何東西", {}, (t["offer"][me.index] as Dictionary).is_empty())
	trade_choices.add_child(none)
	for u in run.all_units():
		var uid := int(u["uid"])
		var where := str(run.find_unit(uid).get("where", ""))
		var label := "%s %s（%s・%s）%s" % [GameData.unit(str(u["id"]))["name"], "★".repeat(int(u["star"])),
			GameData.class_name_of(str(GameData.unit(str(u["id"]))["class"])), GameData.race_name(str(GameData.unit(str(u["id"]))["race"])), "　場上" if where == "board" else ""]
		var cur: Dictionary = t["offer"][me.index]
		var sel := not cur.is_empty() and str(cur["kind"]) == "unit" and int(cur["uid"]) == uid
		trade_choices.add_child(_choice_button(label, {"kind": "unit", "uid": uid}, sel))
	for i in run.inventory.size():
		var id := str(run.inventory[i])
		var cur: Dictionary = t["offer"][me.index]
		var sel := not cur.is_empty() and str(cur["kind"]) == "item" and int(cur["inv"]) == i
		trade_choices.add_child(_choice_button("裝備：%s（%s）" % [GameData.item(id).get("name", id), Equipment.stat_text(id)], {"kind": "item", "inv": i}, sel))


func _choice_button(text: String, offer: Dictionary, selected: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 32)
	b.clip_text = true
	UiStyle.style_button(b, Color(0.35, 0.28, 0.08) if selected else Color(0.14, 0.16, 0.21), UiStyle.GOLD if selected else Color(1, 1, 1, 0.1), 13)
	b.pressed.connect(func():
		var r := m.submit(me.index, {"type": "trade_offer", "offer": offer})
		if r != "":
			_toast(r)
		_ai_reply_at = _trade_clock + 0.8
		_trade_version = -1
		_refresh_trade())
	return b


static func _offer_text(match_: ClashMatch, seat: int, offer: Dictionary) -> String:
	var info := ClashTrade.offer_info(match_, seat, offer)
	if info.is_empty():
		return "[color=#9aa3ad]（尚未提出）[/color]"
	if str(info["kind"]) == "unit":
		var u := GameData.unit(str(info["id"]))
		return "[b]%s[/b] %s\n%s・%s・%s・%d 費" % [u["name"], "★".repeat(int(info["star"])), GameData.class_name_of(str(u["class"])),
			GameData.race_name(str(u["race"])), GameData.type_name(str(u["type"])), int(u["cost"])]
	var id := str(info["id"])
	var uq := Equipment.unique_of(id)
	return "[b]%s[/b]\n%s%s" % [GameData.item(id).get("name", id), Equipment.stat_text(id), ("\n唯一・%s：%s" % [uq.get("name", ""), uq.get("desc", "")]) if not uq.is_empty() else ""]


func _on_trade_confirm() -> void:
	var t := m.trade_for(me.index)
	if t.is_empty():
		return
	var r := m.submit(me.index, {"type": "trade_confirm", "value": not bool(t["confirm"][me.index])})
	if r != "":
		_toast(r)
	if str(t["status"]) == "done":
		_toast("交易完成！", Color(0.6, 0.95, 1.0))
	else:
		_ai_reply_at = _trade_clock + 0.6
	_refresh_trade()


func _end_trade() -> void:
	if phase != Phase.REWARD:
		return
	trade_overlay.visible = false
	m.end_trades()
	_begin_battle_view()


# ---------- 戰鬥 ----------
func _begin_battle_view() -> void:
	phase = Phase.BATTLE
	_set_bar_neutral()
	board.select(-1)
	board.interactive = false
	_last_result = {}
	if m.stage != "battle":
		m.start_battles()
	m.run_battles(true)   # 其他玩家的戰鬥直接算完；自己的那場依畫面播放
	var hb := m.human_battle()
	board.set_prep_visible(false)
	board.battle_mode = true
	battle_player.play_live(hb.sim_for(me.index), board, hb)
	_mark_core_tokens()
	leader.set_stats(battle_player.live_stats())
	speed_btn.visible = true
	skip_btn.visible = true
	menu_btn.visible = false
	_update_speed_label()
	_set_info("none", null)
	coop_panel.visible = hb.kind == "coop"
	_update_coop_panel()
	_refresh()
	_toast("開戰！" + _stage_text())


func _update_coop_panel() -> void:
	var hb := m.human_battle()
	if hb == null or hb.kind != "coop":
		coop_panel.visible = false
		return
	var st := hb.coop_status(me.index)
	var mate: ClashPlayer = m.players[hb.b if hb.a == me.index else hb.a]
	var names := {"fighting": "戰鬥中", "cleared": "已清場", "marching": "已清場，援軍行軍中→", "arrived": "援軍已抵達對方戰場",
		"wiped": "全滅，等待救援", "failed": "失敗"}
	var me_s: Dictionary = st["me"]
	var mate_s: Dictionary = st["mate"]
	var lines: Array = []
	lines.append("[b]我方戰場[/b]　存活 %d／敵 %d" % [me_s["allies"], me_s["enemies"]])
	lines.append("[color=#ffd24d]%s[/color]%s" % [names.get(str(me_s["state"]), ""), "　[color=#7fe0ff]隊友援軍即將抵達！[/color]" if bool(st["incoming"]) else ""])
	lines.append("[b]隊友 %s[/b]" % mate.country)
	lines.append("存活 %d／敵 %d　[color=#ffd24d]%s[/color]" % [mate_s["allies"], mate_s["enemies"], names.get(str(mate_s["state"]), "")])
	coop_label.text = "\n".join(lines)
	coop_panel.visible = true
	_place_players()


func _on_battle_finished() -> void:
	if phase != Phase.BATTLE:
		return
	if not m.all_battles_finished():
		m.run_battles(false)
	var hb := m.human_battle()
	if hb != null:
		_last_result = hb.sim_for(me.index).result()
		leader.set_stats(_last_result.get("stats", []))
	var rep := m.settle_round()
	_toast_clash_report(rep)
	board.battle_mode = false
	skip_btn.visible = false
	coop_panel.visible = false
	phase = Phase.AFTER
	_after_time = 2.2
	_refresh()
	_refresh_players()


func _toast_clash_report(rep: Dictionary) -> void:
	var ps: Dictionary = rep["per_seat"].get(me.index, {})
	if ps.is_empty():
		return
	var d := int(ps.get("damage", 0))
	if rep["kind"] == "pvp":
		if bool(ps.get("won", false)):
			_toast("勝利！", Color(0.55, 0.95, 0.6))
		else:
			_toast("落敗：生命 −%d（剩 %d）" % [d, maxi(0, me.hp)] if d > 0 else "平手", Color(1, 0.6, 0.55))
	else:
		var ok = ps.get("pve", null)
		if ok == true:
			_toast("PvE 成功！雙方都不扣血", Color(0.55, 0.95, 0.6))
			for rw in ps.get("rewards", []):
				_toast("獲得：%s" % rw, UiStyle.GOLD)
		elif ok == false:
			_toast("PvE 失敗：生命 −%d（剩 %d）" % [d, maxi(0, me.hp)], Color(1, 0.6, 0.55))
	if int(ps.get("income", 0)) > 0:
		_toast("+%d 金" % int(ps["income"]), UiStyle.GOLD)
	for note in ps.get("notes", []):
		_toast(str(note), Color(1.0, 0.75, 0.75))
	for s in rep["eliminated"]:
		var p: ClashPlayer = m.players[s]
		_toast("%s 遭到淘汰（第 %d 名）" % [p.country, p.placement], Color(1, 0.5, 0.5))


func _after_done() -> void:
	if m.finished or not me.alive:
		_show_end()
		return
	m.begin_round()
	_enter_prep()


# ---------- 國家制度 ----------
func _show_gov() -> void:
	var pend := ClashGovernment.pending_choice(me, m.round_no)
	if pend == "" or phase != Phase.PREP:
		gov_overlay.visible = false
		gov_reopen.visible = false
		return
	for c in gov_cards.get_children():
		gov_cards.remove_child(c)
		c.queue_free()
	if pend == "system":
		gov_title.text = "第 %d 回合：選擇國家制度" % m.round_no
		for sys in ClashGovernment.systems():
			var sc := ClashGovernment.system_cfg(sys)
			var pol_lines: Array = []
			for pol in ClashGovernment.policies_for(sys):
				var pc := ClashGovernment.policy_cfg(pol)
				pol_lines.append("・%s「%s」" % [pc.get("name", ""), pc.get("slogan", "")])
			var body := "[color=#9aa3ad]%s[/color]\n[color=#5aa9ff]%s[/color]\n[color=#9aa3ad]第 %d 回合可深化：[/color]\n%s" % [sc.get("role", ""), sc.get("base_text", ""), ClashGovernment.policy_round(), "\n".join(pol_lines)]
			gov_cards.add_child(_gov_card(str(sc.get("name", sys)), body, func(): _pick_gov("government", sys)))
	else:
		gov_title.text = "第 %d 回合：%s的深化政策" % [m.round_no, me.government_name()]
		for pol in ClashGovernment.policies_for(me.government):
			var pc := ClashGovernment.policy_cfg(pol)
			var body := "[i]「%s」[/i]\n[color=#5aa9ff]%s[/color]" % [pc.get("slogan", ""), pc.get("text", "")]
			gov_cards.add_child(_gov_card(str(pc.get("name", pol)), body, func(): _pick_gov("policy", pol)))
	gov_overlay.visible = true
	gov_reopen.visible = false
	_update_gov_countdown()


func _gov_card(title: String, body: String, cb: Callable) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.apply_panel(p, Color(0.12, 0.14, 0.19), Color(1.0, 0.82, 0.3, 0.6))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 19)
	t.add_theme_color_override("font_color", UiStyle.GOLD)
	v.add_child(t)
	var r := InfoView.make_rich(body, 13)
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(r)
	var b := Button.new()
	b.text = "選擇"
	b.custom_minimum_size = Vector2(0, 40)
	UiStyle.style_button(b, Color(0.55, 0.36, 0.08), UiStyle.GOLD, 16)
	b.pressed.connect(cb)
	v.add_child(b)
	return p


func _pick_gov(kind: String, value: String) -> void:
	var r := m.submit(me.index, {"type": kind, "value": value})
	if r != "":
		_toast(r)
		return
	_toast("%s：%s" % ["國家制度" if kind == "government" else "深化政策", me.government_name() if kind == "government" else me.policy_name()], UiStyle.GOLD)
	gov_overlay.visible = false
	gov_reopen.visible = false
	_refresh()
	_mark_core_tokens()
	if ClashGovernment.pending_choice(me, m.round_no) != "":
		_show_gov()


func _update_gov_countdown() -> void:
	var pend := ClashGovernment.pending_choice(me, m.round_no)
	if pend == "":
		gov_overlay.visible = false
		gov_reopen.visible = false
		return
	var secs := prep_timer.seconds_left()
	var warn := secs <= 5
	gov_hint.text = ("剩 %d 秒！時間到會隨機決定" if warn else "倒數不暫停・剩 %d 秒（時間到會隨機決定）") % secs
	gov_hint.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if warn else UiStyle.TEXT_DIM)
	gov_reopen.visible = not gov_overlay.visible
	if gov_reopen.visible:
		gov_reopen.text = "選擇%s（剩 %d 秒）" % ["國家制度" if pend == "system" else "深化政策", secs]
		gov_reopen.size = gov_reopen.get_combined_minimum_size()
		var r := board_rect()
		gov_reopen.position = Vector2(r.get_center().x - gov_reopen.size.x * 0.5, r.position.y + 4.0)


func _mark_core_tokens() -> void:
	var core := me.core_uid if me.policy == "i_am_the_state" else -1
	for uid in board._prep_tokens.keys():
		(board._prep_tokens[uid] as UnitToken).is_core = int(uid) == core
	if board.battle_mode:
		for snap in battle_player.player_lineup():
			var tk := battle_player.token(int(snap["cid"]))
			if tk:
				tk.is_core = int(snap.get("uid", -1)) == core and core >= 0


# ---------- 十人列表 ----------
func _refresh_players() -> void:
	if players_list == null:
		return
	players_toggle.text = "十人排名 %s（存活 %d）" % ["▼" if _players_open else "▶", m.alive_count()]
	for c in players_list.get_children():
		players_list.remove_child(c)
		c.queue_free()
	players_list.visible = _players_open
	if not _players_open:
		_place_players()
		return
	var a := m.assignment(me.index)
	var st := m.standings()
	for i in st.size():
		var p: ClashPlayer = st[i]
		players_list.add_child(_player_row(p, i + 1, a))
	_place_players()


## 一列：名次｜國家（＋對手／隊友標記）與生命條｜生命。統治者、等級、制度放在滑鼠提示，保持精簡不擋棋盤。
func _player_row(p: ClashPlayer, rank: int, a: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.name = "Row%d" % p.index
	var tag := ""
	var border := Color(1, 1, 1, 0.0)
	if p.index == me.index:
		border = UiStyle.GOLD
	elif p.alive and int(a.get("other", -1)) == p.index:
		tag = {"pvp": "對手", "ghost": "鏡像", "coop": "隊友"}.get(str(a.get("kind", "")), "")
		border = Color(1.0, 0.45, 0.4) if tag != "隊友" else Color(0.45, 0.9, 1.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.19, 0.95) if p.alive else Color(0.08, 0.08, 0.1, 0.9)
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	row.add_theme_stylebox_override("panel", sb)
	row.tooltip_text = "%s（%s）\nLv.%d・%s%s\n戰績 %d 勝 %d 敗" % [p.country, p.player_name, p.run.level(),
		p.government_name() if p.government != "" else "尚未選擇制度", ("／" + p.policy_name()) if p.policy != "" else "", p.wins, p.losses]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	row.add_child(h)
	var rk := Label.new()
	rk.text = str(rank if p.alive else p.placement)
	rk.custom_minimum_size = Vector2(18, 0)
	rk.add_theme_font_size_override("font_size", 12)
	rk.add_theme_color_override("font_color", UiStyle.GOLD if p.alive else UiStyle.TEXT_DIM)
	h.add_child(rk)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var nm := Label.new()
	var lv := ("Lv%d " % p.run.level()) if p.alive else ""
	nm.text = lv + p.country + (("・" + tag) if tag != "" else "") + ("" if p.alive else "（R%d 淘汰）" % p.eliminated_round)
	nm.clip_text = true
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color.WHITE if p.alive else UiStyle.TEXT_DIM)
	v.add_child(nm)
	var hpb := ProgressBar.new()
	hpb.custom_minimum_size = Vector2(0, 3)
	hpb.show_percentage = false
	hpb.max_value = float(GameData.clash_cfg("match").get("start_hp", 100))
	hpb.value = maxi(0, p.hp)
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.4, 0.85, 0.45) if p.hp > 50 else (Color(0.95, 0.75, 0.25) if p.hp > 20 else Color(0.95, 0.35, 0.3))
	hpb.add_theme_stylebox_override("fill", f)
	v.add_child(hpb)
	var hpl := Label.new()
	hpl.text = str(maxi(0, p.hp))
	hpl.custom_minimum_size = Vector2(26, 0)
	hpl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hpl.add_theme_font_size_override("font_size", 13)
	h.add_child(hpl)
	return row


func _place_players() -> void:
	if players_panel == null:
		return
	var vs := get_viewport_rect().size
	var ins := _safe_insets()
	players_panel.custom_minimum_size = Vector2(PLAYERS_W, 0)
	players_panel.reset_size()
	var top := top_bar.get_global_rect().end.y + COLLAPSED_H + 8.0
	players_panel.position = Vector2(vs.x - ins.z - PLAYERS_W - 6.0, top)
	# 不可蓋到底部商店：超出時縮小字體間距（10 列精簡列約 300px，720p 下可容納）
	var max_h := bottom_bar.get_global_rect().position.y - top - 6.0
	players_panel.size.y = minf(players_panel.size.y, max_h)
	# 右側排行／資訊卡／背包打開時讓位（不擋住它們）
	players_panel.visible = leader.collapsed and not detail_box.visible and not bag_box.visible
	# 隊友戰況放在羈絆清單右側、棋盤左邊的空白處（不擋棋盤與提示文字）
	var r := board_rect()
	var free_w := maxf(200.0, (r.size.x - board.board_size().x * board.get_global_transform_with_canvas().get_scale().x) * 0.5 - 12.0)
	coop_label.custom_minimum_size = Vector2(minf(free_w, 300.0), 0)
	coop_panel.reset_size()
	coop_panel.position = Vector2(r.position.x + 2.0, r.position.y + 2.0)


func _apply_side_layout() -> void:
	super._apply_side_layout()
	_place_players()


func _layout() -> void:
	super._layout()
	_place_players()


# ---------- 選單 ----------
func _connect() -> void:
	super._connect()
	for path in ["MenuOverlay/Panel/VBox/CodexButton", "MenuOverlay/Panel/VBox/SaveQuitButton", "MenuOverlay/Panel/VBox/AbandonButton"]:
		var b: Button = get_node(path)
		for c in b.pressed.get_connections():
			b.pressed.disconnect(c["callable"])
	for c in abandon_confirm.confirmed.get_connections():
		abandon_confirm.confirmed.disconnect(c["callable"])
	$MenuOverlay/Panel/VBox/CodexButton.pressed.connect(func():
		Session.prep_time_left = prep_timer.remaining
		Session.prep_time_round = m.round_no
		Session.open_codex(Session.SCENE_CLASH))
	($MenuOverlay/Panel/VBox/SaveQuitButton as Button).text = "回主選單（對局不保存）"
	$MenuOverlay/Panel/VBox/SaveQuitButton.pressed.connect(func(): abandon_confirm.popup_centered())
	($MenuOverlay/Panel/VBox/AbandonButton as Button).text = "放棄這場對局"
	$MenuOverlay/Panel/VBox/AbandonButton.pressed.connect(func(): abandon_confirm.popup_centered())
	abandon_confirm.dialog_text = "確定要離開這場《氏族爭霸》對局嗎？原型版不保存對局進度。"
	abandon_confirm.confirmed.connect(func():
		Session.end_clash()
		Session.run = null
		Session.goto(Session.SCENE_MENU))


# ---------- 淘汰、觀戰、最終結算 ----------
func _show_end() -> void:
	var key := "final" if m.finished else "elim"
	if _end_shown_for == key and end_overlay.visible:
		return
	_end_shown_for = key
	_ended = true
	phase = Phase.AFTER
	_spectating = false
	prep_timer.stop()
	trade_overlay.visible = false
	gov_overlay.visible = false
	gov_reopen.visible = false
	coop_panel.visible = false
	for c in end_buttons.get_children():
		end_buttons.remove_child(c)
		c.queue_free()
	for c in toasts.get_children():
		toasts.remove_child(c)
		c.queue_free()
	if m.finished:
		var champs: Array = m.players.filter(func(p): return (p as ClashPlayer).placement == 1)
		var names: Array = champs.map(func(p): return (p as ClashPlayer).country)
		end_title.text = ("冠軍！你的國家統一了大陸" if me.placement == 1 else "對局結束：冠軍 %s" % "、".join(names))
	else:
		end_title.text = "你在第 %d 回合遭到淘汰：第 %d 名" % [me.eliminated_round, me.placement]
	end_body.text = _standings_text()
	if not m.finished:
		_end_button("繼續觀戰", func():
			end_overlay.visible = false
			_start_spectate(false))
		_end_button("快轉到結束", func():
			end_overlay.visible = false
			_start_spectate(true))
	_end_button("重新開始", func():
		Session.new_clash(me.player_name, me.country, me.ai_level if not me.is_human else _ai_level_of(), 0)
		Session.goto(Session.SCENE_CLASH))
	_end_button("回主選單", func():
		Session.end_clash()
		Session.run = null
		Session.goto(Session.SCENE_MENU))
	end_overlay.visible = true


func _ai_level_of() -> String:
	for p in m.players:
		if not (p as ClashPlayer).is_human:
			return (p as ClashPlayer).ai_level
	return "normal"


func _end_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_button(b, Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.2), 16)
	b.pressed.connect(cb)
	end_buttons.add_child(b)


func _shop_open() -> bool:
	return not _ended and super._shop_open()


func is_end_open() -> bool:
	return end_overlay.visible


func _standings_text() -> String:
	var lines: Array = ["[b]名次　國家（統治者）　制度／政策　結果[/b]"]
	for p in m.standings():
		var cp: ClashPlayer = p
		var rank := cp.placement if cp.placement > 0 else m.current_rank(cp.index)
		var res := ("存活・生命 %d" % cp.hp) if cp.alive else ("第 %d 回合淘汰" % cp.eliminated_round)
		var gov := cp.government_name() + (("／" + cp.policy_name()) if cp.policy != "" else "")
		var line := "%d　%s（%s）　%s　%s" % [rank, cp.country, cp.player_name, gov if gov != "" else "—", res]
		if cp.index == me.index:
			line = "[color=#ffd24d]%s[/color]" % line
		lines.append(line)
	lines.append("")
	lines.append("[color=#9aa3ad]同一回合多人淘汰：回合開始時生命高者名次較前；再比本回合結算後生命；完全相同則並列。[/color]")
	return "\n".join(lines)


func _start_spectate(fast: bool) -> void:
	_spectating = true
	_spec_fast = fast
	_spec_left = 0.2
	_ended = true
	board.set_prep_visible(false)
	battle_player.clear()
	menu_btn.visible = false
	speed_btn.visible = false
	skip_btn.visible = false
	bar_left.text = " 觀戰中"


func _spec_process(delta: float) -> void:
	_spec_left -= delta
	if _spec_left > 0.0:
		return
	_spec_left = 0.05 if _spec_fast else 1.2
	if m.finished:
		_spectating = false
		_show_end()
		return
	if m.stage == "settled":
		m.begin_round()
	var rep := m.auto_round()
	bar_left.text = " 觀戰中・第 %d 回合（存活 %d 人）" % [int(rep["round"]), m.alive_count()]
	round_label.text = "第 %d 回合" % int(rep["round"])
	for s in rep["eliminated"]:
		var p: ClashPlayer = m.players[s]
		_toast("%s 遭到淘汰（第 %d 名）" % [p.country, p.placement], Color(1, 0.5, 0.5))
	_refresh_players()
	if m.finished:
		_spectating = false
		_show_end()
