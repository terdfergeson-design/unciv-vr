# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Builds the pieces of the "LowPoly" tileset: faceted, flat-shaded models with one colour per
## triangle, in the same style as the low-poly mountains background.
##
## Conventions every tileset piece follows (see tilesets/README.md):
##   - map units: a hex has circumradius 1; tiles are drawn with corners at HEX_RADIUS (0.97)
##   - flat-topped hexes, first corner on +X, Y up, origin at the hex centre at table level
##   - land tiles have their top edge at LAND (0.15) so neighbours always meet; anything inside
##     the edge can rise or dip freely

const HEX_RADIUS := 0.97
const LAND := 0.15
const OCEAN := 0.03
const COAST := 0.06
const LAKE := 0.07

var _rng := RandomNumberGenerator.new()
var _surfaces := {}            # material name -> {st: SurfaceTool, count: int}, for the piece being built
var _special := ""             # while set, _tri() draws into this named surface ("Glow", "Steam", "Lava"...)
var _puff := {}                # while set: {centre, height, t}, written into UV / UV2 / alpha for the puff shaders
var _hint := Vector3.ZERO      # triangles face away from this point (props) ...
var _hint_up := true           # ... or straight up (ground)
## true: build the simpler "-Far" versions (fewer facets and props) used when much of the map is on the table
var far := false

## Surfaces the game animates (see scripts/tileset_shaders.gd); everything else is drawn as it is.
const UNSHADED := ["Glow", "Lava", "Sparkle", "Shimmer"]
const ORDER := ["Ground", "Water", "Glow", "Lava", "Sparkle", "Shimmer", "Steam", "Geyser", "Smoke"]


# region building blocks --------------------------------------------------------------------

func _begin() -> void:
	_surfaces = {}
	_special = ""
	_puff = {}


func _finish() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface_name: String in ORDER:
		if not _surfaces.has(surface_name):
			continue
		var entry: Dictionary = _surfaces[surface_name]
		(entry["st"] as SurfaceTool).commit(mesh)
		var index := mesh.get_surface_count() - 1
		mesh.surface_set_material(index, material_for(surface_name))
		mesh.surface_set_name(index, surface_name)
	return mesh


func _surface(surface_name: String) -> SurfaceTool:
	if not _surfaces.has(surface_name):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[surface_name] = {"st": st, "count": 0}
	_surfaces[surface_name]["count"] += 1
	return _surfaces[surface_name]["st"]


## The material each surface is saved with. The names matter: the game swaps Steam, Geyser, Smoke,
## Lava, Sparkle and Shimmer for animated shaders; other programs just show the still version.
static func material_for(surface_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = surface_name
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match surface_name:
		"Water":
			m.roughness = 0.45
			m.metallic_specular = 0.4
		"Ground":
			m.roughness = 0.92
		"Steam", "Geyser", "Smoke":
			m.roughness = 1.0
		_:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # exported as KHR_materials_unlit
	return m


## One flat-coloured triangle, facing up (ground) or away from _hint (props).
func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color, water := false) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var outward := Vector3.UP if _hint_up else ((a + b + c) / 3.0 - _hint)
	if n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	# Facets turned away from the light get a touch darker, so the shape reads even in flat light
	var surface_name := _special if _special != "" else ("Water" if water else "Ground")
	var shaded := color if surface_name in UNSHADED else color.darkened(0.10 * (1.0 - clampf(n.y, 0.0, 1.0)))
	var linear := shaded.srgb_to_linear()   # glTF vertex colours are linear
	var st := _surface(surface_name)
	if not _puff.is_empty():
		# A puff of steam or smoke: its centre in UV (x, z) and UV2.x, the plume's height in UV2.y,
		# and how far up the plume it is (0..1) in the colour's alpha
		var centre: Vector3 = _puff["centre"]
		linear.a = float(_puff["t"])
		for v: Vector3 in [a, c, b]:
			st.set_normal(n)
			st.set_color(linear)
			st.set_uv(Vector2(centre.x, centre.z))
			st.set_uv2(Vector2(centre.y, float(_puff["height"])))
			st.add_vertex(v)
		return
	for v: Vector3 in [a, c, b]:   # Godot's front faces wind clockwise
		st.set_normal(n)
		st.set_color(linear)
		st.add_vertex(v)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, water := false) -> void:
	_tri(a, b, c, color, water)
	_tri(a, c, d, color, water)


static func corner(i: int, radius := HEX_RADIUS) -> Vector3:
	var angle := deg_to_rad(60.0 * i)
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)


func _jit(c: Color, amount := 0.04) -> Color:
	return Color(clampf(c.r + _rng.randf_range(-amount, amount), 0, 1),
		clampf(c.g + _rng.randf_range(-amount, amount), 0, 1),
		clampf(c.b + _rng.randf_range(-amount, amount), 0, 1))


## A stable pseudo-random number for a point (so shared lattice points jitter the same way).
static func _hash01(p: Vector2, salt: int) -> float:
	var h := sin(p.x * 127.1 + p.y * 311.7 + float(salt) * 74.7) * 43758.5453
	return h - floor(h)


## The hexagonal top of a tile, cut into n*n*6 triangles. [param height] (Callable(x, z) -> y) shapes
## the inside; the rim always stays at [param edge]. [param color] is Callable(centre: Vector3,
## normal: Vector3) -> Color. Then the tile's sides, down to the table, in [param side].
func _hex_top(n: int, edge: float, height: Callable, color: Callable, side: Color, water := false, seed := 0) -> void:
	if far:
		n = mini(n, 3 if n >= 5 else 2)
	_hint_up = true
	var points := {}   # lattice point key -> Vector3, shared by neighbouring sectors
	for s in 6:
		var b := corner(s)
		var c := corner(s + 1)
		var grid := {}
		for i in n + 1:
			for j in n + 1 - i:
				var p := (b * i + c * j) / float(n)
				var key := Vector2i(roundi(p.x * 1000), roundi(p.z * 1000))
				if not points.has(key):
					var on_rim := i + j == n
					var q := Vector2(p.x, p.z)
					if not on_rim and (i + j) > 0:
						q += Vector2(_hash01(q, seed) - 0.5, _hash01(q, seed + 7) - 0.5) * (0.5 * HEX_RADIUS / n)
					var y: float = edge if on_rim else float(height.call(q.x, q.y))
					points[key] = Vector3(q.x, y, q.y)
				grid[Vector2i(i, j)] = points[key]
		for i in n:
			for j in n - i:
				var p0: Vector3 = grid[Vector2i(i, j)]
				var p1: Vector3 = grid[Vector2i(i + 1, j)]
				var p2: Vector3 = grid[Vector2i(i, j + 1)]
				_top_tri(p0, p1, p2, color, water)
				if i + j < n - 1:
					var p3: Vector3 = grid[Vector2i(i + 1, j + 1)]
					_top_tri(p1, p3, p2, color, water)
	for s in 6:
		var a := corner(s)
		var b := corner(s + 1)
		var tone := side.darkened(0.06 * (s % 3))
		_quad(a, b, b + Vector3(0, edge, 0), a + Vector3(0, edge, 0), tone, water)


func _top_tri(a: Vector3, b: Vector3, c: Vector3, color: Callable, water: bool) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0:
		n = -n
	_tri(a, b, c, color.call((a + b + c) / 3.0, n), water)


## A flat-shaded cone or pyramid: [param sides] faces, base centre [param at].
func _cone(at: Vector3, radius: float, height: float, sides: int, color: Color, jitter := 0.0, base_cap := false) -> void:
	_hint_up = false
	_hint = at + Vector3(0, height * 0.3, 0)
	var apex := at + Vector3(_rng.randf_range(-jitter, jitter) * radius, height, _rng.randf_range(-jitter, jitter) * radius)
	var start := _rng.randf() * TAU
	var ring: Array[Vector3] = []
	for i in sides:
		var a := start + TAU * i / sides
		ring.append(at + Vector3(cos(a), 0, sin(a)) * radius * (1.0 + _rng.randf_range(-jitter, jitter)))
	for i in sides:
		_tri(ring[i], ring[(i + 1) % sides], apex, _jit(color, 0.02))
	if base_cap:
		for i in sides:
			_tri(ring[i], ring[(i + 1) % sides], at, color.darkened(0.3))
	_hint_up = true


## A frustum (a cone with its top cut off).
func _frustum(at: Vector3, bottom: float, top: float, height: float, sides: int, color: Color, cap_color := Color.TRANSPARENT) -> void:
	_hint_up = false
	_hint = at + Vector3(0, height * 0.5, 0)
	var start := _rng.randf() * TAU
	for i in sides:
		var a0 := start + TAU * i / sides
		var a1 := start + TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(at + d0 * bottom, at + d1 * bottom, at + d1 * top + Vector3(0, height, 0), at + d0 * top + Vector3(0, height, 0), _jit(color, 0.02))
		if cap_color.a > 0.0:
			_tri(at + Vector3(0, height, 0), at + d0 * top + Vector3(0, height, 0), at + d1 * top + Vector3(0, height, 0), cap_color)
	_hint_up = true


func _box(center: Vector3, size: Vector3, color: Color, yaw := 0.0) -> void:
	_hint_up = false
	_hint = center
	var basis := Basis(Vector3.UP, yaw)
	var h := size / 2.0
	var v: Array[Vector3] = []
	for i in 8:
		var local := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		v.append(center + basis * local)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f: Array in faces:
		_quad(v[f[0]], v[f[1]], v[f[2]], v[f[3]], color)
	_hint_up = true


## A lumpy low-poly blob (an icosahedron with its corners pushed about): rocks, bushes, tree crowns.
func _blob(center: Vector3, size: Vector3, color: Color, lumpiness := 0.2, color_spread := 0.03, water := false) -> void:
	_hint_up = false
	_hint = center
	var t := (1.0 + sqrt(5.0)) / 2.0
	var raw := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var basis := Basis(Vector3.UP, _rng.randf() * TAU)
	var v: Array[Vector3] = []
	for p: Vector3 in raw:
		var d := p.normalized() * (1.0 + _rng.randf_range(-lumpiness, lumpiness))
		v.append(center + basis * (d * size))
	for f: Array in faces:
		_tri(v[f[0]], v[f[1]], v[f[2]], _jit(color, color_spread), water)
	_hint_up = true


## A flat irregular polygon lying at height [param y] (puddles, fields, sand bars, ice floes...).
func _patch(center: Vector3, radius: float, sides: int, color: Color, water := false, irregular := 0.3, squash := 1.0, yaw := 0.0) -> Array[Vector3]:
	_hint_up = true
	var ring: Array[Vector3] = []
	var start := yaw
	for i in sides:
		var a := start + TAU * i / sides
		var r := radius * (1.0 + _rng.randf_range(-irregular, irregular))
		var d := Vector3(cos(a) * r, 0, sin(a) * r * squash).rotated(Vector3.UP, yaw)
		ring.append(center + d)
	for i in sides:
		_tri(center, ring[i], ring[(i + 1) % sides], _jit(color, 0.015), water)
	return ring


## A thin slab with sides: an ice floe, a sand bar, a field.
func _slab(center: Vector3, radius: float, sides: int, thickness: float, top: Color, side: Color, irregular := 0.3, squash := 1.0, yaw := 0.0, water := false) -> void:
	var ring := _patch(center + Vector3(0, thickness, 0), radius, sides, top, water, irregular, squash, yaw)
	_hint_up = false
	_hint = center + Vector3(0, -1.0, 0)
	for i in sides:
		var a := ring[i]
		var b := ring[(i + 1) % sides]
		_hint = center + Vector3(0, thickness * 0.5, 0)
		_quad(a, b, b - Vector3(0, thickness + 0.01, 0), a - Vector3(0, thickness + 0.01, 0), side, water)
	_hint_up = true


## Spots in the outer part of the hex, leaving the middle clear for unit tokens.
func _ring_spots(count: int, inner := 0.45, outer := 0.78, seed := 0) -> Array[Vector3]:
	if far:
		count = maxi(1, int(ceil(count / 2.5)))
	var spots: Array[Vector3] = []
	var start := _rng.randf() * TAU
	for i in count:
		var a := start + TAU * (i + _rng.randf_range(-0.25, 0.25)) / count
		var r := _rng.randf_range(inner, outer)
		# keep inside the hexagon (its sides are at 0.866 of the corner distance)
		var hex_limit := 0.866 * HEX_RADIUS / cos(fposmod(a, PI / 3.0) - PI / 6.0)
		spots.append(Vector3(cos(a), 0, sin(a)) * minf(r, hex_limit - 0.12))
	return spots


# region trees and plants -------------------------------------------------------------------

func conifer(at: Vector3, size: float, color: Color, snowy := false) -> void:
	_frustum(at, 0.025 * size, 0.02 * size, 0.07 * size, 4, Color(0.4, 0.27, 0.16))
	_cone(at + Vector3(0, 0.05 * size, 0), 0.14 * size, 0.2 * size, 6, color, 0.12, true)
	var top := Color(0.93, 0.95, 0.98) if snowy else color.lightened(0.08)
	_cone(at + Vector3(0, 0.16 * size, 0), 0.1 * size, 0.18 * size, 6, top, 0.12, true)


func broadleaf(at: Vector3, size: float, color: Color) -> void:
	_frustum(at, 0.025 * size, 0.018 * size, 0.12 * size, 5, Color(0.42, 0.3, 0.18))
	_blob(at + Vector3(0, 0.2 * size, 0), Vector3(0.13, 0.11, 0.13) * size, color, 0.22, 0.04)


func palm(at: Vector3, size: float, color: Color) -> void:
	var lean := Vector3(_rng.randf_range(-0.04, 0.04), 0, _rng.randf_range(-0.04, 0.04)) * size
	var top := at + Vector3(0, 0.26 * size, 0) + lean
	# a slightly bent trunk in two pieces
	_hint_up = false
	var mid := at + Vector3(0, 0.13 * size, 0) + lean * 0.35
	_trunk(at, mid, 0.022 * size, Color(0.5, 0.36, 0.22))
	_trunk(mid, top, 0.018 * size, Color(0.55, 0.4, 0.24))
	# fronds: drooping leaves
	var count := 6
	var start := _rng.randf() * TAU
	for i in count:
		var a := start + TAU * i / count
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP) * 0.035 * size
		var mid_leaf := top + dir * 0.09 * size + Vector3(0, 0.025 * size, 0)
		var tip := top + dir * 0.17 * size + Vector3(0, -0.05 * size, 0)
		_hint_up = true
		_tri(top, mid_leaf + side, mid_leaf - side, _jit(color, 0.03))
		_tri(mid_leaf + side, tip, mid_leaf - side, _jit(color.darkened(0.08), 0.03))
	_hint_up = false
	_hint = top
	_blob(top + Vector3(0, 0.005, 0), Vector3(0.025, 0.02, 0.025) * size, Color(0.45, 0.32, 0.15), 0.1)
	_hint_up = true


func _trunk(from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var axis := (to - from).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP)
	u = Vector3.RIGHT if u.length_squared() < 1e-6 else u.normalized()
	var w := axis.cross(u).normalized()
	_hint_up = false
	_hint = (from + to) / 2.0
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * (i + 1) / 5.0
		var d0 := (u * cos(a0) + w * sin(a0)) * radius
		var d1 := (u * cos(a1) + w * sin(a1)) * radius
		_quad(from + d0, from + d1, to + d1 * 0.8, to + d0 * 0.8, color)
	_hint_up = true


func tuft(at: Vector3, size: float, color: Color) -> void:
	if far:
		return
	_hint_up = false
	for i in 3:
		var a := _rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var side := d.cross(Vector3.UP) * 0.012 * size
		var tip := at + d * 0.03 * size + Vector3(0, 0.07 * size * _rng.randf_range(0.7, 1.2), 0)
		_hint = at - d
		_tri(at - side, at + side, tip, _jit(color, 0.04))
	_hint_up = true


func reeds(at: Vector3, size: float) -> void:
	_hint_up = false
	for i in 5:
		var a := _rng.randf() * TAU
		var base := at + Vector3(cos(a), 0, sin(a)) * 0.03 * size
		var side := Vector3(cos(a + 1.6), 0, sin(a + 1.6)) * 0.008 * size
		var tip := base + Vector3(_rng.randf_range(-0.02, 0.02), 0.14 * size * _rng.randf_range(0.7, 1.1), _rng.randf_range(-0.02, 0.02))
		_hint = base + Vector3(cos(a), 0, sin(a)) * -0.1
		_tri(base - side, base + side, tip, _jit(Color(0.45, 0.55, 0.25), 0.05))
		if i % 2 == 0:   # a cattail head
			_box(tip + Vector3(0, -0.02 * size, 0), Vector3(0.012, 0.035, 0.012) * size, Color(0.38, 0.25, 0.15))
	_hint_up = true


func rock(at: Vector3, size: float, color: Color) -> void:
	_blob(at + Vector3(0, size * 0.35, 0), Vector3(1.0, 0.65, 0.9) * size, color, 0.28, 0.035)


# region terrain colours -------------------------------------------------------------------

func _picker(colors: Array, weights: Array = []) -> Callable:
	# A colour per facet: one of [param colors], slightly varied, picked by the facet's position
	var total := 0.0
	var w := weights if not weights.is_empty() else colors.map(func(_c: Variant) -> float: return 1.0)
	for x: float in w:
		total += x
	return func(centre: Vector3, _n: Vector3) -> Color:
		var r := _hash01(Vector2(centre.x, centre.z), 3) * total
		for i in colors.size():
			r -= float(w[i])
			if r <= 0.0:
				return _jit(colors[i], 0.025)
		return _jit(colors[-1], 0.025)


const DIRT := Color(0.42, 0.3, 0.2)
const WATER_SIDE := Color(0.1, 0.25, 0.42)

const PALETTE := {
	"Grassland": [Color(0.34, 0.6, 0.24), Color(0.3, 0.55, 0.22), Color(0.4, 0.65, 0.28)],
	"Plains": [Color(0.72, 0.68, 0.34), Color(0.66, 0.63, 0.3), Color(0.6, 0.62, 0.3)],
	"Desert": [Color(0.86, 0.72, 0.47), Color(0.78, 0.63, 0.4), Color(0.9, 0.79, 0.56)],
	"Tundra": [Color(0.55, 0.53, 0.42), Color(0.5, 0.49, 0.38), Color(0.6, 0.57, 0.45)],
	"Snow": [Color(0.86, 0.9, 0.96), Color(0.76, 0.83, 0.92), Color(0.92, 0.94, 0.98)],
}
const SIDES := {
	"Grassland": Color(0.42, 0.3, 0.2), "Plains": Color(0.48, 0.36, 0.22), "Desert": Color(0.72, 0.56, 0.34),
	"Tundra": Color(0.38, 0.33, 0.28), "Snow": Color(0.72, 0.76, 0.84),
}


func _bumpy(amount: float, seed: int) -> Callable:
	return func(x: float, z: float) -> float:
		return LAND + (_hash01(Vector2(x, z), seed + 11) - 0.5) * amount


# region pieces ----------------------------------------------------------------------------

## Every piece of the set: name -> ArrayMesh.
func build_all() -> Dictionary:
	var out := {}
	for base: String in ["Grassland", "Plains", "Desert", "Tundra", "Snow"]:
		for v in 3:
			out[base + ("" if v == 0 else str(v + 1))] = land(base, v)
		for v in 2:
			out[base + " Hill" + ("" if v == 0 else str(v + 1))] = hill(base, v)
	for v in 2:
		var suffix := "" if v == 0 else str(v + 1)
		out["Coast" + suffix] = water_tile(COAST, [Color(0.27, 0.62, 0.76), Color(0.3, 0.66, 0.8)], v)
		out["Ocean" + suffix] = water_tile(OCEAN, [Color(0.12, 0.3, 0.56), Color(0.14, 0.33, 0.6)], v)
		out["Lakes" + suffix] = lake(v)
		out["Mountain" + suffix] = mountain(v)
		out["Forest" + suffix] = forest(v, false)
		out["ForestT" + suffix] = forest(v, true)
		out["Jungle" + suffix] = jungle(v)
		# trees that follow the matching hill variant's slopes
		out["HillForest" + suffix] = forest(v, false, true)
		out["HillForestT" + suffix] = forest(v, true, true)
		out["HillJungle" + suffix] = jungle(v, true)
	out["Marsh"] = marsh()
	out["Flood plains"] = flood_plains()
	out["Oasis"] = oasis()
	out["Ice"] = ice()
	out["Atoll"] = atoll()
	out["Fallout"] = fallout()
	out["River-Bottom"] = river(1)
	out["River-BottomLeft"] = river(2)
	out["River-BottomRight"] = river(0)
	# Simpler stand-ins for when much of the map is on the table (the game uses "<piece>-Far" then)
	far = true
	for base: String in ["Grassland", "Plains", "Desert", "Tundra", "Snow"]:
		out[base + "-Far"] = land(base, 0)
		out[base + " Hill-Far"] = hill(base, 0)
	out["Mountain-Far"] = mountain(0)
	out["Forest-Far"] = forest(0, false)
	out["ForestT-Far"] = forest(0, true)
	out["Jungle-Far"] = jungle(0)
	out["HillForest-Far"] = forest(0, false, true)
	out["HillForestT-Far"] = forest(0, true, true)
	out["HillJungle-Far"] = jungle(0, true)
	out["Marsh-Far"] = marsh()
	out["Flood plains-Far"] = flood_plains()
	far = false
	# A first handful of resources and improvements, to set the direction
	out["Wheat"] = wheat()
	out["Cattle"] = cattle()
	out["Horses"] = horses()
	out["Sheep"] = sheep()
	out["Iron"] = iron()
	out["Fish"] = fish()
	out["Farm"] = farm()
	out["Mine"] = mine()
	out["Pasture"] = pasture()
	return out


func land(base: String, variant: int) -> ArrayMesh:
	_rng.seed = hash(base) + variant * 101
	_begin()
	var colors: Array = PALETTE[base]
	var height := _bumpy(0.035, variant)
	var color := _picker(colors)
	match base:
		"Desert":   # dunes: long low ridges
			var angle := _rng.randf() * PI
			var dir := Vector2(cos(angle), sin(angle))
			height = func(x: float, z: float) -> float:
				var along := Vector2(x, z).dot(dir)
				return LAND + 0.05 * maxf(0.0, sin(along * 7.0 + variant)) * (1.0 - Vector2(x, z).length() * 0.6)
			color = func(centre: Vector3, n: Vector3) -> Color:
				var c: Color = colors[0] if n.dot(Vector3(dir.x, 0, dir.y)) > 0.05 else colors[1]
				if centre.y > LAND + 0.02:
					c = colors[2]
				return _jit(c, 0.015)
		"Tundra":   # patchy snow
			color = func(centre: Vector3, _n: Vector3) -> Color:
				var r := _hash01(Vector2(centre.x, centre.z), variant + 5)
				if r < 0.1:
					return _jit(Color(0.8, 0.83, 0.88), 0.02)
				return _jit(colors[int(r * 10) % colors.size()], 0.025)
		"Snow":
			height = _bumpy(0.05, variant)
	_hex_top(4, LAND, height, color, SIDES[base], false, variant)
	# Little details, mostly near the rim
	match base:
		"Grassland":
			for p in _ring_spots(7, 0.3, 0.8):
				tuft(p + Vector3(0, LAND, 0), 1.0, Color(0.28, 0.55, 0.2))
			for p in _ring_spots(3, 0.5, 0.75):   # a few flowers
				_blob(p + Vector3(0, LAND + 0.02, 0), Vector3(0.018, 0.018, 0.018), [Color(0.95, 0.85, 0.3), Color(0.95, 0.95, 0.95), Color(0.85, 0.45, 0.6)][_rng.randi() % 3], 0.1)
		"Plains":
			for p in _ring_spots(6, 0.3, 0.8):
				tuft(p + Vector3(0, LAND, 0), 1.1, Color(0.78, 0.7, 0.35))
			for p in _ring_spots(2, 0.55, 0.75):
				_blob(p + Vector3(0, LAND + 0.03, 0), Vector3(0.05, 0.035, 0.05), Color(0.45, 0.5, 0.22), 0.25)
		"Desert":
			for p in _ring_spots(2, 0.5, 0.75):
				rock(p + Vector3(0, LAND - 0.005, 0), 0.05, Color(0.75, 0.58, 0.4))
		"Tundra":
			for p in _ring_spots(3, 0.45, 0.75):
				rock(p + Vector3(0, LAND - 0.005, 0), 0.045, Color(0.55, 0.53, 0.5))
			for p in _ring_spots(3, 0.3, 0.8):
				tuft(p + Vector3(0, LAND, 0), 0.8, Color(0.55, 0.5, 0.35))
		"Snow":
			for p in _ring_spots(2, 0.5, 0.75):
				_blob(p + Vector3(0, LAND + 0.01, 0), Vector3(0.06, 0.035, 0.05), Color(0.82, 0.88, 0.96), 0.3)
	return _finish()


## The height of a hill tile: a rounded, irregular mound in the middle (up to about 0.6 from the
## centre), with a flat ring outside it, so resources and improvements on the rim sit on level ground.
func _hill_height(variant: int) -> Callable:
	var wobble: Array[float] = []
	_rng.seed = 900 + variant
	for i in 6:
		wobble.append(_rng.randf_range(0.48, 0.6))
	var peak := Vector2(_rng.randf_range(-0.08, 0.08), _rng.randf_range(-0.08, 0.08))
	var top := 0.3 if variant == 0 else 0.26
	return func(x: float, z: float) -> float:
		var p := Vector2(x, z) - peak
		var a := fposmod(p.angle(), TAU) / TAU * 6.0
		var i := int(a) % 6
		var radius := lerpf(wobble[i], wobble[(i + 1) % 6], a - floor(a))
		var d := p.length() / radius
		return LAND + top * maxf(0.0, 1.0 - d * d)


func hill(base: String, variant: int) -> ArrayMesh:
	_begin()
	var colors: Array = PALETTE[base]
	var height := _hill_height(variant)
	_rng.seed = hash(base) + 77 + variant
	var color := func(centre: Vector3, n: Vector3) -> Color:
		var c: Color = colors[int(_hash01(Vector2(centre.x, centre.z), 9) * colors.size())]
		if base == "Tundra" and centre.y > LAND + 0.15:
			c = Color(0.9, 0.92, 0.96)   # snowy tops
		c = c.darkened(clampf((0.98 - n.y) * 1.5, 0.0, 0.2))   # slopes darker, so the mound reads from above
		return _jit(c, 0.02)
	_hex_top(5, LAND, height, color, SIDES[base], false, variant)
	if base in ["Desert", "Tundra", "Plains"]:
		for p in _ring_spots(2, 0.55, 0.75):
			rock(p + Vector3(0, float(height.call(p.x, p.z)) - 0.005, 0), 0.04, Color(0.6, 0.56, 0.5))
	return _finish()


func water_tile(level: float, colors: Array, variant: int) -> ArrayMesh:
	_rng.seed = 300 + variant + int(level * 1000)
	_begin()
	var waves := func(x: float, z: float) -> float:
		return level + (_hash01(Vector2(x, z), variant + 21) - 0.5) * 0.012
	_hex_top(3, level, waves, _picker(colors), WATER_SIDE, true, variant)
	return _finish()


func lake(variant: int) -> ArrayMesh:
	_rng.seed = 400 + variant
	_begin()
	var waves := func(x: float, z: float) -> float:
		return LAKE + (_hash01(Vector2(x, z), variant + 31) - 0.5) * 0.008
	_hex_top(3, LAKE, waves, _picker([Color(0.16, 0.5, 0.48), Color(0.19, 0.54, 0.5)]), WATER_SIDE, true, variant)
	for p in _ring_spots(5, 0.35, 0.7):   # lily pads
		_patch(p + Vector3(0, LAKE + 0.006, 0), 0.06, 6, Color(0.36, 0.62, 0.26), false, 0.15)
	for p in _ring_spots(4, 0.62, 0.78):
		reeds(p + Vector3(0, LAKE, 0), 1.1)
	return _finish()


func mountain(variant: int) -> ArrayMesh:
	_rng.seed = 500 + variant
	_begin()
	var rock_colors := [Color(0.6, 0.57, 0.52), Color(0.55, 0.52, 0.48), Color(0.64, 0.6, 0.55)]
	_hex_top(4, LAND, _bumpy(0.06, variant + 40), _picker(rock_colors), Color(0.45, 0.42, 0.38), false, variant)
	# one big peak and one or two smaller ones
	var peaks := [[Vector3(0.05, LAND, -0.05), 0.62, 0.95]]
	for i in 1 + variant:
		var a := _rng.randf() * TAU
		peaks.append([Vector3(cos(a), 0, sin(a)) * 0.45 + Vector3(0, LAND, 0), 0.34, 0.5])
	for peak: Array in peaks:
		_peak(peak[0], peak[1], peak[2])
	return _finish()


## A faceted peak like the background mountains: a jittered base ring, a narrower middle ring and an
## apex; grey rock with snow on the upper faces.
func _peak(at: Vector3, base: float, height: float) -> void:
	var sides := _rng.randi_range(5, 7)
	var apex := at + Vector3(_rng.randf_range(-0.12, 0.12) * base, height, _rng.randf_range(-0.12, 0.12) * base)
	var low: Array[Vector3] = []
	var mid: Array[Vector3] = []
	for i in sides:
		var a := TAU * (i + _rng.randf_range(-0.2, 0.2)) / sides
		low.append(at + Vector3(cos(a), 0, sin(a)) * base * _rng.randf_range(0.85, 1.1))
		var b := a + _rng.randf_range(-0.2, 0.2)
		mid.append(at + Vector3(cos(b) * base * _rng.randf_range(0.42, 0.56), height * _rng.randf_range(0.45, 0.58), sin(b) * base * _rng.randf_range(0.42, 0.56)))
	_hint_up = false
	_hint = at + Vector3(0, height * 0.35, 0)
	for i in sides:
		var j := (i + 1) % sides
		var rock_color := Color(0.62, 0.58, 0.53) if i % 2 == 0 else Color(0.55, 0.52, 0.48)
		_tri(low[i], low[j], mid[j], _jit(rock_color, 0.02))
		_tri(low[i], mid[j], mid[i], _jit(rock_color.lightened(0.05), 0.02))
		var cap := Color(0.9, 0.93, 0.97) if height > 0.6 else Color(0.66, 0.62, 0.56)
		_tri(mid[i], mid[j], apex, _jit(cap, 0.015))
	_hint_up = true


func forest(variant: int, snowy: bool, on_hill := false) -> ArrayMesh:
	_rng.seed = 600 + variant + (50 if snowy else 0) + (7 if on_hill else 0)
	_begin()
	var height := _hill_height(variant) if on_hill else func(_x: float, _z: float) -> float: return LAND
	_rng.seed = 610 + variant + (50 if snowy else 0)
	var greens := [Color(0.13, 0.36, 0.18), Color(0.16, 0.4, 0.2), Color(0.11, 0.32, 0.17)]
	if snowy:
		greens = [Color(0.12, 0.28, 0.2), Color(0.14, 0.31, 0.22)]
	for p in _ring_spots(9, 0.5, 0.82):
		conifer(p + Vector3(0, float(height.call(p.x, p.z)) - 0.01, 0), _rng.randf_range(1.0, 1.35), greens[_rng.randi() % greens.size()], snowy)
	return _finish()


func jungle(variant: int, on_hill := false) -> ArrayMesh:
	_rng.seed = 700 + variant + (7 if on_hill else 0)
	_begin()
	var height := _hill_height(variant) if on_hill else func(_x: float, _z: float) -> float: return LAND
	var greens := [Color(0.2, 0.55, 0.15), Color(0.15, 0.48, 0.12), Color(0.28, 0.6, 0.18)]
	var spots := _ring_spots(9, 0.4, 0.8)
	for i in spots.size():
		var p := spots[i]
		var y := float(height.call(p.x, p.z)) - 0.01
		if i % 3 == 0:
			broadleaf(p + Vector3(0, y, 0), _rng.randf_range(1.1, 1.4), greens[1])
		else:
			palm(p + Vector3(0, y, 0), _rng.randf_range(1.0, 1.3), greens[_rng.randi() % greens.size()])
	for p in _ring_spots(4, 0.25, 0.6):   # undergrowth
		_blob(p + Vector3(0, float(height.call(p.x, p.z)) + 0.02, 0), Vector3(0.06, 0.04, 0.06), Color(0.18, 0.45, 0.14), 0.3)
	return _finish()


## A whole tile: muddy ground with pools of still water and reeds.
func marsh() -> ArrayMesh:
	_rng.seed = 800
	_begin()
	_hex_top(4, LAND, _bumpy(0.02, 3), _picker([Color(0.42, 0.52, 0.28), Color(0.47, 0.5, 0.3), Color(0.38, 0.47, 0.26)]), DIRT.darkened(0.1))
	for p in _ring_spots(4, 0.35, 0.65):
		_patch(p + Vector3(0, LAND + 0.012, 0), _rng.randf_range(0.14, 0.2), 7, Color(0.3, 0.52, 0.5), true, 0.3)
	for p in _ring_spots(6, 0.3, 0.8):
		reeds(p + Vector3(0, LAND, 0), 1.0)
	return _finish()


## A whole tile: a broad band of lush green across the desert sand, with tufts and a few pools.
func flood_plains() -> ArrayMesh:
	_rng.seed = 810
	_begin()
	var across_dir := Vector2(-0.3, 1).normalized()
	var color := func(centre: Vector3, _n: Vector3) -> Color:
		var across := absf(Vector2(centre.x, centre.z).dot(across_dir)) + (_hash01(Vector2(centre.x, centre.z), 6) - 0.5) * 0.25
		if across < 0.42:
			return _jit([Color(0.42, 0.62, 0.24), Color(0.5, 0.66, 0.28), Color(0.38, 0.56, 0.22)][int(_hash01(Vector2(centre.x, centre.z), 4) * 3)], 0.02)
		if across < 0.55:
			return _jit(Color(0.62, 0.6, 0.36), 0.02)   # where the green gives way to sand
		return _jit(PALETTE["Desert"][int(_hash01(Vector2(centre.x, centre.z), 5) * 3)], 0.02)
	_hex_top(5, LAND, _bumpy(0.012, 8), color, SIDES["Desert"])
	var along := Vector2(across_dir.y, -across_dir.x)
	for t: float in [-0.45, 0.1, 0.5]:
		var at := Vector3(along.x * t, LAND + 0.01, along.y * t) + Vector3(across_dir.x, 0, across_dir.y) * _rng.randf_range(-0.15, 0.15)
		_patch(at, _rng.randf_range(0.08, 0.12), 7, Color(0.3, 0.56, 0.62), true, 0.3, 0.6, along.angle())
	for i in 9:
		var t := _rng.randf_range(-0.7, 0.7)
		var p := Vector3(along.x * t, LAND, along.y * t) + Vector3(across_dir.x, 0, across_dir.y) * _rng.randf_range(-0.35, 0.35)
		tuft(p, 1.1, Color(0.36, 0.58, 0.2))
	return _finish()


## On top of a desert: a pond off-centre ringed with grass and palms.
func oasis() -> ArrayMesh:
	_rng.seed = 820
	_begin()
	var pond := Vector3(0.32, LAND, -0.28)
	_patch(pond + Vector3(0, 0.008, 0), 0.4, 9, Color(0.5, 0.62, 0.28), false, 0.15)
	_patch(pond + Vector3(0, 0.014, 0), 0.26, 8, Color(0.22, 0.6, 0.65), true, 0.12)
	for i in 4:
		var a := TAU * i / 4.0 + 0.5
		palm(pond + Vector3(cos(a), 0, sin(a)) * 0.33 + Vector3(0, 0.005, 0), _rng.randf_range(1.1, 1.35), Color(0.25, 0.55, 0.2))
	return _finish()


## Floating floes of pack ice over the water.
func ice() -> ArrayMesh:
	_rng.seed = 830
	_begin()
	var spots := [Vector3(0, 0, 0), Vector3(0.48, 0, 0.18), Vector3(-0.42, 0, 0.3), Vector3(-0.2, 0, -0.48), Vector3(0.3, 0, -0.45), Vector3(0.05, 0, 0.55), Vector3(-0.55, 0, -0.15)]
	for i in spots.size():
		var r := 0.3 if i == 0 else _rng.randf_range(0.15, 0.22)
		_slab(spots[i] + Vector3(0, COAST - 0.01, 0), r, 6, _rng.randf_range(0.03, 0.06), Color(0.92, 0.95, 0.99), Color(0.7, 0.82, 0.92), 0.25, 1.0, _rng.randf() * TAU)
	return _finish()


## A broken ring of sandy islets on the water, with a palm or two.
func atoll() -> ArrayMesh:
	_rng.seed = 840
	_begin()
	_patch(Vector3(0, COAST + 0.004, 0), 0.55, 10, Color(0.35, 0.75, 0.78), true, 0.1)   # bright lagoon
	for i in 4:
		var a := TAU * i / 4.0 + 0.3
		var at := Vector3(cos(a), 0, sin(a)) * 0.55
		_slab(at + Vector3(0, COAST - 0.005, 0), 0.2, 7, 0.03, Color(0.93, 0.85, 0.62), Color(0.8, 0.7, 0.5), 0.15, 0.45, -a + PI / 2.0)
		if i % 2 == 0:
			palm(at + Vector3(0, COAST + 0.025, 0), 0.9, Color(0.25, 0.58, 0.22))
	return _finish()


## Nuclear fallout: sickly yellow-green patches, scorched rubble.
func fallout() -> ArrayMesh:
	_rng.seed = 850
	_begin()
	for p in _ring_spots(6, 0.1, 0.7):
		_patch(p + Vector3(0, LAND + 0.01, 0), _rng.randf_range(0.14, 0.22), 6, Color(0.62, 0.7, 0.18), false, 0.35)
	for p in _ring_spots(5, 0.3, 0.75):
		rock(p + Vector3(0, LAND, 0), 0.04, Color(0.22, 0.2, 0.18))
	for p in _ring_spots(3, 0.2, 0.5):
		_blob(p + Vector3(0, LAND + 0.03, 0), Vector3(0.03, 0.03, 0.03), Color(0.75, 0.95, 0.2), 0.1)
	return _finish()


## Unciv's "summary image" idea: one piece for any natural wonder that has no model of its own.
## Tall amber crystals on a rocky base, so it stands out from every ordinary tile.
func natural_wonder() -> ArrayMesh:
	_rng.seed = 860
	_begin()
	_blob(Vector3(0, LAND + 0.02, 0), Vector3(0.5, 0.12, 0.5), Color(0.45, 0.42, 0.4), 0.2)
	var crystals := [[Vector3(0, 0, 0), 0.75, 0.13], [Vector3(0.22, 0, 0.12), 0.48, 0.1], [Vector3(-0.2, 0, 0.16), 0.42, 0.09], [Vector3(-0.05, 0, -0.25), 0.36, 0.08]]
	for c: Array in crystals:
		var at: Vector3 = c[0] + Vector3(0, LAND + 0.06, 0)
		_frustum(at, c[2], c[2] * 0.9, c[1] * 0.75, 5, Color(0.95, 0.7, 0.2))
		_cone(at + Vector3(0, c[1] * 0.75, 0), c[2] * 0.9, c[1] * 0.25, 5, Color(1.0, 0.85, 0.4))
	return _finish()


## A river along one side of the tile ([param side]: 0 = bottom right, 1 = bottom, 2 = bottom left).
## It lies across the edge, so half of it shows on each tile, and wiggles a little on the way.
func river(side: int) -> ArrayMesh:
	_rng.seed = 870 + side
	_begin()
	var a := corner(side)
	var b := corner(side + 1)
	var outward := ((a + b) / 2.0).normalized()
	var steps := 4
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(b, t)
		var wiggle := sin(t * PI * 2.0) * 0.05 if i > 0 and i < steps else 0.0
		p += outward * wiggle
		var width := 0.075 if i > 0 and i < steps else 0.06
		var l := p - outward * width + Vector3(0, LAND + 0.008, 0)
		var r := p + outward * width + Vector3(0, LAND + 0.008, 0)
		if i > 0:
			_quad(prev_l, l, r, prev_r, Color(0.25, 0.55, 0.75).lerp(Color(0.3, 0.6, 0.8), t), true)
			# muddy banks
			_quad(prev_l - outward * 0.03 - Vector3(0, 0.003, 0), l - outward * 0.03 - Vector3(0, 0.003, 0), l, prev_l, Color(0.45, 0.38, 0.25))
			_quad(prev_r, r, r + outward * 0.03 - Vector3(0, 0.003, 0), prev_r + outward * 0.03 - Vector3(0, 0.003, 0), Color(0.45, 0.38, 0.25))
		prev_l = l
		prev_r = r
	return _finish()


# region resources and improvements (first few) --------------------------------------------

## Where resource and improvement models go: a spot off to one side, clear of the unit tokens.
const RESOURCE_SPOTS := [Vector3(0.48, 0, -0.44), Vector3(0.67, 0, -0.02), Vector3(0.22, 0, -0.66)]


func wheat() -> ArrayMesh:
	_rng.seed = 900
	_begin()
	for spot: Vector3 in RESOURCE_SPOTS:
		for i in 3:
			var p := spot + Vector3(_rng.randf_range(-0.07, 0.07), LAND, _rng.randf_range(-0.07, 0.07))
			_frustum(p, 0.04, 0.025, 0.09, 6, Color(0.9, 0.75, 0.3))
			_cone(p + Vector3(0, 0.09, 0), 0.035, 0.05, 6, Color(0.95, 0.82, 0.4))
	return _finish()


func _quadruped(at: Vector3, yaw: float, body: Color, head: Color, length: float, tall := 1.0, neck_up := false) -> void:
	var fwd := Vector3(cos(yaw), 0, sin(yaw))
	var side := fwd.cross(Vector3.UP)
	var leg_h := 0.05 * tall
	for s: float in [-1.0, 1.0]:
		for f: float in [-1.0, 1.0]:
			_box(at + fwd * f * length * 0.35 + side * s * 0.025 + Vector3(0, leg_h / 2.0, 0), Vector3(0.018, leg_h, 0.018), body.darkened(0.3), -yaw)
	_box(at + Vector3(0, leg_h + 0.03, 0), Vector3(length, 0.06, 0.07), body, -yaw)
	if neck_up:
		_box(at + fwd * length * 0.5 + Vector3(0, leg_h + 0.075, 0), Vector3(0.04, 0.08, 0.035), body, -yaw)
		_box(at + fwd * length * 0.62 + Vector3(0, leg_h + 0.11, 0), Vector3(0.06, 0.03, 0.03), head, -yaw)
	else:
		_box(at + fwd * length * 0.58 + Vector3(0, leg_h + 0.045, 0), Vector3(0.05, 0.045, 0.05), head, -yaw)


func cattle() -> ArrayMesh:
	_rng.seed = 910
	_begin()
	for i in 2:
		var spot: Vector3 = RESOURCE_SPOTS[i]
		_quadruped(spot + Vector3(0, LAND, 0), _rng.randf() * TAU, [Color(0.55, 0.35, 0.22), Color(0.92, 0.9, 0.85)][i], Color(0.25, 0.2, 0.18), 0.14)
	return _finish()


func horses() -> ArrayMesh:
	_rng.seed = 920
	_begin()
	for i in 2:
		var spot: Vector3 = RESOURCE_SPOTS[i]
		_quadruped(spot + Vector3(0, LAND, 0), _rng.randf() * TAU, [Color(0.45, 0.28, 0.16), Color(0.25, 0.18, 0.14)][i], Color(0.2, 0.14, 0.1), 0.13, 1.5, true)
	return _finish()


func sheep() -> ArrayMesh:
	_rng.seed = 930
	_begin()
	for spot: Vector3 in RESOURCE_SPOTS:
		var at: Vector3 = spot + Vector3(0, LAND, 0)
		_blob(at + Vector3(0, 0.06, 0), Vector3(0.06, 0.045, 0.05), Color(0.95, 0.94, 0.9), 0.15, 0.02)
		var a := _rng.randf() * TAU
		_box(at + Vector3(cos(a) * 0.06, 0.07, sin(a) * 0.06), Vector3(0.03, 0.03, 0.03), Color(0.2, 0.18, 0.16), -a)
	return _finish()


func iron() -> ArrayMesh:
	_rng.seed = 940
	_begin()
	for spot: Vector3 in RESOURCE_SPOTS:
		rock(spot + Vector3(0, LAND - 0.01, 0), _rng.randf_range(0.06, 0.08), Color(0.58, 0.3, 0.2))
		rock(spot + Vector3(0.06, LAND - 0.01, 0.04), 0.035, Color(0.45, 0.42, 0.42))
	return _finish()


func fish() -> ArrayMesh:
	_rng.seed = 950
	_begin()
	for spot: Vector3 in RESOURCE_SPOTS:
		var at: Vector3 = spot + Vector3(0, COAST + 0.012, 0)
		_patch(at, 0.12, 8, Color(0.62, 0.86, 0.94), true, 0.05)   # ripples
		var a := _rng.randf() * TAU
		var fwd := Vector3(cos(a), 0, sin(a))
		var side := fwd.cross(Vector3.UP)
		var up := Vector3(0, 0.012, 0)
		_hint_up = true
		_quad(at + fwd * 0.05 + up, at + side * 0.022 + up, at - fwd * 0.03 + up, at - side * 0.022 + up, Color(0.85, 0.55, 0.3))
		_tri(at - fwd * 0.03 + up, at - fwd * 0.06 + side * 0.022 + up, at - fwd * 0.06 - side * 0.022 + up, Color(0.85, 0.5, 0.25))
	return _finish()


## Fields: a patchwork of strips covering most of the tile.
func farm() -> ArrayMesh:
	_rng.seed = 960
	_begin()
	var crop := [Color(0.85, 0.75, 0.32), Color(0.6, 0.7, 0.25), Color(0.75, 0.6, 0.3), Color(0.5, 0.62, 0.22)]
	for row in 5:
		var z := -0.55 + row * 0.27
		var half_width := sqrt(maxf(0.0, 0.62 - z * z)) * 0.95
		var c: Color = crop[row % crop.size()]
		var y := LAND + 0.008
		_quad(Vector3(-half_width, y, z - 0.11), Vector3(half_width, y, z - 0.11), Vector3(half_width, y, z + 0.11), Vector3(-half_width, y, z + 0.11), c)
		for k in 4:   # furrows
			var fz := z - 0.08 + k * 0.055
			_quad(Vector3(-half_width, y + 0.004, fz), Vector3(half_width, y + 0.004, fz), Vector3(half_width, y + 0.004, fz + 0.012), Vector3(-half_width, y + 0.004, fz + 0.012), c.darkened(0.2))
	# a little barn on the side
	_box(Vector3(0.55, LAND + 0.05, 0.38), Vector3(0.12, 0.1, 0.09), Color(0.65, 0.22, 0.18), 0.4)
	_cone(Vector3(0.55, LAND + 0.1, 0.38), 0.09, 0.06, 4, Color(0.35, 0.3, 0.28))
	return _finish()


func mine() -> ArrayMesh:
	_rng.seed = 970
	_begin()
	var at := Vector3(0.52, LAND, -0.42)
	rock(at + Vector3(0.08, 0, -0.06), 0.12, Color(0.45, 0.43, 0.4))
	# timber frame around a dark entrance
	_box(at + Vector3(-0.05, 0.05, 0.04), Vector3(0.1, 0.1, 0.02), Color(0.08, 0.06, 0.05), 0.6)
	for s: float in [-1.0, 1.0]:
		_box(at + Vector3(-0.05 + s * 0.05 * cos(0.6), 0.06, 0.05 + s * 0.05 * sin(-0.6)), Vector3(0.02, 0.12, 0.02), Color(0.5, 0.35, 0.2), 0.6)
	_box(at + Vector3(-0.05, 0.12, 0.05), Vector3(0.14, 0.02, 0.025), Color(0.5, 0.35, 0.2), 0.6)
	# a cart of ore
	_box(at + Vector3(-0.2, 0.035, 0.15), Vector3(0.08, 0.04, 0.05), Color(0.45, 0.32, 0.2), 0.3)
	_blob(at + Vector3(-0.2, 0.065, 0.15), Vector3(0.035, 0.02, 0.025), Color(0.3, 0.3, 0.32), 0.2)
	return _finish()


func pasture() -> ArrayMesh:
	_rng.seed = 980
	_begin()
	var posts := 16
	var ring: Array[Vector3] = []
	for i in posts:
		var a := TAU * i / posts
		var r := 0.82 * 0.866 / cos(fposmod(a, PI / 3.0) - PI / 6.0) * HEX_RADIUS
		ring.append(Vector3(cos(a), 0, sin(a)) * r + Vector3(0, LAND, 0))
	for i in posts:
		_box(ring[i] + Vector3(0, 0.035, 0), Vector3(0.015, 0.07, 0.015), Color(0.5, 0.35, 0.2))
		var b := ring[(i + 1) % posts]
		var mid := (ring[i] + b) / 2.0 + Vector3(0, 0.05, 0)
		var yaw := atan2(b.z - ring[i].z, b.x - ring[i].x)
		_box(mid, Vector3(ring[i].distance_to(b), 0.01, 0.01), Color(0.6, 0.45, 0.28), -yaw)
	return _finish()
