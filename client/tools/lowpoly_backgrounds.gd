# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## The scenery of the built-in backgrounds (Studio, Mountains, Space), low-poly like the tiles.
## tools/make_surroundings.gd saves each as backgrounds/<Name>/scenery.glb; the sky, light and fog are in
## that folder's background.json. Everything is modelled around the floor under the table (y = 0).
## Vertex colours are given in sRGB, like everything else in Godot (its glTF exporter converts them).


func studio() -> Node3D:
	var root := _root("Studio")
	_add(root, "Floor", _disc(6.0, Color(0.16, 0.17, 0.2)), _material("Floor", 0.9))
	return root


func mountains() -> Node3D:
	var root := _root("Mountains")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234   # same landscape every time

	# Meadow underfoot
	_add(root, "Meadow", _disc(150.0, Color(0.36, 0.5, 0.27)), _material("Meadow", 0.9))

	# A ring of low-poly peaks, two layers deep
	var st := _begin()
	for layer in 2:
		var count := 18 if layer == 0 else 14
		for i in count:
			var angle := TAU * (i + rng.randf_range(-0.3, 0.3)) / count + layer * 0.2
			var distance := rng.randf_range(55.0, 70.0) + layer * 30.0
			var base := rng.randf_range(14.0, 24.0) + layer * 6.0
			var height := rng.randf_range(16.0, 34.0) + layer * 14.0
			var at := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(cos(angle) * distance, -1.0, sin(angle) * distance))
			_peak(st, rng, base, height, at)
	_add(root, "Peaks", _done(st), _material("Peaks", 0.95, true))

	# A few trees scattered on the meadow, away from the table
	var trees := _begin()
	for i in 40:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(9.0, 45.0)
		_tree(trees, rng, Vector3(cos(angle) * distance, 0, sin(angle) * distance))
	_add(root, "Trees", _done(trees), _material("Trees", 0.9))

	# Clouds drifting slowly around (background.json spins the "Clouds" node)
	var clouds := _begin()
	for i in 14:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(35.0, 90.0)
		var centre := Vector3(cos(angle) * distance, rng.randf_range(22.0, 38.0), sin(angle) * distance)
		for puff in rng.randi_range(3, 6):
			var sphere := SphereMesh.new()
			var r := rng.randf_range(2.5, 5.0)
			sphere.radius = r
			sphere.height = r * 1.6
			sphere.radial_segments = 7
			sphere.rings = 4
			var offset := Vector3(rng.randf_range(-6, 6), rng.randf_range(-1, 1.5), rng.randf_range(-3, 3))
			_append(clouds, sphere, Transform3D(Basis(), centre + offset), Color(1, 1, 1))
	var cloud_material := _material("Clouds", 1.0)
	cloud_material.emission_enabled = true
	cloud_material.emission = Color(0.55, 0.58, 0.62)
	_add(root, "Clouds", _done(clouds), cloud_material)
	return root


func space() -> Node3D:
	var root := _root("Space")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4321

	# Stars: tiny unshaded dots on a big sphere around you (spun slowly by background.json)
	var stars := _begin()
	var dot := SphereMesh.new()
	dot.radius = 0.25
	dot.height = 0.5
	dot.radial_segments = 4
	dot.rings = 2
	for i in 2500:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var size := rng.randf_range(0.4, 1.6)
		var tint: Color = [Color(1, 1, 1), Color(0.75, 0.85, 1.0), Color(1.0, 0.92, 0.75), Color(1.0, 0.8, 0.8)][rng.randi() % 4]
		var brightness := rng.randf_range(0.5, 1.0)
		_append(stars, dot, Transform3D(Basis().scaled(Vector3.ONE * size), direction * 180.0),
			Color(tint.r * brightness, tint.g * brightness, tint.b * brightness))
	var star_material := _material("Stars", 1.0)
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add(root, "Stars", _done(stars), star_material)

	# A ringed planet off to one side, and a small moon
	var planet_mesh := SphereMesh.new()
	planet_mesh.radius = 28.0
	planet_mesh.height = 56.0
	planet_mesh.radial_segments = 48
	planet_mesh.rings = 24
	var planet_st := _begin()
	_append(planet_st, planet_mesh, Transform3D.IDENTITY, Color(0.85, 0.55, 0.32))
	var planet := _add(root, "Planet", _done(planet_st), _material("Planet", 0.9))
	planet.position = Vector3(-95, 25, -110)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 38.0
	ring_mesh.outer_radius = 58.0
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 4
	var ring_st := _begin()
	_append(ring_st, ring_mesh, Transform3D(Basis.from_euler(Vector3(deg_to_rad(18), 0, deg_to_rad(12))) * Basis().scaled(Vector3(1, 0.04, 1)),
		Vector3.ZERO), Color(0.9, 0.8, 0.65, 0.55))
	var ring_material := _material("Rings", 0.9)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := _add(root, "Rings", _done(ring_st), ring_material)
	ring.position = planet.position

	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 5.0
	moon_mesh.height = 10.0
	var moon_st := _begin()
	_append(moon_st, moon_mesh, Transform3D.IDENTITY, Color(0.7, 0.72, 0.78))
	var moon := _add(root, "Moon", _done(moon_st), _material("Moon", 0.9))
	moon.position = Vector3(70, 40, -120)
	return root


# region pieces -------------------------------------------------------------------------------

## A faceted mountain: a jittered base ring, a narrower mid ring and an apex, coloured by height
## (grass, rock, snow) one flat colour per triangle.
func _peak(st: SurfaceTool, rng: RandomNumberGenerator, base: float, height: float, at: Transform3D) -> void:
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
	for i in sides:
		var j := (i + 1) % sides
		_peak_triangle(st, at, ring_low[i], ring_low[j], ring_mid[j], height)
		_peak_triangle(st, at, ring_low[i], ring_mid[j], ring_mid[i], height)
		_peak_triangle(st, at, ring_mid[i], ring_mid[j], apex, height)


func _peak_triangle(st: SurfaceTool, at: Transform3D, a: Vector3, b: Vector3, c: Vector3, peak_height: float) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0:
		normal = -normal
		var t := b
		b = c
		c = t
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
		st.set_normal(at.basis * normal)
		st.set_color(color)
		st.add_vertex(at * v)


func _tree(st: SurfaceTool, rng: RandomNumberGenerator, at: Vector3) -> void:
	var size := rng.randf_range(0.8, 1.6)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12 * size
	trunk.bottom_radius = 0.16 * size
	trunk.height = 1.0 * size
	trunk.radial_segments = 5
	trunk.rings = 1
	_append(st, trunk, Transform3D(Basis(), at + Vector3(0, 0.5 * size, 0)), Color(0.4, 0.28, 0.18))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 0.9 * size
	crown.height = 2.4 * size
	crown.radial_segments = 6
	crown.rings = 1
	_append(st, crown, Transform3D(Basis(), at + Vector3(0, 2.1 * size, 0)),
		Color(0.18, 0.36, 0.2).lerp(Color(0.25, 0.42, 0.2), rng.randf()))


func _disc(radius: float, color: Color) -> ArrayMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 64
	mesh.rings = 1
	var st := _begin()
	_append(st, mesh, Transform3D(Basis(), Vector3(0, -0.011, 0)), color)
	return _done(st)


# region helpers ------------------------------------------------------------------------------

func _root(root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	return root


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Adds a primitive mesh's triangles to [param st], moved by [param xform], in one colour (sRGB).
func _append(st: SurfaceTool, primitive: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var nbasis := xform.basis.inverse().transposed()
	for index in indices:
		st.set_color(color)
		st.set_normal((nbasis * normals[index]).normalized())
		st.add_vertex(xform * verts[index])


func _add(root: Node3D, node_name: String, mesh: ArrayMesh, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	mesh.surface_set_material(0, material)
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	return instance


func _material(material_name: String, roughness: float, double_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = material_name
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Merges shared vertices (smaller files) and makes the mesh.
func _done(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()
