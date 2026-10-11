# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## A 3D tileset: a folder with a tileset.json and a pieces/ folder of models, modelled on Unciv's
## tilesets (Images/TileSets/<name> + jsons/TileSets/<name>.json). See tilesets/README.md.
##
## A tile is drawn as a stack of pieces, looked up by name the way Unciv looks up tile images:
##   terrain:   ruleVariants["Base+Feature+..."], else a piece named "Base+Feature+...",
##              else the base piece then one piece per feature
##   wonder:    a piece named after the natural wonder, else "NaturalWonder"; either one is the whole
##              tile, replacing the terrain (ruleVariants["<wonder>"] can list layers instead)
##   rivers:    "River-Bottom", "River-BottomLeft", "River-BottomRight"
##   resource / improvement: ruleVariants or a piece named "Resource+Improvement", else each one;
##              improvements try "<name>-Pillaged" and "<name>-<era>" first
## Pieces named "X2", "X3"... are variants of "X"; each tile picks one variant number for all its pieces.
## "X-Far" is a simpler stand-in for "X", used when much of the map is on the table.
## Materials named Steam, Geyser, Smoke, Lava, Sparkle or Shimmer are animated (tileset_shaders.gd).
## Anything this set lacks comes from fallbackTileSet, and in the end from a plain coloured hex.

const DataPaths := preload("res://scripts/data_paths.gd")
const Shaders := preload("res://scripts/tileset_shaders.gd")
const BUILT_IN_DIR := "res://tilesets"
const MODEL_EXTENSIONS := ["glb", "gltf", "tscn", "scn", "res", "obj"]


## Where tilesets are looked for: the built-in ones, then the players' and mods' own in
## ~/.unciv-vr/Tilesets (next to the saved games).
static func search_dirs() -> Array:
	var home := DataPaths.home_dir()
	var dirs := [DataPaths.builtin_dir("tilesets")]
	if home != "":
		dirs.append(home.path_join(".unciv-vr/Tilesets"))
	return dirs

var name := ""
var title := ""
var folder := ""
var config: Dictionary = {}
var fallback: RefCounted = null          # another tileset.gd, or null
var _files: Dictionary = {}              # piece name -> file path (only names without a variant number)
var _variants: Dictionary = {}           # piece name -> [path, path2, ...]
var _far_files: Dictionary = {}          # piece name -> path of its "-Far" stand-in
var _unit_files: Dictionary = {}         # unit model name -> path (pieces/Units/)
var _loaded: Dictionary = {}             # path -> {mesh: ArrayMesh} or {scene: PackedScene}


## Every tileset that can be picked: folder name -> its title, from the built-in and user folders.
static func available(extra_dirs: Array = []) -> Dictionary:
	var out := {}
	for dir_path: String in search_dirs() + extra_dirs:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			var json: Variant = _read_json(dir_path.path_join(sub).path_join("tileset.json"))
			if json != null:
				out[sub] = str(json.get("name", sub))
	return out


## Loads the tileset in folder [param tileset_name] (searching search_dirs(), then [param extra_dirs]).
static func open(tileset_name: String, extra_dirs: Array = [], _depth := 0) -> RefCounted:
	for dir_path: String in search_dirs() + extra_dirs:
		var path: String = dir_path.path_join(tileset_name)
		var json: Variant = _read_json(path.path_join("tileset.json"))
		if json == null:
			continue
		var tileset := new()
		tileset._setup(tileset_name, path, json)
		var fallback_name: Variant = json.get("fallbackTileSet")
		if fallback_name != null and str(fallback_name) != "" and str(fallback_name) != tileset_name and _depth < 4:
			tileset.fallback = open(str(fallback_name), extra_dirs, _depth + 1)
		return tileset
	push_warning("Tileset %s not found" % tileset_name)
	return null


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	# Unciv's json files allow // comments; so do ours
	var lines := PackedStringArray()
	for line in text.split("\n"):
		var cut := line.find("//")
		lines.append(line if cut < 0 or line.substr(0, cut).count("\"") % 2 == 1 else line.substr(0, cut))
	var parsed: Variant = JSON.parse_string("\n".join(lines))
	return parsed if parsed is Dictionary else null


func _setup(folder_name: String, path: String, json: Dictionary) -> void:
	name = folder_name
	title = str(json.get("name", folder_name))
	folder = path
	config = json
	var pieces_dir := path.path_join("pieces")
	var found := {}
	for file in _list_files(pieces_dir):
		var ext := file.get_extension().to_lower()
		if ext == "import":
			file = file.get_basename()   # exported builds only list the .import files
			ext = file.get_extension().to_lower()
		if ext not in MODEL_EXTENSIONS:
			continue
		found[file.get_basename()] = pieces_dir.path_join(file)
	var units_dir := pieces_dir.path_join("Units")
	for file in _list_files(units_dir):
		var unit_ext := file.get_extension().to_lower()
		if unit_ext == "import":
			file = file.get_basename()
			unit_ext = file.get_extension().to_lower()
		if unit_ext in MODEL_EXTENSIONS:
			_unit_files[file.get_basename()] = units_dir.path_join(file)
	for piece: String in found.keys():
		if piece.ends_with("-Far"):
			_far_files[piece.trim_suffix("-Far")] = found[piece]
			found.erase(piece)
	# "Grassland2" is a variant of "Grassland" when both exist
	for piece: String in found:
		var stem := piece.rstrip("0123456789")
		if stem != piece and found.has(stem):
			continue
		_files[piece] = found[piece]
		var list: Array = [found[piece]]
		var n := 2
		while found.has(piece + str(n)):
			list.append(found[piece + str(n)])
			n += 1
		_variants[piece] = list


static func _list_files(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path)
	return dir.get_files() if dir != null else PackedStringArray()


func has_piece(piece: String) -> bool:
	return _files.has(piece) or (fallback != null and fallback.has_piece(piece))


## The model for [param piece] (variant [param variant] if it has several):
## {mesh: ArrayMesh} for glTF / OBJ / mesh files, {scene: PackedScene} for Godot scenes, or {}.
## [param far]: the simpler "-Far" stand-in if the set has one.
func get_piece(piece: String, variant := 0, far := false) -> Dictionary:
	if not _files.has(piece):
		return fallback.get_piece(piece, variant, far) if fallback != null else {}
	var list: Array = _variants[piece]
	var path: String = _far_files[piece] if far and _far_files.has(piece) else list[variant % list.size()]
	if not _loaded.has(path):
		_loaded[path] = _load_model(path)
	return _loaded[path]


## The model for a unit (from pieces/Units), like Unciv's unit images: "<unit>-<style>-<era>", "<unit>-<era>",
## "<unit>-<style>", "<unit>"; then the unit it replaces (a civ's unique unit), then its unit type ("Sword",
## "Mounted"...), then the fallback tileset. [param info] is the ruleset's entry for the unit (unitType, replaces).
## [param embarked]: the "Embarked" boat if the set has one. {} when nothing fits (the map draws a token).
func unit_model(unit: String, info: Dictionary, embarked := false, era := "", style := "") -> Dictionary:
	var candidates: Array[String] = []
	if embarked:
		candidates.append("Embarked")
	for name_: String in [unit, str(info.get("replaces", ""))]:
		if name_ == "":
			continue
		if style != "" and era != "":
			candidates.append("%s-%s-%s" % [name_, style, era])
		if era != "":
			candidates.append("%s-%s" % [name_, era])
		if style != "":
			candidates.append("%s-%s" % [name_, style])
		candidates.append(name_)
	if str(info.get("unitType", "")) != "":
		candidates.append(str(info["unitType"]))
	for candidate in candidates:
		if _unit_files.has(candidate):
			var path: String = _unit_files[candidate]
			if not _loaded.has(path):
				_loaded[path] = _load_model(path)
			return _loaded[path]
	return fallback.unit_model(unit, info, embarked, era, style) if fallback != null else {}


## Which model [method unit_model] would use for [param unit] ("Swordsman", "Sword"...), and from which set:
## [model name, tileset folder], or ["", ""] when there's none (the map draws a token).
func unit_model_source(unit: String, info: Dictionary, embarked := false) -> Array:
	var candidates: Array[String] = []
	if embarked:
		candidates.append("Embarked")
	for name_: String in [unit, str(info.get("replaces", "")), str(info.get("unitType", ""))]:
		if name_ != "":
			candidates.append(name_)
	for candidate in candidates:
		if _unit_files.has(candidate):
			return [candidate, name]
	return fallback.unit_model_source(unit, info, embarked) if fallback != null else ["", ""]


## Which set has [param piece]: this one's folder name, the fallback's, or "" if none.
func piece_source(piece: String) -> String:
	if _files.has(piece):
		return name
	return fallback.piece_source(piece) if fallback != null else ""


## Whether this set has unit models of its own (pieces/Units).
func has_units() -> bool:
	return not _unit_files.is_empty()


## How much bigger than modelled units are drawn ("unitScale" in tileset.json).
func unit_scale() -> float:
	return float(config.get("unitScale", 1.0))


func variant_count(piece: String) -> int:
	if _variants.has(piece):
		return _variants[piece].size()
	return fallback.variant_count(piece) if fallback != null else 1


static func _load_model(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext in ["tscn", "scn"]:
		var scene: Variant = load(path)
		return {"scene": scene} if scene is PackedScene else {}
	if ext in ["res", "obj"]:
		var mesh: Variant = load(path)
		return {"mesh": mesh} if mesh is Mesh else {}
	# glTF: read at runtime from the file's bytes, so pieces dropped into a user folder work without
	# Godot's importer (the built-in set's folder has a .gdignore, so it's loaded the same way)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	var error := ERR_FILE_CANT_READ if bytes.is_empty() else OK
	if error == OK and ext == "gltf":
		error = doc.append_from_file(ProjectSettings.globalize_path(path), state)   # may refer to .bin / texture files
	elif error == OK:
		error = doc.append_from_buffer(bytes, path.get_base_dir(), state)
	if error != OK:
		push_warning("Can't read tileset piece %s (error %d)" % [path, error])
		return {}
	var root := doc.generate_scene(state)
	var merged := ArrayMesh.new()
	_merge_meshes(root, Transform3D.IDENTITY, merged)
	root.free()
	return {"mesh": merged} if merged.get_surface_count() > 0 else {}


## Bakes every mesh under [param node] into [param out] (one surface per source surface), so a
## piece can be drawn by a single MultiMesh however it was modelled.
static func _merge_meshes(node: Node, parent: Transform3D, out: ArrayMesh) -> void:
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] = xform * verts[i]
			arrays[Mesh.ARRAY_VERTEX] = verts
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var nbasis := xform.basis.inverse().transposed()
				for i in normals.size():
					normals[i] = (nbasis * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null   # not used by the tileset materials
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material: Material = instance.get_surface_override_material(s)
			if material == null:
				material = mesh.surface_get_material(s)
			if material is BaseMaterial3D and arrays[Mesh.ARRAY_COLOR] != null:
				material = material.duplicate()
				(material as BaseMaterial3D).vertex_color_use_as_albedo = true   # painted with vertex colours
			var animated := Shaders.material_for(material)
			out.surface_set_material(out.get_surface_count() - 1, animated if animated != null else material)
	for child in node.get_children():
		_merge_meshes(child, xform, out)


# region choosing pieces ----------------------------------------------------------------------

## The pieces to draw for [param tile] (a getState tile), bottom to top:
## [{piece: String, rotate: bool, kind: "terrain" / "wonder" / "river" / "resource" / "improvement"}].
## rotate = may be turned with the tile's random rotation.
## [param era] is the owner's era (e.g. "Medieval era") for era-specific improvement models.
func pieces_for(tile: Dictionary, era := "") -> Array:
	var out: Array = []
	var base := str(tile.get("base", ""))
	var features: Array = tile.get("features", [])
	var terrain := "+".join([base] + features)
	var variants: Dictionary = config.get("ruleVariants", {})
	var resource := str(tile.get("resource", ""))
	var improvement := str(tile.get("improvement", ""))
	if tile.has("city"):
		improvement = ""   # cities are drawn by the map itself

	# The whole tile at once, if the set says so ("Grassland+Forest+Deer+Camp": [...])
	var full := terrain
	if resource != "":
		full += "+" + resource
	if improvement != "":
		full += "+" + improvement
	if full != terrain and variants.has(full):
		for p: String in variants[full]:
			out.append(_entry(p, false, "terrain"))
		_add_rivers(tile, out)
		return _existing(out)

	# A natural wonder is a whole tile of its own (unless ruleVariants lists layers for it)
	var wonder := str(tile.get("wonder", ""))
	var wonder_piece := wonder if has_piece(wonder) else ("NaturalWonder" if wonder != "" and has_piece("NaturalWonder") else "")
	if wonder != "" and variants.has(wonder):
		for p: String in variants[wonder]:
			out.append(_entry(p, false, "wonder"))
	elif wonder_piece != "":
		out.append(_entry(wonder_piece, false, "wonder"))
	elif variants.has(terrain):
		for p: String in variants[terrain]:
			out.append(_entry(p, true, "terrain"))
	elif has_piece(terrain):
		out.append(_entry(terrain, true, "terrain"))
	else:
		out.append(_entry(base, true, "terrain"))
		for f: String in features:
			out.append(_entry(f, true, "terrain"))
	_add_rivers(tile, out)

	var pillaged: bool = tile.get("pillaged", false)
	var improvement_piece := improvement_piece_for(improvement, pillaged, era)
	var combined := resource + "+" + improvement
	if resource != "" and improvement != "" and variants.has(combined):
		for p: String in variants[combined]:
			out.append(_entry(p, false, "improvement"))
	elif resource != "" and improvement != "" and has_piece(combined):
		out.append(_entry(combined, false, "improvement"))
	else:
		if resource != "":
			out.append(_entry(resource, false, "resource"))
		if improvement_piece != "":
			out.append(_entry(improvement_piece, false, "improvement"))
	return _existing(out)


## The piece for an improvement: "<name>-Pillaged" if pillaged, "<name>-<era>", then "<name>"; "" if none.
func improvement_piece_for(improvement: String, pillaged := false, era := "") -> String:
	if improvement == "":
		return ""
	for candidate: String in [improvement + "-Pillaged" if pillaged else "", improvement + "-" + era if era != "" else "", improvement]:
		if candidate != "" and has_piece(candidate):
			return candidate
	return ""


static func _entry(piece: String, rotate: bool, kind: String) -> Dictionary:
	return {"piece": piece, "rotate": rotate, "kind": kind}


func _existing(entries: Array) -> Array:
	return entries.filter(func(p: Dictionary) -> bool: return has_piece(p["piece"]))


func _add_rivers(tile: Dictionary, out: Array) -> void:
	var river: Dictionary = tile.get("river", {})
	for side: String in ["bottom", "bottomLeft", "bottomRight"]:
		if river.get(side, false):
			out.append(_entry("River-" + side.capitalize().replace(" ", ""), false, "river"))


## Whether the set has a model for the tile's base terrain at all (if not, draw a plain hex).
func covers(tile: Dictionary) -> bool:
	var base := str(tile.get("base", ""))
	var terrain := "+".join([base] + tile.get("features", []))
	return has_piece(base) or has_piece(terrain) or config.get("ruleVariants", {}).has(terrain)


## How high a unit or city stands on [param tile]: "heights" in tileset.json, checked for the
## tile's natural wonder (then "NaturalWonder"), its features (last first), its base terrain,
## then "Land" / "Water" by terrain type.
func surface_height(tile: Dictionary, terrain_type := "Land") -> float:
	var heights: Dictionary = config.get("heights", {})
	var wonder := str(tile.get("wonder", ""))
	if wonder != "":
		if heights.has(wonder):
			return float(heights[wonder])
		if heights.has("NaturalWonder"):
			return float(heights["NaturalWonder"])
	var features: Array = tile.get("features", [])
	for i in range(features.size() - 1, -1, -1):
		if heights.has(features[i]):
			return float(heights[features[i]])
	var base := str(tile.get("base", ""))
	if heights.has(base):
		return float(heights[base])
	return float(heights.get(terrain_type, 0.15 if terrain_type != "Water" else 0.05))


## How high the rim of [param tile]'s pieces is, where territory borders lie: "edgeHeights" in tileset.json, by
## natural wonder, base terrain, then "Land" / "Water" (Low poly: land tiles all meet at 0.15).
func edge_height(tile: Dictionary, terrain_type := "Land") -> float:
	var edges: Dictionary = config.get("edgeHeights", {})
	var wonder := str(tile.get("wonder", ""))
	if wonder != "" and edges.has(wonder):
		return float(edges[wonder])
	var base := str(tile.get("base", ""))
	if edges.has(base):
		return float(edges[base])
	return float(edges.get(terrain_type, 0.15 if terrain_type != "Water" else 0.05))


## Random 60-degree turns for each tile's terrain pieces, so repeated tiles don't look stamped.
func random_rotation() -> bool:
	return bool(config.get("randomRotation", true))


## Overall scale of the pieces, with per-piece overrides (Unciv's tileScale / tileScales).
func piece_scale(piece: String) -> float:
	var scales: Dictionary = config.get("tileScales", {})
	return float(scales.get(piece, config.get("tileScale", 1.0)))
