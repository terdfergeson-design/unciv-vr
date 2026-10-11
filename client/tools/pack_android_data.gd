# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends SceneTree
## Packs the files the Quest app reads at run time into android_data.pack (gitignored), which the Android export
## includes and the app unpacks on its first start (scripts/data_paths.gd):
##   unciv/android/Images.*, assets/jsons (with Unciv's translations), assets/sounds, assets/ExtraImages  - from ../unciv
##   builtin/backgrounds, tables, tilesets, panels                                                   - from this project
##   credits/: our CREDITS.md and LICENSE, and Unciv's docs/Credits.md - the app carries Unciv's icons and sounds,
##   and their licences ask for the authors' credits to travel with them
## Run before exporting:  godot --headless --path client -s tools/pack_android_data.gd
##
## The format is as plain as can be, so the app can unpack it in one straight read (a zip file has to be searched
## for each of its thousands of files, which took a minute and more on a Quest 2):
##   "UVRP", u32 format version (1), u32 length of the index, the index as JSON
##   {"stamp": md5 of the contents, "files": [[path, size], ...]}, then the files' bytes one after another in that order.

const OUT := "res://android_data.pack"
const MAGIC := "UVRP"
const VERSION := 1

var _files: Array = []                 # [[path, size], ...]
var _blobs: Array[PackedByteArray] = []


func _init() -> void:
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var android := project.path_join("../unciv/android").simplify_path()
	var count := 0
	var dir := DirAccess.open(android)
	if dir == null:
		push_error("No Unciv checkout at " + android)
		quit(1)
		return
	for sub in dir.get_directories():
		if sub.begins_with("Images."):
			count += _add_tree(android.path_join(sub), "unciv/android/" + sub, [])
	for sub in ["jsons", "sounds", "ExtraImages"]:
		count += _add_tree(android.path_join("assets").path_join(sub), "unciv/android/assets/" + sub, [])
	for kind in ["backgrounds", "tables", "tilesets", "panels"]:
		count += _add_tree(project.path_join(kind), "builtin/" + kind, [])
	for pair in [[project.path_join("../CREDITS.md"), "credits/CREDITS.md"], [project.path_join("../LICENSE"), "credits/LICENSE"],
			[android.path_join("../docs/Credits.md"), "credits/Unciv-Credits.md"]]:
		count += _add_file(str(pair[0]).simplify_path(), pair[1])
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	hashing.update(JSON.stringify(_files).to_utf8_buffer())
	for blob in _blobs:
		hashing.update(blob)
	var index := JSON.stringify({"stamp": hashing.finish().hex_encode(), "files": _files}).to_utf8_buffer()
	var out := FileAccess.open(OUT, FileAccess.WRITE)
	if out == null:
		push_error("Can't write " + OUT)
		quit(1)
		return
	out.store_buffer(MAGIC.to_ascii_buffer())
	out.store_32(VERSION)
	out.store_32(index.size())
	out.store_buffer(index)
	for blob in _blobs:
		out.store_buffer(blob)
	var size := out.get_length()
	out.close()
	print("Packed %d files into %s (%.1f MB)" % [count, OUT, size / 1048576.0])
	quit(0)


func _add_file(from: String, to: String) -> int:
	if not FileAccess.file_exists(from):
		push_warning("Missing " + from)
		return 0
	var bytes := FileAccess.get_file_as_bytes(from)
	_files.append([to, bytes.size()])
	_blobs.append(bytes)
	return 1


func _add_tree(from: String, to: String, skip: Array) -> int:
	var dir := DirAccess.open(from)
	if dir == null:
		push_warning("Missing " + from)
		return 0
	var count := 0
	for file in dir.get_files():
		if file == ".gdignore" or file.ends_with(".import") or file.ends_with(".uid"):
			continue
		var bytes := FileAccess.get_file_as_bytes(from.path_join(file))
		_files.append([to.path_join(file), bytes.size()])
		_blobs.append(bytes)
		count += 1
	for sub in dir.get_directories():
		if sub in skip or sub.begins_with("."):
			continue
		count += _add_tree(from.path_join(sub), to.path_join(sub), skip)
	return count
