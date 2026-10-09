# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## Unciv's five map overlays, drawn on the table (toggled by the round buttons next to the overview):
##   "movement"     - arrows showing where visible units moved lately
##   "yields"       - food / production / gold... symbols on each tile
##   "worked"       - a citizen symbol on the tiles your cities work
##   "resources"    - resource and improvement symbols (Unciv's "resources and improvements")
##   "improvements" - the improvements themselves as little models, plus roads
## Lives inside the HexMap's content node, in map units, so it slides and zooms with the map.

const Icons := preload("res://scripts/icons.gd")

var flags := {"movement": false, "yields": false, "worked": false, "resources": true, "improvements": true}

var _map: Node3D                    # the HexMap
var _decals: Node3D                 # flat symbols lying on the tiles (one MultiMesh per picture)
var _models: Node3D                 # improvement models and roads
var _arrows: MeshInstance3D         # unit movement arrows
var _yield_layer: Node3D
var _quad: QuadMesh
var _materials: Dictionary = {}     # texture -> material
var city: Dictionary = {}           # the city view's getCity result (empty outside the city view)
var _city_layer: Node3D             # city view: worked / locked / buy symbols, yields, shading


func setup(map: Node3D) -> void:
	_map = map
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_quad.orientation = PlaneMesh.FACE_Y
	_decals = Node3D.new()
	add_child(_decals)
	_yield_layer = Node3D.new()
	add_child(_yield_layer)
	_models = Node3D.new()
	add_child(_models)
	_city_layer = Node3D.new()
	add_child(_city_layer)
	_arrows = MeshInstance3D.new()
	var arrow_material := StandardMaterial3D.new()
	arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_material.vertex_color_use_as_albedo = true
	arrow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arrows.material_override = arrow_material
	add_child(_arrows)


## Redraws everything except yields (which come from the bridge separately) for the tiles being shown.
func rebuild(shown: Dictionary) -> void:
	if _map == null:
		return
	_clear(_decals)
	_clear(_models)
	_build_city(shown)
	_build_symbols(shown)
	if flags["improvements"]:
		_build_improvement_models(shown)
	_build_arrows(shown)
	if not flags["yields"] or not city.is_empty():
		_clear(_yield_layer)


## Yields per tile from the bridge's getYields: [{x, y, food?, production?, ...}].
func show_yields(tiles: Array, shown: Dictionary) -> void:
	_clear(_yield_layer)
	if not flags["yields"] or not city.is_empty():
		return
	var groups := {}   # stat -> Array[Transform3D]
	for entry: Dictionary in tiles:
		var key := Vector2i(int(entry["x"]), int(entry["y"]))
		if not shown.has(key):
			continue
		var tile: Dictionary = _map.tiles.get(key, {})
		var top: float = _map.tile_height(tile) + 0.04
		var symbols: Array[String] = []
		for stat: String in ["food", "production", "gold", "science", "culture", "faith"]:
			for i in mini(int(entry.get(stat, 0)), 3):   # up to three of each, like Unciv's tile yields
				symbols.append(stat)
		# One row of up to four symbols, two rows beyond that (like Unciv's tile yields)
		var count := symbols.size()
		var per_row := count if count <= 4 else ceili(count / 2.0)
		for i in count:
			var row := i / per_row
			var in_row := mini(per_row, count - row * per_row)
			var x := (i % per_row - (in_row - 1) / 2.0) * 0.36
			var z := -0.05 + (row - (0.5 if count > per_row else 0.0)) * 0.38
			var at: Vector3 = _map.tile_position(key, top) + Vector3(x, 0, z)
			if not groups.has(symbols[i]):
				groups[symbols[i]] = []
			groups[symbols[i]].append(Transform3D(Basis().scaled(Vector3(0.4, 1, 0.4)), at))
	for stat: String in groups:
		_add_decals(_yield_layer, Icons.get_icon("stat", stat.capitalize()), groups[stat])


# region city view ----------------------------------------------------------------------------

## The city view's marks on the table (Unciv's city screen): each tile's yields, a worked / locked / not worked
## symbol on the tiles the city can work, prices on tiles it can buy, a purple outline on the next tile its
## borders will take, and shading over everything it can't work. An empty [param data] clears them.
func show_city(data: Dictionary, shown: Dictionary) -> void:
	city = data
	_clear(_yield_layer)
	_build_city(shown)


func _build_city(shown: Dictionary) -> void:
	_clear(_city_layer)
	if city.is_empty():
		return
	var symbols := {}   # texture -> transforms
	var yields := {}    # stat -> transforms
	var shade: Array = []
	var outline: Array = []
	for t: Dictionary in city.get("tiles", []):
		var key := Vector2i(int(t["x"]), int(t["y"]))
		if not shown.has(key) or not _map.tiles.has(key):
			continue
		var tile: Dictionary = _map.tiles[key]
		var top: float = _map.tile_height(tile) + 0.05
		var centre: Vector3 = _map.tile_position(key, top)
		var state := str(t.get("state", ""))
		# Yields across the middle of the tile (up to three of each, like Unciv)
		var stat_list: Array[String] = []
		for stat: String in ["food", "production", "gold", "science", "culture", "faith"]:
			for i in mini(roundi(float(t.get("yields", {}).get(stat, 0.0))), 3):
				stat_list.append(stat)
		var count := stat_list.size()
		var per_row := count if count <= 4 else ceili(count / 2.0)
		for i in count:
			var row := i / per_row
			var in_row := mini(per_row, count - row * per_row)
			var at := centre + Vector3((i % per_row - (in_row - 1) / 2.0) * 0.34, 0, -0.3 + row * 0.34)
			if not yields.has(stat_list[i]):
				yields[stat_list[i]] = []
			yields[stat_list[i]].append(Transform3D(Basis().scaled(Vector3(0.36, 1, 0.36)), at))
		# The citizen symbol (Unciv's TileIcons) at the bottom of the tile
		var icon := ""
		match state:
			"worked": icon = "Worked"
			"locked": icon = "Locked"
			"notWorked": icon = "NotWorked"
			"center": icon = "CityCenter"
			"blockaded": icon = "Blockaded"
			"buyable": icon = "Buy"
		if icon != "":
			var texture := Icons.get_icon("tile", icon)
			if texture != null:
				if not symbols.has(texture):
					symbols[texture] = []
				symbols[texture].append(Transform3D(Basis().scaled(Vector3(0.5, 1, 0.5)), centre + Vector3(0, 0.01, 0.45)))
		if state == "buyable" and t.has("buyCost"):
			var price := Label3D.new()
			price.text = "%d" % int(t["buyCost"])
			price.font_size = 64
			price.pixel_size = 0.0045
			price.outline_size = 14
			price.modulate = Color(1.0, 0.85, 0.3) if t.get("canAfford", false) else Color(1.0, 0.4, 0.35)
			price.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			price.position = centre + Vector3(0, 0.32, 0.45)
			_city_layer.add_child(price)
		if state in ["foreign", "outOfRange", "otherCity", "buyable"]:
			shade.append(centre + Vector3(0, -0.03, 0))
		if t.get("nextToOwn", false):
			outline.append(centre)
	for stat: String in yields:
		_add_decals(_city_layer, Icons.get_icon("stat", stat.capitalize()), yields[stat])
	for texture: Texture2D in symbols:
		_add_decals(_city_layer, texture, symbols[texture])
	if not shade.is_empty():
		_add_hexes(shade, 0.97, Color(0.0, 0.0, 0.05, 0.55))
	if not outline.is_empty():
		_add_outline(outline, Color(0.8, 0.12, 0.88))


## Translucent flat hexagons (shading over the tiles the city can't work), corners like the map's tiles.
func _add_hexes(centres: Array, radius: float, colour: Color) -> void:
	var vertices := PackedVector3Array()
	for c: Vector3 in centres:
		for i in 6:
			var a := deg_to_rad(60.0 * i)
			var b := deg_to_rad(60.0 * (i + 1))
			vertices.append_array([c, c + Vector3(cos(b), 0, sin(b)) * radius, c + Vector3(cos(a), 0, sin(a)) * radius])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = colour
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_city_layer.add_child(node)


## A coloured hexagon outline around each of [param centres] (Unciv's purple "next tile" outline).
func _add_outline(centres: Array, colour: Color) -> void:
	var segments: Array = []
	for c: Vector3 in centres:
		for i in 6:
			var a := deg_to_rad(60.0 * i)
			var b := deg_to_rad(60.0 * (i + 1))
			segments.append([c + Vector3(cos(a), 0, sin(a)) * 0.88, c + Vector3(cos(b), 0, sin(b)) * 0.88, colour])
	var node := MeshInstance3D.new()
	node.mesh = _ribbons(segments, 0.1, 0.02, false)
	node.material_override = _arrows.material_override
	_city_layer.add_child(node)


# region symbols ----------------------------------------------------------------------------

func _build_symbols(shown: Dictionary) -> void:
	var groups := {}   # texture -> Array[Transform3D]
	for key: Vector2i in shown:
		var tile: Dictionary = _map.tiles[key]
		if not tile.get("explored", false):
			continue
		var top: float = _map.tile_height(tile) + 0.03
		if flags["resources"] and tile.has("resource"):
			var texture := Icons.badge("resource", str(tile["resource"]), _resource_color(str(tile["resource"])), Color.WHITE, 0.62)
			_group(groups, texture, Transform3D(Basis().scaled(Vector3(0.5, 1, 0.5)), _map.tile_position(key, top) + Vector3(-0.4, 0, 0.38)))
		if flags["resources"] and tile.has("improvement") and not tile.has("city"):
			var texture := Icons.badge("improvement", str(tile["improvement"]), Color(0.2, 0.22, 0.28), Color.WHITE, 0.62)
			_group(groups, texture, Transform3D(Basis().scaled(Vector3(0.5, 1, 0.5)), _map.tile_position(key, top) + Vector3(0.4, 0, 0.38)))
		if flags["worked"] and tile.get("worked", false) and not tile.has("city"):
			var texture := Icons.get_icon("stat", "Population")
			_group(groups, texture, Transform3D(Basis().scaled(Vector3(0.36, 1, 0.36)), _map.tile_position(key, top) + Vector3(0, 0, -0.42)))
	for texture: Texture2D in groups:
		_add_decals(_decals, texture, groups[texture])


func _resource_color(resource: String) -> Color:
	match str(_map.resource_info.get(resource, {}).get("type", "")):
		"Luxury":
			return Color(0.72, 0.45, 0.85)
		"Strategic":
			return Color(0.75, 0.35, 0.2)
	return Color(0.3, 0.6, 0.3)   # bonus


func _group(groups: Dictionary, texture: Texture2D, transform: Transform3D) -> void:
	if texture == null:
		return
	if not groups.has(texture):
		groups[texture] = []
	groups[texture].append(transform)


## Flat pictures lying on the tiles: one MultiMesh per picture.
func _add_decals(parent: Node3D, texture: Texture2D, transforms: Array) -> void:
	if texture == null or transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _quad
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _material(texture)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


func _material(texture: Texture2D) -> StandardMaterial3D:
	if _materials.has(texture):
		return _materials[texture]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.4
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[texture] = material
	return material


# region improvement models -----------------------------------------------------------------

## Little models for improvements (fields, mines, camps...) and roads between neighbouring road tiles.
func _build_improvement_models(shown: Dictionary) -> void:
	var road_lines: Array = []   # [from, to, colour]
	for key: Vector2i in shown:
		var tile: Dictionary = _map.tiles[key]
		if not tile.get("explored", false):
			continue
		var top: float = _map.tile_height(tile)
		var centre: Vector3 = _map.tile_position(key, top)
		if tile.has("improvement") and not tile.has("city"):
			var model := _improvement_model(str(tile["improvement"]))
			if model != null:
				model.position = centre + Vector3(0.05, 0, -0.05)
				_models.add_child(model)
		var road := str(tile.get("road", "None"))
		if road != "None" or tile.has("city"):
			for neighbour: Vector2i in _neighbours(key):
				if neighbour < key or not shown.has(neighbour):
					continue   # each pair once
				var other: Dictionary = _map.tiles.get(neighbour, {})
				if str(other.get("road", "None")) == "None" and not other.has("city"):
					continue
				if road == "None" and str(other.get("road", "None")) == "None":
					continue   # two cities next to each other, no road
				var colour := Color(0.3, 0.3, 0.32) if road == "Railroad" or str(other.get("road")) == "Railroad" else Color(0.55, 0.4, 0.25)
				road_lines.append([centre, _map.tile_position(neighbour, _map.tile_height(other)), colour])
	if not road_lines.is_empty():
		var roads := MeshInstance3D.new()
		roads.mesh = _ribbons(road_lines, 0.12, 0.03, false)
		roads.material_override = _arrows.material_override
		_models.add_child(roads)


static func _neighbours(key: Vector2i) -> Array[Vector2i]:
	return [key + Vector2i(1, 0), key + Vector2i(-1, 0), key + Vector2i(0, 1), key + Vector2i(0, -1),
		key + Vector2i(1, 1), key + Vector2i(-1, -1)]


func _improvement_model(improvement: String) -> Node3D:
	var root := Node3D.new()
	match improvement:
		"Farm", "Terrace farm", "Polder":
			for i in 3:   # rows of crops
				_box(root, Vector3(0.62, 0.03, 0.1), Vector3(0, 0.02, -0.2 + i * 0.2), Color(0.85, 0.75, 0.3))
		"Mine":
			_cone(root, 0.22, 0.28, Vector3(0, 0.14, 0), Color(0.35, 0.33, 0.32))
			_box(root, Vector3(0.12, 0.12, 0.04), Vector3(0, 0.06, 0.2), Color(0.1, 0.08, 0.06))
		"Quarry":
			for i in 3:
				_box(root, Vector3(0.16, 0.12, 0.16), Vector3(-0.18 + i * 0.18, 0.06, 0.05 * (i % 2)), Color(0.75, 0.73, 0.68))
		"Pasture":
			for i in 4:   # a little fence
				var angle := TAU * i / 4.0
				_box(root, Vector3(0.04, 0.12, 0.42), Vector3(cos(angle), 0, sin(angle)) * 0.22 + Vector3(0, 0.06, 0), Color(0.5, 0.35, 0.2)).rotation.y = angle
		"Camp":
			_cone(root, 0.18, 0.3, Vector3(0, 0.15, 0), Color(0.6, 0.45, 0.3))
		"Plantation":
			for i in 4:
				_sphere(root, 0.08, Vector3(-0.2 + (i % 2) * 0.4, 0.1, -0.15 + (i / 2) * 0.3), Color(0.25, 0.55, 0.2))
		"Lumber mill":
			_box(root, Vector3(0.4, 0.08, 0.1), Vector3(0, 0.04, 0), Color(0.55, 0.38, 0.22))
			_box(root, Vector3(0.4, 0.08, 0.1), Vector3(0, 0.12, 0), Color(0.6, 0.42, 0.25))
		"Trading post", "Customs house", "Academy", "Manufactory", "Holy site", "Landmark":
			_box(root, Vector3(0.24, 0.18, 0.24), Vector3(0, 0.09, 0), Color(0.75, 0.62, 0.45))
			_cone(root, 0.18, 0.12, Vector3(0, 0.24, 0), Color(0.55, 0.25, 0.2))
		"Fishing Boats", "Offshore Platform":
			_box(root, Vector3(0.3, 0.06, 0.12), Vector3(0, 0.03, 0), Color(0.55, 0.4, 0.25))
			_box(root, Vector3(0.02, 0.22, 0.02), Vector3(0, 0.14, 0), Color(0.9, 0.9, 0.85))
		"Fort", "Citadel":
			for i in 4:
				var angle := TAU * i / 4.0 + PI / 4.0
				_box(root, Vector3(0.1, 0.2, 0.1), Vector3(cos(angle), 0, sin(angle)) * 0.24 + Vector3(0, 0.1, 0), Color(0.55, 0.55, 0.58))
		"Oil well":
			_box(root, Vector3(0.05, 0.35, 0.05), Vector3(0, 0.17, 0), Color(0.15, 0.15, 0.15))
			_box(root, Vector3(0.3, 0.04, 0.04), Vector3(0, 0.33, 0), Color(0.15, 0.15, 0.15))
		"Barbarian encampment":
			_cone(root, 0.16, 0.26, Vector3(-0.12, 0.13, 0), Color(0.45, 0.3, 0.2))
			_cone(root, 0.14, 0.22, Vector3(0.16, 0.11, 0.08), Color(0.4, 0.25, 0.18))
			_sphere(root, 0.06, Vector3(0, 0.06, -0.18), Color(0.95, 0.45, 0.1))
		"Ancient ruins", "City ruins":
			for i in 3:
				_box(root, Vector3(0.08, 0.1 + i * 0.06, 0.08), Vector3(-0.18 + i * 0.18, 0.05 + i * 0.03, 0), Color(0.62, 0.6, 0.55))
		_:
			var texture := Icons.badge("improvement", improvement, Color(0.2, 0.22, 0.28))
			if texture == null:
				return null
			var sprite := Sprite3D.new()   # unknown improvement: its symbol, standing up
			sprite.texture = texture
			sprite.pixel_size = 0.35 / float(texture.get_width())
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sprite.shaded = false
			sprite.position = Vector3(0, 0.25, 0)
			root.add_child(sprite)
	return root


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _solid(color)
	node.position = at
	parent.add_child(node)
	return node


func _cone(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	node.mesh = mesh
	node.material_override = _solid(color)
	node.position = at
	parent.add_child(node)


func _sphere(parent: Node3D, radius: float, at: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	node.mesh = mesh
	node.material_override = _solid(color)
	node.position = at
	parent.add_child(node)


func _solid(color: Color) -> StandardMaterial3D:
	var key := "solid:" + color.to_html()
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	_materials[key] = material
	return material


# region unit movement arrows ---------------------------------------------------------------

## Arrows along each visible unit's recent moves (Unciv's unit-movement overlay).
func _build_arrows(shown: Dictionary) -> void:
	_arrows.mesh = null
	if not flags["movement"]:
		return
	var segments: Array = []
	for key: Vector2i in shown:
		var tile: Dictionary = _map.tiles[key]
		for unit: Dictionary in tile.get("units", []):
			var moves: Array = unit.get("moves", [])
			for i in range(1, moves.size()):
				var a := Vector2i(int(moves[i - 1]["x"]), int(moves[i - 1]["y"]))
				var b := Vector2i(int(moves[i]["x"]), int(moves[i]["y"]))
				if a == b or not _map.tiles.has(a) or not _map.tiles.has(b):
					continue
				var colour := Color(1, 1, 1, 0.9)
				match str(moves[i].get("type", "")):
					"UnitAttacked":
						colour = Color(1.0, 0.3, 0.25)
					"UnitTeleported":
						colour = Color(0.45, 0.65, 1.0)
					"UnitDisembarked", "UnitEmbarked":
						colour = Color(0.4, 0.9, 1.0)
				var from: Vector3 = _map.tile_position(a, _map.tile_height(_map.tiles[a]) + 0.35)
				var to: Vector3 = _map.tile_position(b, _map.tile_height(_map.tiles[b]) + 0.35)
				segments.append([from, to, colour])
	if not segments.is_empty():
		_arrows.mesh = _ribbons(segments, 0.1, 0.0, true)


## Flat strips (with an arrow head when [param heads]) between points: [[from, to, colour], ...].
func _ribbons(segments: Array, width: float, lift: float, heads: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	for segment: Array in segments:
		var from: Vector3 = segment[0] + Vector3(0, lift, 0)
		var to: Vector3 = segment[1] + Vector3(0, lift, 0)
		var colour: Color = segment[2]
		var along := (to - from)
		along.y = 0
		if along.length() < 0.01:
			continue
		var dir := along.normalized()
		var side := Vector3(-dir.z, 0, dir.x) * width / 2.0
		var end := to - dir * (0.3 if heads else 0.0)
		for v in [from - side, from + side, end + side, from - side, end + side, end - side]:
			vertices.append(v)
			colours.append(colour)
		if heads:
			for v in [end - side * 2.6, end + side * 2.6, to]:
				vertices.append(v)
				colours.append(colour)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
