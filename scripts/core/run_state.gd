class_name RunState
extends RefCounted
## 一局遠征的完整狀態與所有玩家操作。畫面只呼叫這裡的方法並讀取欄位。
## 每個操作回傳 "" 代表成功，否則回傳給玩家看的失敗原因。

signal changed

const SAVE_VERSION := 1

var civ_id := ""
var round_no := 1
var hp := 40
var gold := 5
var xp := 0
var run_seed := 0
var shop_rng: SeededRng
var shop: Array = []           # 每格為棋子 id，已購買的格子為 ""
var shop_locked := false
var free_rerolls := 0
var bench: Array = []          # 長度 bench_size；每格為 null 或 {uid, id, star}
var board: Dictionary = {}     # Vector2i -> {uid, id, star}
var next_uid := 1
var prepared_round := 0        # 已執行過「回合開始」流程的回合（避免讀檔重複刷新）
var gold_at_battle_start := 0
var finished := false
var outcome := ""              # "" / "victory" / "defeat" / "incomplete"
var history: Array = []        # 每回合結算報告


static func create(civ: String, seed_value: int) -> RunState:
	var r := RunState.new()
	r.civ_id = civ
	r.run_seed = seed_value
	r.shop_rng = SeededRng.new(SeededRng.mix(seed_value, 7))
	r.hp = Economy.start_hp()
	r.gold = Economy.start_gold()
	r.xp = 0
	r.round_no = 1
	r.bench.resize(Shop.bench_size())
	r.bench.fill(null)
	r.shop = []
	return r


func _notify() -> void:
	changed.emit()


# ---------- 查詢 ----------
func level() -> int:
	return Economy.level_for_xp(xp)


func board_limit() -> int:
	return level()


func board_count() -> int:
	return board.size()


func chapter() -> int:
	return GameData.chapter_of(round_no)


func civ_name() -> String:
	return str(GameData.civ(civ_id).get("name", civ_id))


func bench_free_index() -> int:
	for i in bench.size():
		if bench[i] == null:
			return i
	return -1


func all_units() -> Array:
	var out: Array = []
	for c in _sorted_board_cells():
		out.append(board[c])
	for b in bench:
		if b != null:
			out.append(b)
	return out


func _sorted_board_cells() -> Array:
	var cells := board.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * 10 + a.x < b.y * 10 + b.x)
	return cells


func board_unit_ids() -> Array:
	var out: Array = []
	for c in _sorted_board_cells():
		out.append(board[c]["id"])
	return out


## [{uid, id, star, cell}]，依格子排序
func board_lineup() -> Array:
	var out: Array = []
	for c in _sorted_board_cells():
		var u: Dictionary = board[c]
		out.append({"uid": u["uid"], "id": u["id"], "star": u["star"], "cell": c})
	return out


## 回傳 {"where": "bench"/"board", "index"/"cell", "unit"}；找不到為空字典
func find_unit(uid: int) -> Dictionary:
	for i in bench.size():
		if bench[i] != null and int(bench[i]["uid"]) == uid:
			return {"where": "bench", "index": i, "unit": bench[i]}
	for c in board.keys():
		if int(board[c]["uid"]) == uid:
			return {"where": "board", "cell": c, "unit": board[c]}
	return {}


func copies_of(id: String, star: int) -> int:
	var n := 0
	for u in all_units():
		if u["id"] == id and int(u["star"]) == star:
			n += 1
	return n


func current_interest() -> int:
	return Economy.interest(gold)


func synergy_counts() -> Dictionary:
	return Synergy.count(board_unit_ids())


# ---------- 回合開始 ----------
## 進入備戰階段時呼叫；同一回合只會執行一次（讀檔後不會重複刷新或重複發券）
func begin_round() -> void:
	if finished or prepared_round == round_no:
		return
	prepared_round = round_no
	var rounds: Array = GameData.civ_special(civ_id, "free_reroll_rounds", [])
	for r in rounds:
		if int(r) == round_no:
			free_rerolls += 1
	if not shop_locked or shop.is_empty():
		shop = Shop.roll(shop_rng, level(), civ_id, three_star_ids())
	_notify()


## 已擁有三星版本的棋子 id（商店不再抽出，也不能再購買）。出售該三星後即恢復。
func three_star_ids() -> Dictionary:
	var out := {}
	var max_star := int(GameData.cfg("star").get("max", 3))
	for u in all_units():
		if int(u["star"]) >= max_star:
			out[str(u["id"])] = true
	return out


# ---------- 商店操作 ----------
func can_buy(slot: int) -> String:
	if finished:
		return "遠征已結束"
	if slot < 0 or slot >= shop.size() or str(shop[slot]) == "":
		return "這格沒有棋子"
	var id := str(shop[slot])
	if three_star_ids().has(id):
		return "已擁有三星，不需要更多"
	var cost := GameData.unit_cost(id)
	if gold < cost:
		return "金幣不足"
	if bench_free_index() < 0 and copies_of(id, 1) < 2:
		return "候補區已滿"
	return ""


func buy(slot: int) -> String:
	var reason := can_buy(slot)
	if reason != "":
		return reason
	var id := str(shop[slot])
	gold -= GameData.unit_cost(id)
	shop[slot] = ""
	var idx := bench_free_index()
	if idx >= 0:
		bench[idx] = _new_unit(id, 1)
		_try_merge(id, 1)
	else:
		# 候補已滿，但已有兩隻同名一星：直接合成
		_merge_with_incoming(id)
	_notify()
	return ""


func _new_unit(id: String, star: int) -> Dictionary:
	var u := {"uid": next_uid, "id": id, "star": star}
	next_uid += 1
	return u


## 依「棋盤優先（格子順序）→ 候補（索引順序）」取前三隻同名同星合成；合成後的棋子留在第一隻的位置
func _try_merge(id: String, star: int) -> void:
	var max_star := int(GameData.cfg("star").get("max", 3))
	if star >= max_star:
		return
	var found: Array = []
	for c in _sorted_board_cells():
		var u: Dictionary = board[c]
		if u["id"] == id and int(u["star"]) == star:
			found.append({"where": "board", "cell": c, "unit": u})
	for i in bench.size():
		var u = bench[i]
		if u != null and u["id"] == id and int(u["star"]) == star:
			found.append({"where": "bench", "index": i, "unit": u})
	if found.size() < 3:
		return
	var keep: Dictionary = found[0]
	for k in [1, 2]:
		var f: Dictionary = found[k]
		if f["where"] == "board":
			board.erase(f["cell"])
		else:
			bench[int(f["index"])] = null
	keep["unit"]["star"] = star + 1
	_try_merge(id, star + 1)


func _merge_with_incoming(id: String) -> void:
	var found: Array = []
	for c in _sorted_board_cells():
		var u: Dictionary = board[c]
		if u["id"] == id and int(u["star"]) == 1:
			found.append({"where": "board", "cell": c, "unit": u})
	for i in bench.size():
		var u = bench[i]
		if u != null and u["id"] == id and int(u["star"]) == 1:
			found.append({"where": "bench", "index": i, "unit": u})
	if found.size() < 2:
		return
	var keep: Dictionary = found[0]
	var other: Dictionary = found[1]
	if other["where"] == "board":
		board.erase(other["cell"])
	else:
		bench[int(other["index"])] = null
	keep["unit"]["star"] = 2
	_try_merge(id, 2)


func reroll() -> String:
	if finished:
		return "遠征已結束"
	if free_rerolls > 0:
		free_rerolls -= 1
	elif gold >= Economy.reroll_cost():
		gold -= Economy.reroll_cost()
	else:
		return "金幣不足"
	shop = Shop.roll(shop_rng, level(), civ_id, three_star_ids())
	_notify()
	return ""


func buy_xp() -> String:
	if finished:
		return "遠征已結束"
	if level() >= Economy.max_level():
		return "文明已達最高等級"
	if gold < Economy.xp_cost():
		return "金幣不足"
	gold -= Economy.xp_cost()
	xp += Economy.xp_per_buy()
	_notify()
	return ""


func toggle_lock() -> void:
	shop_locked = not shop_locked
	_notify()


func sell(uid: int) -> String:
	var f := find_unit(uid)
	if f.is_empty():
		return "找不到棋子"
	var u: Dictionary = f["unit"]
	gold += UnitStats.sell_value(u["id"], int(u["star"]))
	if f["where"] == "bench":
		bench[int(f["index"])] = null
	else:
		board.erase(f["cell"])
	_notify()
	return ""


# ---------- 佈陣 ----------
func move_to_bench(uid: int, index: int) -> String:
	if index < 0 or index >= bench.size():
		return "無效位置"
	var f := find_unit(uid)
	if f.is_empty():
		return "找不到棋子"
	var other = bench[index]
	if f["where"] == "bench":
		var from := int(f["index"])
		bench[from] = other
		bench[index] = f["unit"]
	else:
		var cell: Vector2i = f["cell"]
		board.erase(cell)
		if other != null:
			board[cell] = other
		bench[index] = f["unit"]
	_notify()
	return ""


func move_to_board(uid: int, cell: Vector2i) -> String:
	if not HexGrid.is_player_cell(cell):
		return "只能部署在己方區域（下方 4 排）"
	var f := find_unit(uid)
	if f.is_empty():
		return "找不到棋子"
	var other = board.get(cell)
	if f["where"] == "board":
		var from: Vector2i = f["cell"]
		if from == cell:
			return ""
		board.erase(from)
		if other != null:
			board[from] = other
		board[cell] = f["unit"]
	else:
		if other == null and board_count() >= board_limit():
			return "上場人數已達上限（文明 Lv.%d = %d 隻）" % [level(), board_limit()]
		var idx := int(f["index"])
		bench[idx] = other  # 互換：場上那隻回到候補原位置
		board[cell] = f["unit"]
	_notify()
	return ""


# ---------- 戰鬥 ----------
## 人口不足時自動補位（game_config.json → board.auto_fill，預設開啟）：
## 從候補區最左側依序補到場上空缺，直到達上限或候補沒有棋子；已在場上的棋子不會被移動。
## 近戰放最前面的空排、遠程放最後面的空排，同一排優先靠中央，盡量不打亂既有陣型。回傳補上的 uid。
func auto_fill_board() -> Array:
	var placed: Array = []
	if not bool(GameData.cfg("board").get("auto_fill", true)):
		return placed
	var col_order := [3, 2, 4, 1, 5, 0, 6]
	for i in bench.size():
		if board_count() >= board_limit():
			break
		var u = bench[i]
		if u == null:
			continue
		var rows := [4, 5, 6, 7] if GameData.is_melee(str(u["id"])) else [7, 6, 5, 4]
		var target := HexGrid.INVALID
		for r in rows:
			for c in col_order:
				var cell := Vector2i(c, r)
				if not board.has(cell):
					target = cell
					break
			if target != HexGrid.INVALID:
				break
		if target == HexGrid.INVALID:
			break
		bench[i] = null
		board[target] = u
		placed.append(int(u["uid"]))
	if not placed.is_empty():
		_notify()
	return placed


func start_battle() -> Dictionary:
	auto_fill_board()
	gold_at_battle_start = gold
	var sim := BattleSetup.build(board_lineup(), civ_id, round_no, BattleSetup.battle_seed(run_seed, round_no))
	return sim.run()


## 戰後結算（企劃 3.3 的執行順序）。回傳結算報告。
func settle(result: Dictionary) -> Dictionary:
	var report := {
		"round": round_no, "cleared": bool(result.get("cleared", false)), "threat": int(result.get("threat", 0)),
		"hp_before": hp, "hp_loss": 0, "deer_heal": 0, "income_base": 0, "income_interest": 0, "income_clear": 0,
		"xp_gain": 0, "level_before": level(), "level_after": level(), "outcome": "continue",
	}
	# 1~2. 全清與否 → 扣遠征生命
	var loss := 0 if report["cleared"] else Economy.expedition_loss(report["threat"], round_no)
	hp -= loss
	report["hp_loss"] = loss
	# 3. 生命歸零 → 立即戰敗（不再恢復、不發收入）
	if hp <= 0:
		hp = 0
		finished = true
		outcome = "defeat"
		report["outcome"] = "defeat"
		report["hp_after"] = hp
		history.append(report)
		_notify()
		return report
	# 4. 文明能力：鹿角人每完成 4 回合 +1 遠征生命
	var every := int(GameData.civ_special(civ_id, "expedition_heal_every", 0))
	if every > 0 and round_no % every == 0:
		var amount := int(GameData.civ_special(civ_id, "expedition_heal_amount", 1))
		var before := hp
		hp = mini(Economy.max_hp(), hp + amount)
		report["deer_heal"] = hp - before
	# 5. 收入：固定 + 利息（以開戰瞬間金幣計）+ 全清獎勵
	report["income_base"] = Economy.base_income()
	report["income_interest"] = Economy.interest(gold_at_battle_start)
	report["income_clear"] = Economy.clear_bonus() if report["cleared"] else 0
	gold += report["income_base"] + report["income_interest"] + report["income_clear"]
	# 6. 自然 XP
	if level() < Economy.max_level():
		xp += Economy.natural_xp()
		report["xp_gain"] = Economy.natural_xp()
	report["level_after"] = level()
	report["hp_after"] = hp
	# 7. 進入下一回合或結束
	if round_no >= GameData.total_rounds():
		finished = true
		outcome = "victory" if report["cleared"] else "incomplete"
		report["outcome"] = outcome
	else:
		round_no += 1
	history.append(report)
	_notify()
	return report


# ---------- 存檔 ----------
func _unit_to_dict(u: Dictionary) -> Dictionary:
	return {"uid": int(u["uid"]), "id": str(u["id"]), "star": int(u["star"])}


func to_dict() -> Dictionary:
	var bench_out: Array = []
	for b in bench:
		bench_out.append(null if b == null else _unit_to_dict(b))
	var board_out: Array = []
	for c in _sorted_board_cells():
		var d := _unit_to_dict(board[c])
		d["col"] = c.x
		d["row"] = c.y
		board_out.append(d)
	return {
		"version": SAVE_VERSION,
		"civ_id": civ_id, "round": round_no, "hp": hp, "gold": gold, "xp": xp,
		"run_seed": str(run_seed), "shop_rng_state": shop_rng.state_string(),
		"shop": shop.duplicate(), "shop_locked": shop_locked, "free_rerolls": free_rerolls,
		"bench": bench_out, "board": board_out, "next_uid": next_uid, "prepared_round": prepared_round,
		"finished": finished, "outcome": outcome, "history": history.duplicate(true),
	}


static func from_dict(d: Dictionary) -> RunState:
	if int(d.get("version", 0)) != SAVE_VERSION:
		return null
	var civ := str(d.get("civ_id", ""))
	if GameData.civ(civ).is_empty():
		return null
	var r := RunState.create(civ, str(d.get("run_seed", "0")).to_int())
	r.round_no = int(d.get("round", 1))
	r.hp = int(d.get("hp", 40))
	r.gold = int(d.get("gold", 0))
	r.xp = int(d.get("xp", 0))
	r.shop_rng.load_state_string(str(d.get("shop_rng_state", "0")))
	r.shop = []
	for s in d.get("shop", []):
		r.shop.append(str(s) if GameData.has_unit(str(s)) else "")
	r.shop_locked = bool(d.get("shop_locked", false))
	r.free_rerolls = int(d.get("free_rerolls", 0))
	var bench_in: Array = d.get("bench", [])
	for i in mini(bench_in.size(), r.bench.size()):
		var b = bench_in[i]
		if b != null and GameData.has_unit(str(b["id"])):
			r.bench[i] = {"uid": int(b["uid"]), "id": str(b["id"]), "star": int(b["star"])}
	for b in d.get("board", []):
		var cell := Vector2i(int(b["col"]), int(b["row"]))
		if HexGrid.is_player_cell(cell) and GameData.has_unit(str(b["id"])):
			r.board[cell] = {"uid": int(b["uid"]), "id": str(b["id"]), "star": int(b["star"])}
	r.next_uid = int(d.get("next_uid", 1))
	r.prepared_round = int(d.get("prepared_round", 0))
	r.finished = bool(d.get("finished", false))
	r.outcome = str(d.get("outcome", ""))
	r.history = d.get("history", [])
	return r
