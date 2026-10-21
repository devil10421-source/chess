class_name ClashMatchmaking
extends RefCounted
## 《氏族爭霸》配對（固定種子，可重現）。
## PvP：存活玩家兩兩對戰；盡量避開最近兩回合遇過的對手（試多組隨機排列取懲罰最小者，不保證完全避開）。
##      奇數人時一人落單進行幽靈對戰（盡量不要連續同一人落單），對手為另一名存活玩家的陣容鏡像。
## PvE：完全隨機兩兩合作；奇數人時一人單人挑戰。

const TRIES := 40


static func pvp(alive: Array, recent: Dictionary, last_lone: int, rng: SeededRng) -> Dictionary:
	var best: Dictionary = {}
	var best_pen := INF
	for k in TRIES:
		var order := _shuffled(alive, rng)
		var lone := -1
		if order.size() % 2 == 1:
			lone = order.pop_back()
		var pairs: Array = []
		var pen := 0.0
		for i in range(0, order.size(), 2):
			var x := int(order[i])
			var y := int(order[i + 1])
			pairs.append([x, y])
			pen += _penalty(recent.get(x, []), y) + _penalty(recent.get(y, []), x)
		if lone >= 0 and lone == last_lone:
			pen += 6.0
		if pen < best_pen:
			best_pen = pen
			best = {"pairs": pairs, "lone": lone}
		if pen <= 0.0:
			break
	if best.is_empty():
		best = {"pairs": [], "lone": -1}
	# 幽靈：從其他存活玩家中挑一名（避開剛遇過的）
	best["ghost_of"] = -1
	if int(best["lone"]) >= 0:
		var lone_seat := int(best["lone"])
		var cands: Array = alive.filter(func(x): return int(x) != lone_seat)
		var fresh: Array = cands.filter(func(x): return not (recent.get(lone_seat, []) as Array).has(int(x)))
		var pool: Array = fresh if not fresh.is_empty() else cands
		if not pool.is_empty():
			best["ghost_of"] = int(pool[rng.randi_range(0, pool.size() - 1)])
	return best


## 最近遇過的懲罰：上一回合 10、兩回合前 4
static func _penalty(hist: Array, opp: int) -> float:
	var n := hist.size()
	if n >= 1 and int(hist[n - 1]) == opp:
		return 10.0
	if n >= 2 and int(hist[n - 2]) == opp:
		return 4.0
	return 0.0


static func pve(alive: Array, rng: SeededRng) -> Dictionary:
	var order := _shuffled(alive, rng)
	var solo := -1
	if order.size() % 2 == 1:
		solo = order.pop_back()
	var pairs: Array = []
	for i in range(0, order.size(), 2):
		pairs.append([int(order[i]), int(order[i + 1])])
	return {"pairs": pairs, "solo": solo}


static func _shuffled(arr: Array, rng: SeededRng) -> Array:
	var out := arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
