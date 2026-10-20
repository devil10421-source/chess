class_name UiStyle
extends RefCounted
## 畫面共用的顏色與樣式（只影響外觀）。

const BG := Color(0.07, 0.08, 0.11)
const PANEL := Color(0.11, 0.13, 0.18, 0.94)
const PANEL_BORDER := Color(0.26, 0.30, 0.40)
const TEXT := Color(0.92, 0.93, 0.96)
const TEXT_DIM := Color(0.62, 0.66, 0.74)
const GOLD := Color(1.0, 0.82, 0.30)
const HP := Color(0.92, 0.36, 0.38)
const GOOD := Color(0.42, 0.86, 0.52)
const BAD := Color(0.95, 0.42, 0.40)
const PLAYER_SIDE := Color(0.20, 0.42, 0.78)
const ENEMY_SIDE := Color(0.78, 0.26, 0.26)
const STAR_COLOR := Color(1.0, 0.93, 0.45)
const AURA_3STAR := Color(1.0, 0.42, 0.62)

## 執行時才載入（不用 preload），專案第一次匯入時才不會因字型尚未匯入而報錯
static var FONT: Font = load("res://assets/fonts/NotoSansTC-Subset.otf") if ResourceLoader.exists("res://assets/fonts/NotoSansTC-Subset.otf") else ThemeDB.fallback_font


static func panel_box(bg: Color = PANEL, border: Color = PANEL_BORDER, radius: int = 10, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func apply_panel(p: Control, bg: Color = PANEL, border: Color = PANEL_BORDER) -> void:
	p.add_theme_stylebox_override("panel", panel_box(bg, border))


static func style_button(b: Button, bg: Color, border: Color = Color(1, 1, 1, 0.15), font_size: int = 17) -> void:
	var normal := panel_box(bg, border, 8)
	var hover := panel_box(bg.lightened(0.12), border.lightened(0.2), 8)
	var pressed := panel_box(bg.darkened(0.2), border, 8)
	var disabled := panel_box(bg.darkened(0.45), Color(1, 1, 1, 0.06), 8)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))


static func hex_color(c: Color) -> String:
	return "#" + c.to_html(false)


static func unit_line(id: String) -> String:
	var u := GameData.unit(id)
	return "%s・%s・%s" % [GameData.race_name(u["race"]), GameData.type_name(u["type"]), GameData.class_name_of(u["class"])]


static func stars(n: int) -> String:
	return "★".repeat(n)


## 單位資訊（BBCode），給資訊面板與圖鑑使用；mods 可帶入文明／羈絆修正後的數值
static func unit_info_bbcode(id: String, star: int, mods: Dictionary = {}) -> String:
	var u := GameData.unit(id)
	var cost := int(u["cost"])
	var s := UnitStats.final_stats(id, star, mods) if not mods.is_empty() else UnitStats.base_stats(id, star)
	var tier_col := hex_color(GameData.tier_color(cost))
	var lines: Array = []
	lines.append("[color=%s]%s %d 費[/color]　[color=#ffe873]%s[/color]" % [tier_col, GameData.tier_name(cost), cost, stars(star)])
	lines.append(unit_line(id) + "　射程 %d" % int(s["range"]))
	lines.append("生命 [b]%d[/b]　攻擊 [b]%.1f[/b]　攻速 %.2f" % [int(s["hp"]), float(s["atk"]), float(s["atk_speed"])])
	lines.append("護甲 %d　魔抗 %d　魔力 %d" % [int(s["armor"]), int(s["mr"]), int(s["mana_max"])])
	var sk := UnitStats.skill(id)
	lines.append("")
	lines.append("[color=#ffd34d]技能｜%s[/color]" % str(sk.get("name", "")))
	lines.append(UnitStats.skill_text(id, star))
	return "\n".join(lines)
