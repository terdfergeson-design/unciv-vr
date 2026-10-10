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
	// Each puff bobs gently, out of step with its neighbours
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831;
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
var overlays: Node3D                # map_overlays.gd: Unciv's five map overlays
var tileset: RefCounted = null      # tileset.gd; null draws every tile as a plain coloured hex
var tileset_name := ""
var map_extent := 10.0              # half-size of the map, in map units

var _content: Node3D                # everything, offset so the map is centred on this node
var _terrain: MultiMeshInstance3D
var _trees: MultiMeshInstance3D
var _pieces_root: Node3D            # one MultiMeshInstance3D per tileset piece in use
var _piece_nodes: Dictionary = {}   # piece Mesh -> its MultiMeshInstance3D
var _piece_scenes: Node3D           # pieces that are whole Godot scenes, one instance per tile
var _borders: MultiMeshInstance3D
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
	_borders = _make_multimesh_node("Borders", _make_ring_mesh(0.80), _vertex_color_material(0.6, true))
	_highlights = _make_multimesh_node("Highlights", _make_ring_mesh(0.62), _vertex_color_material(0.4, true))
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 0.55
	puff.radial_segments = 9
	puff.rings = 4
	var fog := ShaderMaterial.new()
	fog.shader = Shader.new()
	fog.shader.code = FOG_SHADER
	_clouds = _make_multimesh_node("Fog", puff, fog)
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


func set_ruleset(ruleset: Dictionary) -> void:
	terrain_info = ruleset.get("terrains", {})
	resource_info = ruleset.get("resources", {})


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
	for key: String in new_flags:
		if overlays.flags.has(key):
			overlays.flags[key] = bool(new_flags[key])
	if overlays.flags.get("improvements", true) != pictures_before and tileset != null and not tiles.is_empty():
		_build_terrain()   # the tileset's improvement models follow Unciv's "improvement pictures" toggle
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
	var turns := (h / 7) % 6 if tileset.random_rotation() else 0
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
			i += 1


func _build_borders() -> void:
	var owned: Array[Vector2i] = []
	for key: Vector2i in _shown:
		if tiles[key].has("owner"):
			owned.append(key)
	var mm := _borders.multimesh
	mm.instance_count = owned.size()
	for i in owned.size():
		var key := owned[i]
		var tile: Dictionary = tiles[key]
		mm.set_instance_transform(i, Transform3D(Basis(), tile_position(key, tile_height(tile) + 0.005)))
		mm.set_instance_color(i, civ_color(tile["owner"], "outer"))


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
	for child in _units_root.get_children():
		child.queue_free()
	_unit_labels.clear()
	for key: Vector2i in _shown:
		var tile: Dictionary = tiles[key]
		if not tile.has("units"):
			continue
		var base := tile_position(key, tile_height(tile))
		for unit: Dictionary in tile["units"]:
			var civilian: bool = unit.get("civilian", false)
			var offset := Vector3(0.3, 0, 0.3) if civilian else Vector3(-0.25, 0, -0.2)
			var token := _make_unit_token(unit, base + offset)
			_units_root.add_child(token)
			var label: Label3D = token.get_node("Label")
			if not _unit_labels.has(key):
				_unit_labels[key] = []
			_unit_labels[key].append(label)
	_update_label_visibility()


func _make_unit_token(unit: Dictionary, at: Vector3) -> Node3D:
	var outer := civ_color(unit["civ"], "outer")
	var inner := civ_color(unit["civ"], "inner")
	var token := Node3D.new()
	token.position = at

	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.3
	disc_mesh.bottom_radius = 0.32
	disc_mesh.height = 0.08
	disc.mesh = disc_mesh
	disc.material_override = _flat_material(inner)
	disc.position.y = 0.04
	token.add_child(disc)

	# Unciv-style flag: the unit's icon in the civ's colours on a round badge, always facing you
	var flag := Icons.badge("unit", str(unit["name"]), inner, outer)
	if flag != null:
		token.add_child(_billboard(flag, 0.62, Vector3(0, 0.42, 0)))
		var health_left := int(unit.get("health", 100))
		if health_left < 100:   # a little health bar under the flag
			var bar := MeshInstance3D.new()
			var bar_mesh := BoxMesh.new()
			bar_mesh.size = Vector3(0.5 * health_left / 100.0, 0.05, 0.05)
			bar.mesh = bar_mesh
			bar.material_override = _flat_material(Color(0.3, 0.9, 0.3) if health_left > 50 else Color(0.95, 0.3, 0.2))
			bar.position = Vector3(0, 0.08, 0.3)
			token.add_child(bar)
		var name_label := _make_label(str(unit["name"]) + (" %d%%" % health_left if health_left < 100 else ""), 44)
		name_label.name = "Label"
		name_label.position = Vector3(0, 0.95, 0)
		name_label.visible = false
		token.add_child(name_label)
		return token
	var figure := MeshInstance3D.new()
	if unit.get("civilian", false):
		var sphere := SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		figure.mesh = sphere
		figure.position.y = 0.23
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.12
		capsule.height = 0.5
		figure.mesh = capsule
		figure.position.y = 0.33
	figure.material_override = _flat_material(outer)
	token.add_child(figure)

	var health := int(unit.get("health", 100))
	var text: String = unit["name"]
	if health < 100:
		text += " %d%%" % health
	var label := _make_label(text, 44)
	label.name = "Label"
	label.position = Vector3(0, 0.8, 0)
	label.visible = false
	token.add_child(label)
	return token


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

func _make_multimesh_node(node_name: String, mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
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
