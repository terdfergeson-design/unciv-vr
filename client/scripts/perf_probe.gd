# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node
## A measuring aid for the headset: once a game is on the table, switches parts of the scene off one at a time and
## prints a "PERF_PROBE <step>" line as each starts, so the GPU time the headset logs (logcat VrApi, "App=") can be
## lined up with what was drawn. Everything is put back at the end.
##
## Started by --perf-probe, or on the Quest by an empty file named perf_probe in the app's external files folder:
##   adb shell touch /sdcard/Android/data/org.uncivvr.client/files/perf_probe
## (the file is removed when the probe starts, so it runs once).

const STEP_SECONDS := 12.0
const ANDROID_FLAG := "/sdcard/Android/data/org.uncivvr.client/files/perf_probe"

var _main: Node
var _undo: Array[Callable] = []
var _root_rid: RID


func _init(main: Node) -> void:
	_main = main


static func requested(options: Dictionary) -> bool:
	if options.has("perf-probe"):
		return true
	if OS.has_feature("android") and FileAccess.file_exists(ANDROID_FLAG):
		DirAccess.remove_absolute(ANDROID_FLAG)
		return true
	return false


func _ready() -> void:
	_root_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_root_rid, true)
	_run.call_deferred()


func _run() -> void:
	print("PERF_PROBE waiting for a game")
	while _main._in_lobby or _main.state.is_empty() or _main.hex_map.tiles.is_empty():
		await get_tree().create_timer(1.0).timeout
	await get_tree().create_timer(5.0).timeout   # let the table settle
	var steps: Array = [
		["baseline", func() -> void: pass],
		["boards_hidden", _hide_boards],
		["boards_frozen", _freeze_boards],
		["msaa_off", _msaa_off],
		["shadows_off", _shadows_off],
		["glow_fog_off", _environment_off],
		["scenery_hidden", _scenery_hidden],
		["map_hidden", _map_hidden],
		["units_hidden", _units_hidden],
		["table_hidden", _table_hidden],
	]
	for step: Array in steps:
		(step[1] as Callable).call()
		print("PERF_PROBE %s" % step[0])
		await get_tree().create_timer(2.0).timeout   # let the headset's own measurement catch up
		var gpu := 0.0
		var cpu := 0.0
		var frames := 0
		var until := Time.get_ticks_msec() + int((STEP_SECONDS - 2.0) * 1000.0)
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(_root_rid)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(_root_rid)
			frames += 1
		print("PERF_PROBE %s_end fps=%d gpu_ms=%.2f cpu_ms=%.2f frames=%d" % [step[0],
			Engine.get_frames_per_second(), gpu / maxf(frames, 1), cpu / maxf(frames, 1), frames])
		# each step undoes the one before, except the scene-wide ones that build on each other
		if step[0] in ["boards_hidden", "boards_frozen"]:
			_restore()
	_restore()
	print("PERF_PROBE done")
	queue_free()


func _restore() -> void:
	for i in range(_undo.size() - 1, -1, -1):
		_undo[i].call()
	_undo.clear()


func _boards() -> Array[SubViewport]:
	var result: Array[SubViewport] = []
	for node: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		result.append(node as SubViewport)
	return result


func _hide_boards() -> void:
	for viewport in _boards():
		var holder := viewport.get_parent() as Node3D
		if holder != null and holder.visible:
			holder.visible = false
			_undo.append(func() -> void: if is_instance_valid(holder): holder.visible = true)
	print("PERF_PROBE boards=%d" % _boards().size())


func _freeze_boards() -> void:
	for viewport in _boards():
		var mode := viewport.render_target_update_mode
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_undo.append(func() -> void: if is_instance_valid(viewport): viewport.render_target_update_mode = mode)


func _msaa_off() -> void:
	var vp := get_viewport()
	var old := vp.msaa_3d
	vp.msaa_3d = Viewport.MSAA_DISABLED
	_undo.append(func() -> void: vp.msaa_3d = old)


func _shadows_off() -> void:
	var sun: DirectionalLight3D = _main.backgrounds._sun
	if sun == null:
		return
	var old := sun.shadow_enabled
	sun.shadow_enabled = false
	_undo.append(func() -> void: sun.shadow_enabled = old)


func _environment_off() -> void:
	var env: Environment = _main.backgrounds._environment
	if env == null:
		return
	var glow := env.glow_enabled
	var fog := env.fog_enabled
	var tonemap := env.tonemap_mode
	env.glow_enabled = false
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_undo.append(func() -> void:
		env.glow_enabled = glow
		env.fog_enabled = fog
		env.tonemap_mode = tonemap)


func _hide(node: Node3D) -> void:
	if node == null or not node.visible:
		return
	node.visible = false
	_undo.append(func() -> void: if is_instance_valid(node): node.visible = true)


func _scenery_hidden() -> void:
	_hide(_main.backgrounds._scenery)


func _map_hidden() -> void:
	_hide(_main.hex_map._terrain)
	_hide(_main.hex_map._trees)
	_hide(_main.hex_map._pieces_root)
	_hide(_main.hex_map._piece_scenes)


func _units_hidden() -> void:
	_hide(_main.hex_map._units_root)


func _table_hidden() -> void:
	_hide(_main.table_model)
