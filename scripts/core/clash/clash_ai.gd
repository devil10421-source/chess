class_name ClashAI
extends RefCounted
## 《氏族爭霸》AI 玩家。所有動作都經由 ClashMatch.submit()（與真人相同的規則接口），不能憑空生成棋子或裝備，
## 購買受共用棋池限制。策略（clash_config.json → ai）：
##   normal：依回合目標升級、保留利息、優先買能升星或符合現有羈絆的棋子、預算內刷新、合成並穿裝備、選國家制度與政策
##   easy  ：升級較慢、不刷新、不看羈絆（只看費用與升星）


static func cfg(level: String) -> Dictionary:
	var c := GameData.clash_cfg("ai")
	return c.get(level, c.get("normal", {}))


static func star_mult(star: int) -> float:
	return [1.0, 3.0, 9.0][clampi(star, 1, 3) - 1]


# ---------- 備戰 ----------
static func prep(m: ClashMatch, p: ClashPlayer) -> void:
	var c := cfg(p.ai_level)
	_choose_government(m, p)
	var r := m.round_no
	var targets: Array = c.get("level_targets", [1])
	var target := int(targets[clampi(r - 1, 0, targets.size() - 1)])
	var keep := _keep_gold(m, p, c)
	# 升級（落後目標時可以動用一部分存款）
	var guard := 0
	while p.run.level() < target and guard < 20:
		guard += 1
		var floor_gold := keep - 10 if p.run.level() < target - 1 else keep
		if p.run.gold - Economy.xp_cost() < maxi(0, floor_gold):
			break
		if m.submit(p.index, {"type": "buy_xp"}) != "":
			break
	# 購買與刷新
	var rerolls := 0
	var budget := int(c.get("reroll_budget", 0))
	if p.hp < 40 and p.ai_level != "easy":
		budget += 3
	guard = 0
	while guard < 60:
		guard += 1
		if _buy_best(m, p, c, keep):
			continue
		var cost := Economy.reroll_cost() if p.run.free_rerolls <= 0 else 0
		if rerolls < budget and p.run.gold - cost >= keep + 2:
			if m.submit(p.index, {"type": "reroll"}) != "":
				break
			rerolls += 1
			continue
		if p.run.free_rerolls > 0 and rerolls < budget + 1:
			m.submit(p.index, {"type": "reroll"})
			rerolls += 1
			continue
		break
	_sell_extras(m, p)
	arrange(m, p, c)
	_items(m, p)
	if p.policy == "i_am_the_state":
		var lineup := p.run.board_lineup()
		var core := ClashGovernment.strongest_uid(lineup)
		if core >= 0:
			m.submit(p.index, {"type": "core", "uid": core})


static func _keep_gold(m: ClashMatch, p: ClashPlayer, c: Dictionary) -> int:
	if m.round_no < int(c.get("econ_floor_round", 4)):
		return 0
	if p.hp < 30:
		return 0   # 生命危險：全力強化
	return int(c.get("keep_gold", 20)) if p.hp >= 50 else 10


## 國家制度：依目前陣容與經濟傾向選擇（固定種子）；政策在兩條中隨機
static func _choose_government(m: ClashMatch, p: ClashPlayer) -> void:
	var rng := SeededRng.new(SeededRng.mix(m.seed, 9100 + p.index * 37 + m.round_no))
	var pend := ClashGovernment.pending_choice(p, m.round_no)
	if pend == "system":
		var w := [1.0, 1.0, 1.0]   # democracy, empire, commune
		if p.run.gold >= 30:
			w[0] += 1.5
		var twos := 0
		for u in p.run.all_units():
			if int(u["star"]) >= 2:
				twos += 1
		if twos >= 3:
			w[1] += 1.5
		if p.run.board_count() >= 6:
			w[2] += 1.0
		var opts := ClashGovernment.systems()
		m.submit(p.index, {"type": "government", "value": opts[rng.pick_weighted(w)]})
		pend = ClashGovernment.pending_choice(p, m.round_no)
	if pend == "policy":
		var pols := ClashGovernment.policies_for(p.government)
		m.submit(p.index, {"type": "policy", "value": pols[rng.randi_range(0, pols.size() - 1)]})


## 羈絆契合度：這隻棋子的種族／職業與已持有棋子（不同名）相同的數量
static func fit(p: ClashPlayer, id: String) -> float:
	var u := GameData.unit(id)
	var seen := {}
	var f := 0.0
	for o in p.run.all_units():
		var oid := str(o["id"])
		if oid == id or seen.has(oid):
			continue
		seen[oid] = true
		var ou := GameData.unit(oid)
		if str(ou.get("race", "")) == str(u.get("race", "")):
			f += 1.0
		if str(ou.get("class", "")) == str(u.get("class", "")):
			f += 0.8
	return minf(f, 4.0)


static func _buy_best(m: ClashMatch, p: ClashPlayer, c: Dictionary, keep: int) -> bool:
	var best := -1
	var best_score := -INF
	var syn_w := float(c.get("synergy_weight", 0.0))
	# 棋子不夠上場時什麼都買；夠了才挑剔
	var need_units := p.run.all_units().size() < p.run.board_limit() + 1
	var threshold := 0.0 if need_units else 2.0
	for i in p.run.shop.size():
		var id := str(p.run.shop[i])
		if id == "" or p.run.can_buy(i) != "":
			continue
		var cost := GameData.unit_cost(id)
		var ones := p.run.copies_of(id, 1)
		var twos := p.run.copies_of(id, 2)
		var score := float(cost) + ones * 3.0 + twos * 2.0 + syn_w * fit(p, id)
		if ones >= 2:
			score += 6.0   # 買了就升星
		if cost == 1 and m.round_no >= 16 and ones == 0:
			score -= 3.0
		var completes := ones >= 2
		if p.run.gold - cost < keep and not completes:
			continue
		if score < threshold and not completes:
			continue
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		return false
	return m.submit(p.index, {"type": "buy", "slot": best}) == ""


## 候補區快滿時賣掉最沒用的棋子（沒有同名、契合度低、費用低）
static func _sell_extras(m: ClashMatch, p: ClashPlayer) -> void:
	var guard := 0
	while guard < 12:
		guard += 1
		var filled := 0
		for b in p.run.bench:
			if b != null:
				filled += 1
		if filled <= p.run.bench.size() - 3:
			return
		var worst := -1
		var worst_v := INF
		for b in p.run.bench:
			if b == null:
				continue
			var v := float(GameData.unit_cost(str(b["id"]))) * star_mult(int(b["star"])) + fit(p, str(b["id"]))
			if p.run.copies_of(str(b["id"]), int(b["star"])) >= 2:
				v += 50.0
			if v < worst_v:
				worst_v = v
				worst = int(b["uid"])
		if worst < 0 or m.submit(p.index, {"type": "sell", "uid": worst}) != "":
			return


## 選出上場棋子並站位：戰力＋羈絆契合度最高的 N 隻；近戰前排、遠程後排
static func arrange(m: ClashMatch, p: ClashPlayer, c: Dictionary) -> void:
	var syn_w := float(c.get("synergy_weight", 0.0))
	var all := p.run.all_units()
	all.sort_custom(func(x, y) -> bool:
		var vx := float(GameData.unit_cost(str(x["id"]))) * star_mult(int(x["star"])) + syn_w * 0.5 * fit(p, str(x["id"]))
		var vy := float(GameData.unit_cost(str(y["id"]))) * star_mult(int(y["star"])) + syn_w * 0.5 * fit(p, str(y["id"]))
		if not is_equal_approx(vx, vy):
			return vx > vy
		return int(x["uid"]) < int(y["uid"]))
	# 同名只上一隻（羈絆只算不同名；第二隻同名通常較弱）
	var chosen: Array = []
	var names := {}
	for u in all:
		if chosen.size() >= p.run.board_limit():
			break
		if names.has(str(u["id"])):
			continue
		names[str(u["id"])] = true
		chosen.append(u)
	for u in all:
		if chosen.size() >= p.run.board_limit():
			break
		if not chosen.has(u):
			chosen.append(u)
	var chosen_uids := {}
	for u in chosen:
		chosen_uids[int(u["uid"])] = true
	# 不上場的收回候補
	for cell in p.run.board.keys():
		var u: Dictionary = p.run.board[cell]
		if not chosen_uids.has(int(u["uid"])):
			var idx := p.run.bench_free_index()
			if idx >= 0:
				m.submit(p.index, {"type": "to_bench", "uid": int(u["uid"]), "index": idx})
	var front := [Vector2i(3, 4), Vector2i(2, 4), Vector2i(4, 4), Vector2i(1, 4), Vector2i(5, 4), Vector2i(0, 4), Vector2i(6, 4),
		Vector2i(3, 5), Vector2i(2, 5), Vector2i(4, 5)]
	var back := [Vector2i(3, 6), Vector2i(2, 6), Vector2i(4, 6), Vector2i(3, 7), Vector2i(2, 7), Vector2i(4, 7), Vector2i(1, 6),
		Vector2i(5, 6), Vector2i(1, 7), Vector2i(5, 7), Vector2i(0, 6), Vector2i(6, 6)]
	for u in chosen:
		var uid := int(u["uid"])
		if p.run.find_unit(uid).get("where", "") == "board":
			continue
		var cells: Array = front if GameData.is_melee(str(u["id"])) else back
		var placed := false
		for cell in cells + back + front:
			if not p.run.board.has(cell):
				if m.submit(p.index, {"type": "to_board", "uid": uid, "cell": cell}) == "":
					placed = true
					break
		if not placed:
			break


## 裝備：背包組件兩兩合成，再交給戰力最高的上場棋子（能和身上組件合成就合成）
static func _items(m: ClashMatch, p: ClashPlayer) -> void:
	var merged := true
	var guard := 0
	while merged and guard < 10:
		guard += 1
		merged = false
		for i in p.run.inventory.size():
			for j in range(i + 1, p.run.inventory.size()):
				if GameData.recipe(str(p.run.inventory[i]), str(p.run.inventory[j])) != "":
					if m.submit(p.index, {"type": "combine_bag", "i": i, "j": j}) == "":
						merged = true
						break
			if merged:
				break
	var lineup := p.run.board_lineup()
	lineup.sort_custom(func(x, y) -> bool:
		var vx := float(GameData.unit_cost(str(x["id"]))) * star_mult(int(x["star"]))
		var vy := float(GameData.unit_cost(str(y["id"]))) * star_mult(int(y["star"]))
		if not is_equal_approx(vx, vy):
			return vx > vy
		return int(x["uid"]) < int(y["uid"]))
	for u in lineup:
		var uid := int(u["uid"])
		var k := 0
		var g2 := 0
		while k < p.run.inventory.size() and g2 < 10:
			g2 += 1
			var slot := p.run.combinable_slot(uid, k)
			if slot >= 0 and m.submit(p.index, {"type": "combine_unit", "uid": uid, "slot": slot, "inv": k}) == "":
				continue
			if RunState.unit_items(p.run.find_unit(uid)["unit"]).size() < GameData.item_slots() and m.submit(p.index, {"type": "equip", "uid": uid, "inv": k}) == "":
				continue
			k += 1


# ---------- 交易 ----------
## 一項資源對這名玩家的價值
static func value_for(p: ClashPlayer, thing: Dictionary, own: bool) -> float:
	if thing.is_empty():
		return 0.0
	if str(thing["kind"]) == "item":
		var src := str(GameData.item(str(thing["id"])).get("source", "special"))
		return {"component": 3.0, "craft": 6.0}.get(src, 7.0)
	var id := str(thing["id"])
	var star := int(thing["star"])
	var v := float(GameData.unit_cost(id)) * star_mult(star)
	var same := p.run.copies_of(id, star) - (1 if own else 0)
	if same > 0:
		v += float(GameData.unit_cost(id)) * 2.0 * same   # 有同名：有助升星
	v += 0.5 * fit(p, id)
	return v


## AI 要提出的資源：候補區最沒用、沒有同名的棋子；沒有的話提出一個基礎組件；都沒有就不提出
static func choose_offer(m: ClashMatch, p: ClashPlayer) -> Dictionary:
	var best_uid := -1
	var best_v := INF
	for b in p.run.bench:
		if b == null:
			continue
		if p.run.copies_of(str(b["id"]), int(b["star"])) >= 2:
			continue
		var v := value_for(p, {"kind": "unit", "id": str(b["id"]), "star": int(b["star"])}, true)
		if v < best_v:
			best_v = v
			best_uid = int(b["uid"])
	if best_uid >= 0:
		return {"kind": "unit", "uid": best_uid}
	for i in p.run.inventory.size():
		if GameData.is_component(str(p.run.inventory[i])):
			return {"kind": "item", "inv": i}
	return {}


## 評估交易：對方的提案價值 ≥ 自己提案價值 × trade_accept_ratio 就確認
static func respond_trade(m: ClashMatch, t: Dictionary, seat: int) -> void:
	if str(t["status"]) != "open":
		return
	var p: ClashPlayer = m.players[seat]
	var other := ClashTrade.partner(t, seat)
	var mine := ClashTrade.offer_info(m, seat, t["offer"][seat])
	var theirs := ClashTrade.offer_info(m, other, t["offer"][other])
	if mine.is_empty() or theirs.is_empty():
		return
	var ratio := float(GameData.clash_cfg("ai").get("trade_accept_ratio", 0.9))
	if value_for(p, theirs, false) >= ratio * value_for(p, mine, true):
		ClashTrade.set_confirm(m, t, seat, true)
