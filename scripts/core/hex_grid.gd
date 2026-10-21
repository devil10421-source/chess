class_name HexGrid
extends RefCounted
## 7 欄 × 8 排的錯位六角格（odd-r：奇數排向右錯半格，尖頂朝上）。
## 所有距離、範圍、找路都使用六角格距離（cube 座標），不使用曼哈頓距離。
## 排 0~3 為敵方（0 最後排），排 4~7 為玩家（4 最前排）。

const COLS := 7
const ROWS := 8
const PLAYER_ROW_MIN := 4
const ENEMY_ROW_MAX := 3
const INVALID := Vector2i(-1, -1)

const _EVEN_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const _ODD_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)]


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


static func is_player_cell(c: Vector2i) -> bool:
	return in_bounds(c) and c.y >= PLAYER_ROW_MIN


static func is_enemy_cell(c: Vector2i) -> bool:
	return in_bounds(c) and c.y <= ENEMY_ROW_MAX


static func to_cube(c: Vector2i) -> Vector3i:
	var q := c.x - int((c.y - (c.y & 1)) / 2)
	var r := c.y
	return Vector3i(q, r, -q - r)


static func from_cube(h: Vector3i) -> Vector2i:
	var col := h.x + int((h.y - (h.y & 1)) / 2)
	return Vector2i(col, h.y)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := to_cube(a) - to_cube(b)
	return maxi(absi(d.x), maxi(absi(d.y), absi(d.z)))


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dirs := _ODD_DIRS if (c.y & 1) == 1 else _EVEN_DIRS
	for d in dirs:
		var n := c + d
		if in_bounds(n):
			out.append(n)
	return out


static func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in ROWS:
		for q in COLS:
			out.append(Vector2i(q, r))
	return out


static func player_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in all_cells():
		if is_player_cell(c):
			out.append(c)
	return out


static func cells_in_range(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in all_cells():
		if distance(c, center) <= radius:
			out.append(c)
	return out


static func _cube_round(x: float, y: float, z: float) -> Vector3i:
	var rx := roundi(x)
	var ry := roundi(y)
	var rz := roundi(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3i(rx, ry, rz)


## a 到 b 之間的格子（含兩端）
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var out: Array[Vector2i] = []
	var ca := to_cube(a)
	var cb := to_cube(b)
	for i in n + 1:
		var t := 0.0 if n == 0 else float(i) / float(n)
		var h := _cube_round(
			lerpf(ca.x + 1e-6, cb.x + 1e-6, t),
			lerpf(ca.y + 1e-6, cb.y + 1e-6, t),
			lerpf(ca.z - 2e-6, cb.z - 2e-6, t))
		var cell := from_cube(h)
		if out.is_empty() or out[out.size() - 1] != cell:
			out.append(cell)
	return out


# ---------- 像素座標（尖頂六角格） ----------
static func to_pixel(c: Vector2i, size: float) -> Vector2:
	var w := sqrt(3.0) * size
	return Vector2(w * (c.x + 0.5 * (c.y & 1)) + w * 0.5, size * 1.5 * c.y + size)


static func board_pixel_size(size: float) -> Vector2:
	var w := sqrt(3.0) * size
	return Vector2(w * (COLS + 0.5), size * 1.5 * (ROWS - 1) + size * 2.0)


static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var best := INVALID
	var best_d := INF
	for c in all_cells():
		var d := p.distance_squared_to(to_pixel(c, size))
		if d < best_d:
			best_d = d
			best = c
	if best_d > size * size:
		return INVALID
	return best


## 從 start 出發，在 blocked 以外的格子中，以 BFS 找最近的 goals 之一。
## 回傳 {"step": 第一步, "goal": 抵達格, "dist": 步數}；找不到時回傳空字典。
## 鄰居順序固定，結果可重現。
static func find_path_step(start: Vector2i, goals: Dictionary, blocked: Dictionary) -> Dictionary:
	if goals.has(start):
		return {"step": start, "goal": start, "dist": 0}
	var parent := {start: start}
	var frontier: Array[Vector2i] = [start]
	var dist := 0
	while not frontier.is_empty():
		dist += 1
		var next: Array[Vector2i] = []
		var found := INVALID
		for cell in frontier:
			for n in neighbors(cell):
				if parent.has(n) or blocked.has(n):
					continue
				parent[n] = cell
				if goals.has(n) and found == INVALID:
					found = n
				next.append(n)
		if found != INVALID:
			var step := found
			while parent[step] != start:
				step = parent[step]
			return {"step": step, "goal": found, "dist": dist}
		frontier = next
	return {}


## 從 start 出發、不穿過 blocked 的 BFS 步數表：{格子: 步數}（start 為 0）
static func distance_map(start: Vector2i, blocked: Dictionary) -> Dictionary:
	var dist := {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell in frontier:
			for n in neighbors(cell):
				if dist.has(n) or blocked.has(n):
					continue
				dist[n] = int(dist[cell]) + 1
				next.append(n)
		frontier = next
	return dist
