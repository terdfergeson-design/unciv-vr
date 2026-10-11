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
	return is_android() or OS.get_environment("UNCIV_VR_PACKED_DATA") == "1"


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
