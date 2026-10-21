class_name Shop
extends RefCounted
## 商店抽牌（企劃第 5 節）：先依文明等級抽稀有度，再於該稀有度可抽棋子中等機率抽取。
## 1~3 費：六族全部可抽；4 費：只有玩家所選文明的頂尖棋子。


static func slot_count() -> int:
	return int(GameData.cfg("shop").get("slots", 5))


static func bench_size() -> int:
	return int(GameData.cfg("shop").get("bench_slots", 12))


## 回傳 [1費%, 2費%, 3費%, 4費%]
static func odds_for_level(level: int) -> Array:
	var odds: Dictionary = GameData.cfg("shop").get("odds", {})
	var key := str(clampi(level, 1, Economy.max_level()))
	return odds.get(key, [100, 0, 0, 0])


static func pool_for(civ_id: String, cost: int) -> Array:
	var race := str(GameData.civ(civ_id).get("race", civ_id))
	var out: Array = []
	for u in GameData.units():
		if int(u["cost"]) != cost:
			continue
		if cost >= 4 and str(u["race"]) != race:
			continue
		out.append(str(u["id"]))
	return out


## 這個文明一局可抽到的所有棋子名稱（應為 19 種）
static func full_pool(civ_id: String) -> Array:
	var out: Array = []
	for cost in [1, 2, 3, 4]:
		out.append_array(pool_for(civ_id, cost))
	return out


## excluded：不能再抽到的棋子 id（例如玩家已擁有三星的棋子）。
## 先依等級機率抽稀有度；若該稀有度排除後已無棋子，改在「仍有棋子的稀有度」中依原機率比例重抽，
## 不會讓其他稀有度的相對機率失控。全部都沒有可抽棋子時回傳 ""（空格），不會無限迴圈。
static func roll_slot(rng: SeededRng, level: int, civ_id: String, excluded: Dictionary = {}) -> String:
	var odds := odds_for_level(level)
	var pools: Array = []
	var weights: Array = []
	for cost in [1, 2, 3, 4]:
		var pool: Array = pool_for(civ_id, cost).filter(func(id): return not excluded.has(id))
		pools.append(pool)
		weights.append(float(odds[cost - 1]) if not pool.is_empty() else 0.0)
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		# 該等級機率 > 0 的稀有度都被排除光了：退回任何仍有棋子的稀有度（依低費優先）
		for pool in pools:
			if not pool.is_empty():
				return str(pool[rng.randi_range(0, pool.size() - 1)])
		return ""
	var tier_index := rng.pick_weighted(weights)
	var chosen: Array = pools[tier_index]
	return str(chosen[rng.randi_range(0, chosen.size() - 1)])


static func roll(rng: SeededRng, level: int, civ_id: String, excluded: Dictionary = {}) -> Array:
	var out: Array = []
	for i in slot_count():
		out.append(roll_slot(rng, level, civ_id, excluded))
	return out
