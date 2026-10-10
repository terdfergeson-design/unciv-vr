# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## Draws the Unciv map on the table: each tile from the chosen tileset's pieces (tileset.gd) or, where
## the set has nothing for a terrain, a plain coloured hex prism; plus units, cities, borders and highlights.
## Works in "map units": a hex has circumradius 1, like Unciv's world coordinates.
## Scale this node to fit the table (see main.gd).

const SQRT3 := 1.7320508
signal view_rebuilt   # the drawn tiles changed (the yields overlay re-asks the bridge then)
const Icons := preload("res://scripts/icons.gd")
const OVERLAYS := preload("res://scripts/map_overlays.gd")
const Tileset := preload("res://scripts/tileset.gd")
const Motion := preload("res://scripts/unit_motion.gd")
const DEFAULT_TILESET := "LowPoly"
## With more tiles than this on the table, pieces' simpler "-Far" versions are drawn (they're tiny then)
const FAR_TILES := 900
const HEX_RADIUS := 0.97          # slightly under 1 leaves a hairline gap between tiles
const UNEXPLORED_COLOR := Color(0.16, 0.18, 0.22)   # the ground under the fog

# Fog of war: unexplored tiles are hidden under slowly drifting low-poly clouds
const FOG_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

void vertex() {
	// Each puff bobs gently, out of step with its neighbours. Its phase comes with it (INSTANCE_CUSTOM.r, picked
	// from its tile): a phase worked out from where it is in the world would jump about every frame whenever the
	// map is dragged or the table moved, and every cloud would jiggle.
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	VERTEX.y += sin(TIME * 0.7 + phase) * 0.05;
	VERTEX.xz *= 1.0 + sin(TIME * 0.45 + phase * 1.7) * 0.04;
}

void fragment() {
	// Brighter towards the edges, like sunlit cloud tops
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = mix(COLOR.rgb, vec3(0.92, 0.94, 1.0), rim * 0.45);
	ROUGHNESS = 1.0;
}
"""

var terrain_info: Dictionary = {}   # terrain name -> {type, rgb, impassable}
var tiles: Dictionary = {}          # Vector2i(x, y) -> tile Dictionary from getState
var civ_colors: Dictionary = {}     # civ name -> {outer: Color, inner: Color}
var civ_info: Dictionary = {}       # civ name -> its getState civs entry (nation, city-state type...)
var resource_info: Dictionary = {}  # resource name -> {type: Bonus / Luxury / Strategic}
var unit_info: Dictionary = {}      # unit name -> its ruleset entry (unitType, rangedStrength, replaces, attackSound, domain)
var motion: Node3D                  # unit_motion.gd: unit moves and battles on the table
## Units glide to where they've moved since the last refresh (off: they just appear there)
var animate_moves := true
var overlays: Node3D                # map_overlays.gd: Unciv's five map overlays
var tileset: RefCounted = null      # tileset.gd; null draws every tile as a plain coloured hex
var tileset_name := ""
## Where unit models come from (Unciv's separate "Unitset" option): "tileset" (the tiles' set), "none" (round
## tokens with Unciv's icons), or another tileset folder whose pieces/Units are used.
var unitset_name := "tileset"
var _unitset: RefCounted = null
var map_extent := 10.0              # half-size of the map, in map units

var _content: Node3D                # everything, offset so the map is centred on this node
var _terrain: MultiMeshInstance3D
var _trees: MultiMeshInstance3D
var _pieces_root: Node3D            # one MultiMeshInstance3D per tileset piece in use
var _piece_nodes: Dictionary = {}   # piece Mesh -> its MultiMeshInstance3D
var _piece_scenes: Node3D           # pieces that are whole Godot scenes, one instance per tile
var _borders: MeshInstance3D           # territory edges, rebuilt with the view
const BORDER_INNER := 0.92             # the border strip runs from the hex's edge in to this fraction of it
var _highlights: MultiMeshInstance3D
var _clouds: MultiMeshInstance3D
var _units_root: Node3D
var _cities_root: Node3D
var _center_offset := Vector3.ZERO

# Window onto the map: only tiles within view_radius (map units) of view_center are drawn, so the
# table keeps a comfortable hex size and the map slides underneath it. view_radius 0, or at least
# full_extent, shows the whole map (zoomed all the way out).
var view_center := Vector2.ZERO     # world coords (wx, wy) under the table centre
var view_radius := 0.0
var _built_radius := -1.0           # view_radius when the visuals were last rebuilt
var full_extent := 10.0             # half-size of the whole map, in map units
var full_center := Vector2.ZERO
var _shown: Dictionary = {}         # Vector2i -> true for tiles currently drawn
var _built_center := Vector2.ZERO   # view_center when the visuals were last rebuilt
const EDGE_FADE := 2.0              # map units at the window's rim drawn darker

var _hover := Vector2i(999999, 999999)
var _selected := Vector2i(999999, 999999)
var _reachable: Array[Vector2i] = []
var _targets: Array[Vector2i] = []
var _beacon: MeshInstance3D       # a pulsing light column over the selected unit, to find it at a glance
var _beacon_time := 0.0
var _unit_labels: Dictionary = {}   # Vector2i -> Array[Label3D]; shown only for hovered/selected tiles
var _tokens: Dictionary = {}        # unit id -> its token on the table
var _last_key: Dictionary = {}      # unit id -> the tile it was drawn on last time (to see who moved)
var _facing: Dictionary = {}        # unit id -> which way it faces (radians about Y), kept between redraws
var _civ_materials: Dictionary = {} # "material id|colour" -> a copy of a CivOuter / CivInner material in that colour
const NO_TILE := Vector2i(999999, 999999)
var _aim_key := NO_TILE            # where the selected unit is aimed (click again there to go)
var _aim_root: Node3D


func _ready() -> void:
	_content = Node3D.new()
	_content.name = "Content"
	add_child(_content)

	_terrain = _make_multimesh_node("Terrain", _make_prism_mesh(), _vertex_color_material(0.9))
	_trees = _make_multimesh_node("Trees", _make_cone_mesh(), _vertex_color_material(0.8))
	_pieces_root = Node3D.new()
	_pieces_root.name = "TilesetPieces"
	_content.add_child(_pieces_root)
	_piece_scenes = Node3D.new()
	_piece_scenes.name = "TilesetScenes"
	_content.add_child(_piece_scenes)
	if tileset == null and tileset_name == "":
		set_tileset(DEFAULT_TILESET)
	_borders = MeshInstance3D.new()
	_borders.name = "Borders"
	_borders.material_override = _vertex_color_material(0.6, true)
	_borders.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_content.add_child(_borders)
	_highlights = _make_multimesh_node("Highlights", _make_ring_mesh(0.62), _vertex_color_material(0.4, true))
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 0.55
	puff.radial_segments = 9
	puff.rings = 4
	var fog := ShaderMaterial.new()
	fog.shader = Shader.new()
	fog.shader.code = FOG_SHADER
	_clouds = _make_multimesh_node("Fog", puff, fog, true)
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_units_root = Node3D.new()
	_units_root.name = "Units"
	_content.add_child(_units_root)
	_cities_root = Node3D.new()
	_cities_root.name = "Cities"
	_content.add_child(_cities_root)

	_beacon = MeshInstance3D.new()
	_beacon.name = "Beacon"
	var column := CylinderMesh.new()
	column.top_radius = 0.06
	column.bottom_radius = 0.22
	column.height = 5.0
	column.radial_segments = 12
	column.cap_top = false
	column.cap_bottom = false
	_beacon.mesh = column
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(1.0, 0.85, 0.3, 0.35)
	_beacon.material_override = glow
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.visible = false
	_content.add_child(_beacon)

	motion = Motion.new()
	motion.name = "Motion"
	_content.add_child(motion)

	overlays = OVERLAYS.new()
	overlays.name = "Overlays"
	_content.add_child(overlays)
	overlays.setup(self)


func _process(delta: float) -> void:
	if _beacon.visible:
		_beacon_time += delta
		var material := _beacon.material_override as StandardMaterial3D
		material.albedo_color.a = 0.2 + 0.18 * sin(_beacon_time * 4.0)


## Draws tiles with the tileset in folder [param folder_name] ("" or "classic": plain coloured hexes).
func set_tileset(folder_name: String) -> void:
	tileset_name = folder_name if folder_name != "" else "classic"
	tileset = null if tileset_name == "classic" else Tileset.open(tileset_name)
	if tileset == null and tileset_name != "classic":
		push_warning("Tileset %s not found; drawing plain hexes" % tileset_name)
	for node: Node in _piece_nodes.values():
		node.queue_free()
	_piece_nodes.clear()
	if _content != null and not tiles.is_empty():
		_rebuild_view()


## Takes unit models from [param folder_name] ("tileset": the tiles' set; "none": tokens; or a tileset folder).
func set_unitset(folder_name: String) -> void:
	unitset_name = folder_name if folder_name != "" else "tileset"
	_unitset = null
	if unitset_name not in ["tileset", "none"]:
		_unitset = Tileset.open(unitset_name)
		if _unitset == null:
			push_warning("Unit set %s not found; using the tiles' units" % unitset_name)
	if _content != null and not tiles.is_empty():
		_rebuild_view()


## The tileset unit models come from, or null for tokens.
func _units_set() -> RefCounted:
	match unitset_name:
		"none":
			return null
		"tileset":
			return tileset
	return _unitset if _unitset != null else tileset


func set_ruleset(ruleset: Dictionary) -> void:
	terrain_info = ruleset.get("terrains", {})
	resource_info = ruleset.get("resources", {})
	unit_info = ruleset.get("units", {})


# region building -------------------------------------------------------------------------

func build(state: Dictionary) -> void:
	civ_colors.clear()
	civ_info.clear()
	for civ: Dictionary in state.get("civs", []):
		civ_info[civ["name"]] = civ
		civ_colors[civ["name"]] = {
			"outer": Color.html(civ["outerColor"]),
			"inner": Color.html(civ["innerColor"]),
		}

	tiles.clear()
	var min_corner := Vector2(INF, INF)
	var max_corner := Vector2(-INF, -INF)
	for tile: Dictionary in state.get("tiles", []):
		var key := Vector2i(int(tile["x"]), int(tile["y"]))
		tiles[key] = tile
		var w := Vector2(tile["wx"], tile["wy"])
		min_corner = min_corner.min(w)
		max_corner = max_corner.max(w)

	full_center = (min_corner + max_corner) / 2.0
	full_extent = max((max_corner - min_corner).x, (max_corner - min_corner).y) / 2.0 + 1.0
	_rebuild_view()


## Shows the whole map (radius 0) or a round window [param radius] map units across around [param center].
func set_view(center: Vector2, radius: float) -> void:
	view_radius = radius
	# Keep the window over the map: the closer it is to showing everything, the less it can slide
	var margin := maxf(0.0, full_extent - radius) if radius > 0.0 else 0.0
	view_center = center.clamp(full_center - Vector2.ONE * margin, full_center + Vector2.ONE * margin)
	map_extent = full_extent if shows_whole_map() else view_radius + 1.0
	# Rebuilding the visuals is the slow part, so zooming only rebuilds every few percent and sliding
	# every hex or so; in between, what's drawn just moves (main.gd rescales the table smoothly).
	var resized := absf(view_radius - _built_radius) > maxf(0.4, _built_radius * 0.06)
	if resized or view_center.distance_to(_built_center) > 1.2 or tiles.is_empty():
		_rebuild_view()
	else:
		_place_content()


func pan_view(delta_world: Vector2) -> void:
	if not shows_whole_map():
		set_view(view_center + delta_world, view_radius)


## True when only part of the map is on the table (it can slide).
func is_windowed() -> bool:
	return not shows_whole_map()


func shows_whole_map() -> bool:
	return view_radius <= 0.0 or view_radius >= full_extent


func _place_content() -> void:
	var c := full_center if shows_whole_map() else view_center
	_center_offset = Vector3(-c.x, 0, c.y)
	_content.position = _center_offset


func _rebuild_view() -> void:
	_built_center = view_center
	_built_radius = view_radius
	_place_content()
	map_extent = full_extent if shows_whole_map() else view_radius + 1.0
	_shown.clear()
	var whole := shows_whole_map()
	for key: Vector2i in tiles:
		if whole or _world_of(key).distance_to(view_center) <= view_radius:
			_shown[key] = true
	_build_terrain()
	_build_borders()
	_build_cities()
	_build_units()
	_build_highlights()
	if _aim_root != null:
		_aim_root.visible = _shown.has(_aim_key)
	_place_beacon()
	overlays.rebuild(_shown)
	view_rebuilt.emit()


## The city view's marks on the table (a getCity result), or {} to clear them.
func show_city(city: Dictionary) -> void:
	overlays.show_city(city, _shown)


## Turns map overlays on / off ({"movement": bool, "yields": ..., "worked", "resources", "improvements"}).
func set_overlay_flags(new_flags: Dictionary) -> void:
	var pictures_before: bool = overlays.flags.get("improvements", true)
	var icons_before: bool = overlays.flags.get("unit_icons", true)
	for key: String in new_flags:
		if overlays.flags.has(key):
			overlays.flags[key] = bool(new_flags[key])
	if overlays.flags.get("improvements", true) != pictures_before and tileset != null and not tiles.is_empty():
		_build_terrain()   # the tileset's improvement models follow Unciv's "improvement pictures" toggle
	if overlays.flags.get("unit_icons", true) != icons_before and not tiles.is_empty():
		_build_units()
	overlays.rebuild(_shown)


## The getYields result for the yields overlay.
func show_yields(yield_tiles: Array) -> void:
	overlays.show_yields(yield_tiles, _shown)


## The explored tiles currently drawn, as [[x, y], ...] (what to ask getYields for).
func shown_explored_tiles() -> Array:
	var out := []
	for key: Vector2i in _shown:
		if tiles[key].get("explored", false):
			out.append([key.x, key.y])
	return out


func _world_of(key: Vector2i) -> Vector2:
	var tile: Dictionary = tiles.get(key, {})
	return Vector2(tile.get("wx", 0.0), tile.get("wy", 0.0))


## How far into the darker rim of the window a tile is: 0 inside, up to 1 at the very edge.
func _rim(key: Vector2i) -> float:
	if shows_whole_map():
		return 0.0
	return clampf((_world_of(key).distance_to(view_center) - (view_radius - EDGE_FADE)) / EDGE_FADE, 0.0, 1.0)


func is_shown(key: Vector2i) -> bool:
	return _shown.has(key)


func _build_terrain() -> void:
	var far := _shown.size() > FAR_TILES
	var buckets := {}   # piece Mesh -> [transforms, colours, custom data]
	for child in _piece_scenes.get_children():
		child.queue_free()
	var prism_keys: Array[Vector2i] = []
	for key: Vector2i in _shown:
		var tile: Dictionary = tiles[key]
		if not (tileset != null and tile.get("explored", false) and tileset.covers(tile) and _add_pieces(key, tile, far, buckets)):
			prism_keys.append(key)
	_build_prisms(prism_keys)
	# Hand each piece's instances to its MultiMesh (made the first time it's needed)
	for mesh: Mesh in _piece_nodes.keys():
		if not buckets.has(mesh):
			(_piece_nodes[mesh] as MultiMeshInstance3D).multimesh.instance_count = 0
	for mesh: Mesh in buckets:
		if not _piece_nodes.has(mesh):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true   # r: 1 on tiles out of sight (the water shader dims its shine there)
			mm.mesh = mesh
			var node := MultiMeshInstance3D.new()
			node.multimesh = mm
			_pieces_root.add_child(node)
			_piece_nodes[mesh] = node
		var mmesh: MultiMesh = (_piece_nodes[mesh] as MultiMeshInstance3D).multimesh
		var transforms: Array = buckets[mesh][0]
		var colors: Array = buckets[mesh][1]
		var custom: Array = buckets[mesh][2]
		mmesh.instance_count = transforms.size()
		for n in transforms.size():
			mmesh.set_instance_transform(n, transforms[n])
			mmesh.set_instance_color(n, colors[n])
			mmesh.set_instance_custom_data(n, custom[n])
	_build_fog()


## Queues the tileset's pieces for [param key]; false if the set had nothing to draw there.
func _add_pieces(key: Vector2i, tile: Dictionary, far: bool, buckets: Dictionary) -> bool:
	var entries: Array = tileset.pieces_for(tile)
	if entries.is_empty() or entries[0]["kind"] not in ["terrain", "wonder"]:
		return false
	var h := absi(hash(key))
	var variant := h % 7
	var turns := int(h / 7.0) % 6 if tileset.random_rotation() else 0
	var tint := Color.WHITE
	var unseen := 0.0 if tile.get("visible", false) else 1.0
	if unseen > 0.0:
		tint = tint.darkened(0.45)
	tint = tint.darkened(0.55 * _rim(key))
	var custom := Color(maxf(unseen, _rim(key)), 0, 0, 0)
	var at := tile_position(key, 0.0)
	var drew := false
	for entry: Dictionary in entries:
		if entry["kind"] == "improvement" and not overlays.flags.get("improvements", true):
			continue   # Unciv's "improvement pictures" overlay is off
		var model: Dictionary = tileset.get_piece(entry["piece"], variant, far)
		var piece_basis := Basis(Vector3.UP, turns * PI / 3.0) if entry["rotate"] else Basis()
		piece_basis = piece_basis.scaled(Vector3.ONE * tileset.piece_scale(entry["piece"]))
		if model.has("mesh"):
			if not buckets.has(model["mesh"]):
				buckets[model["mesh"]] = [[], [], []]
			buckets[model["mesh"]][0].append(Transform3D(piece_basis, at))
			buckets[model["mesh"]][1].append(tint)
			buckets[model["mesh"]][2].append(custom)
			drew = true
		elif model.has("scene"):
			var instance: Node = (model["scene"] as PackedScene).instantiate()
			if instance is Node3D:
				(instance as Node3D).transform = Transform3D(piece_basis, at)
			_piece_scenes.add_child(instance)
			drew = true
	return drew


## True when the tileset draws [param tile]'s improvement itself (so the overlay's little model isn't needed).
func tileset_draws_improvement(tile: Dictionary) -> bool:
	return tileset != null and tile.get("explored", false) and tileset.covers(tile) \
		and tileset.improvement_piece_for(str(tile.get("improvement", ""))) != ""


## Plain coloured hex prisms (and cone trees), for unexplored tiles and terrain the tileset doesn't cover.
func _build_prisms(keys: Array[Vector2i]) -> void:
	var mm := _terrain.multimesh
	mm.instance_count = keys.size()
	var tree_transforms: Array[Transform3D] = []
	var tree_colors: Array[Color] = []
	var i := 0
	for key: Vector2i in keys:
		var tile: Dictionary = tiles[key]
		var height := tile_height(tile)
		var tile_basis := Basis().scaled(Vector3(1, height, 1))
		mm.set_instance_transform(i, Transform3D(tile_basis, tile_position(key, 0.0)))
		mm.set_instance_color(i, tile_color(tile).darkened(0.55 * _rim(key)))
		i += 1

		if tile.get("explored", false):
			var features: Array = tile.get("features", [])
			if "Forest" in features or "Jungle" in features:
				var tree_color := Color(0.12, 0.35, 0.15) if "Forest" in features else Color(0.1, 0.42, 0.12)
				if not tile.get("visible", false):
					tree_color = tree_color.darkened(0.45)
				for offset: Vector2 in [Vector2(-0.35, 0.2), Vector2(0.3, 0.3), Vector2(0.0, -0.35)]:
					var p := tile_position(key, height) + Vector3(offset.x, 0.225, offset.y)  # cone is centred
					tree_transforms.append(Transform3D(Basis(), p))
					tree_colors.append(tree_color)

	var tmm := _trees.multimesh
	tmm.instance_count = tree_transforms.size()
	for t in tree_transforms.size():
		tmm.set_instance_transform(t, tree_transforms[t])
		tmm.set_instance_color(t, tree_colors[t])


## A few cloud puffs over every unexplored tile, spilling a little over its edges so the fog's border is soft.
func _build_fog() -> void:
	var unexplored: Array[Vector2i] = []
	for key: Vector2i in _shown:
		if not tiles[key].get("explored", false):
			unexplored.append(key)
	var per_tile := 4 if unexplored.size() < 1500 else 2   # fewer puffs when the whole of a big map is on the table
	var cmm := _clouds.multimesh
	cmm.instance_count = unexplored.size() * per_tile
	var rng := RandomNumberGenerator.new()
	var i := 0
	for key in unexplored:
		rng.seed = hash(key)   # the same tile always gets the same clouds
		var base := tile_position(key, 0.0)
		for p in per_tile:
			var angle := rng.randf() * TAU
			var offset := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(0.1, 0.65)
			var size := rng.randf_range(1.2, 1.7) if per_tile > 2 else rng.randf_range(1.6, 2.1)
			var height := rng.randf_range(0.2, 0.45)
			var puff_basis := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * rng.randf_range(1.0, 1.3), size * 0.8, size))
			cmm.set_instance_transform(i, Transform3D(puff_basis, base + offset + Vector3(0, height, 0)))
			var shade := rng.randf_range(0.5, 0.64)
			cmm.set_instance_color(i, Color(shade, shade + 0.02, shade + 0.06))
			cmm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))   # its bobbing phase, the same every time
			i += 1


## Territory borders like Unciv's: a thin strip in the owner's colour along each edge where the territory ends
## (the next tile belongs to someone else or no one), lying on the ground at the tile's rim.
func _build_borders() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strips := 0
	for key: Vector2i in _shown:
		var tile: Dictionary = tiles[key]
		if not tile.has("owner"):
			continue
		var territory := str(tile["owner"])
		var center := tile_position(key, edge_height(tile) + 0.012)
		var color := civ_color(territory, "outer").darkened(0.55 * _rim(key))
		for neighbour: Vector2i in NEIGHBOURS:
			var other: Dictionary = tiles.get(key + neighbour, {})
			if str(other.get("owner", "")) == territory:
				continue   # same territory: no line between them
			var edge := _edge_towards(key, key + neighbour)
			if edge < 0:
				continue
			var a := _hex_corner(edge, HEX_RADIUS)
			var b := _hex_corner(edge + 1, HEX_RADIUS)
			for v: Vector3 in [a, b, b * BORDER_INNER, a, b * BORDER_INNER, a * BORDER_INNER]:
				st.set_normal(Vector3.UP)
				st.set_color(color)
				st.add_vertex(center + v)
			strips += 1
	_borders.mesh = st.commit() if strips > 0 else null


## Unciv's six neighbours of a tile, as offsets of its (x, y).
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]


## Which of [param key]'s six edges (0-5, edge i runs from corner i to i+1) faces the tile [param other]
## (a neighbour); -1 if that can't be told yet. Unciv's coordinates map linearly to positions on the table,
## so each neighbour offset always means the same edge: worked out once from any pair of tiles.
func _edge_towards(key: Vector2i, other: Vector2i) -> int:
	var offset := other - key
	if _edge_for_offset.has(offset):
		return _edge_for_offset[offset]
	for k: Vector2i in tiles:
		if tiles.has(k + offset):
			var d := tile_position(k + offset, 0) - tile_position(k, 0)
			var edge := posmod(roundi((rad_to_deg(atan2(d.z, d.x)) - 30.0) / 60.0), 6)
			_edge_for_offset[offset] = edge
			return edge
	return -1

var _edge_for_offset: Dictionary = {}   # neighbour offset -> edge index


## How high a tile's rim is (where borders lie): the tileset's "edgeHeights", or the plain hex's top.
func edge_height(tile: Dictionary) -> float:
	if not tile.get("explored", false):
		return 0.02
	if tileset != null and tileset.covers(tile):
		var type := "Water" if terrain_info.get(tile.get("base", ""), {}).get("type") == "Water" else "Land"
		return tileset.edge_height(tile, type)
	return tile_height(tile)


func _build_cities() -> void:
	for child in _cities_root.get_children():
		child.queue_free()
	for key: Vector2i in _shown:
		var tile: Dictionary = tiles[key]
		if not tile.has("city"):
			continue
		var city: Dictionary = tile["city"]
		var outer := civ_color(city["civ"], "outer")
		var inner := civ_color(city["civ"], "inner")
		var node := Node3D.new()
		node.position = tile_position(key, tile_height(tile))
		_cities_root.add_child(node)

		var blocks := [Vector3(-0.25, 0, -0.1), Vector3(0.2, 0, -0.2), Vector3(0.0, 0, 0.25), Vector3(0.3, 0, 0.2)]
		var heights := [0.35, 0.5, 0.3, 0.25]
		for b in blocks.size():
			var box := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.28, heights[b], 0.28)
			box.mesh = mesh
			box.material_override = _flat_material(outer if b % 2 == 0 else inner)
			box.position = blocks[b] + Vector3(0, heights[b] / 2.0, 0)
			node.add_child(box)

		var label := _make_label("%s  %d" % [city["name"], int(city["population"])], 72)
		label.position = Vector3(0, 1.0, 0)
		label.outline_size = 14
		label.modulate = outer.lightened(0.3)
		node.add_child(label)
		# The civ's emblem above the name, like Unciv's city banners
		var emblem := Icons.civ_badge(civ_info.get(city["civ"], {"name": city["civ"]}))
		if emblem != null:
			node.add_child(_billboard(emblem, 0.5, Vector3(0, 1.55, 0)))


func _build_units() -> void:
	for id: int in _tokens:
		var old: Variant = _tokens[id]   # Variant: a token freed by a death animation can still be in here
		if is_instance_valid(old):
			_facing[id] = (old as Node3D).rotation.y
	for child in _units_root.get_children():
		child.queue_free()
	_unit_labels.clear()
	_tokens.clear()
	var moved: Array = []   # [token, from key, to key]
	var seen := {}
	for key: Vector2i in _shown:
		var tile: Dictionary = tiles[key]
		if not tile.has("units"):
			continue
		var base := tile_position(key, tile_height(tile))
		for unit: Dictionary in tile["units"]:
			var token := _make_unit_token(unit, base + _unit_offset(unit))
			_units_root.add_child(token)
			var id := int(unit.get("id", -1))
			_tokens[id] = token
			seen[id] = true
			if _last_key.has(id) and _last_key[id] != key and animate_moves and _shown.has(_last_key[id]) \
					and _world_of(_last_key[id]).distance_to(_world_of(key)) < 12.0:
				moved.append([token, _last_key[id], key, unit])
			_last_key[id] = key
			var label: Label3D = token.get_node("Label")
			if not _unit_labels.has(key):
				_unit_labels[key] = []
			_unit_labels[key].append(label)
	_update_label_visibility()
	for m: Array in moved:   # glide the units that moved since the last refresh
		var token: Node3D = m[0]
		var target := token.position
		token.position = tile_position(m[1], tile_height(tiles.get(m[1], {}))) + _unit_offset(m[3])
		var path := path_points(m[1], m[2], m[3])
		motion.move(token, path.slice(1) if path.size() > 1 else [target])


## Where a unit stands on its tile: military units back left, civilians front right (both can share a tile).
func _unit_offset(unit: Dictionary) -> Vector3:
	return Vector3(0.3, 0, 0.3) if unit.get("civilian", false) else Vector3(-0.25, 0, -0.2)


## The table positions a unit passes through going from [param from] to [param to] in a straight hex line
## (Unciv only says where a unit started and ended), ending exactly on [param to].
func path_points(from: Vector2i, to: Vector2i, unit: Dictionary = {}) -> Array:
	var a := _world_of(from)
	var b := _world_of(to)
	var steps := maxi(1, roundi(a.distance_to(b) / SQRT3))
	var points: Array = []
	var last := from
	for i in range(0, steps + 1):
		var p := a.lerp(b, float(i) / steps)
		var key := _nearest_tile(p, last)
		if i == steps:
			key = to
		if i > 0 and key == last:
			continue
		last = key
		points.append(tile_position(key, tile_height(tiles.get(key, {}))) + _unit_offset(unit))
	return points


func _nearest_tile(p: Vector2, near: Vector2i) -> Vector2i:
	var best := near
	var best_d := INF
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var k := near + Vector2i(dx, dy)
			if tiles.has(k):
				var d := _world_of(k).distance_to(p)
				if d < best_d:
					best_d = d
					best = k
	return best


## Plays one of the bridge's turn events (endTurn "events": moves and attacks the player could see) on the
## table, and changes the map's own copy of the units to match, so redraws during playback stay right.
func play_event(e: Dictionary) -> void:
	var from := _coord(e.get("from"))
	var to := _coord(e.get("to"))
	var seen := _shown.has(from) or _shown.has(to)
	match str(e.get("type", "")):
		"move":
			var id := int(e.get("unit", -1))
			var unit := _take_unit(id, from)
			if unit.is_empty():
				unit = {"id": id, "name": str(e.get("name", "")), "civ": str(e.get("civ", "")), "health": 100}
			_put_unit(unit, to)
			_last_key[id] = to
			var token := token_for(id)
			if token == null and seen:
				token = _make_unit_token(unit, tile_position(from, tile_height(tiles.get(from, {}))) + _unit_offset(unit))
				_units_root.add_child(token)
				_tokens[id] = token
			if token != null and seen:
				var path := path_points(from, to, unit)
				motion.hear("whoosh", to_global(tile_position(to, tile_height(tiles.get(to, {})))), 0.7)
				await motion.move(token, path.slice(1) if path.size() > 1 else path)
		"attack":
			var target_pos := tile_position(to, tile_height(tiles.get(to, {})))
			var attacker: Node3D = null
			if e.has("attacker"):
				attacker = token_for(int(e["attacker"]))
				if attacker == null and seen:
					var unit := {"id": int(e["attacker"]), "name": str(e.get("name", "")), "civ": str(e.get("civ", "")), "health": 100}
					attacker = _make_unit_token(unit, tile_position(from, tile_height(tiles.get(from, {}))) + _unit_offset(unit))
					_units_root.add_child(attacker)
					_tokens[int(e["attacker"])] = attacker
			var defender: Node3D = token_for(int(e["defender"])) if e.has("defender") else null
			if defender != null:
				target_pos = defender.position
			var damage := int(e.get("damage", 0))
			var died: bool = e.get("defenderDied", false)
			if seen:
				var info: Dictionary = unit_info.get(str(e.get("name", "")), {})
				var ranged: bool = e.get("ranged", false) or float(info.get("rangedStrength", 0)) > 0.0
				if ranged or attacker == null:
					await motion.ranged(attacker, target_pos, defender, str(e.get("sound", "")), damage, died,
						tile_position(from, tile_height(tiles.get(from, {}))))
				else:
					await motion.melee(attacker, defender, damage, int(e.get("damageTaken", 0)), died,
						e.get("attackerDied", false), str(e.get("sound", "")))
			# the map's copy of the units: health, and the fallen
			if e.has("defender"):
				var def_id := int(e["defender"])
				if died:
					_take_unit(def_id, to)
					_tokens.erase(def_id)
				else:
					_change_health(def_id, to, -damage)
			if e.has("attacker"):
				if e.get("attackerDied", false):   # its token has been freed by the death animation
					_take_unit(int(e["attacker"]), from)
					_tokens.erase(int(e["attacker"]))
				else:
					_change_health(int(e["attacker"]), from, -int(e.get("damageTaken", 0)))


## Your own attack, after the bridge has done it ([param r] is the attack result): the unit fires or charges,
## then (if it won and advanced) steps onto the tile.
func animate_attack(unit_id: int, unit_name: String, target: Vector2i, r: Dictionary) -> void:
	var token := token_for(unit_id)
	if token == null or not _shown.has(target):
		return
	var info: Dictionary = unit_info.get(unit_name, {})
	var def_id := _first_unit_id_on(target, unit_id)
	var defender := token_for(def_id)
	var target_pos := defender.position if defender != null else tile_position(target, tile_height(tiles.get(target, {})))
	var start_key: Vector2i = _last_key.get(unit_id, target)
	var died: bool = r.get("defenderDefeated", false)
	if float(info.get("rangedStrength", 0)) > 0.0:
		await motion.ranged(token, target_pos, defender, str(info.get("attackSound", "")), int(r.get("damageToDefender", 0)), died)
	else:
		# melee units first walk up next to the target if they weren't already
		var path := path_points(start_key, target, {})
		if path.size() > 2:
			var unit := {"civilian": false}
			await motion.move(token, path_points(start_key, target, unit).slice(1, -1))
		await motion.melee(token, defender, int(r.get("damageToDefender", 0)), int(r.get("damageToAttacker", 0)), died,
			not r.get("attackerAlive", true), str(info.get("attackSound", "")))
	# The fallen are freed by their death animation, so forget their tokens before anything looks them up
	if died:
		_tokens.erase(def_id)
	if not r.get("attackerAlive", true):
		_tokens.erase(unit_id)
	if r.has("x") and r.has("y"):
		var now := Vector2i(int(r["x"]), int(r["y"]))
		if now == target and is_instance_valid(token) and r.get("attackerAlive", true):
			await motion.move(token, [tile_position(target, tile_height(tiles.get(target, {}))) + Vector3(-0.25, 0, -0.2)])
		_last_key[unit_id] = now


## A city's bombardment of [param target].
func animate_bombard(city_key: Vector2i, target: Vector2i, r: Dictionary) -> void:
	if not (_shown.has(city_key) or _shown.has(target)):
		return
	var def_id := _first_unit_id_on(target, -1)
	var defender := token_for(def_id)
	var target_pos := defender.position if defender != null else tile_position(target, tile_height(tiles.get(target, {})))
	await motion.ranged(null, target_pos, defender, "cannon", int(r.get("damageToDefender", 0)), r.get("defenderDefeated", false),
		tile_position(city_key, tile_height(tiles.get(city_key, {}))), "bombard")
	if r.get("defenderDefeated", false):
		_tokens.erase(def_id)


## Which unit on [param key] defends it (the last non-civilian, as Unciv would), by id; -1 if none has a token.
func _first_unit_id_on(key: Vector2i, except_id: int) -> int:
	var units: Array = tiles.get(key, {}).get("units", [])
	var best := -1
	for unit: Dictionary in units:
		var id := int(unit.get("id", -1))
		if id == except_id or token_for(id) == null:
			continue
		if best == -1 or not unit.get("civilian", false):
			best = id
	return best


static func _coord(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return NO_TILE


func _take_unit(id: int, near: Vector2i) -> Dictionary:
	for key: Vector2i in ([near] if tiles.has(near) else []) + tiles.keys():
		var units: Array = tiles[key].get("units", [])
		for i in units.size():
			if int(units[i].get("id", -1)) == id:
				var unit: Dictionary = units[i]
				units.remove_at(i)
				return unit
	return {}


func _put_unit(unit: Dictionary, key: Vector2i) -> void:
	if not tiles.has(key):
		return
	if not tiles[key].has("units"):
		tiles[key]["units"] = []
	tiles[key]["units"].append(unit)


func _change_health(id: int, key: Vector2i, delta: int) -> void:
	for unit: Dictionary in tiles.get(key, {}).get("units", []):
		if int(unit.get("id", -1)) == id:
			unit["health"] = clampi(int(unit.get("health", 100)) + delta, 0, 100)


## Forgets where units were (a new or loaded game: its unit ids mean different units).
func forget_unit_positions() -> void:
	_last_key.clear()
	_facing.clear()


## Tells the map a unit is now on [param key] (after a played-back move), so the next refresh doesn't move it again.
func note_unit_at(id: int, key: Vector2i) -> void:
	_last_key[id] = key


## The unit's token, or null. Variant on the way in: a unit that died in an animation leaves a freed node
## behind until the next rebuild, and assigning that to a typed variable is an error that stops the script.
func token_for(id: int) -> Node3D:
	var token: Variant = _tokens.get(id)
	if not is_instance_valid(token):
		_tokens.erase(id)
		return null
	return token as Node3D


## A unit on the table: its model from the tileset in its civ's colours (or, without one, a disc with its flag),
## a health bar when hurt, optionally its Unciv icon above it, and its name for when the tile is pointed at.
func _make_unit_token(unit: Dictionary, at: Vector3) -> Node3D:
	var outer := civ_color(unit["civ"], "outer")
	var inner := civ_color(unit["civ"], "inner")
	var token := Node3D.new()
	token.position = at
	var id := int(unit.get("id", -1))
	token.rotation.y = _facing.get(id, 0.0)
	var info: Dictionary = unit_info.get(str(unit["name"]), {})
	var domain := str(info.get("domain", "Land"))
	token.set_meta("unit_id", id)
	token.set_meta("naval", domain == "Water" or unit.get("embarked", false))
	var units := _units_set()
	var model: Dictionary = units.unit_model(str(unit["name"]), info, unit.get("embarked", false)) if units != null else {}
	var health_left := int(unit.get("health", 100))
	var flag_height := 0.42
	if model.has("mesh") or model.has("scene"):
		var base := MeshInstance3D.new()   # a thin disc in the civ's colours under the model
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.24
		base_mesh.bottom_radius = 0.25
		base_mesh.height = 0.016
		base_mesh.radial_segments = 16
		base.mesh = base_mesh
		base.material_override = _flat_material(outer)
		base.position.y = 0.008
		token.add_child(base)
		var figure: Node3D
		if model.has("mesh"):
			var mi := MeshInstance3D.new()
			mi.mesh = model["mesh"]
			_tint_civ_surfaces(mi, outer, inner)
			figure = mi
		else:
			figure = (model["scene"] as PackedScene).instantiate()
		figure.name = "Model"
		figure.scale = Vector3.ONE * units.unit_scale()
		figure.position.y = 0.016
		token.add_child(figure)
		flag_height = 0.95 if domain == "Air" else 0.62
		if overlays.flags.get("unit_icons", true):
			var icon := Icons.badge("unit", str(unit["name"]), inner, outer)
			if icon != null:
				token.add_child(_billboard(icon, 0.34, Vector3(0, flag_height, 0)))
	else:
		var disc := MeshInstance3D.new()
		var disc_mesh := CylinderMesh.new()
		disc_mesh.top_radius = 0.3
		disc_mesh.bottom_radius = 0.32
		disc_mesh.height = 0.08
		disc.mesh = disc_mesh
		disc.material_override = _flat_material(inner)
		disc.position.y = 0.04
		token.add_child(disc)
		var flag := Icons.badge("unit", str(unit["name"]), inner, outer)
		if flag != null:
			token.add_child(_billboard(flag, 0.62, Vector3(0, 0.42, 0)))
		else:
			var figure := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.12
			capsule.height = 0.5
			figure.mesh = capsule
			figure.position.y = 0.33
			figure.material_override = _flat_material(outer)
			token.add_child(figure)
	if health_left < 100:   # the health bar, always shown when hurt (green / yellow / red, like the unit card)
		token.add_child(_health_bar(health_left, flag_height - 0.22))
	var text := str(unit["name"]) + (" %d%%" % health_left if health_left < 100 else "")
	var name_label := _make_label(text, 44)
	name_label.name = "Label"
	name_label.position = Vector3(0, flag_height + 0.5, 0)
	name_label.visible = false
	token.add_child(name_label)
	return token


func _health_bar(health: int, height: float) -> Node3D:
	var bar := Sprite3D.new()   # a billboard, so it reads the same from every side
	var image := Image.create(50, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.1, 0.1, 0.85))
	var fill := Color(0.3, 0.85, 0.3) if health > 66 else (Color(0.95, 0.8, 0.2) if health > 33 else Color(0.95, 0.3, 0.2))
	image.fill_rect(Rect2i(1, 1, maxi(1, int(48 * health / 100.0)), 4), fill)
	bar.texture = ImageTexture.create_from_image(image)
	bar.pixel_size = 0.4 / 50.0
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.shaded = false
	bar.no_depth_test = true
	bar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bar.position = Vector3(0, height, 0)
	bar.name = "HealthBar"
	return bar


## Gives the model's CivOuter / CivInner surfaces the owner's colours (one material per colour, shared).
func _tint_civ_surfaces(mi: MeshInstance3D, outer: Color, inner: Color) -> void:
	var mesh := mi.mesh
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		if not material is BaseMaterial3D:
			continue
		var which := material.resource_name.to_lower()
		var color: Color
		if which.ends_with("civouter"):
			color = outer
		elif which.ends_with("civinner"):
			color = inner
		else:
			continue
		var key := "%d|%s" % [material.get_instance_id(), color.to_html()]
		if not _civ_materials.has(key):
			var tinted := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
			tinted.albedo_color = color
			_civ_materials[key] = tinted
		mi.set_surface_override_material(i, _civ_materials[key])


# region highlights -------------------------------------------------------------------------

func set_hover(key: Vector2i) -> void:
	if key != _hover:
		_hover = key
		_build_highlights()
		_update_label_visibility()


func set_selection(selected: Vector2i, reachable: Array[Vector2i], targets: Array[Vector2i] = []) -> void:
	_selected = selected
	_reachable = reachable
	_targets = targets
	_build_highlights()
	_place_beacon()
	_update_label_visibility()


func _place_beacon() -> void:
	if _shown.has(_selected):
		var tile: Dictionary = tiles[_selected]
		_beacon.position = tile_position(_selected, tile_height(tile) + 2.5)
		_beacon.visible = true
	else:
		_beacon.visible = false


func clear_selection() -> void:
	set_selection(Vector2i(999999, 999999), [], [])


func is_target(key: Vector2i) -> bool:
	return key in _targets


func is_reachable(key: Vector2i) -> bool:
	return key in _reachable


## Marks where the selected unit is aimed: a bright ring on [param key], a dot where each turn of the
## journey ends (numbered), and [param text] floating above, e.g. "Move here: 2 turns - click again".
func set_aim(key: Vector2i, stops: Array[Vector2i], text: String, color: Color) -> void:
	clear_aim()
	_aim_key = key
	if not tiles.has(key):
		return
	_aim_root = Node3D.new()
	_aim_root.name = "Aim"
	_content.add_child(_aim_root)

	var ring := MeshInstance3D.new()
	ring.mesh = _make_ring_mesh(0.45)
	var glow := _flat_material(color)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = glow
	ring.position = tile_position(key, tile_height(tiles[key]) + 0.03)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_root.add_child(ring)

	for i in stops.size():
		var stop := stops[i]
		if stop == key or not tiles.has(stop):
			continue
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		dot.mesh = sphere
		dot.material_override = _flat_material(color)
		dot.position = tile_position(stop, tile_height(tiles[stop]) + 0.15)
		_aim_root.add_child(dot)
		var number := _make_label(str(i + 1), 40)
		number.position = dot.position + Vector3(0, 0.45, 0)
		_aim_root.add_child(number)

	var label := _make_label(text, 36)
	label.modulate = color.lightened(0.5)
	label.no_depth_test = true   # always readable, even behind a unit or a city
	label.position = tile_position(key, tile_height(tiles[key]) + 1.3)
	_aim_root.add_child(label)


func clear_aim() -> void:
	_aim_key = NO_TILE
	if _aim_root != null:
		_aim_root.queue_free()
		_aim_root = null


func aim_key() -> Vector2i:
	return _aim_key


func _update_label_visibility() -> void:
	for key: Vector2i in _unit_labels:
		var shown := key == _hover or key == _selected or key in _targets
		for label: Label3D in _unit_labels[key]:
			label.visible = shown


func _build_highlights() -> void:
	var rings: Array = []  # [key, color]
	for key in _reachable:
		if key not in _targets:
			rings.append([key, Color(0.3, 0.9, 1.0)])
	for key in _targets:
		rings.append([key, Color(1.0, 0.2, 0.15)])
	if tiles.has(_selected):
		rings.append([_selected, Color(1.0, 0.85, 0.2)])
	if tiles.has(_hover):
		rings.append([_hover, Color(1, 1, 1)])
	rings = rings.filter(func(r: Array) -> bool: return _shown.has(r[0]))
	var mm := _highlights.multimesh
	mm.instance_count = rings.size()
	for i in rings.size():
		var key: Vector2i = rings[i][0]
		var tile: Dictionary = tiles.get(key, {})
		mm.set_instance_transform(i, Transform3D(Basis(), tile_position(key, tile_height(tile) + 0.01)))
		mm.set_instance_color(i, rings[i][1])


# region queries ---------------------------------------------------------------------------

## Position of a tile centre in this node's local space (i.e. before this node's own scale).
func tile_local_center(key: Vector2i) -> Vector3:
	return tile_position(key, tile_height(tiles.get(key, {}))) + _center_offset


## The tile under a point given in global coordinates, or null.
func tile_at_global(point: Vector3) -> Variant:
	var local := to_local(point) - _center_offset
	var p := Vector2(local.x, -local.z)
	var best: Variant = null
	var best_distance := 1.0  # must be within one hex radius
	for key: Vector2i in _shown:
		var tile: Dictionary = tiles[key]
		var d := p.distance_to(Vector2(tile["wx"], tile["wy"]))
		if d < best_distance:
			best_distance = d
			best = key
	return best


## Intersects a ray (global space) with the table surface and returns the tile hit, or null.
func pick(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	var plane := Plane(global_transform.basis.y.normalized(), global_position + global_transform.basis.y * 0.15)
	var hit: Variant = plane.intersects_ray(ray_origin, ray_direction)
	if hit == null:
		return null
	return tile_at_global(hit)


func tile_position(key: Vector2i, y: float) -> Vector3:
	var tile: Dictionary = tiles.get(key, {})
	return Vector3(tile.get("wx", 0.0), y, -float(tile.get("wy", 0.0)))


func tile_height(tile: Dictionary) -> float:
	if not tile.get("explored", false):
		return 0.02
	if tileset != null and tileset.covers(tile):
		var type := "Water" if terrain_info.get(tile.get("base", ""), {}).get("type") == "Water" else "Land"
		return tileset.surface_height(tile, type)
	var features: Array = tile.get("features", [])
	if tile.get("base") == "Mountain" or "Mountain" in features:
		return 0.6
	if tile.has("wonder"):
		return 0.4
	if "Hill" in features:
		return 0.3
	var info: Dictionary = terrain_info.get(tile.get("base", ""), {})
	if info.get("type") == "Water":
		return 0.03 if tile.get("base") == "Ocean" else 0.06
	return 0.15


func tile_color(tile: Dictionary) -> Color:
	if not tile.get("explored", false):
		return UNEXPLORED_COLOR
	var color := _terrain_rgb(tile.get("base", ""), Color(0.5, 0.5, 0.5))
	for feature: String in tile.get("features", []):
		if feature == "Forest" or feature == "Jungle":
			continue  # drawn as trees instead
		color = color.lerp(_terrain_rgb(feature, color), 0.6)
	if tile.has("wonder"):
		color = Color(0.85, 0.7, 0.25)
	if not tile.get("visible", false):
		color = color.darkened(0.45)
	return color


func civ_color(civ_name: String, which: String) -> Color:
	var colors: Dictionary = civ_colors.get(civ_name, {})
	return colors.get(which, Color.WHITE)


func describe_tile(key: Vector2i) -> String:
	var tile: Dictionary = tiles.get(key, {})
	if tile.is_empty():
		return ""
	if not tile.get("explored", false):
		return "Unexplored (%d, %d)" % [key.x, key.y]
	var parts: Array[String] = [tile.get("base", "?")]
	for f: String in tile.get("features", []):
		parts.append(f)
	if tile.has("wonder"):
		parts.append(tile["wonder"])
	if tile.has("resource"):
		parts.append("[%s]" % tile["resource"])
	if tile.has("improvement"):
		parts.append(tile["improvement"])
	var text := ", ".join(parts)
	if tile.has("owner"):
		text += " - %s territory" % tile["owner"]
	if tile.has("city"):
		text += " - city of %s" % tile["city"]["name"]
	for unit: Dictionary in tile.get("units", []):
		text += "\n  %s (%s, %d HP)" % [unit["name"], unit["civ"], int(unit["health"])]
	return text


func _terrain_rgb(terrain_name: String, fallback: Color) -> Color:
	var info: Dictionary = terrain_info.get(terrain_name, {})
	var rgb: Array = info.get("rgb", [])
	if rgb.size() < 3:
		return fallback
	return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))


# region mesh helpers ----------------------------------------------------------------------

## [param custom_data]: each instance also carries four numbers of its own for the shader (INSTANCE_CUSTOM).
func _make_multimesh_node(node_name: String, mesh: Mesh, material: Material, custom_data := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom_data
	mm.mesh = mesh
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = material
	_content.add_child(node)
	return node


func _vertex_color_material(roughness: float, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


func _hex_corner(i: int, radius: float) -> Vector3:
	var angle := deg_to_rad(60.0 * i)  # corner on +X => flat-topped, matching Unciv's layout
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)


## Hex prism from y=0 to y=1 (scaled per tile), with explicit normals.
func _make_prism_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 1, 0)
	for i in 6:
		var a := _hex_corner(i, HEX_RADIUS)
		var b := _hex_corner((i + 1) % 6, HEX_RADIUS)
		# top face
		st.set_normal(Vector3.UP)
		st.add_vertex(top)
		st.set_normal(Vector3.UP)
		st.add_vertex(b + top)
		st.set_normal(Vector3.UP)
		st.add_vertex(a + top)
		# side face
		var n := ((a + b) / 2.0).normalized()
		for v: Vector3 in [a, b + top, a + top, a, b, b + top]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()


## Flat hexagonal ring (annulus) at y=0, used for borders and highlights.
func _make_ring_mesh(inner_ratio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a := _hex_corner(i, HEX_RADIUS)
		var b := _hex_corner((i + 1) % 6, HEX_RADIUS)
		var ai := a * inner_ratio
		var bi := b * inner_ratio
		for v: Vector3 in [a, b, bi, a, bi, ai]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _make_cone_mesh() -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.17
	cone.height = 0.45
	cone.radial_segments = 8
	return cone


## A picture that always faces you, [param diameter] map units across.
func _billboard(texture: Texture2D, diameter: float, at: Vector3) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = diameter / float(texture.get_width())
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.shaded = false
	sprite.position = at
	return sprite


func _make_label(text: String, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 8
	label.no_depth_test = false
	return label
