# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends "res://tools/lowpoly_pieces.gd"
## The LowPoly tileset's natural wonders: one whole-tile model per wonder in Unciv's Civ V rulesets,
## and "NaturalWonder", an Everest-like massif, for wonders from mods that have no model here.
## Each one replaces the tile's terrain entirely (see tileset.gd).

const WONDERS := ["Great Barrier Reef", "Old Faithful", "El Dorado", "Fountain of Youth", "Grand Mesa",
	"Mount Fuji", "Krakatoa", "Rock of Gibraltar", "Cerro de Potosi", "Barringer Crater", "Mount Kailash",
	"Mount Sinai", "Sri Pada", "Uluru", "King Solomon's Mines", "Lake Victoria", "Mount Kilimanjaro"]

const SNOW := Color(0.9, 0.93, 0.97)
const SNOW_SHADE := Color(0.82, 0.87, 0.94)


func build_all() -> Dictionary:
	var out := super.build_all()
	out["NaturalWonder"] = everest()
	var makers := {
		"Great Barrier Reef": great_barrier_reef, "Old Faithful": old_faithful, "El Dorado": el_dorado,
		"Fountain of Youth": fountain_of_youth, "Grand Mesa": grand_mesa, "Mount Fuji": mount_fuji,
		"Krakatoa": krakatoa, "Rock of Gibraltar": rock_of_gibraltar, "Cerro de Potosi": cerro_de_potosi,
		"Barringer Crater": barringer_crater, "Mount Kailash": mount_kailash, "Mount Sinai": mount_sinai,
		"Sri Pada": sri_pada, "Uluru": uluru, "King Solomon's Mines": king_solomons_mines,
		"Lake Victoria": lake_victoria, "Mount Kilimanjaro": mount_kilimanjaro,
	}
	for wonder: String in WONDERS:
		out[wonder] = (makers[wonder] as Callable).call()
	return out


# region helpers -------------------------------------------------------------------------------

## A faceted mass built from stacked rings: [param rings] is [[radius fraction, height fraction], ...]
## from the foot up. A last ring of radius 0 makes a point; otherwise the top is a flat cap.
## [param color] is Callable(level 0..1, normal) -> Color. [param squash] flattens it along Z,
## [param lean] pushes the upper rings sideways (fraction of the radius at the top).
func _massif(at: Vector3, radius: float, height: float, rings: Array, color: Callable, sides := 7,
		jitter := 0.12, squash := 1.0, yaw := 0.0, lean := Vector2.ZERO, cap_color := Color.TRANSPARENT) -> void:
	var wobble: Array[float] = []
	for i in sides:
		wobble.append(1.0 + _rng.randf_range(-jitter, jitter))
	var start := _rng.randf() * TAU
	var stack: Array = []
	for k in rings.size():
		var rf: float = rings[k][0]
		var hf: float = rings[k][1]
		var ring: Array[Vector3] = []
		for i in sides:
			var a := start + TAU * (i + _rng.randf_range(-0.15, 0.15)) / sides
			var r := radius * rf * wobble[i] * (1.0 + _rng.randf_range(-jitter, jitter) * 0.4)
			var y := height * hf * (1.0 + (_rng.randf_range(-0.04, 0.04) if k > 0 and rf > 0.0 else 0.0))
			var local := Vector3(cos(a) * r, y, sin(a) * r * squash) + Vector3(lean.x, 0, lean.y) * radius * hf
			ring.append(at + local.rotated(Vector3.UP, yaw))
		stack.append(ring)
	var inside := at + (Vector3(lean.x, 0, lean.y) * radius * 0.35).rotated(Vector3.UP, yaw) + Vector3(0, height * 0.3, 0)
	for k in rings.size() - 1:
		var low: Array[Vector3] = stack[k]
		var high: Array[Vector3] = stack[k + 1]
		for i in sides:
			var j := (i + 1) % sides
			for t: Array in [[low[i], low[j], high[j]], [low[i], high[j], high[i]]]:
				_mass_tri(t[0], t[1], t[2], at.y, height, inside, color)
	var top: Array[Vector3] = stack[-1]
	if float(rings[-1][0]) > 0.0:
		var centre := Vector3.ZERO
		for v in top:
			centre += v
		centre /= top.size()
		for i in sides:
			_hint_up = true
			var c: Color = cap_color if cap_color.a > 0.0 else color.call(1.0, Vector3.UP)
			_tri(centre, top[i], top[(i + 1) % sides], _jit(c, 0.015))
	_hint_up = true


func _mass_tri(a: Vector3, b: Vector3, c: Vector3, base_y: float, height: float, inside: Vector3, color: Callable) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
	var level := (((a.y + b.y + c.y) / 3.0) - base_y) / height
	_hint_up = false
	_hint = inside
	_tri(a, b, c, color.call(level, n))
	_hint_up = true


## Colours for a mountain: [param low] near the foot, [param rock] in the middle, snow above
## [param snow_line] (with a ragged edge); faces turned away from the sun a little bluer in the snow.
func _alpine(low: Color, rock: Color, snow_line: float, foot := 0.18) -> Callable:
	return func(level: float, n: Vector3) -> Color:
		var ragged := level + (_rng.randf() - 0.5) * 0.12
		if ragged > snow_line:
			return _jit(SNOW if n.x + n.z > -0.75 else SNOW_SHADE, 0.015)
		if level < foot:
			return _jit(low, 0.025)
		return _jit(rock, 0.03)


func _ground_hex(colors: Array, side: Color, bump := 0.03, seed := 0) -> void:
	_hex_top(4, LAND, _bumpy(bump, seed), _picker(colors), side, false, seed)


## A plume of [param puffs] puffs, [param height] tall, drawn into the [param kind] surface so the game
## can animate it: "Steam" rises and loops, "Geyser" also erupts now and then, "Smoke" billows and drifts.
func _steam(at: Vector3, height: float, size: float, color := Color(0.93, 0.95, 0.97), kind := "Steam", puffs := 6) -> void:
	var before := _special
	_special = kind
	for i in puffs:
		var t := float(i) / puffs
		var drift := Vector3(_rng.randf_range(-0.03, 0.03), 0, _rng.randf_range(-0.03, 0.03)) * (1.0 + t * 3.0)
		var s := size * lerpf(0.45, 1.3, t)
		var centre := at + drift + Vector3(0, height * t, 0)
		_puff = {"centre": centre, "height": height, "t": t}
		_blob(centre, Vector3(s, s * 0.8, s), color.darkened(0.06 * t), 0.18, 0.02)
	_puff = {}
	_special = before


func acacia(at: Vector3, size: float) -> void:
	_frustum(at, 0.018 * size, 0.012 * size, 0.14 * size, 5, Color(0.42, 0.3, 0.2))
	_blob(at + Vector3(0, 0.16 * size, 0), Vector3(0.14, 0.03, 0.12) * size, Color(0.38, 0.5, 0.2), 0.2)


func shrine(at: Vector3, size: float, wall: Color, roof: Color, yaw := 0.0) -> void:
	_box(at + Vector3(0, 0.03 * size, 0), Vector3(0.07, 0.06, 0.06) * size, wall, yaw)
	_hint = at
	_cone(at + Vector3(0, 0.06 * size, 0), 0.055 * size, 0.045 * size, 4, roof)


# region the wonders ---------------------------------------------------------------------------

## A tall jagged massif with a main summit and two shoulders, deep in snow: any wonder without its own model.
func everest() -> ArrayMesh:
	_rng.seed = 2000
	_begin()
	_ground_hex([Color(0.55, 0.53, 0.5), Color(0.5, 0.49, 0.47), Color(0.6, 0.58, 0.55)], Color(0.42, 0.4, 0.37), 0.06)
	var colors := _alpine(Color(0.55, 0.53, 0.5), Color(0.52, 0.5, 0.5), 0.42)
	_massif(Vector3(0.38, LAND, 0.22), 0.42, 0.62, [[1, 0], [0.55, 0.5], [0, 1]], colors, 6, 0.18)
	_massif(Vector3(-0.4, LAND, 0.2), 0.4, 0.72, [[1, 0], [0.5, 0.55], [0, 1]], colors, 6, 0.18)
	_massif(Vector3(0.02, LAND, -0.12), 0.7, 1.3, [[1, 0], [0.62, 0.3], [0.34, 0.62], [0.12, 0.88], [0, 1]], colors, 7, 0.2, 1.0, 0.0, Vector2(0.08, 0.05))
	return _finish()


## Bright shallow water over coral heads: pink, orange, purple and yellow.
func great_barrier_reef() -> ArrayMesh:
	_rng.seed = 2010
	_begin()
	var waves := func(x: float, z: float) -> float:
		return COAST + (_hash01(Vector2(x, z), 40) - 0.5) * 0.008
	_hex_top(3, COAST, waves, _picker([Color(0.16, 0.6, 0.7), Color(0.19, 0.64, 0.73)]), WATER_SIDE, true)
	var corals := [Color(0.95, 0.45, 0.55), Color(0.98, 0.6, 0.3), Color(0.65, 0.4, 0.8), Color(0.95, 0.85, 0.35), Color(0.9, 0.35, 0.4)]
	for i in 30:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 0.72
		var at := Vector3(cos(a) * r, COAST - 0.01, sin(a) * r)
		var s := _rng.randf_range(0.05, 0.09)
		if i % 4 == 0:   # branching coral: a few little spikes
			for k in 3:
				_cone(at + Vector3(_rng.randf_range(-0.02, 0.02), 0, _rng.randf_range(-0.02, 0.02)), 0.015, s * 0.9, 4, corals[i % corals.size()])
		else:
			_blob(at + Vector3(0, s * 0.4, 0), Vector3(s, s * 0.55, s), corals[i % corals.size()], 0.25, 0.05)
	for p in _ring_spots(3, 0.3, 0.6):   # pale sandy shoals
		_patch(p + Vector3(0, COAST + 0.003, 0), 0.14, 7, Color(0.75, 0.88, 0.8), true, 0.3)
	return _finish()


## A geyser: a terraced orange-and-white mineral mound with a tall plume of steam, pines around.
func old_faithful() -> ArrayMesh:
	_rng.seed = 2020
	_begin()
	_ground_hex(PALETTE["Grassland"], SIDES["Grassland"])
	var terraces := func(level: float, _n: Vector3) -> Color:
		return _jit([Color(0.85, 0.6, 0.35), Color(0.92, 0.88, 0.8), Color(0.8, 0.5, 0.3)][int(level * 5.0) % 3], 0.02)
	_massif(Vector3(0, LAND, 0), 0.5, 0.14, [[1, 0], [0.75, 0.35], [0.5, 0.7], [0.25, 1]], terraces, 9, 0.08, 1.0, 0.0, Vector2.ZERO, Color(0.4, 0.68, 0.75))
	_special = "Shimmer"   # the hot pool at the top
	_patch(Vector3(0, LAND + 0.15, 0), 0.1, 7, Color(0.45, 0.8, 0.85), false, 0.15)
	_special = ""
	_steam(Vector3(0, LAND + 0.17, 0), 0.75, 0.11, Color(0.95, 0.97, 1.0), "Geyser", 9)
	for p in _ring_spots(5, 0.62, 0.8):
		conifer(p + Vector3(0, LAND, 0), 1.0, Color(0.15, 0.38, 0.2))
	return _finish()


## The lost city of gold: a stepped golden pyramid and gilded houses in the jungle, a pool.
func el_dorado() -> ArrayMesh:
	_rng.seed = 2030
	_begin()
	_ground_hex([Color(0.3, 0.56, 0.22), Color(0.26, 0.5, 0.2), Color(0.34, 0.6, 0.25)], SIDES["Grassland"])
	var gold := Color(0.95, 0.75, 0.25)
	var at := Vector3(0.05, LAND, -0.05)
	for k in 4:
		var w := 0.46 - k * 0.1
		_box(at + Vector3(0, 0.035 + k * 0.07, 0), Vector3(w, 0.07, w), gold.darkened(0.05 * (k % 2)), 0.3)
	_box(at + Vector3(0, 0.3, 0), Vector3(0.1, 0.06, 0.1), gold.lightened(0.15), 0.3)
	_special = "Sparkle"   # glints of gold
	for i in 6:
		var a := TAU * i / 6.0
		_blob(at + Vector3(cos(a) * 0.12, 0.36 + _rng.randf() * 0.05, sin(a) * 0.12), Vector3(0.012, 0.012, 0.012), Color(1.0, 0.95, 0.6), 0.1)
	_special = ""
	for i in 3:
		var a := TAU * i / 3.0 + 1.2
		_box(Vector3(cos(a), 0, sin(a)) * 0.52 + Vector3(0, LAND + 0.04, 0), Vector3(0.1, 0.08, 0.1), gold.darkened(0.1), a)
	_patch(Vector3(-0.15, LAND + 0.01, 0.45), 0.14, 4, Color(0.3, 0.65, 0.7), true, 0.05, 1.0, 0.3)
	for p in _ring_spots(6, 0.66, 0.82):
		palm(p + Vector3(0, LAND, 0), 1.1, Color(0.22, 0.55, 0.18))
	return _finish()


## A round stone basin of glowing turquoise water with a little spout, flowers and old trees.
func fountain_of_youth() -> ArrayMesh:
	_rng.seed = 2040
	_begin()
	_ground_hex(PALETTE["Plains"], SIDES["Plains"])
	_frustum(Vector3(0, LAND, 0), 0.42, 0.4, 0.06, 10, Color(0.75, 0.72, 0.66), Color(0.7, 0.67, 0.6))
	_special = "Shimmer"
	_patch(Vector3(0, LAND + 0.065, 0), 0.33, 10, Color(0.4, 0.95, 0.95), false, 0.02)
	_special = ""
	_frustum(Vector3(0, LAND + 0.06, 0), 0.05, 0.035, 0.12, 6, Color(0.8, 0.78, 0.72), Color(0.82, 0.8, 0.75))
	_steam(Vector3(0, LAND + 0.18, 0), 0.12, 0.03, Color(0.75, 0.97, 1.0), "Steam", 5)
	_special = "Sparkle"
	for i in 8:   # sparkles over the water
		var a := _rng.randf() * TAU
		_blob(Vector3(cos(a) * 0.25, LAND + 0.12 + _rng.randf() * 0.12, sin(a) * 0.25), Vector3(0.01, 0.01, 0.01), Color(0.9, 1.0, 1.0), 0.1)
	_special = ""
	for p in _ring_spots(9, 0.55, 0.8):
		_blob(p + Vector3(0, LAND + 0.02, 0), Vector3(0.02, 0.02, 0.02), [Color(0.95, 0.5, 0.7), Color(0.95, 0.95, 0.95), Color(0.95, 0.85, 0.3), Color(0.6, 0.5, 0.9)][_rng.randi() % 4], 0.1)
	for p in _ring_spots(3, 0.62, 0.78):
		broadleaf(p + Vector3(0, LAND, 0), 1.4, Color(0.25, 0.5, 0.22))
	return _finish()


## A great flat-topped mesa: sheer walls in red and orange layers, scrub on the top.
func grand_mesa() -> ArrayMesh:
	_rng.seed = 2050
	_begin()
	_ground_hex(PALETTE["Desert"], SIDES["Desert"])
	var strata := func(level: float, _n: Vector3) -> Color:
		return _jit([Color(0.72, 0.38, 0.25), Color(0.82, 0.52, 0.32), Color(0.65, 0.32, 0.22), Color(0.88, 0.62, 0.4)][int(level * 7.0) % 4], 0.02)
	_massif(Vector3(0, LAND, 0), 0.76, 0.42, [[1, 0], [0.86, 0.12], [0.82, 0.3], [0.8, 0.55], [0.78, 0.8], [0.74, 1]], strata, 9, 0.12, 1.0, 0.0, Vector2.ZERO, Color(0.55, 0.58, 0.3))
	for p in _ring_spots(5, 0.15, 0.5):
		_blob(p + Vector3(0, LAND + 0.44, 0), Vector3(0.05, 0.03, 0.05), Color(0.4, 0.5, 0.22), 0.25)
	for p in _ring_spots(3, 0.78, 0.84):
		rock(p + Vector3(0, LAND, 0), 0.05, Color(0.75, 0.42, 0.28))
	return _finish()


## The classic volcano: a broad symmetric cone with a wide snow cap and a small crater.
func mount_fuji() -> ArrayMesh:
	_rng.seed = 2060
	_begin()
	_ground_hex(PALETTE["Grassland"], SIDES["Grassland"])
	var colors := _alpine(Color(0.38, 0.55, 0.3), Color(0.55, 0.5, 0.54), 0.5, 0.12)
	_massif(Vector3(0, LAND, 0), 0.82, 0.95, [[1, 0], [0.62, 0.22], [0.38, 0.52], [0.2, 0.84], [0.13, 1]], colors, 10, 0.05, 1.0, 0.0, Vector2.ZERO, Color(0.5, 0.48, 0.5))
	for p in _ring_spots(4, 0.74, 0.84):
		broadleaf(p + Vector3(0, LAND, 0), 0.9, Color(0.85, 0.55, 0.65))   # cherry blossom
	return _finish()


## A volcanic island in the open sea: dark slopes, a glowing crater and a column of smoke.
func krakatoa() -> ArrayMesh:
	_rng.seed = 2070
	_begin()
	var waves := func(x: float, z: float) -> float:
		return OCEAN + (_hash01(Vector2(x, z), 41) - 0.5) * 0.01
	_hex_top(3, OCEAN, waves, _picker([Color(0.12, 0.3, 0.56), Color(0.14, 0.33, 0.6)]), WATER_SIDE, true)
	_slab(Vector3(0, OCEAN - 0.01, 0), 0.72, 9, 0.03, Color(0.3, 0.27, 0.25), Color(0.25, 0.22, 0.2), 0.15)
	var colors := func(level: float, _n: Vector3) -> Color:
		if level < 0.25:
			return _jit(Color(0.25, 0.42, 0.22), 0.03)   # a green fringe
		return _jit([Color(0.28, 0.24, 0.24), Color(0.34, 0.28, 0.26)][_rng.randi() % 2], 0.02)
	_massif(Vector3(-0.05, OCEAN + 0.02, 0.05), 0.62, 0.72, [[1, 0], [0.6, 0.35], [0.3, 0.8], [0.2, 1]], colors, 8, 0.15, 1.0, 0.0, Vector2(0.1, -0.05), Color(0.2, 0.15, 0.14))
	_special = "Lava"
	_patch(Vector3(0.0, OCEAN + 0.75, 0.02), 0.09, 7, Color(1.0, 0.45, 0.1), false, 0.2)
	for i in 4:   # lava running down one side
		var t := float(i) / 4.0
		_blob(Vector3(0.05 + t * 0.12, OCEAN + 0.7 - t * 0.35, 0.05 + t * 0.2), Vector3(0.03, 0.015, 0.03), Color(1.0, 0.35 + t * 0.1, 0.05), 0.2)
	_special = ""
	_steam(Vector3(0.02, OCEAN + 0.78, 0.0), 0.7, 0.13, Color(0.55, 0.53, 0.52), "Smoke", 8)
	return _finish()


## A long limestone ridge with one sheer cliff face and scrub on its gentle back.
func rock_of_gibraltar() -> ArrayMesh:
	_rng.seed = 2080
	_begin()
	_ground_hex(PALETTE["Grassland"], SIDES["Grassland"])
	var colors := func(level: float, n: Vector3) -> Color:
		if n.y > 0.55 and level > 0.2:
			return _jit(Color(0.42, 0.55, 0.3), 0.03)   # scrub on the gentle slopes
		return _jit([Color(0.85, 0.83, 0.76), Color(0.78, 0.76, 0.7)][_rng.randi() % 2], 0.02)
	_massif(Vector3(0.05, LAND, 0), 0.75, 0.7, [[1, 0], [0.72, 0.3], [0.4, 0.7], [0.12, 1]], colors, 8, 0.12, 0.42, 0.5, Vector2(0.25, 0))
	return _finish()


## A reddish mountain riddled with silver: pale streaks of ore and little mine entrances at its foot.
func cerro_de_potosi() -> ArrayMesh:
	_rng.seed = 2090
	_begin()
	_ground_hex(PALETTE["Plains"], SIDES["Plains"])
	var colors := func(level: float, _n: Vector3) -> Color:
		if _rng.randf() < 0.18 and level > 0.15:
			return _jit(Color(0.82, 0.84, 0.88), 0.02)   # silver
		return _jit([Color(0.62, 0.36, 0.25), Color(0.7, 0.42, 0.28), Color(0.55, 0.32, 0.24)][_rng.randi() % 3], 0.02)
	_massif(Vector3(0, LAND, 0), 0.72, 0.85, [[1, 0], [0.65, 0.3], [0.35, 0.65], [0.12, 0.95], [0, 1]], colors, 8, 0.12)
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var at := Vector3(cos(a), 0, sin(a)) * 0.66 + Vector3(0, LAND, 0)
		_box(at + Vector3(0, 0.035, 0), Vector3(0.06, 0.07, 0.03), Color(0.08, 0.06, 0.05), -a + PI / 2.0)
		_box(at + Vector3(0, 0.075, 0), Vector3(0.09, 0.015, 0.035), Color(0.5, 0.35, 0.2), -a + PI / 2.0)
	return _finish()


## A great round crater in the desert: a raised rim and a deep bowl.
func barringer_crater() -> ArrayMesh:
	_rng.seed = 2100
	_begin()
	var height := func(x: float, z: float) -> float:
		var r := Vector2(x, z).length()
		var rim := 0.12 * exp(-pow((r - 0.56) / 0.12, 2.0))
		var bowl := -0.1 * clampf(1.0 - r / 0.5, 0.0, 1.0)
		return LAND + rim + bowl * 0.9 + (_hash01(Vector2(x, z), 50) - 0.5) * 0.015
	var color := func(centre: Vector3, n: Vector3) -> Color:
		var r := Vector2(centre.x, centre.z).length()
		if r < 0.48:
			return _jit(Color(0.72, 0.58, 0.42) if n.y > 0.85 else Color(0.62, 0.48, 0.35), 0.02)
		return _jit(PALETTE["Desert"][int(_hash01(Vector2(centre.x, centre.z), 9) * 3)], 0.02)
	_hex_top(6, LAND, height, color, SIDES["Desert"])
	for p in _ring_spots(6, 0.62, 0.8):
		rock(p + Vector3(0, LAND + 0.01, 0), 0.04, Color(0.6, 0.5, 0.4))
	return _finish()


## The four-faced holy peak: a pyramid ringed with bands of snow.
func mount_kailash() -> ArrayMesh:
	_rng.seed = 2110
	_begin()
	_ground_hex(PALETTE["Plains"], SIDES["Plains"])
	var colors := func(level: float, n: Vector3) -> Color:
		if level > 0.62 or (level > 0.3 and int(level * 9.0) % 2 == 0):
			return _jit(SNOW if n.x + n.z > -0.75 else SNOW_SHADE, 0.015)
		return _jit(Color(0.5, 0.4, 0.35) if level > 0.12 else Color(0.55, 0.52, 0.32), 0.02)
	_massif(Vector3(0, LAND, 0), 0.68, 1.0, [[1, 0], [0.8, 0.12], [0.62, 0.3], [0.45, 0.48], [0.28, 0.66], [0.12, 0.84], [0, 1]], colors, 4, 0.04, 1.0, PI / 4.0)
	# prayer flags strung across the foot
	for i in 7:
		var t := float(i) / 6.0
		_box(Vector3(-0.6 + t * 0.4, LAND + 0.06 - sin(t * PI) * 0.02, 0.58 - t * 0.1), Vector3(0.02, 0.025, 0.004), [Color(0.2, 0.4, 0.85), Color(0.95, 0.95, 0.95), Color(0.85, 0.2, 0.2), Color(0.2, 0.65, 0.3), Color(0.95, 0.8, 0.2)][i % 5], 0.25)
	return _finish()


## Rugged red-granite peaks with a small white chapel on the highest one.
func mount_sinai() -> ArrayMesh:
	_rng.seed = 2120
	_begin()
	_ground_hex(PALETTE["Desert"], SIDES["Desert"])
	var colors := func(level: float, _n: Vector3) -> Color:
		return _jit([Color(0.66, 0.36, 0.28), Color(0.58, 0.32, 0.26), Color(0.74, 0.45, 0.32)][_rng.randi() % 3], 0.02)
	_massif(Vector3(0.38, LAND, 0.25), 0.35, 0.42, [[1, 0], [0.5, 0.6], [0, 1]], colors, 5, 0.25)
	_massif(Vector3(-0.35, LAND, 0.3), 0.32, 0.36, [[1, 0], [0.45, 0.6], [0, 1]], colors, 5, 0.25)
	_massif(Vector3(0.0, LAND, -0.1), 0.6, 0.72, [[1, 0], [0.62, 0.38], [0.3, 0.78], [0.16, 1]], colors, 6, 0.2, 1.0, 0.0, Vector2.ZERO, Color(0.6, 0.35, 0.28))
	var top := Vector3(0.0, LAND + 0.72, -0.1)
	shrine(top, 1.0, Color(0.95, 0.93, 0.88), Color(0.55, 0.35, 0.25))
	return _finish()


## A steep green peak with a small white temple on its summit and a path winding up.
func sri_pada() -> ArrayMesh:
	_rng.seed = 2130
	_begin()
	_ground_hex([Color(0.3, 0.55, 0.22), Color(0.34, 0.6, 0.25)], SIDES["Grassland"])
	var colors := func(level: float, _n: Vector3) -> Color:
		if level > 0.8:
			return _jit(Color(0.55, 0.5, 0.45), 0.02)
		return _jit([Color(0.3, 0.58, 0.24), Color(0.36, 0.62, 0.27), Color(0.27, 0.52, 0.22)][_rng.randi() % 3], 0.025)
	_massif(Vector3(0, LAND, 0), 0.62, 1.05, [[1, 0], [0.6, 0.25], [0.32, 0.6], [0.14, 0.92], [0.08, 1]], colors, 8, 0.1, 1.0, 0.0, Vector2.ZERO, Color(0.6, 0.55, 0.5))
	shrine(Vector3(0, LAND + 1.05, 0), 1.0, Color(0.97, 0.96, 0.93), Color(0.85, 0.6, 0.25))
	for i in 10:   # lanterns along the pilgrims' path
		var t := float(i) / 10.0
		var a := t * TAU * 1.2
		var r := lerpf(0.6, 0.1, t)
		_special = "Sparkle"
		_blob(Vector3(cos(a) * r, LAND + t * 1.0 + 0.03, sin(a) * r), Vector3(0.012, 0.012, 0.012), Color(1.0, 0.85, 0.4), 0.1)
		_special = ""
	for p in _ring_spots(5, 0.64, 0.82):
		broadleaf(p + Vector3(0, LAND, 0), 1.0, Color(0.2, 0.48, 0.18))
	return _finish()


## The great red monolith: a long, rounded dome glowing orange, in red sand with spinifex.
func uluru() -> ArrayMesh:
	_rng.seed = 2140
	_begin()
	_ground_hex([Color(0.82, 0.55, 0.35), Color(0.76, 0.5, 0.32), Color(0.85, 0.62, 0.4)], Color(0.62, 0.38, 0.25))
	var colors := func(level: float, n: Vector3) -> Color:
		var c := Color(0.86, 0.38, 0.18) if n.y > 0.4 else Color(0.74, 0.3, 0.16)
		if level < 0.15:
			c = c.darkened(0.12)
		return _jit(c, 0.025)
	_massif(Vector3(0, LAND, 0), 0.72, 0.38, [[1, 0], [0.96, 0.3], [0.86, 0.62], [0.66, 0.88], [0.4, 1]], colors, 10, 0.06, 0.55, 0.35, Vector2.ZERO, Color(0.88, 0.42, 0.2))
	for p in _ring_spots(6, 0.68, 0.84):
		_blob(p + Vector3(0, LAND + 0.02, 0), Vector3(0.04, 0.025, 0.04), Color(0.6, 0.6, 0.3), 0.3)
	return _finish()


## Rocky hills honeycombed with mine shafts, gold showing in the rock, a cart of ore.
func king_solomons_mines() -> ArrayMesh:
	_rng.seed = 2150
	_begin()
	_ground_hex(PALETTE["Desert"], SIDES["Desert"])
	var colors := func(_level: float, _n: Vector3) -> Color:
		if _rng.randf() < 0.12:
			return _jit(Color(0.95, 0.78, 0.3), 0.02)   # gold seams
		return _jit([Color(0.62, 0.5, 0.38), Color(0.55, 0.44, 0.34), Color(0.68, 0.56, 0.42)][_rng.randi() % 3], 0.02)
	_massif(Vector3(-0.2, LAND, -0.15), 0.48, 0.42, [[1, 0], [0.6, 0.5], [0.25, 0.9], [0.1, 1]], colors, 7, 0.2)
	_massif(Vector3(0.32, LAND, -0.25), 0.36, 0.3, [[1, 0], [0.55, 0.55], [0.15, 1]], colors, 6, 0.2)
	for at: Vector3 in [Vector3(-0.2, LAND, 0.32), Vector3(0.3, LAND, 0.12)]:
		_box(at + Vector3(0, 0.045, 0), Vector3(0.08, 0.09, 0.03), Color(0.07, 0.05, 0.04))
		for s: float in [-1.0, 1.0]:
			_box(at + Vector3(s * 0.045, 0.05, 0.01), Vector3(0.015, 0.1, 0.015), Color(0.5, 0.35, 0.2))
		_box(at + Vector3(0, 0.1, 0.01), Vector3(0.11, 0.015, 0.02), Color(0.5, 0.35, 0.2))
	_box(Vector3(0.05, LAND + 0.03, 0.5), Vector3(0.09, 0.04, 0.06), Color(0.45, 0.32, 0.2), 0.3)
	_special = "Glow"
	for i in 5:
		_blob(Vector3(0.05 + _rng.randf_range(-0.03, 0.03), LAND + 0.06, 0.5 + _rng.randf_range(-0.02, 0.02)), Vector3(0.015, 0.012, 0.015), [Color(1.0, 0.85, 0.3), Color(0.4, 0.9, 0.5), Color(0.9, 0.3, 0.4)][i % 3], 0.2)
	_special = ""
	return _finish()


## A great lake almost filling the tile: green banks, wooded islands and papyrus.
func lake_victoria() -> ArrayMesh:
	_rng.seed = 2160
	_begin()
	var height := func(x: float, z: float) -> float:
		var r := Vector2(x, z).length()
		return LAKE - 0.02 if r < 0.62 else LAND
	var color := func(centre: Vector3, _n: Vector3) -> Color:
		return _jit(PALETTE["Plains"][int(_hash01(Vector2(centre.x, centre.z), 3) * 3)], 0.02)
	_hex_top(5, LAND, height, color, SIDES["Plains"])
	_patch(Vector3(0, LAKE + 0.01, 0), 0.68, 12, Color(0.18, 0.52, 0.55), true, 0.06)
	for at: Vector3 in [Vector3(0.12, 0, -0.1), Vector3(-0.28, 0, 0.18)]:
		_slab(at + Vector3(0, LAKE, 0), 0.12, 7, 0.03, Color(0.4, 0.58, 0.28), Color(0.5, 0.42, 0.28), 0.25)
		broadleaf(at + Vector3(0, LAKE + 0.03, 0), 1.0, Color(0.22, 0.48, 0.2))
	for p in _ring_spots(7, 0.62, 0.72):
		reeds(p + Vector3(0, LAKE + 0.01, 0), 1.2)
	return _finish()


## Africa's broad giant: a gentle massif with a wide flat snowy summit, savannah and acacias below.
func mount_kilimanjaro() -> ArrayMesh:
	_rng.seed = 2170
	_begin()
	_ground_hex([Color(0.68, 0.64, 0.34), Color(0.62, 0.6, 0.3), Color(0.72, 0.68, 0.38)], SIDES["Plains"])
	var colors := _alpine(Color(0.45, 0.56, 0.3), Color(0.58, 0.5, 0.44), 0.68, 0.2)
	_massif(Vector3(0.0, LAND, -0.05), 0.82, 0.82, [[1, 0], [0.75, 0.25], [0.52, 0.6], [0.38, 0.9], [0.32, 1]], colors, 9, 0.1, 1.0, 0.0, Vector2.ZERO, SNOW)
	for p in _ring_spots(4, 0.74, 0.84):
		acacia(p + Vector3(0, LAND, 0), 1.4)
	return _finish()
