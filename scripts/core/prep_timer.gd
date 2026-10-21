class_name PrepTimer
extends RefCounted
## 備戰倒數（V0.5：依回合設定，見 game_config.json → rounds.prep_by_round：第 1 回合 45、2–6 回合 30、7–18 回合 25、19–24 回合 30 秒）。
## 由畫面在商店與棋盤初始化完成後 start()；暫停時不計時；歸零時 tick() 回傳 true 一次。

var duration := 30.0
var remaining := 30.0
var running := false
var paused := false
var _fired := false


func _init() -> void:
	duration = float(GameData.cfg("rounds").get("prep_seconds", 15))
	remaining = duration


## 某回合的備戰秒數
static func seconds_for_round(round_no: int) -> float:
	var cfg := GameData.cfg("rounds")
	for e in cfg.get("prep_by_round", []):
		if round_no >= int(e["from"]) and round_no <= int(e["to"]):
			return float(e["seconds"])
	return float(cfg.get("prep_seconds", 30))


func start_round(round_no: int) -> void:
	duration = seconds_for_round(round_no)
	start()


func start() -> void:
	remaining = duration
	running = true
	paused = false
	_fired = false


func stop() -> void:
	running = false


## 推進 delta 秒；倒數剛好結束的那一次回傳 true
func tick(delta: float) -> bool:
	if not running or paused or _fired:
		return false
	remaining = maxf(0.0, remaining - delta)
	if remaining <= 0.0:
		_fired = true
		running = false
		return true
	return false


## 10～6 秒：黃色提醒
func is_caution() -> bool:
	return running and remaining <= float(GameData.cfg("rounds").get("prep_caution_seconds", 10))


## 5～0 秒：紅色警示
func is_warning() -> bool:
	return running and remaining <= float(GameData.cfg("rounds").get("prep_warning_seconds", 5))


func seconds_left() -> int:
	return int(ceil(remaining))
