class_name ClashMatch
extends RefCounted
## 《氏族爭霸》本地權威對局管理器：十人對局、回合流程、配對、交易、戰鬥、生命結算、淘汰與名次。
## 真人與 AI 都透過同一套規則接口行動：submit(seat, action)（內部呼叫 RunState／ClashGovernment／ClashTrade）。
## 未來改成連線版時，這個類別（加上 SharedPool、ClashTrade）就是伺服器端的權威狀態；畫面只讀取狀態與送出動作。
##
## 每回合流程：
##   begin_round()   回合開始：每人刷新商店、計算配對（PvP／合作 PvE）、AI 備戰
##   lock_in()       備戰時間到：未選的國家制度自動選、自動補位；PvE → 進入交易，PvP → 直接開戰
##   end_trades()    交易時間到（或真人那組已成交）：未成立的交易取消 → 開戰
##   start_battles() 建立所有戰鬥（真人那場由畫面逐步播放，其他直接算完）
##   settle_round()  全部戰鬥結束：扣血、PvE 獎勵、淘汰與名次、收入、經驗、政策結算 → 下一回合

signal changed

var seed := 0
var round_no := 1
var players: Array = []          # Array[ClashPlayer]，依座位
var pool := SharedPool.new()
var human_seat := -1
var stage := "prep"              # prep／trade／battle／settled／over
var round_kind := "pvp"          # pvp／pve
var pvp_plan: Dictionary = {}    # {pairs, lone, ghost_of}
var pve_plan: Dictionary = {}    # {pairs, solo}
var pve_count := 0               # 到本回合為止第幾次 PvE
var trades: Array = []
var battles: Array = []
var finished := false
var reports: Array = []
var event_log: Array = []
var last_lone := -1
var gov_auto_notes: Array = []   # 本回合因時間到而自動選擇的制度／政策（畫面提示用）


static func create(human_name: String, country: String, seed_value: int, ai_level: String = "", with_human: bool = true) -> ClashMatch:
	GameData.set_clash_clans(true)
	var m := ClashMatch.new()
	m.seed = seed_value
	var mc := GameData.clash_cfg("match")
	var n := int(mc.get("players", 10))
	var names: Array = mc.get("ai_names", [])
	var pre: Array = mc.get("ai_country_prefix", ["測試"])
	var suf: Array = mc.get("ai_country_suffix", ["國"])
	var lvl := ai_level if ai_level != "" else str(GameData.clash_cfg("ai").get("default_difficulty", "normal"))
	for i in n:
		var p := ClashPlayer.new()
		p.index = i
		p.run = RunState.create("", SeededRng.mix(seed_value, 100 + i))
		p.run.gold = int(mc.get("start_gold", Economy.start_gold()))
		p.hp = int(mc.get("start_hp", 100))
		p.hp_at_round_start = p.hp
		if i == 0 and with_human:
			p.is_human = true
			p.player_name = human_name if human_name.strip_edges() != "" else "玩家001"
			p.country = country if country.strip_edges() != "" else "無名之國"
			m.human_seat = 0
		else:
			var k := i - (1 if with_human else 0)
			p.player_name = "AI-%s" % (str(names[k % names.size()]) if not names.is_empty() else str(k + 1))
			# 前綴依座位輪替（不重複），後綴依種子打散
			p.country = "%s%s" % [pre[(k + absi(seed_value)) % pre.size()], suf[(k * 7 + absi(seed_value) / 7) % suf.size()]]
			p.ai_level = lvl
		m.players.append(p)
		m.pool.register(p.run)
	m.begin_round()
	return m


# ---------- 查詢 ----------
func alive_seats() -> Array:
	var out: Array = []
	for p in players:
		if (p as ClashPlayer).alive:
			out.append((p as ClashPlayer).index)
	return out


func alive_count() -> int:
	return alive_seats().size()


func human() -> ClashPlayer:
	return players[human_seat] if human_seat >= 0 else null


## 回合類型：pve_first 起每 pve_every 回合一次合作 PvE；只剩 2 人時一律 PvP（最終決戰）
static func round_type(r: int, alive_n: int) -> String:
	var c := GameData.clash_cfg("rounds")
	var first := int(c.get("pve_first", 2))
	var every := int(c.get("pve_every", 6))
	if alive_n <= 2:
		return "pvp"
	if r >= first and (r - first) % every == 0:
		return "pve"
	return "pvp"


static func prep_seconds(r: int) -> float:
	for e in GameData.clash_cfg("rounds").get("prep_by_round", []):
		if r >= int(e["from"]) and r <= int(e["to"]):
			return float(e["seconds"])
	return 30.0


static func trade_seconds() -> float:
	return float(GameData.clash_cfg("rounds").get("trade_seconds", 20))


static func _range_value(table: Array, r: int, default_value: int) -> int:
	for e in table:
		if r >= int(e["from"]) and r <= int(e["to"]):
			return int(e["value"])
	return default_value


static func pvp_base_damage(r: int) -> int:
	return _range_value(GameData.clash_cfg("pvp").get("base_damage", []), r, 2)


static func pve_loss(r: int) -> int:
	return _range_value(GameData.clash_cfg("pve").get("loss", []), r, 5)


static func unit_damage(stars: Array) -> int:
	var arr: Array = GameData.clash_cfg("pvp").get("unit_damage_by_star", [1, 2, 3])
	var t := 0
	for s in stars:
		t += int(arr[clampi(int(s), 1, arr.size()) - 1])
	return t


## 這名玩家本回合的對手／隊友：{kind: pvp／ghost／coop／solo, other: 座位, ghost_of}
func assignment(seat: int) -> Dictionary:
	if round_kind == "pvp":
		for pr in pvp_plan.get("pairs", []):
			if int(pr[0]) == seat:
				return {"kind": "pvp", "other": int(pr[1])}
			if int(pr[1]) == seat:
				return {"kind": "pvp", "other": int(pr[0])}
		if int(pvp_plan.get("lone", -1)) == seat:
			return {"kind": "ghost", "other": int(pvp_plan.get("ghost_of", -1))}
	else:
		for pr in pve_plan.get("pairs", []):
			if int(pr[0]) == seat:
				return {"kind": "coop", "other": int(pr[1])}
			if int(pr[1]) == seat:
				return {"kind": "coop", "other": int(pr[0])}
		if int(pve_plan.get("solo", -1)) == seat:
			return {"kind": "solo", "other": -1}
	return {}


## 名次表：存活者依生命排序（同生命依座位），淘汰者依名次
func standings() -> Array:
	var arr: Array = players.duplicate()
	arr.sort_custom(func(x: ClashPlayer, y: ClashPlayer) -> bool:
		if x.alive != y.alive:
			return x.alive
		if x.alive:
			if x.hp != y.hp:
				return x.hp > y.hp
			return x.index < y.index
		if x.placement != y.placement:
			return x.placement < y.placement
		return x.index < y.index)
	return arr


## 目前名次（存活者以生命排序推算）
func current_rank(seat: int) -> int:
	var st := standings()
	for i in st.size():
		if (st[i] as ClashPlayer).index == seat:
			var p: ClashPlayer = st[i]
			return p.placement if not p.alive else i + 1
	return 0


func log_event(text: String) -> void:
	event_log.append("R%d %s" % [round_no, text])


# ---------- 回合開始 ----------
func begin_round() -> void:
	if finished:
		return
	stage = "prep"
	trades = []
	battles = []
	gov_auto_notes = []
	var alive := alive_seats()
	round_kind = round_type(round_no, alive.size())
	# 每回合輪流決定刷新順序，避免固定座位總是先抽
	var order: Array = []
	for k in alive.size():
		order.append(alive[(k + round_no) % alive.size()])
	for s in order:
		var p: ClashPlayer = players[s]
		p.hp_at_round_start = p.hp
		p.run.round_no = round_no
		ClashGovernment.apply_round_perks(p)
		p.run.begin_round()
	var rng := SeededRng.new(SeededRng.mix(seed, 5000 + round_no))
	if round_kind == "pvp":
		var recent := {}
		for s in alive:
			recent[s] = (players[s] as ClashPlayer).recent_opponents
		pvp_plan = ClashMatchmaking.pvp(alive, recent, last_lone, rng)
		pve_plan = {}
	else:
		pve_count += 1
		pve_plan = ClashMatchmaking.pve(alive, rng)
		pvp_plan = {}
	for s in order:
		var p: ClashPlayer = players[s]
		if not p.is_human:
			ClashAI.prep(self, p)
	changed.emit()


# ---------- 統一的行動接口（真人與 AI 共用） ----------
## action：{type, ...}。回傳 "" 成功，否則為原因。
func submit(seat: int, action: Dictionary) -> String:
	if seat < 0 or seat >= players.size():
		return "沒有這個座位"
	var p: ClashPlayer = players[seat]
	if finished or not p.alive:
		return "已經淘汰或對局已結束"
	var t := str(action.get("type", ""))
	var shop_ok := stage != "trade"
	var r := ""
	match t:
		"buy":
			r = "交易中不能購買" if not shop_ok else p.run.buy(int(action["slot"]), int(action.get("prefer", -1)))
		"sell":
			r = "交易中不能出售" if not shop_ok else p.run.sell(int(action["uid"]))
		"reroll":
			r = "交易中不能刷新" if not shop_ok else p.run.reroll()
		"buy_xp":
			r = "交易中不能升級" if not shop_ok else p.run.buy_xp()
		"lock":
			p.run.toggle_lock()
		"to_board":
			r = p.run.move_to_board(int(action["uid"]), action["cell"])
		"to_bench":
			r = p.run.move_to_bench(int(action["uid"]), int(action["index"]))
		"equip":
			r = p.run.equip(int(action["uid"]), int(action["inv"]))
		"combine_bag":
			r = p.run.combine_inventory(int(action["i"]), int(action["j"]))
		"combine_unit":
			r = p.run.combine_on_unit(int(action["uid"]), int(action["slot"]), int(action["inv"]))
		"remover":
			r = p.run.use_remover(int(action["uid"]), int(action["slot"]))
		"government":
			r = ClashGovernment.choose_system(p, str(action["value"]), round_no)
			if r == "":
				log_event("%s 成為%s" % [p.country, p.government_name()])
		"policy":
			r = ClashGovernment.choose_policy(p, str(action["value"]), round_no)
			if r == "":
				ClashGovernment.apply_round_perks(p)
				log_event("%s 推行「%s」" % [p.country, p.policy_name()])
		"core":
			if p.policy != "i_am_the_state":
				r = "只有「朕即是國家」可以指定核心"
			elif p.run.find_unit(int(action["uid"])).is_empty():
				r = "找不到棋子"
			else:
				p.core_uid = int(action["uid"])
		"trade_offer":
			var tr := trade_for(seat)
			r = "目前沒有交易" if tr.is_empty() or stage != "trade" else ClashTrade.set_offer(self, tr, seat, action.get("offer", {}))
		"trade_confirm":
			var tr := trade_for(seat)
			r = "目前沒有交易" if tr.is_empty() or stage != "trade" else ClashTrade.set_confirm(self, tr, seat, bool(action.get("value", true)))
		_:
			r = "未知的動作：%s" % t
	if r == "":
		changed.emit()
	return r


# ---------- 備戰結束 ----------
## 備戰時間到。回傳 "trade" 或 "battle"（下一個階段）
func lock_in() -> String:
	for s in alive_seats():
		var p: ClashPlayer = players[s]
		_auto_government(p)
		p.run.auto_fill_board()
	if round_kind == "pve" and not (pve_plan.get("pairs", []) as Array).is_empty():
		_start_trades()
		return "trade"
	start_battles()
	return "battle"


## 時間到仍未選擇制度／政策：從可選項目中隨機選一個（固定種子）
func _auto_government(p: ClashPlayer) -> void:
	for k in 2:
		var pend := ClashGovernment.pending_choice(p, round_no)
		if pend == "":
			return
		var rng := SeededRng.new(SeededRng.mix(seed, 9300 + p.index * 50 + round_no))
		if pend == "system":
			var opts := ClashGovernment.systems()
			submit(p.index, {"type": "government", "value": opts[rng.randi_range(0, opts.size() - 1)]})
		else:
			var opts := ClashGovernment.policies_for(p.government)
			submit(p.index, {"type": "policy", "value": opts[rng.randi_range(0, opts.size() - 1)]})
		if p.is_human:
			gov_auto_notes.append("時間到，自動選擇：%s" % (p.policy_name() if pend == "policy" else p.government_name()))


# ---------- 交易 ----------
func _start_trades() -> void:
	stage = "trade"
	trades = []
	for pr in pve_plan.get("pairs", []):
		var t := ClashTrade.new_trade(int(pr[0]), int(pr[1]))
		trades.append(t)
	# AI 提出交易；兩名 AI 的組合直接談完
	for t in trades:
		for seat in [int(t["a"]), int(t["b"])]:
			var p: ClashPlayer = players[seat]
			if not p.is_human:
				var offer := ClashAI.choose_offer(self, p)
				if not offer.is_empty():
					ClashTrade.set_offer(self, t, seat, offer)
		var pa: ClashPlayer = players[int(t["a"])]
		var pb: ClashPlayer = players[int(t["b"])]
		if not pa.is_human and not pb.is_human:
			ClashAI.respond_trade(self, t, pa.index)
			ClashAI.respond_trade(self, t, pb.index)
			ClashTrade.close(t)
	changed.emit()


func trade_for(seat: int) -> Dictionary:
	for t in trades:
		if int(t["a"]) == seat or int(t["b"]) == seat:
			return t
	return {}


## 真人那組的交易是否已結束（成交或取消）
func human_trade_done() -> bool:
	var t := trade_for(human_seat)
	return t.is_empty() or str(t["status"]) != "open"


func end_trades() -> void:
	for t in trades:
		ClashTrade.close(t)
	start_battles()


# ---------- 戰鬥 ----------
func start_battles() -> void:
	stage = "battle"
	battles = []
	var snaps := {}
	for s in alive_seats():
		var p: ClashPlayer = players[s]
		p.run.auto_fill_board()
		ClashGovernment.on_battle_start(p, p.run.board_lineup())
		p.run.gold_at_battle_start = p.run.gold
		snaps[s] = ClashBattle.lineup_snapshot(p)
	var idx := 0
	if round_kind == "pvp":
		for pr in pvp_plan.get("pairs", []):
			var x := int(pr[0])
			var y := int(pr[1])
			if y == human_seat:
				var tmp := x
				x = y
				y = tmp
			battles.append(ClashBattle.make_pvp(snaps[x], snaps[y], SeededRng.mix(seed, round_no * 100 + idx), false))
			idx += 1
			_note_opponent(x, y)
			_note_opponent(y, x)
		var lone := int(pvp_plan.get("lone", -1))
		var g := int(pvp_plan.get("ghost_of", -1))
		if lone >= 0 and g >= 0:
			battles.append(ClashBattle.make_pvp(snaps[lone], snaps[g], SeededRng.mix(seed, round_no * 100 + idx), true))
		last_lone = lone
	else:
		for pr in pve_plan.get("pairs", []):
			var x := int(pr[0])
			var y := int(pr[1])
			if y == human_seat:
				var tmp := x
				x = y
				y = tmp
			battles.append(ClashBattle.make_coop(snaps[x], snaps[y], pve_count, SeededRng.mix(seed, round_no * 100 + idx)))
			idx += 1
		var solo := int(pve_plan.get("solo", -1))
		if solo >= 0:
			battles.append(ClashBattle.make_solo(snaps[solo], pve_count, SeededRng.mix(seed, round_no * 100 + idx)))
	for s in alive_seats():
		var p: ClashPlayer = players[s]
		p.run.battle_active = true
		p.run.live_battle = null
	var hb := human_battle()
	if hb != null:
		human().run.live_battle = hb.sim_for(human_seat)
	changed.emit()


func _note_opponent(seat: int, opp: int) -> void:
	var p: ClashPlayer = players[seat]
	p.recent_opponents.append(opp)
	while p.recent_opponents.size() > 3:
		p.recent_opponents.pop_front()


func human_battle() -> ClashBattle:
	if human_seat < 0 or not human().alive:
		return null
	for bt in battles:
		var b: ClashBattle = bt
		if b.a == human_seat or (b.kind == "coop" and b.b == human_seat):
			return b
	return null


## 算完所有戰鬥（except_human：真人那場留給畫面播放）
func run_battles(except_human: bool = false) -> void:
	var hb := human_battle()
	for bt in battles:
		if except_human and bt == hb:
			continue
		(bt as ClashBattle).run()


func all_battles_finished() -> bool:
	for bt in battles:
		if not (bt as ClashBattle).finished:
			return false
	return true


# ---------- 結算 ----------
## 所有戰鬥結束後呼叫。回傳本回合報告。
func settle_round() -> Dictionary:
	# 防止重複結算：只有在戰鬥階段、且全部戰鬥結束後才結算一次
	if stage != "battle" or not all_battles_finished():
		return {}
	stage = "settled"
	var rep := {"round": round_no, "kind": round_kind, "per_seat": {}, "eliminated": [], "lines": [], "champion": -1}
	var dmg := {}
	var won := {}
	var pve_ok := {}
	var base := pvp_base_damage(round_no)
	for bt in battles:
		var b: ClashBattle = bt
		var o := b.outcome()
		match b.kind:
			"pvp":
				var pa: ClashPlayer = players[b.a]
				var pb: ClashPlayer = players[b.b]
				match str(o["winner"]):
					"a":
						dmg[b.b] = int(dmg.get(b.b, 0)) + base + unit_damage(o["a_stars"])
						won[b.a] = true
						pa.wins += 1
						pb.losses += 1
					"b":
						dmg[b.a] = int(dmg.get(b.a, 0)) + base + unit_damage(o["b_stars"])
						won[b.b] = true
						pb.wins += 1
						pa.losses += 1
					_:
						dmg[b.a] = int(dmg.get(b.a, 0)) + base + unit_damage(o["b_stars"])
						dmg[b.b] = int(dmg.get(b.b, 0)) + base + unit_damage(o["a_stars"])
				rep["lines"].append("PvP %s vs %s：%s" % [pa.country, pb.country, {"a": pa.country + " 勝", "b": pb.country + " 勝"}.get(str(o["winner"]), "平手")])
			"ghost":
				var pa: ClashPlayer = players[b.a]
				if str(o["winner"]) == "a":
					won[b.a] = true
					pa.wins += 1
				else:
					dmg[b.a] = int(dmg.get(b.a, 0)) + base + unit_damage(o["b_stars"])
					if str(o["winner"]) == "b":
						pa.losses += 1
				rep["lines"].append("幽靈戰 %s vs %s 的鏡像：%s" % [pa.country, (players[b.ghost_of] as ClashPlayer).country, "勝" if str(o["winner"]) == "a" else ("敗" if str(o["winner"]) == "b" else "平手")])
			"coop", "solo":
				var seats := [b.a] if b.kind == "solo" else [b.a, b.b]
				for s in seats:
					pve_ok[s] = bool(o["success"])
					if not bool(o["success"]):
						dmg[s] = int(dmg.get(s, 0)) + pve_loss(round_no)
				var names: Array = seats.map(func(s): return (players[s] as ClashPlayer).country)
				rep["lines"].append("%s %s：%s" % ["合作 PvE" if b.kind == "coop" else "單人 PvE", "＋".join(names), "成功" if bool(o["success"]) else "失敗"])
	# 1) 扣血（同一回合的所有結果一起套用，不會因先後順序影響淘汰）
	for s in alive_seats():
		var p: ClashPlayer = players[s]
		var d := int(dmg.get(s, 0))
		p.hp -= d
		rep["per_seat"][s] = {"damage": d, "won": won.has(s), "pve": pve_ok.get(s, null), "income": 0, "rewards": [], "notes": []}
	# 2) 淘汰與名次
	rep["eliminated"] = _eliminate()
	# 3) 存活者：PvE 獎勵、收入、經驗、政策結算
	for s in alive_seats():
		var p: ClashPlayer = players[s]
		var ps: Dictionary = rep["per_seat"][s]
		if pve_ok.get(s, false):
			ps["rewards"] = _pve_rewards(p)
		var inc := maxi(0, Economy.base_income() + ClashGovernment.income_adjust(p))
		inc += ClashGovernment.interest(p, p.run.gold_at_battle_start)
		if won.has(s):
			inc += ClashGovernment.pvp_win_gold(p)
		p.run.gold += inc
		ps["income"] = inc
		if p.run.level() < Economy.max_level():
			p.run.xp += Economy.natural_xp()
		var note := ClashGovernment.on_round_end(p, round_no)
		if note != "":
			ps["notes"].append(note)
	for p in players:
		(p as ClashPlayer).run.battle_active = false
		(p as ClashPlayer).run.live_battle = null
	# 4) 終局判定
	var alive := alive_seats()
	if alive.size() <= 1:
		finished = true
		if alive.size() == 1:
			(players[alive[0]] as ClashPlayer).placement = 1
	elif round_no >= int(GameData.clash_cfg("match").get("max_rounds", 45)):
		_rank_by_hp(alive)
		finished = true
	for p in players:
		if (p as ClashPlayer).placement == 1:
			rep["champion"] = (p as ClashPlayer).index
	for s in alive_seats() + rep["eliminated"]:
		(players[s] as ClashPlayer).round_log.append({"round": round_no, "hp": (players[s] as ClashPlayer).hp, "dmg": rep["per_seat"].get(s, {}).get("damage", 0)})
	for line in rep["lines"]:
		log_event(line)
	for s in rep["eliminated"]:
		log_event("%s 淘汰（第 %d 名）" % [(players[s] as ClashPlayer).country, (players[s] as ClashPlayer).placement])
	reports.append(rep)
	if finished:
		stage = "over"
		for p in players:
			(p as ClashPlayer).run.finished = true
	else:
		round_no += 1
	changed.emit()
	return rep


## PvE 成功獎勵：金幣＋1 個隨機基礎組件；指定的第 n 次 PvE 另外 1 件特殊裝備（固定種子）
func _pve_rewards(p: ClashPlayer) -> Array:
	var c := GameData.clash_cfg("pve")
	var got: Array = []
	var rng := SeededRng.new(SeededRng.mix(seed, 8000 + round_no * 16 + p.index))
	p.run.gold += int(c.get("reward_gold", 2))
	got.append("+%d 金" % int(c.get("reward_gold", 2)))
	if bool(c.get("reward_component", true)):
		var comps := GameData.components()
		if not comps.is_empty():
			var id := str(comps[rng.randi_range(0, comps.size() - 1)]["id"])
			p.run.inventory.append(id)
			got.append(str(GameData.item(id).get("name", id)))
	if (c.get("special_item_pves", []) as Array).has(pve_count):
		var st := ClashBattle.pve_stage(pve_count)
		var fac := str(GameData.stage(int(st["round"])).get("faction", ""))
		if fac == "":
			fac = "cult"
		var choices := Equipment.roll_choices(rng, fac, "normal")
		if not choices.is_empty():
			p.run.inventory.append(str(choices[0]))
			got.append(str(GameData.item(str(choices[0])).get("name", "")))
	return got


## 生命 ≤ 0 的玩家淘汰。同一回合多人淘汰的名次規則（clash_config.json → tie_rule）：
## ① 回合開始時生命高者較前 ② 結算後生命（可為負）高者較前 ③ 完全相同則並列（共用較前的名次）。
## 淘汰者持有的棋子與商店預留份數立即回到共用棋池。
func _eliminate() -> Array:
	var dead: Array = []
	for s in alive_seats():
		if (players[s] as ClashPlayer).hp <= 0:
			dead.append(players[s])
	if dead.is_empty():
		return []
	var n_before := alive_count()
	dead.sort_custom(func(x: ClashPlayer, y: ClashPlayer) -> bool:
		if x.hp_at_round_start != y.hp_at_round_start:
			return x.hp_at_round_start > y.hp_at_round_start
		if x.hp != y.hp:
			return x.hp > y.hp
		return x.index < y.index)
	var start := n_before - dead.size() + 1
	var i := 0
	while i < dead.size():
		var j := i
		while j + 1 < dead.size() and _same_key(dead[j + 1], dead[i]):
			j += 1
		for k in range(i, j + 1):
			(dead[k] as ClashPlayer).placement = start + i
		i = j + 1
	var out: Array = []
	for p in dead:
		var cp: ClashPlayer = p
		cp.alive = false
		cp.eliminated_round = round_no
		cp.run.battle_active = false
		cp.run.live_battle = null
		pool.unregister(cp.run)
		out.append(cp.index)
	return out


static func _same_key(x: ClashPlayer, y: ClashPlayer) -> bool:
	return x.hp_at_round_start == y.hp_at_round_start and x.hp == y.hp


## 達到回合上限：存活者依生命排名（相同則並列）
func _rank_by_hp(alive: Array) -> void:
	var arr: Array = alive.map(func(s): return players[s])
	arr.sort_custom(func(x: ClashPlayer, y: ClashPlayer) -> bool:
		if x.hp != y.hp:
			return x.hp > y.hp
		return x.index < y.index)
	var i := 0
	while i < arr.size():
		var j := i
		while j + 1 < arr.size() and (arr[j + 1] as ClashPlayer).hp == (arr[i] as ClashPlayer).hp:
			j += 1
		for k in range(i, j + 1):
			(arr[k] as ClashPlayer).placement = i + 1
		i = j + 1


# ---------- 一次跑完（AI 模擬、測試、觀戰快轉） ----------
## 不經過畫面，直接跑完一個回合（真人座位若存在也由 AI 代打交易／備戰以外的部分：備戰不動作、交易不提出）
func auto_round() -> Dictionary:
	var next := lock_in()
	if next == "trade":
		for t in trades:
			if str(t["status"]) == "open":
				for seat in [int(t["a"]), int(t["b"])]:
					if not (players[seat] as ClashPlayer).is_human:
						ClashAI.respond_trade(self, t, seat)
		end_trades()
	run_battles(false)
	var rep := settle_round()
	if not finished:
		begin_round()
	return rep


func play_to_end(max_loops: int = 200) -> void:
	var guard := 0
	while not finished and guard < max_loops:
		guard += 1
		auto_round()
