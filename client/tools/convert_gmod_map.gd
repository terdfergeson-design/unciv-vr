# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends SceneTree
## Command-line tool to convert Garry's Mod / Source Engine maps (.bsp, .gma or .zip) into Unciv VR backgrounds:
## runs tools/convert_gmod_map.py with Python (needs numpy and Pillow). See backgrounds/GMOD_MAP_CONVERSION.md.
##
## Usage from the client folder:
##   godot --headless --path . -s tools/convert_gmod_map.gd -- <map.bsp | addon.gma | maps.zip> [--name "My Background"]

func _init() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.is_empty():
		print("Usage: godot --headless --path . -s tools/convert_gmod_map.gd -- <map.bsp | addon.gma | maps.zip> [--name Name]")
		quit(1)
		return

	var py_script := ProjectSettings.globalize_path("res://tools/convert_gmod_map.py")
	var args := PackedStringArray([py_script])
	args.append_array(user_args)

	print("Running GMod BSP converter tool...")
	var output: Array = []
	var exit_code := OS.execute("py", args, output, true)   # the Python launcher on Windows
	if exit_code != 0:
		output.clear()
		exit_code = OS.execute("python3", args, output, true)   # elsewhere, or no launcher

	for line in output:
		print(line)

	if exit_code == 0:
		print("Done!")
	else:
		push_error("Converter failed with code %d" % exit_code)

	quit(exit_code)
