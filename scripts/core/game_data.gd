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
	_item_map.clear()
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
			_unit_map[u["id"]] = _resolve_variant(u)
	return _unit_map.get(id, {})


## 異界變體：以 base 指定的基礎棋子為底（沿用其職業、費用、技能、外觀），再覆寫變體自己的欄位。
## 這樣新增腐化變體只需要寫差異，不必重寫整隻棋子。
static func _resolve_variant(u: Dictionary) -> Dictionary:
	if not u.has("base"):
		return u
	var base_id := str(u["base"])
	var base: Dictionary = {}
	for b in units():
		if b["id"] == base_id:
			base = b
	if base.is_empty():
		push_error("異界變體 %s 的 base %s 不存在" % [u.get("id", "?"), base_id])
		return u
	var merged: Dictionary = base.duplicate(true)
	for k in u.keys():
		merged[k] = u[k]
	merged["base_unit"] = base_id
	return merged


## 中立陣營（V0.4）：所有文明都能招募；沒有種族羈絆、沒有文明效果，但吃玩家文明的全軍效果
static func is_neutral(id: String) -> bool:
	return str(unit(id).get("race", "")) == "neutral"


static func is_special(id: String) -> bool:
	var u := unit(id)
	return u.has("stats") or u.has("phase")


# ---------- 異界勢力（V0.3） ----------
static func phase(key: String) -> Dictionary:
	return cfg("otherworld").get("phases", {}).get(key, {})


# ---------- 裝備（V0.3） ----------
static var _item_map: Dictionary = {}


static func equipment() -> Dictionary:
	return _load("equipment")


static func items() -> Array:
	return equipment().get("items", [])


static func item(id: String) -> Dictionary:
	if _item_map.is_empty():
		for it in items():
			_item_map[it["id"]] = it
	return _item_map.get(id, {})


static func has_item(id: String) -> bool:
	return not item(id).is_empty()


static func reward_rounds() -> Array:
	return equipment().get("reward_rounds", [])


## 該回合的裝備獎勵設定 {round, faction, drop}；不是獎勵回合回傳空字典
static func reward_for_round(round_no: int) -> Dictionary:
	for r in reward_rounds():
		if int(r["round"]) == round_no:
			return r
	return {}


static func item_slots() -> int:
	return int(equipment().get("slots_per_unit", 2))


## 裝備卸除器（V0.4）：名稱與額外獲得的回合
## 兩個組件的合成結果（順序不拘）；不能合成回傳 ""
static func recipe(a: String, b: String) -> String:
	for r in equipment().get("recipes", []):
		if (r["a"] == a and r["b"] == b) or (r["a"] == b and r["b"] == a):
			return str(r["result"])
	return ""


static func is_component(id: String) -> bool:
	return str(item(id).get("source", "")) == "component"


static func components() -> Array:
	return items().filter(func(it): return str(it.get("source", "")) == "component")


static func component_drop_cfg() -> Dictionary:
	return equipment().get("component_drops", {})


static func remover_rounds() -> Array:
	return equipment().get("remover", {}).get("rounds", [])


static func remover_name() -> String:
	return str(equipment().get("remover", {}).get("name", "裝備卸除器"))


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
