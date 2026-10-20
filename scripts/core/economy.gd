class_name Economy
extends RefCounted
## 經濟、文明等級、遠征生命扣血公式（企劃第 3、4 節）。全部為純函式。


static func _eco(key: String, default_value: Variant) -> Variant:
	return GameData.cfg("economy").get(key, default_value)


static func start_gold() -> int:
	return int(_eco("start_gold", 5))


static func base_income() -> int:
	return int(_eco("base_income", 5))


static func clear_bonus() -> int:
	return int(_eco("clear_bonus", 2))


static func reroll_cost() -> int:
	return int(_eco("reroll_cost", 2))


static func xp_cost() -> int:
	return int(_eco("xp_cost", 4))


static func xp_per_buy() -> int:
	return int(_eco("xp_per_buy", 4))


static func natural_xp() -> int:
	return int(_eco("natural_xp", 2))


## interest = min(2, floor(gold / 10))
static func interest(gold: int) -> int:
	var step := int(_eco("interest_step", 10))
	return clampi(int(floor(float(maxi(gold, 0)) / float(step))), 0, int(_eco("interest_max", 2)))


## 出售回收：1 星 cost、2 星 3×cost、3 星 9×cost
static func sell_value(cost: int, star: int) -> int:
	var mult: Array = _eco("sell_multiplier_by_star", [1, 3, 9])
	return cost * int(mult[clampi(star, 1, mult.size()) - 1])


# ---------- 等級 ----------
static func xp_thresholds() -> Array:
	return GameData.cfg("level").get("xp_thresholds", [0, 2, 6, 12, 20, 30, 42, 56, 72, 90])


static func max_level() -> int:
	return int(GameData.cfg("level").get("max_level", 10))


## 以累積 XP 判斷文明等級
static func level_for_xp(xp: int) -> int:
	var th := xp_thresholds()
	var lv := 1
	for i in th.size():
		if xp >= int(th[i]):
			lv = i + 1
	return mini(lv, max_level())


## 回傳 [本級已累積, 本級所需]；滿級回傳 [0, 0]
static func xp_progress(xp: int) -> Array:
	var lv := level_for_xp(xp)
	if lv >= max_level():
		return [0, 0]
	var th := xp_thresholds()
	var cur := int(th[lv - 1])
	var nxt := int(th[lv])
	return [xp - cur, nxt - cur]


# ---------- 遠征生命 ----------
static func start_hp() -> int:
	return int(GameData.cfg("expedition").get("start_hp", 40))


static func max_hp() -> int:
	return int(GameData.cfg("expedition").get("max_hp", 40))


static func round_multiplier(round_no: int) -> float:
	for m in GameData.cfg("expedition").get("round_multipliers", []):
		if round_no >= int(m["from"]) and round_no <= int(m["to"]):
			return float(m["mult"])
	return 1.0


static func threat_of_star(star: int) -> int:
	var arr: Array = GameData.cfg("expedition").get("threat_by_star", [1, 2, 4])
	return int(arr[clampi(star, 1, arr.size()) - 1])


## stars：存活敵軍的星級清單
static func threat(stars: Array) -> int:
	var t := 0
	for s in stars:
		t += threat_of_star(int(s))
	return t


## min(10, ceil(remainingThreat × roundMultiplier))；全清（威脅 0）不扣
static func expedition_loss(remaining_threat: int, round_no: int) -> int:
	if remaining_threat <= 0:
		return 0
	var raw := float(remaining_threat) * round_multiplier(round_no)
	var cap := int(GameData.cfg("expedition").get("max_loss_per_round", 10))
	# 減去極小值，避免 5×1.4=7.0000000001 這類浮點誤差被進位成 8
	return mini(cap, int(ceil(raw - 1e-6)))
