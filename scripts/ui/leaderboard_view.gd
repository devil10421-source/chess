class_name LeaderboardView
extends RefCounted
## 戰鬥貢獻排行的畫面（資料由 Leaderboard.rows 計算）。

const BAR_COLORS := {"damage": Color(1.0, 0.62, 0.3), "taken": Color(0.95, 0.38, 0.38), "shielded": Color(0.8, 0.9, 1.0), "healing": Color(0.42, 0.86, 0.52)}


static func build(container: VBoxContainer, stats: Array, metric: String) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()
	var rows := Leaderboard.rows(stats, metric, 0)
	var total := Leaderboard.total(stats, metric, 0)
	if rows.is_empty() or total <= 0.0:
		var l := Label.new()
		l.text = "本場沒有%s紀錄。" % Leaderboard.METRICS.get(metric, "")
		l.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		container.add_child(l)
		return
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var name := Label.new()
		name.custom_minimum_size = Vector2(170, 0)
		name.clip_text = true
		name.text = "%s %s" % [r["name"], "★".repeat(int(r["star"]))]
		name.add_theme_font_size_override("font_size", 14)
		name.add_theme_color_override("font_color", GameData.tier_color(GameData.unit_cost(r["id"])).lightened(0.35))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.value = float(r["ratio"])
		bar.custom_minimum_size = Vector2(0, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_COLORS.get(metric, Color.WHITE)
		fill.set_corner_radius_all(3)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.08)
		bg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		var val := Label.new()
		val.custom_minimum_size = Vector2(120, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.text = "%d（%.1f%%）" % [int(r["value"]), float(r["pct"])]
		val.add_theme_font_size_override("font_size", 14)
		h.add_child(name)
		h.add_child(bar)
		h.add_child(val)
		container.add_child(h)
	var sum := Label.new()
	sum.text = "全隊合計：%d" % int(total)
	sum.add_theme_font_size_override("font_size", 13)
	sum.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	container.add_child(sum)
