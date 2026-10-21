class_name RunState
extends RefCounted
## 一局遠征的完整狀態與所有玩家操作。畫面只呼叫這裡的方法並讀取欄位。
## 每個操作回傳 "" 代表成功，否則回傳給玩家看的失敗原因。

signal changed

## 存檔版本：1 = V0.1/V0.2；2 = V0.3（裝備、背包、獎勵領取狀態）；3 = V0.4（有限卡池快照、裝備卸除器）。讀取舊版會自動轉換。
const SAVE_VERSION := 3

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
var inventory: Array = []      # 裝備背包（裝備 id）
var rewards_claimed: Array = []  # 已領取裝備獎勵的回合
var pending_reward: Dictionary = {}  # 尚未選擇的三選一：{round, faction, drop, choices: [id, id, id]}
## V0.5：倒數歸零仍未選擇、開戰時自動發放的那一件（畫面提示用；不存檔）
var last_auto_reward: String = ""
var removers := 0                 # 裝備卸除器數量（V0.4）
## 進行中的即時戰鬥（V0.5）：開戰到結算之間有效；戰鬥中替場上棋子換裝會排入這場模擬
var live_battle: CombatSim = null
var battle_active := false
var removers_granted: Array = []  # 已發放卸除器的回合
## 一般戰鬥的組件掉落紀錄（V0.5）：[{round, id, kind: "drop"／"guarantee"}]
var component_log: Array = []
## 《氏族爭霸》：十人共用棋池（null＝單人模式，各自計算）。剩餘張數由所有存活玩家的持有＋商店預留即時重算。
var shared_pool: SharedPool = null
## 《氏族爭霸》：國家制度與政策帶來的經濟效果（例如出售二星以上額外得金）
var perks: Dictionary = {}


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
		out.append({"uid": u["uid"], "id": u["id"], "star": u["star"], "cell": c, "items": unit_items(u).duplicate()})
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
	resolve_pending_merges()
	var rounds: Array = GameData.civ_special(civ_id, "free_reroll_rounds", [])
	for r in rounds:
		if int(r) == round_no:
			free_rerolls += 1
	if not shop_locked or shop.is_empty():
		_reroll_shop()
	_notify()


## 重新擺商店：舊的商店棋子先回到卡池（清空即代表歸還），再依剩餘張數抽新的 5 格
func _reroll_shop() -> void:
	shop = []
	shop = Shop.roll(shop_rng, level(), civ_id, three_star_ids(), pool_remaining())


# ---------- 有限卡池（V0.4） ----------
## 每種可招募棋子的剩餘張數＝供應量 − 商店上顯示的張數（預留）− 玩家持有的底層張數（1★=1、2★=3、3★=9）。
## 不會小於 0（舊版存檔若持有超過供應量，視為 0）。
func pool_remaining() -> Dictionary:
	if shared_pool != null:
		return shared_pool.remaining()
	var out := Shop.initial_pool(civ_id)
	var used := pool_used()
	for id in out.keys():
		out[id] = maxi(0, int(out[id]) - int(used.get(id, 0)))
	return out


## 已離開卡池的張數：商店預留＋玩家持有（棋盤、候補區）
func pool_used() -> Dictionary:
	var used := {}
	for s in shop:
		if str(s) != "":
			used[str(s)] = int(used.get(str(s), 0)) + 1
	for u in all_units():
		used[str(u["id"])] = int(used.get(str(u["id"]), 0)) + Shop.copies_for_star(int(u["star"]))
	return used


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
	if bench_free_index() < 0 and _merge_candidates(id, 1).size() < 2:
		return "候補區已滿"
	return ""


## 戰鬥中買到的棋子若要和場上（正在戰鬥）的棋子合成，延到下一次備戰才合成（V0.5）。
## 進入備戰時呼叫：依序嘗試每種棋子的一星→二星、二星→三星合成。
func resolve_pending_merges() -> void:
	if battle_active:
		return
	var ids := {}
	for u in all_units():
		ids[str(u["id"])] = true
	for id in ids.keys():
		_try_merge(id, 1)
		_try_merge(id, 2)


## preferred_uid：玩家目前選取的棋子；購買觸發合成時，它優先成為合成主體（若沒有已上場的同名棋子）
var merge_preferred_uid := -1


func buy(slot: int, preferred_uid: int = -1) -> String:
	merge_preferred_uid = preferred_uid
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
	var u := {"uid": next_uid, "id": id, "star": star, "items": []}
	next_uid += 1
	return u


## 合成主體的固定優先順序（V0.4）：① 已上場的棋子 ② 玩家選中的棋子 ③ 編號（uid）較小者。
## 主體保留身份（uid）、位置與裝備；其他材料的裝備依同一順序補進空格，超過 2 件回背包。
static func _merge_order(a: Dictionary, b: Dictionary, preferred: int) -> bool:
	var ab := 0 if a["where"] == "board" else 1
	var bb := 0 if b["where"] == "board" else 1
	if ab != bb:
		return ab < bb
	var ap := 0 if int(a["unit"]["uid"]) == preferred else 1
	var bp := 0 if int(b["unit"]["uid"]) == preferred else 1
	if ap != bp:
		return ap < bp
	return int(a["unit"]["uid"]) < int(b["unit"]["uid"])


func _merge_candidates(id: String, star: int) -> Array:
	var found: Array = []
	for c in _sorted_board_cells():
		var u: Dictionary = board[c]
		if battle_active:
			break   # 戰鬥中不動場上棋子：和它們的合成延到下一次備戰
		if u["id"] == id and int(u["star"]) == star:
			found.append({"where": "board", "cell": c, "unit": u})
	for i in bench.size():
		var u = bench[i]
		if u != null and u["id"] == id and int(u["star"]) == star:
			found.append({"where": "bench", "index": i, "unit": u})
	var pref := merge_preferred_uid
	found.sort_custom(func(a, b): return _merge_order(a, b, pref))
	return found


func _try_merge(id: String, star: int) -> void:
	var max_star := int(GameData.cfg("star").get("max", 3))
	if star >= max_star:
		return
	var found := _merge_candidates(id, star)
	if found.size() < 3:
		return
	_merge_into(found[0], [found[1], found[2]], star + 1)
	_try_merge(id, star + 1)


## 把 others 合進 keep（keep 留在原位、保留 uid 與裝備）
func _merge_into(keep: Dictionary, others: Array, new_star: int) -> void:
	var merged_items: Array = unit_items(keep["unit"]).duplicate()
	for f in others:
		merged_items.append_array(unit_items(f["unit"]))
		f["unit"]["items"] = []
		if f["where"] == "board":
			board.erase(f["cell"])
		else:
			bench[int(f["index"])] = null
	keep["unit"]["star"] = new_star
	_settle_merged_items(keep["unit"], merged_items)


func _merge_with_incoming(id: String) -> void:
	var found := _merge_candidates(id, 1)
	if found.size() < 2:
		return
	_merge_into(found[0], [found[1]], 2)
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
	_reroll_shop()
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
	if is_fighting(uid):
		return "戰鬥中的場上棋子不能出售"
	var u: Dictionary = f["unit"]
	gold += UnitStats.sell_value(u["id"], int(u["star"]))
	if int(u["star"]) >= 2:
		gold += int(perks.get("sell_bonus_2star", 0))   # 《氏族爭霸》選擇式民主
	# 出售時裝備自動返回背包
	inventory.append_array(unit_items(u))
	u["items"] = []
	if f["where"] == "bench":
		bench[int(f["index"])] = null
	else:
		board.erase(f["cell"])
	_notify()
	return ""


# ---------- 裝備（V0.3） ----------
static func unit_items(u: Dictionary) -> Array:
	if not u.has("items") or u["items"] == null:
		u["items"] = []
	return u["items"]


## 合成後最多保留 2 件在棋子身上（主體原有的優先，再依合成順序補空格），其餘返回背包，不會遺失或複製
func _settle_merged_items(u: Dictionary, all_items: Array) -> void:
	var slots := GameData.item_slots()
	u["items"] = all_items.slice(0, slots)
	if all_items.size() > slots:
		inventory.append_array(all_items.slice(slots))


## 把背包第 inv_index 件裝到棋子上（V0.4：裝上後鎖定，不能直接免費卸下或覆蓋；欄位已滿時失敗）
func equip(uid: int, inv_index: int) -> String:
	if finished:
		return "遠征已結束"
	var f := find_unit(uid)
	if f.is_empty():
		return "找不到棋子"
	if inv_index < 0 or inv_index >= inventory.size():
		return "背包沒有這件裝備"
	var items := unit_items(f["unit"])
	if items.size() >= GameData.item_slots():
		return "裝備欄已滿（最多 %d 件），需要用%s取下" % [GameData.item_slots(), GameData.remover_name()]
	items.append(inventory[inv_index])
	inventory.remove_at(inv_index)
	_sync_live_items(uid)
	_notify()
	return ""


# ---------- 組件合成（V0.5） ----------
## 背包裡兩件組件合成一件完整裝備（放在較前面的位置）；不能合成時回傳原因
func combine_inventory(i: int, j: int) -> String:
	if i == j or i < 0 or j < 0 or i >= inventory.size() or j >= inventory.size():
		return "請選兩件不同的組件"
	var res := GameData.recipe(str(inventory[i]), str(inventory[j]))
	if res == "":
		return "這兩件不能合成"
	var lo := mini(i, j)
	var hi := maxi(i, j)
	inventory.remove_at(hi)
	inventory[lo] = res
	_notify()
	return ""


## 棋子身上第 slot 格是組件、背包第 inv_index 件也是組件 → 合成，結果留在同一格（只佔一格）。
## 戰鬥中的場上棋子也可以：合成完成後立即生效（組件數值移除、換成完整裝備）。
func combine_on_unit(uid: int, slot: int, inv_index: int) -> String:
	if finished:
		return "遠征已結束"
	var f := find_unit(uid)
	if f.is_empty():
		return "找不到棋子"
	var items := unit_items(f["unit"])
	if slot < 0 or slot >= items.size() or inv_index < 0 or inv_index >= inventory.size():
		return "沒有可以合成的組件"
	var res := GameData.recipe(str(items[slot]), str(inventory[inv_index]))
	if res == "":
		return "這兩件不能合成"
	items[slot] = res
	inventory.remove_at(inv_index)
	_sync_live_items(uid)
	_notify()
	return ""


## 拖背包第 inv_index 件到棋子身上時，可以和棋子哪一格合成（-1＝不能）
func combinable_slot(uid: int, inv_index: int) -> int:
	var f := find_unit(uid)
	if f.is_empty() or inv_index < 0 or inv_index >= inventory.size():
		return -1
	var items := unit_items(f["unit"])
	for s in items.size():
		if GameData.recipe(str(items[s]), str(inventory[inv_index])) != "":
			return s
	return -1


# ---------- 一般戰鬥組件掉落與每章保底（V0.5） ----------
func chapter_components(chapter_no: int) -> int:
	return component_log.filter(func(e): return GameData.chapter_of(int(e["round"])) == chapter_no).size()


## 戰鬥結束（存活）時呼叫：一般戰鬥依機率掉落；章節第 5 場（第 5、11、17、23 回合）結束時補足保底。回傳這次取得的組件 id。
func _component_drops(round_done: int) -> Array:
	var cfg := GameData.component_drop_cfg()
	if cfg.is_empty():
		return []
	var got: Array = []
	var ch := GameData.chapter_of(round_done)
	var cap := int(cfg.get("cap", 3))
	var rng := SeededRng.new(SeededRng.mix(run_seed, 7000 + round_done))
	var comps := GameData.components()
	var normal := GameData.reward_for_round(round_done).is_empty() and round_done < GameData.total_rounds()
	if normal and chapter_components(ch) < cap and rng.randf() < float(cfg.get("chance", 0.35)):
		got.append({"round": round_done, "id": str(comps[rng.randi_range(0, comps.size() - 1)]["id"]), "kind": "drop"})
		component_log.append(got[-1])
	var chapter_len := int(GameData.cfg("rounds").get("chapter_length", 6))
	var g_round := (ch - 1) * chapter_len + int(cfg.get("guarantee_round_in_chapter", 5))
	if round_done == g_round:
		while chapter_components(ch) < int(cfg.get("guarantee", 2)):
			got.append({"round": round_done, "id": str(comps[rng.randi_range(0, comps.size() - 1)]["id"]), "kind": "guarantee"})
			component_log.append(got[-1])
	var ids: Array = []
	for e in got:
		inventory.append(str(e["id"]))
		ids.append(str(e["id"]))
	return ids


## 使用裝備卸除器：消耗 1 個，把棋子第 slot 件裝備移回背包（星級、位置不變）
func use_remover(uid: int, slot: int) -> String:
	if finished:
		return "遠征已結束"
	if removers <= 0:
		return "沒有%s（第 %s 回合可獲得）" % [GameData.remover_name(), "、".join(GameData.remover_rounds().map(func(x): return str(int(x))))]
	var f := find_unit(uid)
	if f.is_empty():
		return "找不到棋子"
	if is_fighting(uid):
		return "戰鬥中不能卸下場上棋子的裝備"
	var items := unit_items(f["unit"])
	if slot < 0 or slot >= items.size():
		return "這格沒有裝備"
	inventory.append(items[slot])
	items.remove_at(slot)
	removers -= 1
	_notify()
	return ""


## 目前擁有的所有裝備（背包＋棋子身上），檢查不遺失、不複製用
func all_items() -> Array:
	var out: Array = inventory.duplicate()
	for u in all_units():
		out.append_array(unit_items(u))
	return out


## 戰後若剛完成裝備獎勵回合，產生三選一（每個獎勵回合只會產生一次）
func _maybe_create_reward(round_done: int) -> void:
	var cfg := GameData.reward_for_round(round_done)
	if cfg.is_empty() or rewards_claimed.has(round_done) or not pending_reward.is_empty():
		return
	pending_reward = {"round": round_done, "faction": cfg["faction"], "drop": str(cfg.get("drop", "normal")),
		"choices": Equipment.roll_choices(shop_rng, str(cfg["faction"]), str(cfg.get("drop", "normal")))}


## 額外獎勵：完成指定回合時獲得 1 個裝備卸除器（每回合只發一次；不取代三選一）
func _maybe_grant_remover(round_done: int) -> bool:
	if removers_granted.has(round_done) or not GameData.remover_rounds().any(func(x): return int(x) == round_done):
		return false
	removers += 1
	removers_granted.append(round_done)
	return true


func has_pending_reward() -> bool:
	return not pending_reward.is_empty()


## 選擇三選一中的第 index 件，加入背包
func claim_reward(index: int) -> String:
	if pending_reward.is_empty():
		return "沒有可領取的獎勵"
	if battle_active:
		return "戰鬥已開始，不能再選擇獎勵"
	var choices: Array = pending_reward["choices"]
	if index < 0 or index >= choices.size():
		return "無效的選擇"
	var r := int(pending_reward["round"])
	if rewards_claimed.has(r):
		pending_reward = {}
		return "這個回合的獎勵已領取"
	inventory.append(choices[index])
	rewards_claimed.append(r)
	pending_reward = {}
	_notify()
	return ""


## V0.5：特殊戰鬥的獎勵在下一回合備戰時選擇，倒數不暫停。
## 倒數歸零仍未選擇 → 開戰前從畫面顯示的三件中隨機發放一件（固定種子，與操作時機無關、可重播）。回傳發放的裝備 id。
func auto_claim_reward() -> String:
	if pending_reward.is_empty() or battle_active:
		return ""
	var choices: Array = pending_reward["choices"]
	if choices.is_empty():
		pending_reward = {}
		return ""
	var rng := SeededRng.new(SeededRng.mix(run_seed, 9000 + int(pending_reward["round"])))
	var idx := rng.randi_range(0, choices.size() - 1)
	var id := str(choices[idx])
	if claim_reward(idx) != "":
		return ""
	return id


# ---------- 《氏族爭霸》交易用的所有權轉移 ----------
## 把棋子從這名玩家身上移除（不歸還棋池：交易時只是轉移所有權）。身上裝備退回自己的背包。回傳棋子資料（新 uid 由接收者分配）。
func take_unit_for_trade(uid: int) -> Dictionary:
	var f := find_unit(uid)
	if f.is_empty():
		return {}
	var u: Dictionary = f["unit"]
	inventory.append_array(unit_items(u))
	u["items"] = []
	if f["where"] == "bench":
		bench[int(f["index"])] = null
	else:
		board.erase(f["cell"])
	_notify()
	return {"id": str(u["id"]), "star": int(u["star"])}


## 接收交易來的棋子：放進候補區第一個空格（沒有空格回傳 -1，不會刪除棋子），接著檢查是否能升星。回傳新 uid。
func receive_traded_unit(unit_id: String, star: int) -> int:
	var idx := bench_free_index()
	if idx < 0:
		return -1
	var u := _new_unit(unit_id, star)
	bench[idx] = u
	_try_merge(unit_id, star)
	_notify()
	return int(u["uid"])


# ---------- 佈陣 ----------
func move_to_bench(uid: int, index: int) -> String:
	if index < 0 or index >= bench.size():
		return "無效位置"
	var f := find_unit(uid)
	if f.is_empty():
		return "找不到棋子"
	if battle_active and f["where"] == "board":
		return "戰鬥中不能移動場上棋子"
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
	if battle_active:
		return "戰鬥中不能改變站位或上場棋子"
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


## 開戰（V0.5 即時模擬）：自動補位 → 記錄開戰金幣 → 建立尚未推進的戰鬥模擬，由畫面依播放時間推進
func create_battle() -> CombatSim:
	# 倒數歸零仍未選擇獎勵：開戰前隨機發放（開戰後就不能再選）
	last_auto_reward = auto_claim_reward()
	auto_fill_board()
	gold_at_battle_start = gold
	live_battle = BattleSetup.build(board_lineup(), civ_id, round_no, BattleSetup.battle_seed(run_seed, round_no))
	battle_active = true
	_notify()
	return live_battle


## 一次算完整場（測試、bot 用）
func start_battle() -> Dictionary:
	return create_battle().run()


## 這隻棋子是否正在本回合的戰鬥中（場上棋子；戰鬥中不能出售、移動或替換）
func is_fighting(uid: int) -> bool:
	if not battle_active:
		return false
	for c in board.keys():
		if int(board[c]["uid"]) == uid:
			return true
	return false


## 戰鬥中替場上棋子更換裝備：通知即時模擬（下一個步進生效）
func _sync_live_items(uid: int) -> void:
	if live_battle == null or not is_fighting(uid):
		return
	var f := find_unit(uid)
	if not f.is_empty():
		live_battle.queue_items(uid, unit_items(f["unit"]))


## 戰後結算（企劃 3.3 的執行順序）。回傳結算報告。
func settle(result: Dictionary) -> Dictionary:
	battle_active = false
	live_battle = null
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
	# 裝備獎勵：完成特殊戰鬥（存活）→ 排定三選一，於下一回合備戰時選擇（倒數不暫停）
	_maybe_create_reward(round_no)
	report["reward"] = not pending_reward.is_empty()
	report["remover"] = _maybe_grant_remover(round_no)
	report["components"] = _component_drops(round_no)
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
	return {"uid": int(u["uid"]), "id": str(u["id"]), "star": int(u["star"]), "items": unit_items(u).duplicate()}


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
		"inventory": inventory.duplicate(), "rewards_claimed": rewards_claimed.duplicate(),
		"pending_reward": pending_reward.duplicate(true),
		"pool": pool_remaining(),   # 快照（讀檔時以持有狀態重新計算並核對）
		"removers": removers, "removers_granted": removers_granted.duplicate(),
		"component_log": component_log.duplicate(true),
	}


static func _items_from(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			if GameData.has_item(str(x)):
				out.append(str(x))
	return out


## 讀取存檔。version 1（V0.1/V0.2）沒有裝備資料，自動補上空背包與空裝備欄。
static func from_dict(d: Dictionary) -> RunState:
	var ver := int(d.get("version", 0))
	if ver < 1 or ver > SAVE_VERSION:
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
			r.bench[i] = {"uid": int(b["uid"]), "id": str(b["id"]), "star": int(b["star"]), "items": _items_from(b.get("items", []))}
	for b in d.get("board", []):
		var cell := Vector2i(int(b["col"]), int(b["row"]))
		if HexGrid.is_player_cell(cell) and GameData.has_unit(str(b["id"])):
			r.board[cell] = {"uid": int(b["uid"]), "id": str(b["id"]), "star": int(b["star"]), "items": _items_from(b.get("items", []))}
	r.next_uid = int(d.get("next_uid", 1))
	r.prepared_round = int(d.get("prepared_round", 0))
	r.finished = bool(d.get("finished", false))
	r.outcome = str(d.get("outcome", ""))
	r.history = d.get("history", [])
	r.inventory = _items_from(d.get("inventory", []))
	for x in d.get("rewards_claimed", []):
		r.rewards_claimed.append(int(x))
	var pr = d.get("pending_reward", {})
	if typeof(pr) == TYPE_DICTIONARY and not pr.is_empty():
		r.pending_reward = {"round": int(pr["round"]), "faction": str(pr["faction"]), "drop": str(pr.get("drop", pr.get("tier", "normal"))),
			"choices": _items_from(pr.get("choices", []))}
	r.removers = int(d.get("removers", 0))
	for e in d.get("component_log", []):
		if typeof(e) == TYPE_DICTIONARY and GameData.has_item(str(e.get("id", ""))):
			r.component_log.append({"round": int(e["round"]), "id": str(e["id"]), "kind": str(e.get("kind", "drop"))})
	for x in d.get("removers_granted", []):
		r.removers_granted.append(int(x))
	return r
