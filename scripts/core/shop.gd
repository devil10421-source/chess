class_name Shop
extends RefCounted
## 商店抽牌（V0.4 有限卡池）。
## 兩階段：① 依文明等級機率抽「費用」；② 在該費用「可招募、未被排除、還有剩餘張數」的棋子中，依剩餘張數加權抽取。
## 可招募範圍：1～3 費＝六族全部＋中立；4 費＝玩家所選文明的專屬 4 費＋中立 4 費（其他文明的 4 費不可招募）。
## 卡池（pool）：{棋子 id: 剩餘張數}。PVE 只有玩家會抽，所以剩餘張數＝供應量 − 商店上顯示（已預留）− 玩家持有（1★=1、2★=3、3★=9），
## 由 RunState.pool_remaining() 隨時重新計算，存讀檔後必然一致，不會複製或遺失棋子。


static func slot_count() -> int:
	return int(GameData.cfg("shop").get("slots", 5))


static func bench_size() -> int:
	return int(GameData.cfg("shop").get("bench_slots", 12))


## 回傳 [1費%, 2費%, 3費%, 4費%]
static func odds_for_level(level: int) -> Array:
	var odds: Dictionary = GameData.cfg("shop").get("odds", {})
	var key := str(clampi(level, 1, Economy.max_level()))
	return odds.get(key, [100, 0, 0, 0])


## 每種棋子的供應張數（依費用；game_config.json → shop.pool_size）
static func supply(cost: int) -> int:
	return int(GameData.cfg("shop").get("pool_size", {}).get(str(cost), 0))


## 某星級棋子代表的底層張數：1★=1、2★=3、3★=9
static func copies_for_star(star: int) -> int:
	var arr: Array = GameData.cfg("shop").get("copies_by_star", [1, 3, 9])
	return int(arr[clampi(star, 1, arr.size()) - 1])


static func pool_for(civ_id: String, cost: int) -> Array:
	var race := str(GameData.civ(civ_id).get("race", civ_id))
	var out: Array = []
	for u in GameData.units():
		if int(u["cost"]) != cost:
			continue
		if cost >= 4 and str(u["race"]) != race and not GameData.is_neutral(str(u["id"])):
			continue
		out.append(str(u["id"]))
	return out


## 這個文明一局可招募的所有棋子 id
static func full_pool(civ_id: String) -> Array:
	var out: Array = []
	for cost in [1, 2, 3, 4]:
		out.append_array(pool_for(civ_id, cost))
	return out


## 開局卡池：每種可招募棋子的完整供應量
static func initial_pool(civ_id: String) -> Dictionary:
	var out := {}
	for id in full_pool(civ_id):
		out[id] = supply(GameData.unit_cost(id))
	return out


## excluded：不能抽到的棋子（例如已擁有三星）。pool：剩餘張數（null＝不限量，只給舊測試／工具用）；抽中後立即扣 1。
## 抽中的費用沒有合格棋子時，改在「仍有合格棋子的費用」中依原機率比例重抽；全部都沒有時回傳 ""（空格），不會無限迴圈。
static func roll_slot(rng: SeededRng, level: int, civ_id: String, excluded: Dictionary = {}, pool: Variant = null) -> String:
	var odds := odds_for_level(level)
	var limited := pool is Dictionary
	var pools: Array = []
	var weights: Array = []
	for cost in [1, 2, 3, 4]:
		var cands: Array = pool_for(civ_id, cost).filter(func(id): return not excluded.has(id) and (not limited or int(pool.get(id, 0)) > 0))
		pools.append(cands)
		weights.append(float(odds[cost - 1]) if not cands.is_empty() else 0.0)
	var total := 0.0
	for w in weights:
		total += float(w)
	var chosen: Array = []
	if total <= 0.0:
		# 該等級機率 > 0 的費用都沒有合格棋子：退回任何仍有棋子的費用（低費優先）
		for p in pools:
			if not p.is_empty():
				chosen = p
				break
		if chosen.is_empty():
			return ""
	else:
		chosen = pools[rng.pick_weighted(weights)]
	var id := ""
	if limited:
		var w2: Array = []
		for c in chosen:
			w2.append(float(pool[c]))
		id = str(chosen[rng.pick_weighted(w2)])
		pool[id] = int(pool[id]) - 1
	else:
		id = str(chosen[rng.randi_range(0, chosen.size() - 1)])
	return id


static func roll(rng: SeededRng, level: int, civ_id: String, excluded: Dictionary = {}, pool: Variant = null) -> Array:
	var out: Array = []
	for i in slot_count():
		out.append(roll_slot(rng, level, civ_id, excluded, pool))
	return out
