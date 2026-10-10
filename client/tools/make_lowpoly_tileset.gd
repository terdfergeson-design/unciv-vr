# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends SceneTree
## Writes the "LowPoly" tileset's pieces as .glb files into tilesets/LowPoly/pieces/.
## Run from the client folder:  godot --headless --path . -s tools/make_lowpoly_tileset.gd
## (the same format anyone can export from Blender for their own tileset).

const Pieces := preload("res://tools/lowpoly_wonders.gd")   # every piece, wonders included


func _init() -> void:
	var out_dir := ProjectSettings.globalize_path("res://tilesets/LowPoly/pieces")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var pieces: Dictionary = Pieces.new().build_all()
	var triangles := 0
	for piece: String in pieces:
		var mesh: ArrayMesh = pieces[piece]
		var root := Node3D.new()
		root.name = piece.replace("+", "_")
		var instance := MeshInstance3D.new()
		instance.name = "Mesh"
		instance.mesh = mesh
		root.add_child(instance)
		instance.owner = root
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var error := doc.append_from_scene(root, state)
		if error == OK:
			error = doc.write_to_filesystem(state, out_dir.path_join(piece + ".glb"))
		if error != OK:
			push_error("Couldn't write %s: %d" % [piece, error])
		for s in mesh.get_surface_count():
			triangles += mesh.surface_get_array_len(s) / 3
		root.free()
	print("Wrote %d pieces (%d triangles) to %s" % [pieces.size(), triangles, out_dir])
	quit()
