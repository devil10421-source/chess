class_name BattleFx
extends Node2D
## 戰鬥特效：彈道、傷害數字、技能範圍、技能名稱。全部以 _draw 繪製，只影響畫面。

var hex_size := 36.0
var _fx: Array = []   # {type, t, dur, ...}


func clear() -> void:
	_fx.clear()
	queue_redraw()


## dur 為模擬秒數（與 _process 的播放倍率換算一致）；rate 參數保留相容
func projectile(from: Vector2, to: Vector2, color: Color, dur: float, _rate: float = 1.0) -> void:
	_fx.append({"type": "proj", "t": 0.0, "dur": maxf(0.05, dur), "from": from, "to": to, "color": color})


func float_text(pos: Vector2, text: String, color: Color, size: int = 18, dur: float = 0.8) -> void:
	_fx.append({"type": "text", "t": 0.0, "dur": dur, "pos": pos + Vector2(randf_range(-8, 8), 0), "text": text, "color": color, "size": size})


func area(centers: Array, color: Color, dur: float = 0.55) -> void:
	_fx.append({"type": "area", "t": 0.0, "dur": dur, "cells": centers, "color": color})


func ring(pos: Vector2, color: Color, radius: float, dur: float = 0.45) -> void:
	_fx.append({"type": "ring", "t": 0.0, "dur": dur, "pos": pos, "color": color, "radius": radius})


func _process(delta: float) -> void:
	if _fx.is_empty():
		return
	var d := delta * Session.playback_rate
	for f in _fx:
		f["t"] = float(f["t"]) + d
	_fx = _fx.filter(func(f): return float(f["t"]) < float(f["dur"]))
	queue_redraw()


func _hex_points(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(a), sin(a)) * size)
	return pts


func _draw() -> void:
	for f in _fx:
		var k := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		var col: Color = f["color"]
		match f["type"]:
			"proj":
				var p: Vector2 = (f["from"] as Vector2).lerp(f["to"], k)
				draw_circle(p, hex_size * 0.13, col)
				draw_line(p, (f["from"] as Vector2).lerp(f["to"], maxf(0.0, k - 0.25)), Color(col, 0.5), hex_size * 0.07)
			"text":
				var pos: Vector2 = f["pos"] + Vector2(0, -hex_size * 0.9 * k)
				var a := 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
				var size := int(f["size"])
				draw_string_outline(UiStyle.FONT, pos + Vector2(-60, 0), str(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, 120, size, 4, Color(0, 0, 0, a * 0.85))
				draw_string(UiStyle.FONT, pos + Vector2(-60, 0), str(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, 120, size, Color(col, a))
			"area":
				var a := 0.45 * (1.0 - k)
				for c in f["cells"]:
					draw_colored_polygon(_hex_points(c, hex_size * 0.95), Color(col, a))
					draw_polyline(_hex_points(c, hex_size * 0.95) + PackedVector2Array([_hex_points(c, hex_size * 0.95)[0]]), Color(col, a * 1.8), 2.0)
			"ring":
				draw_arc(f["pos"], float(f["radius"]) * (0.6 + 0.8 * k), 0, TAU, 32, Color(col, 1.0 - k), 3.0, true)
