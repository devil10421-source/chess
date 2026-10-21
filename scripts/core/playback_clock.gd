class_name PlaybackClock
extends RefCounted
## 戰鬥播放時間軸：把「實際播放經過秒數」對應到「戰鬥模擬秒數」。
## 戰鬥在開戰時已用固定步長算完，這裡只改變播放快慢，所以勝負、事件順序與時間比例都不變。
## 倍率設定在 game_config.json → battle_playback.segments（V0.2：0–15 秒 1.0×、15–25 秒 1.5×、25 秒後 2.0×）。


static func segments() -> Array:
	var segs: Array = GameData.cfg("battle_playback").get("segments", [{"from": 0, "rate": 1.0}])
	return segs


## 目前（實際經過 real 秒時）的播放倍率
static func rate_at_real(real: float) -> float:
	var rate := 1.0
	for seg in segments():
		if real + 1e-9 >= float(seg["from"]):
			rate = float(seg["rate"])
	return rate


## 實際經過 real 秒時，戰鬥模擬已播放到第幾秒
static func sim_from_real(real: float) -> float:
	var segs := segments()
	var sim := 0.0
	for i in segs.size():
		var a := float(segs[i]["from"])
		var b := INF if i + 1 >= segs.size() else float(segs[i + 1]["from"])
		if real <= a:
			break
		sim += (minf(real, b) - a) * float(segs[i]["rate"])
	return sim


## 播放到模擬第 sim 秒需要的實際秒數（sim_from_real 的反函數）
static func real_from_sim(sim: float) -> float:
	var segs := segments()
	var real := 0.0
	var left := sim
	for i in segs.size():
		var a := float(segs[i]["from"])
		var b := INF if i + 1 >= segs.size() else float(segs[i + 1]["from"])
		var rate := float(segs[i]["rate"])
		var span_sim := (b - a) * rate
		if left <= span_sim:
			return a + left / rate
		left -= span_sim
		real = b
	return real
