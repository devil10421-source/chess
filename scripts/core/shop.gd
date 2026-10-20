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


static func roll_slot(rng: SeededRng, level: int, civ_id: String) -> String:
	var odds := odds_for_level(level)
	var tier_index := rng.pick_weighted(odds)
	# 若該稀有度沒有棋子（理論上不會），往低稀有度退
	for cost in range(tier_index + 1, 0, -1):
		var pool := pool_for(civ_id, cost)
		if not pool.is_empty():
			return str(pool[rng.randi_range(0, pool.size() - 1)])
	return ""


static func roll(rng: SeededRng, level: int, civ_id: String) -> Array:
	var out: Array = []
	for i in slot_count():
		out.append(roll_slot(rng, level, civ_id))
	return out
