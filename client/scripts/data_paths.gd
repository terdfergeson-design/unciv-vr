# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Where the game's files are, on the PC and in the standalone Quest app.
##
## On the PC: Unciv's images, sounds and rulesets come straight from the Unciv checkout next to the client
## (../unciv/android), the built-in backgrounds / tables / tilesets / panels from the project (res://), and players'
## own folders from ~/.unciv-vr.
## In the Android app those folders can't be read from the APK the way they're read on the PC (they're .gdignore'd,
## and Unciv's live outside the project), so the export packs them into android_data.pack (tools/pack_android_data.gd)
## and the first start unpacks it into the app's storage: user://data/unciv/android and user://data/builtin/<kind>.
## The players' folder (.unciv-vr) is in the app's storage too.

const PACK := "res://android_data.pack"
const STAMP := "user://data/stamp.txt"


static func is_android() -> bool:
	return OS.has_feature("android")


## Whether the game's files come from the unpacked android_data.pack: in the Android app, or on the PC with the
## environment variable UNCIV_VR_PACKED_DATA=1 (to test the packed data without a headset).
static func packed() -> bool:
	return is_android() or OS.has_feature("packed_data") or OS.get_environment("UNCIV_VR_PACKED_DATA") == "1"


## Unciv's android folder (Images.*, assets/jsons, assets/sounds, assets/ExtraImages), as an absolute path.
static func unciv_android_dir() -> String:
	if packed():
		return OS.get_user_data_dir().path_join("data/unciv/android")
	return ProjectSettings.globalize_path("res://").path_join("../unciv/android").simplify_path()


## A built-in folder of the project ("backgrounds", "tables", "tilesets", "panels").
static func builtin_dir(kind: String) -> String:
	if packed():
		return OS.get_user_data_dir().path_join("data/builtin").path_join(kind)
	return "res://" + kind


## The folder that holds .unciv-vr (saves, players' backgrounds, tilesets...): the home folder on the PC.
static func home_dir() -> String:
	if is_android():
		return OS.get_user_data_dir()
	var home := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	return home.replace("\\", "/")


## Android: unpacks android_data.pack into the app's storage, unless this version of it is there already.
## Returns "" when all is well, else what went wrong. Takes a few seconds the first time (thousands of small files).
static func unpack_android_data() -> String:
	if not packed():
		return ""
	var pack := FileAccess.open(PACK, FileAccess.READ)
	if pack == null:
		return "android_data.pack isn't in the app - export with tools/pack_android_data.gd first"
	if pack.get_buffer(4).get_string_from_ascii() != "UVRP" or pack.get_32() != 1:
		return "android_data.pack is from another version of the app"
	var index: Variant = JSON.parse_string(pack.get_buffer(pack.get_32()).get_string_from_utf8())
	if not index is Dictionary:
		return "android_data.pack's index is damaged"
	var stamp := str(index.get("stamp", ""))
	if FileAccess.file_exists(STAMP) and FileAccess.get_file_as_string(STAMP) == stamp:
		return ""
	var started := Time.get_ticks_msec()
	var root := OS.get_user_data_dir().path_join("data")
	var made := {}
	var count := 0
	for entry: Array in index.get("files", []):
		var target := root.path_join(str(entry[0]))
		var folder := target.get_base_dir()
		if not made.has(folder):
			DirAccess.make_dir_recursive_absolute(folder)
			made[folder] = true
		var bytes := pack.get_buffer(int(entry[1]))
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			return "couldn't write %s" % target
		out.store_buffer(bytes)
		out.close()
		count += 1
	var stamp_file := FileAccess.open(STAMP, FileAccess.WRITE)
	stamp_file.store_string(stamp)
	stamp_file.close()
	print("Unpacked %d files of game data into %s in %d ms" % [count, root, Time.get_ticks_msec() - started])
	return ""


# region saves shared with a PC ---------------------------------------------------------------

const STORAGE_PERMISSION := "android.permission.MANAGE_EXTERNAL_STORAGE"
## Tests on the PC point the shared folder somewhere (--shared-saves=<folder>); "" uses the Quest's Documents.
static var shared_dir_override := ""


## The bridge's save folder: ~/.unciv-vr/SaveFiles (in the app's own storage on the Quest, which uninstalling clears).
static func saves_dir() -> String:
	return home_dir().path_join(".unciv-vr/SaveFiles")


## Where the Quest app shares saves with a PC: Documents/UncivVR/SaveFiles in the headset's shared storage, which a
## PC sees over USB (Quest > Internal shared storage > Documents) and which outlives the app. "" on the PC.
static func shared_saves_dir() -> String:
	if shared_dir_override != "":
		return shared_dir_override
	if is_android():
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("UncivVR/SaveFiles")
	return ""


## Android: whether the app still needs "All files access" to read and write the shared folder (files a PC put
## there belong to no app, so reading them needs it). Asking opens the headset's settings page for it.
static func needs_storage_permission() -> bool:
	return is_android() and shared_dir_override == "" and not OS.get_granted_permissions().has(STORAGE_PERMISSION)


static func ask_storage_permission() -> void:
	if is_android():
		OS.request_permission(STORAGE_PERMISSION)


## Copies every save in [param from_dir] into [param to_dir]. The same file already there is left alone; a different
## one with the same name is replaced when [param overwrite], else the copy gets a free name ("Name (2)").
## Returns {copied, same, renamed: [names], failed: [names], error}.
static func copy_saves(from_dir: String, to_dir: String, overwrite: bool) -> Dictionary:
	var result := {"copied": 0, "same": 0, "renamed": [], "failed": [], "error": ""}
	if from_dir == "" or to_dir == "":
		result["error"] = "no folder"
		return result
	if not DirAccess.dir_exists_absolute(from_dir):
		return result   # nothing to copy yet
	if DirAccess.make_dir_recursive_absolute(to_dir) != OK and not DirAccess.dir_exists_absolute(to_dir):
		result["error"] = "Couldn't make %s" % to_dir
		return result
	for file_name: String in DirAccess.get_files_at(from_dir):
		if file_name.begins_with(".") or file_name.ends_with(".tmp"):
			continue
		var data := FileAccess.get_file_as_bytes(from_dir.path_join(file_name))
		if data.is_empty() and FileAccess.get_open_error() != OK:
			(result["failed"] as Array).append(file_name)
			continue
		var target := to_dir.path_join(file_name)
		if FileAccess.file_exists(target):
			var there := FileAccess.get_file_as_bytes(target)
			if there == data:
				result["same"] = int(result["same"]) + 1
				continue
			if not overwrite:
				var n := 2
				while FileAccess.file_exists(to_dir.path_join("%s (%d)" % [file_name, n])):
					n += 1
				target = to_dir.path_join("%s (%d)" % [file_name, n])
				(result["renamed"] as Array).append(target.get_file())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			(result["failed"] as Array).append(file_name)
			continue
		out.store_buffer(data)
		out.close()
		result["copied"] = int(result["copied"]) + 1
	return result
