class_name SharedPool
extends RefCounted
## 《氏族爭霸》十人共用有限棋池。
## 剩餘份數不另外存狀態，而是隨時由「所有登記中（存活）玩家」重新計算：
##   剩餘 ＝ 供應量 − Σ（商店上顯示的預留 ＋ 持有棋子的底層份數 1★=1／2★=3／3★=9）
## 所以：購買、出售、升星、交易（只轉移所有權）、淘汰（玩家移出登記 → 份數自動回池）都自然守恆，
## 不可能憑空多出或少掉份數。幽靈陣容與援軍只是戰鬥快照，不屬於任何玩家，不佔份數。
## 未來改成權威伺服器時，這個類別就是伺服器上唯一的棋池來源。

var players: Array = []   # Array[RunState]（存活玩家）


## 每種棋子的總份數（依費用；clash_config.json → pool.supply）
static func supply(cost: int) -> int:
	return int(GameData.clash_cfg("pool").get("supply", {}).get(str(cost), 0))


## 所有可招募棋子的完整供應（34 隻，沒有文明限制）
static func full_supply() -> Dictionary:
	var out := {}
	for id in Shop.full_pool(""):
		out[id] = supply(GameData.unit_cost(id))
	return out


func register(run: RunState) -> void:
	if not players.has(run):
		players.append(run)
		run.shared_pool = self


## 玩家淘汰：移出登記，他的商店預留與持有棋子份數自動回到棋池
func unregister(run: RunState) -> void:
	players.erase(run)


## 已離開棋池的份數（所有登記玩家的商店預留＋持有）
func used() -> Dictionary:
	var out := {}
	for r in players:
		var u: Dictionary = (r as RunState).pool_used()
		for id in u.keys():
			out[id] = int(out.get(id, 0)) + int(u[id])
	return out


func remaining() -> Dictionary:
	var out := full_supply()
	var u := used()
	for id in out.keys():
		out[id] = int(out[id]) - int(u.get(id, 0))
	return out


## 守恆檢查：每種棋子 剩餘 ≥ 0 且 剩餘＋已使用＝供應量。回傳錯誤訊息清單（空＝正常）
func audit() -> Array:
	var errors: Array = []
	var sup := full_supply()
	var u := used()
	for id in u.keys():
		if not sup.has(id):
			errors.append("%s 不在棋池中" % id)
	for id in sup.keys():
		var used_n := int(u.get(id, 0))
		if used_n > int(sup[id]):
			errors.append("%s 使用 %d 份，超過供應 %d" % [id, used_n, sup[id]])
	return errors
