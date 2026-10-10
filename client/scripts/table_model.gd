# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## The table the map lies on, read from a table folder (tables/<Name>/table.json plus its models; see
## tables/README.md). Built-in: Plain and OrnateOak (made by tools/make_surroundings.gd); players' and
## mods' own go in ~/.unciv-vr/Tables.
##
## A table has up to three parts:
##   top     moves, turns and scales with the map (it's put under the table node); play surface at y = 0
##   base    stands on the floor under the table, turning and scaling with it (squashed if it doesn't fit)
##   column  fills the gap between them: modelled 1 m tall and stretched to the height the table is at
## Keep this node at the scene root; call follow() every frame.

const ModFolders := preload("res://scripts/mod_folders.gd")
const KIND := "Tables"
const JSON_NAME := "table.json"
const DEFAULT := "OrnateOak"

var current := ""
var _top: Node3D
var _column: Node3D
var _base: Node3D
var _column_top := -0.04   # table-space y where the column meets the top (metres)
var _base_height := 0.0    # how tall the base is (metres)


## Every table that can be picked: folder name -> title.
static func available() -> Dictionary:
	return ModFolders.available(KIND, JSON_NAME)


## Shows the table in folder [param folder_name] (unknown ones show the default), its top under [param table].
func apply(folder_name: String, table: Node3D) -> void:
	var path := ModFolders.find(KIND, folder_name, JSON_NAME)
	if path == "":
		path = ModFolders.find(KIND, DEFAULT, JSON_NAME)
	for node: Node3D in [_top, _column, _base]:
		if node != null:
			node.get_parent().remove_child(node)   # out of the way now, so the new parts get their names
			node.queue_free()
	_top = null
	_column = null
	_base = null
	if path == "":
		push_warning("No tables found")
		return
	current = path.get_file()
	var json: Dictionary = ModFolders.read_json(path.path_join(JSON_NAME))
	_column_top = float(json.get("columnTop", -0.04))
	_base_height = float(json.get("baseHeight", 0.0))
	_top = ModFolders.load_model(ModFolders.model_path(path, str(json.get("top", "top"))))
	if _top != null:
		_top.name = "TableTop"
		table.add_child(_top)
	_column = ModFolders.load_model(ModFolders.model_path(path, str(json.get("column", "column"))))
	if _column != null:
		_column.name = "TableColumn"
		add_child(_column)
	_base = ModFolders.load_model(ModFolders.model_path(path, str(json.get("base", "base"))))
	if _base != null:
		_base.name = "TableBase"
		add_child(_base)
	if json.has("specular"):   # glTF can't say how shiny a surface is apart from its roughness
		for part: Node3D in [_top, _column, _base]:
			if part != null:
				_set_specular(part, float(json["specular"]))


static func _set_specular(node: Node, amount: float) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance := node as MeshInstance3D
		for s in instance.mesh.get_surface_count():
			var material := instance.get_active_material(s)
			if material is BaseMaterial3D:
				var changed := material.duplicate() as BaseMaterial3D
				changed.metallic_specular = amount
				instance.set_surface_override_material(s, changed)
	for child in node.get_children():
		_set_specular(child, amount)


## Puts the base on the floor under [param table] and stretches the column up to it.
## [param has_floor] false (floating in space): only the top shows.
func follow(table: Node3D, floor_y: float, has_floor: bool) -> void:
	if _column == null and _base == null:
		return
	var s := table.scale.x
	var yaw := Basis(Vector3.UP, table.global_rotation.y)
	var gap := table.global_position.y + _column_top * s - floor_y   # from the floor to the top's underside
	var shown := has_floor and gap > 0.02
	var base_scale := minf(s, gap / _base_height) if _base_height > 0.0 else s
	var column_height := gap - _base_height * base_scale
	var foot := Vector3(table.global_position.x, floor_y, table.global_position.z)
	if _base != null:
		_base.visible = shown
		if shown:
			_base.global_transform = Transform3D(yaw.scaled(Vector3(s, base_scale, s)), foot)
	if _column != null:
		_column.visible = shown and column_height > 0.003
		if _column.visible:
			_column.global_transform = Transform3D(yaw.scaled(Vector3(s, column_height, s)),
				foot + Vector3(0, _base_height * base_scale, 0))
