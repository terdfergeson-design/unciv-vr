extends Node3D
## The world around the table: sky, lighting and scenery. Switch with apply("studio" | "mountains" | "space").
## Everything is generated in code (low-poly, flat-shaded), so there are no asset files to manage.
## Place this node at floor level; the scenery is built relative to it.

const NAMES := ["studio", "mountains", "space"]
const TITLES := {"studio": "Studio", "mountains": "Mountains", "space": "Space"}

var current := ""
var has_floor := true          # false when the table should look like it floats (space)

var _environment: Environment
var _sun: DirectionalLight3D
var _scenery: Node3D
var _spinners: Array[Array] = []   # [node, radians per second] slowly rotated in _process


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


func apply(background: String) -> void:
	if background not in NAMES:
		background = "studio"
	current = background
	for child in _scenery.get_children():
		child.queue_free()
	_spinners.clear()
	match background:
		"mountains":
			_build_mountains()
		"space":
			_build_space()
		_:
			_build_studio()


# region studio -----------------------------------------------------------------------------

func _build_studio() -> void:
	has_floor = true
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.11, 0.12, 0.15)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.9, 0.9, 0.95)
	_environment.ambient_light_energy = 0.9
	_environment.fog_enabled = false
	_set_sun(Vector3(-55, 35, 0), Color(1, 1, 1), 1.4)
	_scenery.add_child(_disc(6.0, Color(0.16, 0.17, 0.2)))


# region mountains --------------------------------------------------------------------------

func _build_mountains() -> void:
	has_floor = true
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.52, 0.82)
	sky_material.sky_horizon_color = Color(0.78, 0.86, 0.93)
	sky_material.ground_bottom_color = Color(0.25, 0.33, 0.22)
	sky_material.ground_horizon_color = Color(0.6, 0.68, 0.6)
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_energy = 1.0
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.75, 0.83, 0.9)
	_environment.fog_density = 0.004
	_environment.fog_sky_affect = 0.0
	_set_sun(Vector3(-40, 140, 0), Color(1.0, 0.96, 0.88), 1.3)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1234   # same landscape every time

	# Meadow underfoot
	_scenery.add_child(_disc(150.0, Color(0.36, 0.5, 0.27)))

	# A ring of low-poly peaks, two layers deep
	var peaks := Node3D.new()
	_scenery.add_child(peaks)
	for layer in 2:
		var count := 18 if layer == 0 else 14
		for i in count:
			var angle := TAU * (i + rng.randf_range(-0.3, 0.3)) / count + layer * 0.2
			var distance := rng.randf_range(55.0, 70.0) + layer * 30.0
			var base := rng.randf_range(14.0, 24.0) + layer * 6.0
			var height := rng.randf_range(16.0, 34.0) + layer * 14.0
			var peak := MeshInstance3D.new()
			peak.mesh = _make_peak(rng, base, height)
			peak.material_override = _vertex_color_material(0.95)
			peak.position = Vector3(cos(angle) * distance, -1.0, sin(angle) * distance)
			peak.rotation.y = rng.randf() * TAU
			peaks.add_child(peak)

	# A few trees scattered on the meadow, away from the table
	for i in 40:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(9.0, 45.0)
		_scenery.add_child(_tree(rng, Vector3(cos(angle) * distance, 0, sin(angle) * distance)))

	# Clouds drifting slowly around
	var clouds := Node3D.new()
	_scenery.add_child(clouds)
	_spinners.append([clouds, 0.01])
	var cloud_material := StandardMaterial3D.new()
	cloud_material.albedo_color = Color(1, 1, 1)
	cloud_material.roughness = 1.0
	cloud_material.emission_enabled = true
	cloud_material.emission = Color(0.55, 0.58, 0.62)
	for i in 14:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(35.0, 90.0)
		var cloud := Node3D.new()
		cloud.position = Vector3(cos(angle) * distance, rng.randf_range(22.0, 38.0), sin(angle) * distance)
		for puff in rng.randi_range(3, 6):
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			var r := rng.randf_range(2.5, 5.0)
			sphere.radius = r
			sphere.height = r * 1.6
			sphere.radial_segments = 7
			sphere.rings = 4
			ball.mesh = sphere
			ball.material_override = cloud_material
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ball.position = Vector3(rng.randf_range(-6, 6), rng.randf_range(-1, 1.5), rng.randf_range(-3, 3))
			cloud.add_child(ball)
		clouds.add_child(cloud)


## A faceted mountain: a jittered base ring, a narrower mid ring and an apex, coloured by height
## (grass, rock, snow) one flat colour per triangle.
func _make_peak(rng: RandomNumberGenerator, base: float, height: float) -> ArrayMesh:
	var sides := rng.randi_range(5, 7)
	var apex := Vector3(rng.randf_range(-0.15, 0.15) * base, height, rng.randf_range(-0.15, 0.15) * base)
	var ring_low: Array[Vector3] = []
	var ring_mid: Array[Vector3] = []
	for i in sides:
		var a := TAU * (i + rng.randf_range(-0.2, 0.2)) / sides
		ring_low.append(Vector3(cos(a), 0, sin(a)) * base * rng.randf_range(0.85, 1.15))
		var b := a + rng.randf_range(-0.2, 0.2)
		ring_mid.append(Vector3(cos(b) * base * rng.randf_range(0.42, 0.58), height * rng.randf_range(0.42, 0.55),
			sin(b) * base * rng.randf_range(0.42, 0.58)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var j := (i + 1) % sides
		_flat_triangle(st, ring_low[i], ring_low[j], ring_mid[j], height)
		_flat_triangle(st, ring_low[i], ring_mid[j], ring_mid[i], height)
		_flat_triangle(st, ring_mid[i], ring_mid[j], apex, height)
	return st.commit()


func _flat_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, peak_height: float) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0:
		normal = -normal
	var level := (a.y + b.y + c.y) / 3.0 / peak_height
	var color: Color
	if level > 0.62 and peak_height > 26.0:
		color = Color(0.93, 0.94, 0.97)                     # snow
	elif level > 0.3:
		color = Color(0.45, 0.43, 0.4).lerp(Color(0.55, 0.52, 0.47), level)   # rock
	else:
		color = Color(0.3, 0.42, 0.25)                      # grassy foothills
	# Light facets a little differently so the low-poly shape reads even in flat light
	color = color.darkened(0.12 * (1.0 - normal.y))
	for v in [a, b, c]:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(v)


func _tree(rng: RandomNumberGenerator, at: Vector3) -> Node3D:
	var tree := Node3D.new()
	tree.position = at
	var size := rng.randf_range(0.8, 1.6)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12 * size
	trunk_mesh.bottom_radius = 0.16 * size
	trunk_mesh.height = 1.0 * size
	trunk_mesh.radial_segments = 5
	trunk.mesh = trunk_mesh
	trunk.material_override = _flat_material(Color(0.4, 0.28, 0.18))
	trunk.position.y = 0.5 * size
	tree.add_child(trunk)
	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 0.9 * size
	crown_mesh.height = 2.4 * size
	crown_mesh.radial_segments = 6
	crown.mesh = crown_mesh
	crown.material_override = _flat_material(Color(0.18, 0.36, 0.2).lerp(Color(0.25, 0.42, 0.2), rng.randf()))
	crown.position.y = 1.0 * size + 1.1 * size
	tree.add_child(crown)
	return tree


# region space ------------------------------------------------------------------------------

func _build_space() -> void:
	has_floor = false
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.005, 0.006, 0.015)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.55, 0.6, 0.85)
	_environment.ambient_light_energy = 0.55
	_environment.fog_enabled = false
	_set_sun(Vector3(-25, -60, 0), Color(1.0, 0.97, 0.9), 1.8)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4321

	# Stars: tiny unshaded dots on a big sphere around you
	var stars := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var dot := SphereMesh.new()
	dot.radius = 0.25
	dot.height = 0.5
	dot.radial_segments = 4
	dot.rings = 2
	mm.mesh = dot
	mm.instance_count = 2500
	for i in mm.instance_count:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var size := rng.randf_range(0.4, 1.6)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), direction * 180.0))
		var tint: Color = [Color(1, 1, 1), Color(0.75, 0.85, 1.0), Color(1.0, 0.92, 0.75), Color(1.0, 0.8, 0.8)][rng.randi() % 4]
		mm.set_instance_color(i, tint * rng.randf_range(0.5, 1.0))
	stars.multimesh = mm
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.vertex_color_use_as_albedo = true
	stars.material_override = star_material
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scenery.add_child(stars)
	_spinners.append([stars, 0.003])

	# A ringed planet off to one side, and a small moon
	var planet := MeshInstance3D.new()
	var planet_mesh := SphereMesh.new()
	planet_mesh.radius = 28.0
	planet_mesh.height = 56.0
	planet_mesh.radial_segments = 48
	planet_mesh.rings = 24
	planet.mesh = planet_mesh
	var planet_material := StandardMaterial3D.new()
	planet_material.albedo_color = Color(0.85, 0.55, 0.32)
	planet_material.roughness = 0.9
	planet_material.rim_enabled = true
	planet_material.rim = 0.6
	planet_material.rim_tint = 0.4
	planet.material_override = planet_material
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.position = Vector3(-95, 25, -110)
	_scenery.add_child(planet)
	_spinners.append([planet, 0.02])

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 38.0
	ring_mesh.outer_radius = 58.0
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 4
	ring.mesh = ring_mesh
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.9, 0.8, 0.65, 0.55)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.04, 1)
	ring.rotation_degrees = Vector3(18, 0, 12)
	ring.position = planet.position
	_scenery.add_child(ring)

	var moon := MeshInstance3D.new()
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 5.0
	moon_mesh.height = 10.0
	moon.mesh = moon_mesh
	moon.material_override = _flat_material(Color(0.7, 0.72, 0.78))
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.position = Vector3(70, 40, -120)
	_scenery.add_child(moon)


# region helpers ----------------------------------------------------------------------------

func _set_sun(rotation_deg: Vector3, color: Color, energy: float) -> void:
	_sun.rotation_degrees = rotation_deg
	_sun.light_color = color
	_sun.light_energy = energy


func _disc(radius: float, color: Color) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 64
	disc.mesh = mesh
	disc.material_override = _flat_material(color)
	disc.position.y = -0.011
	return disc


func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


func _vertex_color_material(roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
