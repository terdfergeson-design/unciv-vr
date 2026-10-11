# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Folders of things players and modders can add without touching the game: backgrounds and tables
## (tilesets have their own loader, tileset.gd, built the same way). Each kind has a built-in folder
## (res://backgrounds, res://tables) and one next to the saved games (~/.unciv-vr/Backgrounds, .../Tables).
## A thing is a sub-folder with a json file (background.json, table.json) and its models, read when the
## game runs, so there's nothing to import.

const DataPaths := preload("res://scripts/data_paths.gd")
const Tileset := preload("res://scripts/tileset.gd")
const Shaders := preload("res://scripts/tileset_shaders.gd")
const MODEL_EXTENSIONS := ["glb", "gltf", "tscn", "scn"]


## Where things of [param kind] ("Backgrounds", "Tables") are looked for: built-in first, then the user's.
static func search_dirs(kind: String) -> Array:
	var dirs := [DataPaths.builtin_dir(kind.to_lower())]
	var home := DataPaths.home_dir()
	if home != "":
		dirs.append(home.path_join(".unciv-vr").path_join(kind))
	return dirs


## Every folder of [param kind] with a [param json_name] in it: folder name -> its "name" (the title).
## A built-in folder wins over one of yours with the same name, as in [method find] - yours is never loaded.
static func available(kind: String, json_name: String) -> Dictionary:
	var out := {}
	for dir_path: String in search_dirs(kind):
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			if out.keys().any(func(k: String) -> bool: return k.to_lower() == sub.to_lower()):
				push_warning("%s is hidden by the built-in %s of the same name; rename the folder to use it" % [dir_path.path_join(sub), sub])
				continue
			var json: Variant = read_json(dir_path.path_join(sub).path_join(json_name))
			if json != null:
				out[sub] = str(json.get("name", sub))
	return out


## The path of folder [param folder_name] of [param kind], or "" if there's none. Matches ignoring case, so
## older settings ("mountains") still find their folder ("Mountains").
static func find(kind: String, folder_name: String, json_name: String) -> String:
	for exact in [true, false]:
		for dir_path: String in search_dirs(kind):
			var dir := DirAccess.open(dir_path)
			if dir == null:
				continue
			for sub in dir.get_directories():
				if (sub == folder_name) if exact else (sub.to_lower() == folder_name.to_lower()):
					var path: String = dir_path.path_join(sub)
					if FileAccess.file_exists(path.path_join(json_name)):
						return path
	return ""


## Unciv-style json (// comments allowed); null if missing or not an object.
static func read_json(path: String) -> Variant:
	return Tileset._read_json(path)


## The model file in [param folder] named [param file_name] (with or without its extension), or "".
static func model_path(folder: String, file_name: String) -> String:
	if file_name == "":
		return ""
	if file_name.get_extension().to_lower() in MODEL_EXTENSIONS:
		var direct := folder.path_join(file_name)
		return direct if FileAccess.file_exists(direct) else ""
	for ext: String in MODEL_EXTENSIONS:
		var path := folder.path_join(file_name + "." + ext)
		if FileAccess.file_exists(path):
			return path
	return ""


## Loads a model (.glb / .gltf, read at runtime; or a Godot scene) as a node tree, or null.
## Materials named like the tileset's animated ones (Water, Lava, Smoke...) get their shaders.
static func load_model(path: String) -> Node3D:
	if path == "":
		return null
	var ext := path.get_extension().to_lower()
	var root: Node = null
	if ext in ["tscn", "scn"]:
		var scene: Variant = load(path)
		if scene is PackedScene:
			root = (scene as PackedScene).instantiate()
	else:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var error := OK
		if ext == "gltf":
			error = doc.append_from_file(ProjectSettings.globalize_path(path), state)   # may refer to .bin / textures
		else:
			var bytes := FileAccess.get_file_as_bytes(path)
			error = ERR_FILE_CANT_READ if bytes.is_empty() else doc.append_from_buffer(bytes, path.get_base_dir(), state)
		if error == OK:
			root = doc.generate_scene(state)
		else:
			push_warning("Can't read %s (error %d)" % [path, error])
	if root == null:
		return null
	if not root is Node3D:
		var holder := Node3D.new()
		holder.add_child(root)
		root = holder
	_fix_materials(root)
	return root as Node3D


static func _fix_materials(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		for s in mesh.get_surface_count():
			var material: Material = instance.get_surface_override_material(s)
			if material == null:
				material = mesh.surface_get_material(s)
			if material == null:
				continue
			if material is BaseMaterial3D and mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR:
				material = material.duplicate()
				(material as BaseMaterial3D).vertex_color_use_as_albedo = true   # painted with vertex colours
			if material is BaseMaterial3D:
				_add_mipmaps(material as BaseMaterial3D)
			var animated := Shaders.material_for(material)
			instance.set_surface_override_material(s, animated if animated != null else material)
	for child in node.get_children():
		_fix_materials(child)


## Textures read at runtime come without mipmaps, which makes wood grain and the like shimmer from afar.
static func _add_mipmaps(material: BaseMaterial3D) -> void:
	for param: BaseMaterial3D.TextureParam in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL,
			BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION]:
		var texture := material.get_texture(param)
		if texture is ImageTexture:
			var image := (texture as ImageTexture).get_image()
			if image != null and not image.has_mipmaps():
				if image.is_compressed():
					continue
				image.generate_mipmaps()
				material.set_texture(param, ImageTexture.create_from_image(image))


## A colour from json: [r, g, b] or [r, g, b, a] in 0-255 like Unciv's, or "#rrggbb"; [param default] otherwise.
static func color(value: Variant, default: Color) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color8(int(a[0]), int(a[1]), int(a[2]), int(a[3]) if a.size() > 3 else 255)
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	return default
