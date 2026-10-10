extends SceneTree
## Renders a tileset for review: one picture per tile type, and a small sample map (plus the same map
## drawn the old way, for comparison). Usage:
##   godot --path . -s tools/preview_tileset.gd -- <tileset> <out folder>

const Tileset := preload("res://scripts/tileset.gd")
const SQRT3 := 1.7320508

var ts: RefCounted
var vp: SubViewport
var world: Node3D
var out_dir := "/tmp/preview"
var cells: Array = CELLS
var wonders_only := false
var battle_mode := false   # "battle": a few fights played with unit_motion.gd, as frames
var units_only := false   # "units": every unit model, in civ colours
var anim_wonder := ""   # "anim <wonder>": a run of frames of one wonder, to check its animation

const CELLS := [
	["Grassland", {"base": "Grassland"}],
	["Plains", {"base": "Plains"}],
	["Desert", {"base": "Desert"}],
	["Tundra", {"base": "Tundra"}],
	["Snow", {"base": "Snow"}],
	["Coast", {"base": "Coast"}],
	["Ocean", {"base": "Ocean"}],
	["Lakes", {"base": "Lakes"}],
	["Mountain", {"base": "Mountain"}],
	["Grassland + Hill", {"base": "Grassland", "features": ["Hill"]}],
	["Plains + Hill", {"base": "Plains", "features": ["Hill"]}],
	["Desert + Hill", {"base": "Desert", "features": ["Hill"]}],
	["Tundra + Hill", {"base": "Tundra", "features": ["Hill"]}],
	["Snow + Hill", {"base": "Snow", "features": ["Hill"]}],
	["Grassland + Forest", {"base": "Grassland", "features": ["Forest"]}],
	["Tundra + Forest", {"base": "Tundra", "features": ["Forest"]}],
	["Hill + Forest", {"base": "Grassland", "features": ["Hill", "Forest"]}],
	["Plains + Jungle", {"base": "Plains", "features": ["Jungle"]}],
	["Hill + Jungle", {"base": "Grassland", "features": ["Hill", "Jungle"]}],
	["Marsh", {"base": "Grassland", "features": ["Marsh"]}],
	["Flood plains", {"base": "Desert", "features": ["Flood plains"]}],
	["Oasis", {"base": "Desert", "features": ["Oasis"]}],
	["Ice", {"base": "Coast", "features": ["Ice"]}],
	["Atoll", {"base": "Coast", "features": ["Atoll"]}],
	["Fallout", {"base": "Plains", "features": ["Fallout"]}],
	["Natural wonder", {"base": "Desert", "wonder": "Uluru"}],
	["River (3 sides)", {"base": "Grassland", "river": {"bottom": true, "bottomLeft": true, "bottomRight": true}}],
	["Wheat", {"base": "Plains", "resource": "Wheat"}],
	["Wheat + Farm", {"base": "Plains", "resource": "Wheat", "improvement": "Farm"}],
	["Cattle + Pasture", {"base": "Grassland", "resource": "Cattle", "improvement": "Pasture"}],
	["Horses", {"base": "Plains", "resource": "Horses"}],
	["Sheep (Hill)", {"base": "Grassland", "features": ["Hill"], "resource": "Sheep"}],
	["Iron + Mine (Hill)", {"base": "Desert", "features": ["Hill"], "resource": "Iron", "improvement": "Mine"}],
	["Fish", {"base": "Coast", "resource": "Fish"}],
	["Farm", {"base": "Grassland", "improvement": "Farm"}],
	["Mine (Hill)", {"base": "Plains", "features": ["Hill"], "improvement": "Mine"}],
]

# The sample map, column by column in Unciv's offset layout. Codes: O ocean, C coast, L lakes,
# G grassland, P plains, D desert, T tundra, S snow, M mountain; then h hill, f forest, j jungle,
# m marsh, F flood plains, o oasis, i ice, a atoll.
const MAP := [
	"Oi Ci S  Sh Tf T  Th M  M  Tf T  C  O  O",
	"O  C  T  Tf T  Thf Gf M  Gh P  Pf C  O  O",
	"O  C  G  Gf G  G  Gh G  P  Ph P  L  C  O",
	"O  Ca C  G  Gm P  G  Pf P  D  D  Dh C  O",
	"O  O  C  G  Gf Gj P  P  DF D  Do D  C  O",
	"O  O  C  Gj Gj Ghj Pj P  DF D  Dh M  C  O",
	"O  Ca O  C  C  Gm G  C  DF C  D  C  O  O",
	"O  O  O  O  O  C  C  O  C  O  C  O  O  O",
]
const EXTRAS := {
	Vector2i(4, 2): {"resource": "Wheat", "improvement": "Farm"},
	Vector2i(9, 1): {"resource": "Horses"},
	Vector2i(5, 3): {"resource": "Cattle", "improvement": "Pasture"},
	Vector2i(8, 2): {"resource": "Sheep"},
	Vector2i(11, 3): {"resource": "Iron", "improvement": "Mine"},
	Vector2i(2, 3): {"resource": "Fish"},
	Vector2i(7, 6): {"resource": "Fish"},
	Vector2i(9, 4): {"wonder": "Uluru"},
	Vector2i(3, 2): {"improvement": "Farm"},
}
const RIVER := [Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 3)]
const CODES := {"O": "Ocean", "C": "Coast", "L": "Lakes", "G": "Grassland", "P": "Plains", "D": "Desert",
	"T": "Tundra", "S": "Snow", "M": "Mountain"}
const FEATURES := {"h": "Hill", "f": "Forest", "j": "Jungle", "m": "Marsh", "F": "Flood plains", "o": "Oasis",
	"i": "Ice", "a": "Atoll"}
# Unciv's terrain colours (Civ V - Gods & Kings Terrains.json), for the "before" picture
const RGB := {"Ocean": Color8(43, 87, 151), "Coast": Color8(70, 138, 216), "Grassland": Color8(0, 163, 0),
	"Plains": Color8(153, 180, 51), "Tundra": Color8(124, 62, 57), "Desert": Color8(230, 172, 0),
	"Lakes": Color8(0, 171, 169), "Mountain": Color8(102, 102, 102), "Snow": Color8(230, 238, 255), "Hill": Color8(105, 125, 72)}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var tileset_name := args[0] if args.size() > 0 else "LowPoly"
	if args.size() > 1:
		out_dir = args[1]
	if args.size() > 3 and args[2] == "anim":
		anim_wonder = args[3]
	if args.size() > 2 and args[2] == "battle":
		battle_mode = true
	if args.size() > 2 and args[2] == "units":
		units_only = true
	if args.size() > 2 and args[2] == "wonders":
		wonders_only = true
		cells = []
		for w: String in ["Mount Fuji", "Mount Kilimanjaro", "Mount Kailash", "Sri Pada", "Mount Sinai", "Cerro de Potosi",
				"Krakatoa", "Rock of Gibraltar", "Uluru", "Grand Mesa", "Barringer Crater", "Old Faithful",
				"Great Barrier Reef", "Lake Victoria", "Fountain of Youth", "El Dorado", "King Solomon's Mines", "Some mod's wonder"]:
			cells.append([w if w != "Some mod's wonder" else "Fallback (any other wonder)", {"base": "Mountain", "wonder": w}])
	DirAccess.make_dir_recursive_absolute(out_dir)
	ts = Tileset.open(tileset_name)
	_setup_scene()
	_run.call_deferred()


func _setup_scene() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.52, 0.82)
	sky_material.sky_horizon_color = Color(0.78, 0.86, 0.93)
	sky_material.ground_bottom_color = Color(0.25, 0.33, 0.22)
	sky_material.ground_horizon_color = Color(0.6, 0.68, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_material
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 140, 0) if not OS.get_cmdline_user_args().has("frontlight") else Vector3(-45, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	vp.add_child(sun)
	world = Node3D.new()
	vp.add_child(world)


func _run() -> void:
	var cam := Camera3D.new()
	if units_only:
		await _render_units(cam)
		return
	if battle_mode:
		await _render_battles(cam)
		return
	if anim_wonder != "":
		vp.add_child(cam)
		vp.size = Vector2i(360, 400)
		cam.fov = 32
		world.add_child(_table_disc(2.2))
		world.add_child(build_tile({"base": "Mountain", "wonder": anim_wonder, "explored": true, "visible": true}, Vector3.ZERO, 0, 0))
		cam.look_at_from_position(Vector3(0, 2.3, 3.3), Vector3(0, 0.55, 0.0))
		var started := Time.get_ticks_msec()
		var frame := 0
		while Time.get_ticks_msec() - started < 16000:
			await _frames(1)
			if Time.get_ticks_msec() - started >= frame * 250:
				vp.get_texture().get_image().save_png(out_dir.path_join("anim_%03d.png" % frame))
				frame += 1
		print("frames ", frame)
		quit()
		return
	# one picture per tile type
	cam.fov = 32
	vp.add_child(cam)
	vp.size = Vector2i(420, 340)
	var table := _table_disc(2.2)
	for i in cells.size():
		_clear()
		world.add_child(table.duplicate())
		var tile: Dictionary = cells[i][1].duplicate(true)
		tile["explored"] = true
		tile["visible"] = true
		world.add_child(build_tile(tile, Vector3.ZERO, 0, 0))
		if wonders_only:
			cam.look_at_from_position(Vector3(0, 2.5, 3.3), Vector3(0, 0.42, 0.05))
		else:
			cam.look_at_from_position(Vector3(0, 2.25, 2.9), Vector3(0, 0.22, 0.05))
		await _frames(4)
		vp.get_texture().get_image().save_png(out_dir.path_join("cell_%02d.png" % i))
	if wonders_only:
		_write_names()
		print("done")
		quit()
		return
	# the sample map, new and old
	vp.size = Vector2i(1600, 1000)
	cam.fov = 38
	for style in ["new", "old"]:
		_clear()
		world.add_child(_table_disc(13.0, Vector3(9.75, 0, 7.0)))
		_build_map(style == "new")
		cam.look_at_from_position(Vector3(9.75, 13.0, 19.5), Vector3(9.75, 0, 6.6))
		await _frames(5)
		vp.get_texture().get_image().save_png(out_dir.path_join("map_%s.png" % style))
	# a close look, roughly what you see leaning over the table
	_clear()
	world.add_child(_table_disc(13.0, Vector3(9.75, 0, 7.0)))
	_build_map(true)
	cam.fov = 45
	cam.look_at_from_position(Vector3(6.0, 4.2, 10.8), Vector3(7.2, 0.2, 4.6))
	await _frames(5)
	vp.get_texture().get_image().save_png(out_dir.path_join("map_close.png"))
	_write_names()
	print("done")
	quit()


func _write_names() -> void:
	var names := []
	for c: Array in cells:
		names.append(c[0])
	var f := FileAccess.open(out_dir.path_join("cells.txt"), FileAccess.WRITE)
	f.store_string("\n".join(names))
	f.close()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _clear() -> void:
	for child in world.get_children():
		child.free()


func _table_disc(radius: float, at := Vector3.ZERO) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.1
	mesh.radial_segments = 48
	disc.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.26, 0.19)
	m.roughness = 0.8
	disc.material_override = m
	disc.position = at + Vector3(0, -0.051, 0)
	return disc


## The tile's pieces from the tileset, stacked at [param at]. (The game draws them with one
## MultiMesh per piece instead; this is the simple version for pictures.)
func build_tile(tile: Dictionary, at: Vector3, variant: int, turns: int) -> Node3D:
	var node := Node3D.new()
	node.position = at
	for entry: Dictionary in ts.pieces_for(tile):
		var model: Dictionary = ts.get_piece(entry["piece"], variant)
		if model.has("mesh"):
			var mi := MeshInstance3D.new()
			mi.mesh = model["mesh"]
			if entry["rotate"]:
				mi.rotation.y = turns * PI / 3.0
			mi.scale = Vector3.ONE * ts.piece_scale(entry["piece"])
			node.add_child(mi)
		elif model.has("scene"):
			node.add_child(model["scene"].instantiate())
	return node


func _parse(code: String) -> Dictionary:
	var tile := {"base": CODES[code[0]], "features": [], "explored": true, "visible": true}
	for ch in code.substr(1):
		tile["features"].append(FEATURES[ch])
	return tile


func _build_map(new_style: bool) -> void:
	for row in MAP.size():
		var codes: PackedStringArray = MAP[row].split(" ", false)
		for col in codes.size():
			var key := Vector2i(col, row)
			var tile := _parse(codes[col])
			tile.merge(EXTRAS.get(key, {}))
			if key in RIVER:
				tile["river"] = {"bottom": true, "bottomLeft": true}
			var at := Vector3(1.5 * col, 0, SQRT3 * (row + 0.5 * (col % 2)))
			var h := hash(key)
			if new_style:
				world.add_child(build_tile(tile, at, h % 7, (h / 7) % 6))
			else:
				world.add_child(_old_tile(tile, at))
	# a city and two units, to see how they sit on the new ground
	_city(Vector3(1.5 * 6, ts.surface_height({"base": "Grassland"}) if new_style else 0.15, SQRT3 * 3), Color(0.15, 0.35, 0.8), Color(0.95, 0.85, 0.3))
	_unit(Vector3(1.5 * 4, ts.surface_height({"base": "Grassland", "features": ["Forest"]}) if new_style else 0.15, SQRT3 * 4) + Vector3(-0.25, 0, -0.2), Color(0.95, 0.85, 0.3))
	_unit(Vector3(1.5 * 8, ts.surface_height({"base": "Plains", "features": ["Hill"]}) if new_style else 0.3, SQRT3 * 1) + Vector3(-0.25, 0, -0.2), Color(0.9, 0.2, 0.2))


func _old_tile(tile: Dictionary, at: Vector3) -> Node3D:
	# hex_map.gd's current look: a coloured prism, cones for forests
	var features: Array = tile["features"]
	var height := 0.15
	if tile["base"] == "Mountain":
		height = 0.6
	elif tile.has("wonder"):
		height = 0.4
	elif "Hill" in features:
		height = 0.3
	elif tile["base"] in ["Ocean", "Coast", "Lakes"]:
		height = 0.03 if tile["base"] == "Ocean" else 0.06
	var color: Color = RGB[tile["base"]]
	for f: String in features:
		if RGB.has(f):
			color = color.lerp(RGB[f], 0.6)
	if tile.has("wonder"):
		color = Color(0.85, 0.7, 0.25)
	var node := Node3D.new()
	node.position = at
	var prism := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.97
	mesh.bottom_radius = 0.97
	mesh.radial_segments = 6
	mesh.height = height
	prism.mesh = mesh
	prism.position.y = height / 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	prism.material_override = m
	node.add_child(prism)
	if "Forest" in features or "Jungle" in features:
		for offset: Vector2 in [Vector2(-0.35, 0.2), Vector2(0.3, 0.3), Vector2(0.0, -0.35)]:
			var cone := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.17
			c.height = 0.45
			c.radial_segments = 8
			cone.mesh = c
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(0.12, 0.35, 0.15) if "Forest" in features else Color(0.1, 0.42, 0.12)
			cone.material_override = cm
			cone.position = Vector3(offset.x, height + 0.225, offset.y)
			node.add_child(cone)
	return node


func _city(at: Vector3, outer: Color, inner: Color) -> void:
	var blocks := [Vector3(-0.25, 0, -0.1), Vector3(0.2, 0, -0.2), Vector3(0.0, 0, 0.25), Vector3(0.3, 0, 0.2)]
	var heights := [0.35, 0.5, 0.3, 0.25]
	for b in blocks.size():
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.28, heights[b], 0.28)
		box.mesh = mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = outer if b % 2 == 0 else inner
		box.material_override = m
		box.position = at + blocks[b] + Vector3(0, heights[b] / 2.0, 0)
		world.add_child(box)


func _unit(at: Vector3, color: Color) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.32
	mesh.height = 0.08
	disc.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	disc.material_override = m
	disc.position = at + Vector3(0, 0.04, 0)
	world.add_child(disc)
	var flag := MeshInstance3D.new()
	var q := SphereMesh.new()
	q.radius = 0.2
	q.height = 0.4
	flag.mesh = q
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.22, 0.28)
	flag.material_override = fm
	flag.position = at + Vector3(0, 0.42, 0)
	world.add_child(flag)


const CIV_COLOURS := [[Color(0.75, 0.12, 0.12), Color(0.98, 0.85, 0.3)], [Color(0.15, 0.3, 0.75), Color(0.95, 0.95, 0.95)],
	[Color(0.1, 0.5, 0.25), Color(0.95, 0.8, 0.2)], [Color(0.45, 0.2, 0.55), Color(0.85, 0.85, 0.9)]]


## Every model in pieces/Units, each on a little tile in one of four civs' colours.
func _render_units(cam: Camera3D) -> void:
	vp.add_child(cam)
	vp.size = Vector2i(300, 300)
	cam.fov = 30
	var folder: String = str(ts.folder).path_join("pieces/Units")
	var names: Array = []
	for f in DirAccess.get_files_at(folder):
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	names.sort()
	var ground := {"base": "Grassland", "explored": true, "visible": true}
	var sea := {"base": "Coast", "explored": true, "visible": true}
	for i in names.size():
		_clear()
		var unit: String = names[i]
		var model: Dictionary = Tileset._load_model(folder.path_join(unit + ".glb"))
		var naval := unit in ["Trireme", "Galleass", "Caravel", "Privateer", "Frigate", "Ironclad", "Destroyer", "Battleship",
			"Missile Cruiser", "Submarine", "Nuclear Submarine", "Carrier", "Work Boats", "Great Admiral", "Embarked",
			"Melee Water", "Ranged Water", "Civilian Water", "Aircraft Carrier"]
		var tile := build_tile(sea if naval else ground, Vector3.ZERO, i % 3, 0)
		world.add_child(tile)
		var mi := MeshInstance3D.new()
		mi.mesh = model["mesh"]
		mi.position = Vector3(0, 0.06 if naval else 0.15, 0)
		mi.rotation.y = -0.5
		mi.scale = Vector3.ONE * 2.2
		var colours: Array = CIV_COLOURS[i % CIV_COLOURS.size()]
		for sidx in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(sidx)
			if mat != null and mat.resource_name in ["CivOuter", "CivInner"]:
				var tinted := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				tinted.albedo_color = colours[0] if mat.resource_name == "CivOuter" else colours[1]
				mi.set_surface_override_material(sidx, tinted)
		world.add_child(mi)
		cam.look_at_from_position(Vector3(0, 1.45, 2.0), Vector3(0, 0.55, 0))
		await _frames(3)
		vp.get_texture().get_image().save_png(out_dir.path_join("cell_%02d.png" % i))
	cells = []
	for n: String in names:
		cells.append([n, {}])
	_write_names()
	print("done")
	quit()


const Motion := preload("res://scripts/unit_motion.gd")
var _recording := false


func _unit_node(unit: String, colours: Array, at: Vector3, naval := false) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	holder.set_meta("naval", naval)
	var model: Dictionary = Tileset._load_model(str(ts.folder).path_join("pieces/Units/%s.glb" % unit))
	var mi := MeshInstance3D.new()
	mi.mesh = model["mesh"]
	for sidx in mi.mesh.get_surface_count():
		var mat: Material = mi.mesh.surface_get_material(sidx)
		if mat != null and mat.resource_name in ["CivOuter", "CivInner"]:
			var tinted := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			tinted.albedo_color = colours[0] if mat.resource_name == "CivOuter" else colours[1]
			mi.set_surface_override_material(sidx, tinted)
	mi.scale = Vector3.ONE * float(ts.config.get("unitScale", 1.0))
	holder.add_child(mi)
	return holder


func _record(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var frame := 0
	var started := Time.get_ticks_msec()
	while _recording:
		await _frames(1)
		if Time.get_ticks_msec() - started >= frame * 80:
			vp.get_texture().get_image().save_png(folder.path_join("f_%03d.png" % frame))
			frame += 1


func _render_battles(cam: Camera3D) -> void:
	vp.add_child(cam)
	vp.size = Vector2i(560, 380)
	cam.fov = 34
	var red: Array = CIV_COLOURS[0]
	var blue: Array = CIV_COLOURS[1]
	var fights := ["melee", "arrows", "cannon", "tank", "ships", "bomber", "move"]
	for fight: String in fights:
		_clear()
		var motion: Node3D = Motion.new()
		world.add_child(motion)
		var a_tile := Vector3(0, 0, 0)
		var d_tile := Vector3(1.5, 0, -0.866)
		var land := {"base": "Plains", "explored": true, "visible": true}
		var grass := {"base": "Grassland", "explored": true, "visible": true}
		var sea := {"base": "Coast", "explored": true, "visible": true}
		var naval := fight == "ships"
		if fight in ["arrows", "cannon", "bomber"]:
			d_tile = Vector3(3.0, 0, -1.732)
			motion.add_child(build_tile(grass, Vector3(1.5, 0, -0.866), 1, 2))
		var tiles: Array = [a_tile, d_tile]
		if fight == "move":
			tiles = [Vector3(0, 0, 0), Vector3(1.5, 0, -0.866), Vector3(3.0, 0, 0), Vector3(4.5, 0, -0.866)]
		for i in tiles.size():
			motion.add_child(build_tile(sea if naval else (land if i % 2 == 0 else grass), tiles[i], i, i))
		var y := 0.06 if naval else 0.15
		var pairs := {"melee": ["Swordsman", "Spearman"], "arrows": ["Archer", "Warrior"], "cannon": ["Cannon", "Pikeman"],
			"tank": ["Tank", "Rifleman"], "ships": ["Frigate", "Galleass"], "bomber": ["Bomber", "Infantry"], "move": ["Horseman", ""]}
		var attacker := _unit_node(pairs[fight][0], red, a_tile + Vector3(0, y, 0), naval)
		motion.add_child(attacker)
		var defender: Node3D = null
		if pairs[fight][1] != "":
			defender = _unit_node(pairs[fight][1], blue, d_tile + Vector3(0, y, 0), naval)
			motion.add_child(defender)
		var centre: Vector3 = (tiles[0] + tiles[-1]) / 2.0
		var span := (tiles[0] as Vector3).distance_to(tiles[-1])
		var dist := 2.4 + span * 0.78
		cam.look_at_from_position(centre + Vector3(0, dist * 0.6, dist * 0.8), centre + Vector3(0, 0.25, 0))
		await _frames(3)
		_recording = true
		_record(out_dir.path_join(fight))
		await create_timer(0.3).timeout
		match fight:
			"melee":
				await motion.melee(attacker, defender, 34, 18)
			"arrows":
				await motion.ranged(attacker, defender.position, defender, "arrow", 21)
			"cannon":
				await motion.ranged(attacker, defender.position, defender, "cannon", 100, true)
			"tank":
				await motion.melee(attacker, defender, 100, 7, true)
			"ships":
				await motion.ranged(attacker, defender.position, defender, "shipCannonVolley", 100, true)
			"bomber":
				await motion.ranged(attacker, defender.position, defender, "bombing", 45)
			"move":
				await motion.move(attacker, [tiles[1] + Vector3(0, y, 0), tiles[2] + Vector3(0, y, 0), tiles[3] + Vector3(0, y, 0)])
		await create_timer(0.6).timeout
		_recording = false
		await _frames(2)
	print("done")
	quit()
