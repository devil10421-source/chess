class_name GameData
extends RefCounted
## 讀取 data/*.json 的唯一入口。所有平衡數值都放在 data/ 內，程式只透過這裡取用。

const DATA_DIR := "res://data/"

static var _cache: Dictionary = {}
static var _unit_map: Dictionary = {}
static var _civ_map: Dictionary = {}
static var _stage_map: Dictionary = {}


static func reload() -> void:
	_cache.clear()
	_unit_map.clear()
	_civ_map.clear()
	_stage_map.clear()


static func _load(file_name: String) -> Dictionary:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := DATA_DIR + file_name + ".json"
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("無法讀取資料檔：%s" % path)
		_cache[file_name] = {}
		return {}
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON 格式錯誤：%s 第 %d 行：%s" % [path, json.get_error_line(), json.get_error_message()])
		_cache[file_name] = {}
		return {}
	var data: Dictionary = json.data
	_cache[file_name] = data
	return data


# ---------- 設定 ----------
static func config() -> Dictionary:
	return _load("game_config")


static func cfg(section: String) -> Dictionary:
	return config().get(section, {})


static func total_rounds() -> int:
	return int(cfg("rounds").get("total", 24))


static func chapter_of(round_no: int) -> int:
	var length := int(cfg("rounds").get("chapter_length", 6))
	return int((round_no - 1) / length) + 1


static func is_boss_round(round_no: int) -> bool:
	for r in cfg("rounds").get("boss_rounds", []):
		if int(r) == round_no:
			return true
	return false


# ---------- 棋子 ----------
static func units() -> Array:
	return _load("units").get("units", [])


## 特殊單位（例如第一回合的教學弱敵）：不在 24 種基礎棋子內，不進商店／圖鑑／羈絆
static func special_units() -> Array:
	return _load("units").get("special_units", [])


static func unit(id: String) -> Dictionary:
	if _unit_map.is_empty():
		for u in units():
			_unit_map[u["id"]] = u
		for u in special_units():
			_unit_map[u["id"]] = u
	return _unit_map.get(id, {})


static func is_special(id: String) -> bool:
	return unit(id).has("stats")


static func has_unit(id: String) -> bool:
	return not unit(id).is_empty()


static func unit_cost(id: String) -> int:
	return int(unit(id).get("cost", 1))


static func is_melee(id: String) -> bool:
	return int(unit(id).get("range", 1)) <= 1


# ---------- 文明 ----------
static func civs() -> Array:
	return _load("civs").get("civs", [])


static func civ(id: String) -> Dictionary:
	if _civ_map.is_empty():
		for c in civs():
			_civ_map[c["id"]] = c
	return _civ_map.get(id, {})


static func civ_special(id: String, key: String, default_value: Variant = null) -> Variant:
	var c := civ(id)
	for group in ["buffs", "debuffs"]:
		for b in c.get(group, []):
			var sp: Dictionary = b.get("special", {})
			if sp.has(key):
				return sp[key]
	return default_value


# ---------- 羈絆 ----------
static func traits() -> Dictionary:
	return _load("traits")


static func trait_groups() -> Array:
	return ["race", "type", "class"]


# ---------- 關卡 ----------
static func stages() -> Array:
	return _load("stages").get("stages", [])


static func stage(round_no: int) -> Dictionary:
	if _stage_map.is_empty():
		for s in stages():
			_stage_map[int(s["round"])] = s
	return _stage_map.get(round_no, {})


# ---------- 文字標籤 ----------
static func race_name(key: String) -> String:
	return str(cfg("labels").get("races", {}).get(key, key))


static func type_name(key: String) -> String:
	return str(cfg("labels").get("types", {}).get(key, key))


static func class_name_of(key: String) -> String:
	return str(cfg("classes").get(key, {}).get("name", key))


static func race_color(key: String) -> Color:
	return Color(str(cfg("labels").get("race_colors", {}).get(key, "#888888")))


static func tier_name(cost: int) -> String:
	return str(cfg("tiers").get(str(cost), {}).get("name", "?"))


static func tier_color(cost: int) -> Color:
	return Color(str(cfg("tiers").get(str(cost), {}).get("color", "#888888")))


static func trait_label(group: String, key: String) -> String:
	match group:
		"race":
			return race_name(key)
		"type":
			return type_name(key)
		_:
			return class_name_of(key)
