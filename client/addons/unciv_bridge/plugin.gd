# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

@tool
extends EditorPlugin
## Adds the UncivBridge Android plugin to Android exports: the AAR from the Unciv fork's bridge-android module
## (gradlew :bridge-android:copyToClient puts it in bin/), and the libraries it needs (bin/android-deps.txt),
## which Godot's Gradle build fetches from Maven Central. Desktop exports are untouched.

var _export_plugin: UncivBridgeExport


func _enter_tree() -> void:
	_export_plugin = UncivBridgeExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class UncivBridgeExport extends EditorExportPlugin:
	const AAR := "unciv_bridge/bin/unciv-bridge-android.aar"
	const DEPS := "res://addons/unciv_bridge/bin/android-deps.txt"

	func _get_name() -> String:
		return "UncivBridge"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if not FileAccess.file_exists("res://addons/" + AAR):
			push_error("UncivBridge: %s is missing - build it with gradlew :bridge-android:copyToClient in the Unciv fork" % AAR)
			return PackedStringArray()
		return PackedStringArray([AAR])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		var out := PackedStringArray()
		if not FileAccess.file_exists(DEPS):
			push_error("UncivBridge: %s is missing" % DEPS)
			return out
		for line in FileAccess.get_file_as_string(DEPS).split("\n", false):
			if line.strip_edges() != "":
				out.append(line.strip_edges())
		return out
