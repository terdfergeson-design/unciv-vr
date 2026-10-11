# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## The world around the table: sky, lighting and scenery, read from a background folder
## (backgrounds/<Name>/background.json plus a scenery model; see backgrounds/README.md).
## Built-in: Studio, Mountains, Space (made by tools/make_surroundings.gd); players' and mods' own go in
## ~/.unciv-vr/Backgrounds. Place this node at floor level; the scenery is modelled around it.

const ModFolders := preload("res://scripts/mod_folders.gd")
const KIND := "Backgrounds"
const JSON_NAME := "background.json"
const DEFAULT := "Mountains"

var current := ""              # folder name of the background shown
var has_floor := true          # false when the table should look like it floats (space)

var _environment: Environment
var _sun: DirectionalLight3D
var _scenery: Node3D
var _sun_yaw := 35.0           # the background's own sun direction, before turning (see place)
var _spot := Vector3.ZERO       # where the table stands in the scenery, in the scenery's own metres
var _spot_yaw := 0.0            # how far the scenery is turned around the table, degrees
var _home := Vector3.ZERO       # the table's usual spot, in this node's space (the scenery's middle goes here)
var _colliders_built := false   # collision for pointing at the scenery is built on demand (spot_at)
const SCENERY_LAYER := 1 << 19      # physics layer of those colliders; nothing else uses physics
var _spinners: Array[Array] = []   # [node, radians per second] slowly turned in _process


## Every background that can be picked: folder name -> title.
static func available() -> Dictionary:
	return ModFolders.available(KIND, JSON_NAME)


func _ready() -> void:
	_environment = Environment.new()
	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 20.0
	add_child(_sun)

	_scenery = Node3D.new()
	_scenery.name = "Scenery"
	add_child(_scenery)


func _process(delta: float) -> void:
	for spinner in _spinners:
		var node: Node3D = spinner[0]
		node.rotate_y(spinner[1] * delta)


## Shows the background in folder [param background] (case doesn't matter; unknown ones show the default).
func apply(background: String) -> void:
	var path := ModFolders.find(KIND, background, JSON_NAME)
	if path == "":
		path = ModFolders.find(KIND, DEFAULT, JSON_NAME)
	for child in _scenery.get_children():
		_scenery.remove_child(child)
		child.queue_free()
	_colliders_built = false
	_spinners.clear()
	if path == "":
		push_warning("No backgrounds found")
		_plain()
		return
	current = path.get_file()
	var json: Dictionary = ModFolders.read_json(path.path_join(JSON_NAME))
	has_floor = bool(json.get("floor", true))
	_set_sky(path, json.get("sky", {}) if json.get("sky") is Dictionary else {})
	_set_ambient(json.get("ambient", {}) if json.get("ambient") is Dictionary else {})
	_set_fog(json.get("fog"))
	_set_sun(json.get("sun", {}) if json.get("sun") is Dictionary else {})
	var model := ModFolders.model_path(path, str(json.get("scenery", "scenery")))
	var scenery := ModFolders.load_model(model)
	if scenery != null:
		_scenery.add_child(scenery)
		var spin: Variant = json.get("spin", {})
		if spin is Dictionary:
			for node_name: String in spin:
				var node := scenery.find_child(node_name, true, false) as Node3D
				if node != null:
					_spinners.append([node, deg_to_rad(float(spin[node_name]))])
				else:
					push_warning("%s: no node named %s to spin" % [current, node_name])


func _plain() -> void:
	has_floor = true
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.11, 0.12, 0.15)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.9, 0.9, 0.95)
	_environment.fog_enabled = false
	_set_sun({})


## "sky": {"color": c} a plain colour; {"panorama": "sky.png"} an equirectangular picture (png, jpg, hdr, exr);
## or a gradient {"top", "horizon", "groundHorizon", "groundBottom", "sunSize"} (Godot's procedural sky).
func _set_sky(folder: String, sky_json: Dictionary) -> void:
	if sky_json.has("panorama"):
		var image := Image.load_from_file(folder.path_join(str(sky_json["panorama"])))
		if image != null and not image.is_empty():
			var panorama := PanoramaSkyMaterial.new()
			panorama.panorama = ImageTexture.create_from_image(image)
			panorama.energy_multiplier = float(sky_json.get("energy", 1.0))
			_use_sky(panorama)
			return
		push_warning("%s: can't read the sky picture %s" % [folder, sky_json["panorama"]])
	if sky_json.has("top") or sky_json.has("horizon"):
		var gradient := ProceduralSkyMaterial.new()
		gradient.sky_top_color = ModFolders.color(sky_json.get("top"), gradient.sky_top_color)
		gradient.sky_horizon_color = ModFolders.color(sky_json.get("horizon"), gradient.sky_horizon_color)
		gradient.ground_horizon_color = ModFolders.color(sky_json.get("groundHorizon"), gradient.sky_horizon_color)
		gradient.ground_bottom_color = ModFolders.color(sky_json.get("groundBottom"), gradient.ground_bottom_color)
		gradient.sun_angle_max = float(sky_json.get("sunSize", 20.0))
		_use_sky(gradient)
		return
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = ModFolders.color(sky_json.get("color"), Color(0.11, 0.12, 0.15))


func _use_sky(material: Material) -> void:
	var sky := Sky.new()
	sky.sky_material = material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky


## "ambient": {"color": c, "energy": 1}; without a colour the light comes from the sky.
func _set_ambient(ambient: Dictionary) -> void:
	var from_sky := not ambient.has("color") and _environment.background_mode == Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if from_sky else Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = ModFolders.color(ambient.get("color"), Color(0.9, 0.9, 0.95))
	_environment.ambient_light_energy = float(ambient.get("energy", 1.0))


## "fog": {"color": c, "density": 0.004}, or leave it out for none.
func _set_fog(fog: Variant) -> void:
	_environment.fog_enabled = fog is Dictionary
	if fog is Dictionary:
		_environment.fog_light_color = ModFolders.color(fog.get("color"), Color(0.75, 0.83, 0.9))
		_environment.fog_density = float(fog.get("density", 0.004))
		_environment.fog_sky_affect = float(fog.get("skyAffect", 0.0))


## "sun": {"pitch": degrees down (negative) or up, "yaw": degrees, "color": c, "energy": 1, "shadows": true}.
## Energy 0 turns it off. Yaw 0 shines from behind you towards the far side of the table.
func _set_sun(sun: Dictionary) -> void:
	_sun_yaw = float(sun.get("yaw", 35.0))
	_sun.rotation_degrees = Vector3(float(sun.get("pitch", -55.0)), _sun_yaw + _spot_yaw, 0)
	_sun.light_color = ModFolders.color(sun.get("color"), Color(1, 1, 1))
	_sun.light_energy = float(sun.get("energy", 1.4))
	_sun.visible = _sun.light_energy > 0.0
	_sun.shadow_enabled = bool(sun.get("shadows", true))


# region where the table stands ------------------------------------------------------------------

## Stands the table somewhere else in a big scenery (a converted map, a skatepark...): [param spot] is that place in
## the scenery's own coordinates (its floor there becomes the floor under the table), [param yaw] turns the scenery
## around the table, and [param home] is where the table usually stands in this node's space. The sun and a sky
## picture turn with it. spot ZERO, yaw 0 is the background as made.
func place(spot: Vector3, yaw: float, home: Vector3) -> void:
	_spot = spot
	_spot_yaw = yaw
	_home = Vector3(home.x, 0.0, home.z)
	var turn := Basis(Vector3.UP, deg_to_rad(yaw))
	_scenery.transform = Transform3D(turn, _home - turn * spot)
	_sun.rotation_degrees.y = _sun_yaw + yaw
	_environment.sky_rotation = Vector3(0, deg_to_rad(yaw), 0)


func spot() -> Vector3:
	return _spot


func spot_yaw() -> float:
	return _spot_yaw


## Where a ray meets the scenery: [global point, the same point in the scenery's own coordinates], or [] if it
## misses. The first call builds collision shapes from the scenery's meshes (big maps take a moment).
func spot_at(origin: Vector3, direction: Vector3) -> Array:
	if not _colliders_built:
		_build_colliders()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 400.0, SCENERY_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return []
	var point: Vector3 = hit["position"]
	return [point, _scenery.to_local(point)]


func _build_colliders() -> void:
	for node in _scenery.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		var shape := mesh_node.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = SCENERY_LAYER
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		mesh_node.add_child(body)
	_colliders_built = true
