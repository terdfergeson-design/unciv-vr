# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## The built-in tables. tools/make_surroundings.gd saves each part as tables/<Name>/<part>.glb:
##   top     the table top, around the map; the play surface is at y = 0, in metres
##   column  the stretchy middle, modelled 1 m tall (y 0..1); the game stretches it to fill the gap
##   base    the feet, standing on the floor (y = 0)
## (see tables/README.md). Vertex colours darken the carving's hollows.

const PLAY_SURFACE := -0.001   # just under the tiles (as the old plain table top)

var _materials: Dictionary = {}


## The plain dark wooden table (the original one): a round slab on a tapering column.
func plain() -> Dictionary:
	var wood := _flat_material("Wood", Color(0.32, 0.22, 0.14), 0.8)
	var stem := _flat_material("Stem", Color(0.26, 0.18, 0.12), 0.8)
	var top := _grid_builder()
	var radius := 0.84
	_lathe(top, [[Vector2(0, PLAY_SURFACE), Vector2(radius, PLAY_SURFACE)],
		[Vector2(radius, PLAY_SURFACE), Vector2(radius, PLAY_SURFACE - 0.04)],
		[Vector2(radius, PLAY_SURFACE - 0.04), Vector2(0, PLAY_SURFACE - 0.04)]], 48)
	var column := _grid_builder()
	_lathe(column, [[Vector2(0.12, 1.0), Vector2(0.3, 0.0)]], 24)
	return {"top": _scene("Top", [[top, wood]]), "column": _scene("Column", [[column, stem]])}


# region ornate oak ---------------------------------------------------------------------------

## An ornate round oak table: a plank top framed by walnut and holly stringing and crossbanding, a
## gadrooned rope edge, a scalloped apron, and a pedestal of turned, gadrooned urns on a fluted column,
## standing on four carved scroll feet.
func ornate_oak() -> Dictionary:
	var planks := _texture_material("Oak top", _oak_image(true), Color(1, 1, 1), 0.72)
	var oak := _texture_material("Oak", _oak_image(false), Color(1, 1, 1), 0.66)
	var walnut := _texture_material("Walnut", _oak_image(false, 7), Color(0.42, 0.3, 0.22), 0.62)
	var holly := _flat_material("Holly", Color(0.88, 0.8, 0.64), 0.62)

	# --- top ---
	var field := _grid_builder()
	var field_edge := 0.836
	_lathe(field, [[Vector2(0, PLAY_SURFACE), Vector2(0.3, PLAY_SURFACE), Vector2(0.6, PLAY_SURFACE), Vector2(field_edge, PLAY_SURFACE)]],
		160, Callable(), Callable(), _planar_uv)
	var inlays := _grid_builder()
	_lathe(inlays, [[Vector2(field_edge, PLAY_SURFACE), Vector2(0.843, PLAY_SURFACE)]], 160, Callable(), Callable(), _planar_uv)
	_lathe(inlays, [[Vector2(0.868, PLAY_SURFACE), Vector2(0.874, PLAY_SURFACE)]], 160, Callable(), Callable(), _planar_uv)
	var band := _grid_builder()   # crossbanding: the grain runs across the band
	_lathe(band, [[Vector2(0.843, PLAY_SURFACE), Vector2(0.868, PLAY_SURFACE)]], 160, Callable(), Callable(),
		func(theta: float, r: float, _along: float, _p: Vector3) -> Vector2: return Vector2(r * 2.0, theta / TAU * roundf(TAU * 0.87 * 2.0)))
	var holly_line := _grid_builder()
	_lathe(holly_line, [[Vector2(0.874, PLAY_SURFACE), Vector2(0.878, PLAY_SURFACE)]], 160)

	# The edge: a gadrooned (slanting-lobed, like a rope) round-over, a step, then a cove back underneath
	var edge := _grid_builder()
	var lobes := 140
	var gadroon := func(theta: float, run: int, i: int, _point: Vector2) -> float:
		if run != 0:
			return 0.0
		var weight := sin(PI * float(i) / 8.0)   # 0 at both ends of the bead, so it meets the flat parts
		return 0.0045 * weight * (sqrt(absf(sin((theta * lobes + float(i) * 0.35) * 0.5))) - 0.6)
	var gadroon_shade := func(theta: float, run: int, i: int, _point: Vector2) -> float:
		if run != 0:
			return 0.92 if run == 2 else 1.0
		var groove := 1.0 - sqrt(absf(sin((theta * lobes + float(i) * 0.35) * 0.5)))
		return 1.0 - 0.45 * groove * sin(PI * float(i) / 8.0)
	var bead: Array[Vector2] = []
	for k in 9:
		var a := PI * 0.5 * (1.0 - float(k) / 8.0) * 1.15 - 0.075   # from the top, over the round, a little under
		bead.append(Vector2(0.878 + 0.024 * maxf(cos(a), 0.0) - 0.002 * (1.0 - float(k == 0)), PLAY_SURFACE - 0.022 + 0.021 * sin(a)))
	bead[0] = Vector2(0.878, PLAY_SURFACE)
	var under := bead[bead.size() - 1]
	_lathe(edge, [bead,
		[under, Vector2(0.892, under.y - 0.004), Vector2(0.892, under.y - 0.01)],
		[Vector2(0.892, under.y - 0.01), Vector2(0.886, under.y - 0.012), Vector2(0.879, under.y - 0.018),
			Vector2(0.876, under.y - 0.026), Vector2(0.875, -0.064)]], 560, gadroon, gadroon_shade, _around_uv)
	_lathe(edge, [[Vector2(0.875, -0.064), Vector2(0.6, -0.064), Vector2(0.3, -0.064), Vector2(0.0, -0.064)]], 160,
		Callable(), Callable(), _planar_uv)   # underneath

	# The apron: a skirt under the top with a bead along its top and scalloped arches below
	var apron := _grid_builder()
	var arches := 20
	var scallop := func(theta: float) -> float:
		var f := fposmod(theta * arches / TAU, 1.0)
		return -0.125 - 0.026 * pow(sin(PI * f), 0.45)   # rounded lobes, with small notches between
	_apron(apron, 0.77, 0.75, -0.064, scallop, 240)

	# Under the top: a round cleat and the turned capital, an urn with gadroons, down to the column
	var capital := _grid_builder()
	var urn_lobes := 14
	var urn_mod := func(theta: float, run: int, i: int, point: Vector2) -> float:
		if run != 1:
			return 0.0
		var t := float(i) / 10.0
		return 0.008 * sin(PI * t) * (sqrt(absf(sin(theta * urn_lobes * 0.5))) - 0.5) * (point.x / 0.13)
	var urn_shade := func(theta: float, run: int, i: int, _point: Vector2) -> float:
		if run != 1:
			return 1.0
		return 1.0 - 0.4 * sin(PI * float(i) / 10.0) * (1.0 - sqrt(absf(sin(theta * urn_lobes * 0.5))))
	var top_y := -0.064
	_lathe(capital, [
		[Vector2(0.24, top_y), Vector2(0.24, top_y - 0.018), Vector2(0.17, top_y - 0.024), Vector2(0.16, top_y - 0.03),
			Vector2(0.15, top_y - 0.036), Vector2(0.15, top_y - 0.04), Vector2(0.115, top_y - 0.048), Vector2(0.1, top_y - 0.06),
			Vector2(0.098, top_y - 0.066), Vector2(0.108, top_y - 0.072), Vector2(0.11, top_y - 0.078)],
		_urn(Vector2(0.11, top_y - 0.078), top_y - 0.15, 0.135, 0.095, true),
		[Vector2(0.095, top_y - 0.15), Vector2(0.104, top_y - 0.152), Vector2(0.104, top_y - 0.158), Vector2(0.092, top_y - 0.16),
			Vector2(0.092, -0.226)]], 96, urn_mod, urn_shade, _around_uv)

	# --- column: fluted, 1 m tall, stretched to fit ---
	var column := _grid_builder()
	var flutes := 18
	var flute := func(theta: float, _run: int, _i: int, _point: Vector2) -> float:
		var s := sin(theta * flutes)
		return -0.006 * pow(maxf(0.0, s), 0.7)
	var flute_shade := func(theta: float, _run: int, _i: int, _point: Vector2) -> float:
		return 1.0 - 0.35 * pow(maxf(0.0, sin(theta * flutes)), 0.7)
	_lathe(column, [[Vector2(0.088, 1.0), Vector2(0.088, 0.75), Vector2(0.088, 0.5), Vector2(0.088, 0.25), Vector2(0.088, 0.0)]],
		144, flute, flute_shade, _around_uv)

	# --- base: a turned urn and plinth, four scroll feet, and an acorn drop underneath ---
	var base_turned := _grid_builder()
	var base_top := 0.32
	_lathe(base_turned, [
		[Vector2(0.092, base_top), Vector2(0.104, base_top - 0.002), Vector2(0.104, base_top - 0.008), Vector2(0.096, base_top - 0.01)],
		_urn(Vector2(0.096, base_top - 0.01), base_top - 0.11, 0.15, 0.1, false),
		[Vector2(0.1, base_top - 0.11), Vector2(0.135, base_top - 0.118), Vector2(0.14, base_top - 0.126), Vector2(0.14, base_top - 0.2),
			Vector2(0.13, base_top - 0.21), Vector2(0.12, base_top - 0.22)],
		[Vector2(0.12, base_top - 0.22), Vector2(0.06, base_top - 0.225), Vector2(0.05, base_top - 0.24), Vector2(0.055, base_top - 0.255),
			Vector2(0.045, base_top - 0.272), Vector2(0.025, base_top - 0.282), Vector2(0.0, base_top - 0.285)]],
		96, urn_mod, urn_shade, _around_uv)
	var feet := _grid_builder()
	for k in 4:
		_scroll_foot(feet, TAU * (k + 0.5) / 4.0)

	return {
		"top": _scene("Top", [[field, planks], [inlays, walnut], [band, oak], [holly_line, holly], [edge, oak],
			[apron, oak], [capital, oak]]),
		"column": _scene("Column", [[column, oak]]),
		"base": _scene("Base", [[base_turned, oak], [feet, oak]]),
	}


## A bulging urn profile from [param start] down to [param bottom_y]: out to [param belly] radius, in to [param neck].
## [param belly_low]: the widest part is low (a vase) rather than high (an inverted one).
func _urn(start: Vector2, bottom_y: float, belly: float, neck: float, belly_low: bool) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in 11:
		var t := float(k) / 10.0
		var y := lerpf(start.y, bottom_y, t)
		var bulge := sin(PI * pow(t, 1.4 if belly_low else 0.7))
		var r := lerpf(start.x, neck, t) + (belly - maxf(start.x, neck)) * bulge
		out.append(Vector2(r, y))
	return out


## The apron: outer and inner faces between [param top_y] and the scalloped bottom edge, a bead along the top.
func _apron(g: Dictionary, outer_r: float, inner_r: float, top_y: float, bottom: Callable, segments: int) -> void:
	# outer face (with a half-round bead near the top), the bottom edge, and the inner face
	var rows := 12
	var grid: Array = []
	for i in rows + 1:
		var row: Array = []
		var t := float(i) / rows
		for j in segments + 1:
			var theta := TAU * j / segments
			var y_bottom: float = bottom.call(theta)
			var y := lerpf(top_y, y_bottom, t)
			var r := outer_r
			var shade := 1.0
			# bead: a bump in the first two-sevenths, a groove under it
			var bead_t := (top_y - y) / 0.03
			if bead_t < 1.0:
				r += 0.007 * sin(PI * bead_t)
				shade = 0.85 + 0.15 * sin(PI * bead_t)
			elif bead_t < 1.25:
				shade = 0.75
			shade *= lerpf(1.0, 0.85, t)
			row.append({"p": Vector3(cos(theta) * r, y, sin(theta) * r), "uv": Vector2(theta / TAU * roundf(TAU * outer_r * 1.6), y * 1.6), "c": shade})
		grid.append(row)
	_emit_grid(g, grid, true, false, Vector3.ZERO)
	# bottom edge
	var edge: Array = []
	for r: float in [outer_r, inner_r]:
		var row: Array = []
		for j in segments + 1:
			var theta := TAU * j / segments
			var y: float = bottom.call(theta)
			row.append({"p": Vector3(cos(theta) * r, y, sin(theta) * r), "uv": Vector2(theta / TAU * roundf(TAU * outer_r * 1.6), r * 1.6), "c": 0.8})
		edge.append(row)
	_emit_grid(g, edge, true, false, Vector3.DOWN)
	# inner face (seldom seen)
	var inner: Array = []
	for i in 2:
		var row: Array = []
		for j in segments + 1:
			var theta := TAU * j / segments
			var y: float = bottom.call(theta) if i == 0 else top_y
			row.append({"p": Vector3(cos(theta) * inner_r, y, sin(theta) * inner_r), "uv": Vector2(theta / TAU * roundf(TAU * outer_r * 1.6), y * 1.6), "c": 0.6})
		inner.append(row)
	_emit_grid(g, inner, true, false, Vector3.ZERO)


## One carved scroll foot at angle [param angle] around the pedestal: it springs from the plinth, sweeps out and
## down to the floor in an S, and ends in a tight curl (a volute) with a carved ridge along its back.
func _scroll_foot(g: Dictionary, angle: float) -> void:
	var out_dir := Vector3(cos(angle), 0, sin(angle))
	# The path in (out, up), from inside the plinth to the curl; sampled from a smooth curve
	var keys: Array[Vector2] = [Vector2(0.06, 0.19), Vector2(0.14, 0.2), Vector2(0.21, 0.18), Vector2(0.28, 0.125),
		Vector2(0.34, 0.07), Vector2(0.4, 0.04), Vector2(0.46, 0.035), Vector2(0.5, 0.045)]
	# ...then the curl: a shrinking spiral turning up and back over the toe
	var curl_centre := Vector2(0.495, 0.085)
	var path: Array[Vector2] = []
	for k in 60:
		var t := float(k) / 59.0 * (keys.size() - 1)
		var i := mini(int(t), keys.size() - 2)
		var f := t - i
		var p0 := keys[maxi(i - 1, 0)]
		var p1 := keys[i]
		var p2 := keys[i + 1]
		var p3 := keys[mini(i + 2, keys.size() - 1)]
		path.append(_catmull(p0, p1, p2, p3, f))
	var start_angle := -PI * 0.5
	var spiral_r := curl_centre.distance_to(keys[keys.size() - 1])
	for k in range(1, 40):
		var t := float(k) / 39.0
		var a := start_angle + t * TAU * 0.95
		var r := spiral_r * (1.0 - 0.62 * t)
		path.append(curl_centre + Vector2(cos(a), sin(a)) * r)
	# Cross-section size along the path: thick at the plinth, slim at the ankle, a fuller toe, a fine curl
	var n := path.size()
	var sides := 18
	var grid: Array = []
	var along := 0.0
	for k in n:
		var t := float(k) / (n - 1)
		var width: float
		var height: float
		if k < 60:
			var s := float(k) / 59.0
			width = lerpf(0.095, 0.048, smoothstep(0.0, 0.75, s)) + 0.01 * smoothstep(0.75, 1.0, s)
			height = lerpf(0.09, 0.042, smoothstep(0.0, 0.7, s)) + 0.006 * smoothstep(0.7, 1.0, s)
		else:
			var s := float(k - 60) / (n - 61)
			var close := 1.0 - smoothstep(0.82, 1.0, s) * 0.92   # rounds off the end of the curl
			width = lerpf(0.058, 0.03, s) * close
			height = lerpf(0.048, 0.016, s) * close
		var p := path[k]
		var prev := path[maxi(k - 1, 0)]
		var next := path[mini(k + 1, n - 1)]
		var tangent2 := (next - prev).normalized()
		var normal2 := Vector2(-tangent2.y, tangent2.x)   # left of travel: the back (top) of the leg
		if k > 0:
			along += p.distance_to(prev)
		var centre := out_dir * p.x + Vector3.UP * p.y
		var normal3 := out_dir * normal2.x + Vector3.UP * normal2.y
		var side3 := out_dir.cross(Vector3.UP).normalized()
		var row: Array = []
		for j in sides + 1:
			var phi := TAU * j / sides
			var ridge := 1.0 + 0.3 * pow(maxf(0.0, sin(phi)), 10.0)   # a carved spine along the back
			var flank := 1.0 - 0.12 * pow(absf(cos(phi)), 6.0) * (1.0 - absf(sin(phi)))   # hollowed flanks
			var offset := side3 * cos(phi) * width * 0.5 * flank + normal3 * sin(phi) * height * 0.5 * ridge
			var shade := 1.0 - 0.25 * maxf(0.0, -sin(phi)) - 0.15 * (1.0 - flank) * 6.0
			row.append({"p": centre + offset, "uv": Vector2(along * 1.6, phi * 0.02 * 1.6), "c": clampf(shade, 0.55, 1.0)})
		grid.append(row)
	_emit_grid(g, grid, true, true, Vector3.ZERO, true)
	# A pad under the toe, so it stands on the floor
	var pad := _grid_builder()
	var toe := path[52]
	var pad_centre := out_dir * toe.x
	var pad_grid: Array = []
	for ring in [[0.0, maxf(0.004, toe.y - 0.01)], [0.024, maxf(0.004, toe.y - 0.01)], [0.024, 0.0], [0.0, 0.0]]:
		var row: Array = []
		for j in 25:
			var phi := TAU * j / 24
			row.append({"p": pad_centre + Vector3(cos(phi) * ring[0], ring[1], sin(phi) * ring[0]), "uv": Vector2(phi * 0.03, ring[1]), "c": 0.8})
		pad_grid.append(row)
	_emit_grid(g, pad_grid, true, false, Vector3.ZERO)


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# region wood ---------------------------------------------------------------------------------

## A tileable oak picture, 1024 square, covering about 0.6 m: the grain runs along x.
## [param planks]: four boards with seams and slightly different colours (the table top).
func _oak_image(planks: bool, seed_offset := 0) -> Image:
	var size := 1024
	var warp := _noise_image(seed_offset + 1, 16, 24, size, 1.0)     # slow wobble of the grain
	var fine := _noise_image(seed_offset + 2, 24, 640, size, 1.0)    # pores, long along the grain
	var figure := _noise_image(seed_offset + 3, 20, 40, size, 1.0)   # broad light and dark figure
	var flecks := _noise_image(seed_offset + 4, 48, 360, size, 1.0)  # quartersawn ray flecks
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var boards := 4 if planks else 1
	var early := Color(0.52, 0.35, 0.19)
	var late := Color(0.32, 0.2, 0.1)
	for y in size:
		var v := float(y) / size
		var board := int(v * boards)
		var local := fposmod(v * boards, 1.0)
		var tint := 1.0 + 0.07 * sin(board * 2.4 + seed_offset * 1.3)
		var rings := (11.0 + 5.0 * fposmod(board * 0.618, 1.0)) if planks else 48.0
		var phase := board * 1.9 + seed_offset
		var centre := 0.35 + 0.3 * fposmod(board * 0.37 + 0.2, 1.0)
		for x in size:
			var u := float(x) / size
			var w := warp.get_pixel(x, y).r - 0.5
			var ring_coord: float
			if planks:
				# Flat-sawn boards: rings round a pith below the board make arches ("cathedrals") along it
				var depth := 0.16 + 0.11 * sin(TAU * u * 2.0 + phase) + 0.05 * sin(TAU * u * 3.0 + phase * 2.0)
				ring_coord = sqrt(pow(local - centre + w * 0.08, 2.0) + depth * depth) * rings * 2.0
			else:
				ring_coord = local * rings + w * 2.5
			var ring := fposmod(ring_coord, 1.0)
			var late_amount := smoothstep(0.5, 0.9, ring) * (1.0 - smoothstep(0.9, 1.0, ring))
			var color := early.lerp(late, late_amount * 0.7)
			color = color.lerp(late, (figure.get_pixel(x, y).r - 0.5) * 0.4)
			var pore := fine.get_pixel(x, y).r
			color = color.darkened(0.14 * smoothstep(0.55, 0.85, pore))
			var fleck := flecks.get_pixel(x, y).r
			color = color.lightened(0.1 * smoothstep(0.86, 0.95, fleck))
			color = Color(color.r * tint, color.g * tint, color.b * tint)
			if planks and (local < 0.003 or local > 0.997):
				color = color.darkened(0.6)   # the seam between two boards
			image.set_pixel(x, y, color)
	return image


## A seamless noise picture made at [param w] x [param h] and stretched to [param size] square (so its features are
## longer along x when w < h... and the other way round).
func _noise_image(noise_seed: int, w: int, h: int, size: int, gain: float) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = 9000 + noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var image := noise.get_seamless_image(w, h, false, false, 0.2, true)
	image.convert(Image.FORMAT_RGB8)
	image.resize(size, size, Image.INTERPOLATE_CUBIC)
	if gain != 1.0:
		image.adjust_bcs(1.0, gain, 1.0)
	return image


# region meshes -------------------------------------------------------------------------------

func _grid_builder() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return {"st": st, "count": 0}


func _planar_uv(_theta: float, _r: float, _along: float, p: Vector3) -> Vector2:
	return Vector2(p.x / 0.62, p.z / 0.62)


## Grain running around a turned part; a whole number of repeats per turn, so there's no seam.
func _around_uv(theta: float, r: float, along: float, _p: Vector3) -> Vector2:
	var repeats := maxf(1.0, roundf(TAU * maxf(r, 0.05) * 1.6))
	return Vector2(theta / TAU * repeats, along * 1.6)


## Turns profiles about the y axis. [param runs]: lists of (radius, y) points, each a smoothly shaded run, joined
## by hard edges; walk them with the solid on your right (outer surfaces top to bottom, tops outwards, bottoms
## inwards). [param radius_mod] (theta, run, index, point) -> radius offset carves the surface; [param shade]
## (same arguments) -> 0..1 darkens its hollows; [param uv] (theta, radius, distance along the profile, position).
func _lathe(g: Dictionary, runs: Array, segments: int, radius_mod := Callable(), shade := Callable(), uv := Callable()) -> void:
	for run_index in runs.size():
		var run: Array = runs[run_index]
		var grid: Array = []
		var along := 0.0
		for i in run.size():
			var point: Vector2 = run[i]
			if i > 0:
				along += point.distance_to(run[i - 1])
			var row: Array = []
			for j in segments + 1:
				var theta := TAU * j / segments
				var r := point.x
				if radius_mod.is_valid():
					r += float(radius_mod.call(theta, run_index, i, point))
				var p := Vector3(cos(theta) * r, point.y, sin(theta) * r)
				var c := float(shade.call(theta, run_index, i, point)) if shade.is_valid() else 1.0
				var texture_uv: Vector2 = uv.call(theta, point.x, along, p) if uv.is_valid() else _around_uv(theta, point.x, along, p)
				row.append({"p": p, "uv": texture_uv, "c": c})
			grid.append(row)
		var flat := Vector3.ZERO
		if absf(run[0].y - run[run.size() - 1].y) < 1e-6:
			flat = Vector3.UP if run[run.size() - 1].x > run[0].x else Vector3.DOWN
		_emit_grid(g, grid, true, false, flat)


## Emits a grid of vertices {p, uv, c} as triangles with smooth normals from the neighbouring vertices.
## Columns wrap (the last column repeats the first) when [param wrap_columns]. [param flat]: a fixed normal for
## flat discs. [param flip]: the other side faces out.
func _emit_grid(g: Dictionary, grid: Array, wrap_columns: bool, flip: bool, flat: Vector3, sweep := false) -> void:
	var st: SurfaceTool = g["st"]
	var rows := grid.size()
	var cols: int = grid[0].size()
	var normals: Array = []
	for i in rows:
		var row_normals: Array[Vector3] = []
		for j in cols:
			if flat != Vector3.ZERO:
				row_normals.append(flat)
				continue
			var jm := j - 1 if j > 0 else (cols - 2 if wrap_columns else 0)
			var jp := j + 1 if j < cols - 1 else (1 if wrap_columns else cols - 1)
			var d_col: Vector3 = grid[i][jp]["p"] - grid[i][jm]["p"]
			var d_row: Vector3 = grid[mini(i + 1, rows - 1)][j]["p"] - grid[maxi(i - 1, 0)][j]["p"]
			var n := d_col.cross(d_row)
			if sweep:
				n = -n
			if flip:
				n = -n
			if n.length_squared() < 1e-14:
				# at an axis (the column shrinks to a point): use the neighbouring row's direction
				var other: Vector3 = grid[i - 1 if i > 0 else i + 1][j]["p"]
				n = Vector3.DOWN if (grid[i][j]["p"] as Vector3).y < other.y else Vector3.UP
			row_normals.append(n.normalized())
		normals.append(row_normals)
	for i in rows - 1:
		for j in cols - 1:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			_triangle(st, grid, normals, quad[0], quad[1], quad[2])
			_triangle(st, grid, normals, quad[0], quad[2], quad[3])
	g["count"] += 1


func _triangle(st: SurfaceTool, grid: Array, normals: Array, a: Array, b: Array, c: Array) -> void:
	var va: Dictionary = grid[a[0]][a[1]]
	var vb: Dictionary = grid[b[0]][b[1]]
	var vc: Dictionary = grid[c[0]][c[1]]
	var pa: Vector3 = va["p"]
	var pb: Vector3 = vb["p"]
	var pc: Vector3 = vc["p"]
	var face := (pb - pa).cross(pc - pa)
	if face.length_squared() < 1e-16:
		return
	var avg: Vector3 = normals[a[0]][a[1]] + normals[b[0]][b[1]] + normals[c[0]][c[1]]
	var order := [[va, a], [vb, b], [vc, c]]
	if face.dot(avg) > 0.0:   # Godot's front faces wind the other way
		order = [[va, a], [vc, c], [vb, b]]
	for entry: Array in order:
		var v: Dictionary = entry[0]
		var idx: Array = entry[1]
		var shade := float(v["c"])
		var dark := pow(shade, 1.6)   # hollows fall off quickly
		st.set_color(Color(dark, dark, dark))
		st.set_normal(normals[idx[0]][idx[1]])
		st.set_uv(v["uv"])
		st.add_vertex(v["p"])


func _scene(root_name: String, parts: Array) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	var mesh := ArrayMesh.new()
	for part: Array in parts:
		var g: Dictionary = part[0]
		if g["count"] == 0:
			continue
		var st: SurfaceTool = g["st"]
		st.index()
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[1])
	var instance := MeshInstance3D.new()
	instance.name = root_name + "Mesh"
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	return root


func _flat_material(material_name: String, color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = material_name
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	return m


func _texture_material(material_name: String, image: Image, tint: Color, roughness: float) -> StandardMaterial3D:
	var m := _flat_material(material_name, tint, roughness)
	m.albedo_texture = ImageTexture.create_from_image(image)
	var bump := image.duplicate() as Image
	bump.convert(Image.FORMAT_RGBA8)
	bump.bump_map_to_normal_map(3.0)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(bump)
	m.normal_scale = 0.6
	return m
