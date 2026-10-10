# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## Overview of the whole map, standing at the far edge of the table, for maps too big to show whole.
## Shows explored terrain, borders, your cities and units, and a ring for the part the table shows.
## Point at it and pull the trigger (or click it) to slide the table's window there.

const IMAGE_SIZE := 256
const SIZE := 0.42                       # metres across
const FRAME_COLOR := Color(0.2, 0.14, 0.09)
const Icons := preload("res://scripts/icons.gd")
## Unciv's map overlay toggles, in Unciv's order: [id, icon in TileIcons, tooltip]
const OVERLAY_BUTTONS := [
	["movement", "MapOverlayToggleMovement", "Unit movements"],
	["yields", "MapOverlayToggleYields", "Tile yields"],
	["worked", "MapOverlayToggleWorkedTiles", "Worked tiles"],
	["resources", "MapOverlayToggleResources", "Resources and improvements"],
	["improvements", "MapOverlayToggleImprovements", "Improvement pictures"],
	["unit_icons", "Warrior", "Unit icons over the unit models", "unit"],   # ours: Unciv has no unit models
]
const BUTTON_SIZE := 0.062
const BUTTON_GAP := 0.071
const BUTTON_ON := Color(0.2, 0.42, 0.75)
const BUTTON_OFF := Color(0.13, 0.13, 0.15, 0.85)

var hex_map: Node3D                      # the HexMap whose tiles and window this shows
var _quad: MeshInstance3D
var _texture: ImageTexture
var _ring: MeshInstance3D
var _hover_dot: MeshInstance3D
var _bounds_center := Vector2.ZERO       # world coords at the image centre
var _bounds_half := 10.0                 # world units from the centre to an image edge
var _buttons: Dictionary = {}            # overlay id -> {back: MeshInstance3D, icon: MeshInstance3D}
var _button_states: Dictionary = {}      # overlay id -> on?
var _hovered_button := ""
var _title: Label3D


func setup(map: Node3D) -> void:
	hex_map = map
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(SIZE + 0.03, SIZE + 0.03, 0.012)
	frame.mesh = frame_mesh
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = FRAME_COLOR
	frame_material.roughness = 0.8
	frame.material_override = frame_material
	frame.position.z = -0.007
	add_child(frame)

	_quad = MeshInstance3D.new()
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(SIZE, SIZE)
	_quad.mesh = quad_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_texture = ImageTexture.create_from_image(Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGB8))
	material.albedo_texture = _texture
	_quad.material_override = material
	add_child(_quad)

	_ring = MeshInstance3D.new()
	_ring.mesh = _make_ring_mesh(0.86)
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(1.0, 0.92, 0.5)
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = ring_material
	_ring.position.z = 0.002
	add_child(_ring)

	_hover_dot = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	_hover_dot.mesh = dot
	_hover_dot.material_override = ring_material
	_hover_dot.visible = false
	add_child(_hover_dot)

	_title = Label3D.new()
	_title.text = "Overview: point and click to go there"
	_title.font_size = 40
	_title.pixel_size = 0.0007
	_title.outline_size = 8
	_title.position = Vector3(0, SIZE / 2.0 + 0.03, 0)
	add_child(_title)

	# Unciv's five overlay toggles (and our unit icons), in a column down the right-hand side
	for i in OVERLAY_BUTTONS.size():
		var id: String = OVERLAY_BUTTONS[i][0]
		var at := _button_center(i)
		var back := _flat_quad(Icons.disc(Color.WHITE), BUTTON_SIZE)
		back.position = Vector3(at.x, at.y, 0.0)
		add_child(back)
		var icon_kind: String = OVERLAY_BUTTONS[i][3] if OVERLAY_BUTTONS[i].size() > 3 else "tile"
		var icon := _flat_quad(Icons.get_icon(icon_kind, OVERLAY_BUTTONS[i][1]), BUTTON_SIZE * 0.72)
		icon.position = Vector3(at.x, at.y, 0.002)
		add_child(icon)
		_buttons[id] = {"back": back, "icon": icon}
		_button_states[id] = false
		_paint_button(id)


func _button_center(i: int) -> Vector2:
	return Vector2(SIZE / 2.0 + 0.015 + BUTTON_SIZE / 2.0, SIZE / 2.0 - BUTTON_SIZE / 2.0 - i * BUTTON_GAP)


func _flat_quad(texture: Texture2D, size: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Shows which overlays are on ({id: bool}).
func set_overlay_states(states: Dictionary) -> void:
	for id: String in states:
		if _buttons.has(id):
			_button_states[id] = bool(states[id])
			_paint_button(id)


func _paint_button(id: String) -> void:
	var back := _buttons[id]["back"] as MeshInstance3D
	var colour: Color = BUTTON_ON if _button_states[id] else BUTTON_OFF
	if id == _hovered_button:
		colour = colour.lightened(0.3)
	(back.material_override as StandardMaterial3D).albedo_color = colour
	var icon := _buttons[id]["icon"] as MeshInstance3D
	(icon.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 1.0 if _button_states[id] else 0.6)
	back.scale = Vector3.ONE * (1.12 if id == _hovered_button else 1.0)


## The overlay button a ray points at ("" if none).
func overlay_button_at(origin: Vector3, direction: Vector3) -> String:
	if not is_visible_in_tree():
		return ""
	var t := global_transform
	var hit: Variant = Plane(t.basis.z.normalized(), t.origin).intersects_ray(origin, direction)
	if hit == null:
		return ""
	var local := to_local(hit)
	for i in OVERLAY_BUTTONS.size():
		if Vector2(local.x, local.y).distance_to(_button_center(i)) <= BUTTON_SIZE * 0.6:
			return OVERLAY_BUTTONS[i][0]
	return ""


## Highlights the pointed-at button and names it in the title ("" = none).
func hover_button(id: String) -> void:
	if id == _hovered_button:
		return
	var old := _hovered_button
	_hovered_button = id
	if old != "":
		_paint_button(old)
	if id != "":
		_paint_button(id)
		for entry: Array in OVERLAY_BUTTONS:
			if entry[0] == id:
				_title.text = "%s: %s (click to turn %s)" % [entry[2], "on" if _button_states[id] else "off", "off" if _button_states[id] else "on"]
	else:
		_update_title()


func _update_title() -> void:
	if hex_map != null and hex_map.is_windowed():
		_title.text = "Overview: point and click to go there"
	else:
		_title.text = "Overview"


## Global position of an overlay button (for the pointer dot).
func button_global_position(id: String) -> Vector3:
	return (_buttons[id]["back"] as Node3D).global_position


## Repaints the overview from the map's current tiles (call after each refresh).
func redraw(units: Array, cities: Array) -> void:
	if hex_map == null:
		return
	_bounds_center = hex_map.full_center
	_bounds_half = hex_map.full_extent
	var image := Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGB8)
	image.fill(Color(0.03, 0.03, 0.04))
	var px_per_unit := IMAGE_SIZE / (2.0 * _bounds_half)
	var cell := maxi(2, int(ceil(px_per_unit * 1.8)))
	for key: Vector2i in hex_map.tiles:
		var tile: Dictionary = hex_map.tiles[key]
		if not tile.get("explored", false):
			continue
		var color: Color = hex_map.tile_color(tile)
		if tile.has("owner"):
			color = color.lerp(hex_map.civ_color(tile["owner"], "outer"), 0.45)
		_fill_cell(image, Vector2(tile["wx"], tile["wy"]), cell, color)
	for city: Dictionary in cities:
		var key := Vector2i(int(city["x"]), int(city["y"]))
		if hex_map.tiles.has(key):
			_fill_cell(image, hex_map._world_of(key), cell + 3, Color(1, 1, 1))
	for unit: Dictionary in units:
		var key := Vector2i(int(unit["x"]), int(unit["y"]))
		if hex_map.tiles.has(key):
			_fill_cell(image, hex_map._world_of(key), maxi(2, cell - 1), Color(1.0, 0.85, 0.2))
	_texture.update(image)
	update_window()
	if _hovered_button == "":
		_update_title()


## Moves the ring to where the table's window is.
func update_window() -> void:
	if hex_map == null or not hex_map.is_windowed():
		_ring.visible = false
		return
	_ring.visible = true
	var local := _world_to_local(hex_map.view_center)
	_ring.position = Vector3(local.x, local.y, 0.002)
	var r: float = hex_map.view_radius / (2.0 * _bounds_half) * SIZE
	_ring.scale = Vector3(r, r, 1)


## The world point (wx, wy) a ray points at on the overview, or null.
func ray_hit(origin: Vector3, direction: Vector3) -> Variant:
	if not is_visible_in_tree():
		return null
	var t := _quad.global_transform
	var hit: Variant = Plane(t.basis.z.normalized(), t.origin).intersects_ray(origin, direction)
	if hit == null:
		return null
	var local := _quad.to_local(hit)
	if absf(local.x) > SIZE / 2.0 or absf(local.y) > SIZE / 2.0:
		return null
	return _local_to_world(Vector2(local.x, local.y))


## Where a ray hits the overview including its frame (global point), or null - for grabbing it to move it.
func ray_hit_point(origin: Vector3, direction: Vector3) -> Variant:
	if not is_visible_in_tree():
		return null
	var t := _quad.global_transform
	var hit: Variant = Plane(t.basis.z.normalized(), t.origin).intersects_ray(origin, direction)
	if hit == null:
		return null
	var local := _quad.to_local(hit)
	var half := SIZE / 2.0 + 0.04   # the frame and the label above count too
	if absf(local.x) > half or local.y < -half or local.y > half + 0.03:
		return null
	if overlay_button_at(origin, direction) != "":
		return null   # the overlay buttons are clicked, not grabbed
	return hit


## Shows a dot where the pointer is (or hides it with null).
func show_hover(world: Variant) -> void:
	_hover_dot.visible = world != null
	if world != null:
		var local := _world_to_local(world)
		_hover_dot.position = Vector3(local.x, local.y, 0.004)


func _world_to_local(world: Vector2) -> Vector2:
	return (world - _bounds_center) / (2.0 * _bounds_half) * SIZE


func _local_to_world(local: Vector2) -> Vector2:
	return _bounds_center + local / SIZE * (2.0 * _bounds_half)


func _fill_cell(image: Image, world: Vector2, size: int, color: Color) -> void:
	var p := (world - _bounds_center) / (2.0 * _bounds_half) + Vector2(0.5, 0.5)
	var x := int(p.x * IMAGE_SIZE) - size / 2
	var y := int((1.0 - p.y) * IMAGE_SIZE) - size / 2   # image rows go down, +wy is north
	image.fill_rect(Rect2i(x, y, size, size).intersection(Rect2i(0, 0, IMAGE_SIZE, IMAGE_SIZE)), color)


func _make_ring_mesh(inner: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var segments := 48
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var o0 := Vector3(cos(a0), sin(a0), 0)
		var o1 := Vector3(cos(a1), sin(a1), 0)
		vertices.append_array([o0 * inner, o0, o1, o0 * inner, o1, o1 * inner])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
