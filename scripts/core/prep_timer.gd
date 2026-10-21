class_name PrepTimer
extends RefCounted
## 備戰倒數（每回合固定秒數，見 game_config.json → rounds.prep_seconds）。
## 由畫面在商店與棋盤初始化完成後 start()；暫停時不計時；歸零時 tick() 回傳 true 一次。

var duration := 15.0
var remaining := 15.0
var running := false
var paused := false
var _fired := false


func _init() -> void:
	duration = float(GameData.cfg("rounds").get("prep_seconds", 15))
	remaining = duration


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


func is_warning() -> bool:
	return running and remaining <= float(GameData.cfg("rounds").get("prep_warning_seconds", 5))


func seconds_left() -> int:
	return int(ceil(remaining))
