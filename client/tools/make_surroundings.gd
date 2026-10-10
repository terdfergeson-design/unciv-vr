# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends SceneTree
## Writes the models of the built-in backgrounds and tables:
##   backgrounds/<Name>/scenery.glb      (tools/lowpoly_backgrounds.gd)
##   tables/<Name>/top.glb, column.glb, base.glb   (tools/tables.gd)
## The json files next to them are written by hand. Run from the client folder:
##   godot --headless --path . -s tools/make_surroundings.gd [backgrounds | tables]
## (the same format anyone can export from Blender for their own).

const Backgrounds := preload("res://tools/lowpoly_backgrounds.gd")
const Tables := preload("res://tools/tables.gd")


func _init() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		only = arg
	if only in ["", "backgrounds"]:
		var builder := Backgrounds.new()
		_save(builder.studio(), "res://backgrounds/Studio/scenery.glb")
		_save(builder.mountains(), "res://backgrounds/Mountains/scenery.glb")
		_save(builder.space(), "res://backgrounds/Space/scenery.glb")
	if only in ["", "tables"]:
		var tables := Tables.new()
		for folder: String in ["Plain", "OrnateOak"]:
			var parts: Dictionary = tables.plain() if folder == "Plain" else tables.ornate_oak()
			for part: String in parts:
				_save(parts[part], "res://tables/%s/%s.glb" % [folder, part])
	quit()


func _save(root: Node3D, res_path: String) -> void:
	var path := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"   # wood pictures; much smaller than PNG
	doc.lossy_quality = 0.88
	var state := GLTFState.new()
	var error := doc.append_from_scene(root, state)
	if error == OK:
		error = doc.write_to_filesystem(state, path)
	var triangles := 0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			triangles += mesh.surface_get_array_len(s) / 3 if mesh.surface_get_array_index_len(s) == 0 else mesh.surface_get_array_index_len(s) / 3
	if error != OK:
		push_error("Couldn't write %s: %d" % [path, error])
	else:
		print("Wrote %s (%d triangles, %d KB)" % [res_path, triangles, FileAccess.get_file_as_bytes(path).size() / 1024])
	root.free()
