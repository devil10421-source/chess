class_name SeededRng
extends RefCounted
## 可重現的亂數（Godot 內建 PCG32）。狀態可存檔，重新載入後接續同一序列。

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


func randf() -> float:
	return _rng.randf()


## 包含 a 與 b
func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


## weights 為非負數陣列；回傳抽中的索引
func pick_weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return 0
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if roll < acc:
			return i
	return weights.size() - 1


func get_state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value


## 用於存檔：64 位元整數以字串保存，避免 JSON 浮點數失真
func state_string() -> String:
	return str(_rng.state)


func load_state_string(s: String) -> void:
	_rng.state = s.to_int()


static func mix(a: int, b: int) -> int:
	return int(hash(str(a) + ":" + str(b)))
