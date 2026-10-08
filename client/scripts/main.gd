extends Node3D
## Unciv VR - phase 0 client.
## Connects to the bridge, starts (or resumes) a game, and draws it as a tabletop map.
## Runs in VR when an OpenXR runtime is active, otherwise in a desktop window.
##
## Command-line options (after "--"):  --new-game  --civ=Rome  --map-size=Small  --ai=3
##   --load=C:/path/to/save  --port=8765  --smoke-test (scripted run that exits; for testing)
##
## Desktop: left-click select/move, right-drag orbit, middle-drag or WASD pan, wheel zoom,
##   Space end turn, F found city, N next unit, Esc deselect, R refresh.
## VR (right controller): point + trigger select/move, A end turn, B found city;
##   left controller: X next unit, stick rotates (x) and scales (y) the table.

# Loaded by path rather than class_name, so the project runs even before the editor has scanned it
const BridgeClient := preload("res://scripts/bridge_client.gd")
const HexMap := preload("res://scripts/hex_map.gd")

const TABLE_HALF_SIZE := 0.7   # metres: the map is scaled so its half-width fits this
const VR_TABLE_POSITION := Vector3(0, 0.8, -0.85)

var bridge: BridgeClient
var hex_map: HexMap
var table: Node3D

var state: Dictionary = {}
var selected_unit: Dictionary = {}   # getUnit result, or empty
var busy := false
var options := {}

var _xr_mode := false
var _hud_label: Label
var _hud_label_3d: Label3D
var _status_text := "Connecting..."
var _hover_text := ""

# desktop camera
var _camera: Camera3D
var _yaw := 0.0
var _pitch := deg_to_rad(55.0)
var _distance := 1.7
var _focus := Vector3.ZERO

# VR rig
var _right_hand: XRController3D
var _left_hand: XRController3D
var _pointer_dot: MeshInstance3D


func _ready() -> void:
	options = _parse_args()
	_setup_environment()

	table = Node3D.new()
	table.name = "Table"
	add_child(table)
	hex_map = HexMap.new()
	hex_map.name = "HexMap"
	table.add_child(hex_map)

	_xr_mode = _try_start_xr()
	if _xr_mode:
		_setup_xr_rig()
		table.position = VR_TABLE_POSITION
	else:
		_setup_desktop_camera()
	_setup_hud()

	bridge = BridgeClient.new()
	bridge.port = int(options.get("port", 8765))
	add_child(bridge)
	bridge.connected.connect(_on_bridge_connected)
	bridge.disconnected.connect(func() -> void: _set_status("Lost connection to the bridge - retrying..."))
	bridge.connect_to_bridge()
	_set_status("Waiting for the bridge on 127.0.0.1:%d\nStart it with:  gradlew :bridge:run" % bridge.port)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1] if parts.size() > 1 else ""
	return result


# region game flow ------------------------------------------------------------------------

func _on_bridge_connected() -> void:
	var ping := await bridge.request("ping")
	if not ping.ok:
		_set_status("Bridge error: %s" % ping.error)
		return
	_set_status("Connected to Unciv %s" % ping.result.uncivVersion)

	if options.has("load"):
		var loaded := await bridge.request("loadGame", {"path": options["load"]})
		if not loaded.ok:
			_set_status("Couldn't load the save: %s" % loaded.error)
			return
	elif options.has("new-game") or options.has("smoke-test") or not ping.result.gameRunning:
		_set_status("Starting a new game...")
		var params := {
			"mapSize": options.get("map-size", "Tiny"),
			"aiPlayers": int(options.get("ai", 3)),
			"cityStates": 4,
		}
		if options.has("civ"):
			params["civ"] = options["civ"]
		if options.has("smoke-test"):
			params["seed"] = 42
		var started := await bridge.request("newGame", params)
		if not started.ok:
			_set_status("Couldn't start a game: %s" % started.error)
			return

	var rules := await bridge.request("getRuleset")
	if rules.ok:
		hex_map.set_ruleset(rules.result)
	await refresh()
	_fit_table()
	_set_status("Your move.")
	_select_next_unit()

	if options.has("smoke-test"):
		await _run_smoke_test()
	if options.has("screenshot"):
		for i in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(options["screenshot"])
		print("Saved screenshot to %s" % options["screenshot"])
		get_tree().quit()


func refresh() -> void:
	var reply := await bridge.request("getState")
	if not reply.ok:
		_set_status("getState failed: %s" % reply.error)
		return
	state = reply.result
	hex_map.build(state)
	if not selected_unit.is_empty():
		await _select_unit(int(selected_unit["id"]), false)
	_update_hud()


func _fit_table() -> void:
	var s := TABLE_HALF_SIZE / hex_map.map_extent
	hex_map.scale = Vector3(s, s, s)
	_add_table_top()


func click_tile(key: Vector2i) -> void:
	if busy or state.is_empty():
		return
	var own_units := _own_units_at(key)
	var selected_key := _selected_key()

	# Clicking one of your units selects it (clicking the selected tile again cycles through its stack)
	if not own_units.is_empty() and (selected_unit.is_empty() or key != selected_key or own_units.size() > 1):
		var pick: Dictionary = own_units[0]
		if key == selected_key and own_units.size() > 1:
			var index := own_units.find_custom(func(u: Dictionary) -> bool: return int(u["id"]) == int(selected_unit["id"]))
			pick = own_units[(index + 1) % own_units.size()]
		await _select_unit(int(pick["id"]))
		return

	if not selected_unit.is_empty() and key != selected_key:
		await move_selected_to(key)
		return

	_deselect()


func move_selected_to(key: Vector2i) -> void:
	busy = true
	var reply := await bridge.request("moveUnit", {"unitId": int(selected_unit["id"]), "x": key.x, "y": key.y})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	await refresh()
	if not selected_unit.is_empty() and float(selected_unit.get("movement", 0)) <= 0.0:
		_select_next_unit()


func found_city() -> void:
	await unit_action("FoundCity")


func unit_action(action: String) -> void:
	if busy or selected_unit.is_empty():
		return
	busy = true
	var reply := await bridge.request("unitAction", {"unitId": int(selected_unit["id"]), "action": action})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	_set_status("%s: done" % action)
	if not reply.result.get("unitStillExists", true):
		_deselect()
	await refresh()


func end_turn() -> void:
	if busy:
		return
	busy = true
	_deselect()
	_set_status("Ending turn - the AI players are moving...")
	var reply := await bridge.request("endTurn")
	busy = false
	if not reply.ok:
		_set_status("endTurn failed: %s" % reply.error)
		return
	var result: Dictionary = reply.result
	var lines: Array[String] = ["Turn %d" % int(result["turn"])]
	if result.get("gameOver", false):
		lines.append("GAME OVER - %s wins (%s victory)" % [result.get("winner", "?"), result.get("victoryType", "?")])
	var notes: Array = result.get("notifications", [])
	for i in mini(notes.size(), 5):
		lines.append("- " + str(notes[i]["text"]))
	_set_status("\n".join(lines))
	await refresh()
	_select_next_unit()


func _select_unit(unit_id: int, focus := true) -> void:
	var reply := await bridge.request("getUnit", {"unitId": unit_id})
	if not reply.ok:
		_deselect()
		return
	selected_unit = reply.result
	var reachable: Array[Vector2i] = []
	for t: Dictionary in selected_unit.get("reachable", []):
		reachable.append(Vector2i(int(t["x"]), int(t["y"])))
	hex_map.set_selection(_selected_key(), reachable)
	if focus and not _xr_mode:
		_focus = hex_map.to_global(hex_map.tile_local_center(_selected_key())) - table.global_position
		_update_camera()
	_update_hud()


func _select_next_unit() -> void:
	var units: Array = state.get("units", [])
	var candidates := units.filter(func(u: Dictionary) -> bool:
		return u.get("idle", false) and float(u.get("movement", 0)) > 0.0)
	if candidates.is_empty():
		_deselect()
		return
	var start := 0
	if not selected_unit.is_empty():
		var current := candidates.find_custom(func(u: Dictionary) -> bool: return int(u["id"]) == int(selected_unit["id"]))
		start = (current + 1) % candidates.size()
	_select_unit(int(candidates[start]["id"]))


func _deselect() -> void:
	selected_unit = {}
	hex_map.clear_selection()
	_update_hud()


func _selected_key() -> Vector2i:
	if selected_unit.is_empty():
		return Vector2i(999999, 999999)
	return Vector2i(int(selected_unit["x"]), int(selected_unit["y"]))


func _own_units_at(key: Vector2i) -> Array:
	return state.get("units", []).filter(func(u: Dictionary) -> bool:
		return int(u["x"]) == key.x and int(u["y"]) == key.y)


func _run_smoke_test() -> void:
	print("SMOKE: state turn=%s tiles=%d units=%d" % [state.get("turn"), state.get("tiles", []).size(), state.get("units", []).size()])
	var settler: Variant = null
	for u: Dictionary in state.get("units", []):
		if u["name"] == "Settler":
			settler = u
	if settler != null:
		await _select_unit(int(settler["id"]))
		print("SMOKE: settler actions ", selected_unit.get("actions", []).map(func(a: Dictionary) -> String: return a["type"]))
		await found_city()
		print("SMOKE: cities after founding ", state.get("cities", []).map(func(c: Dictionary) -> String: return c["name"]))
	for u: Dictionary in state.get("units", []):
		if not u.get("civilian", false):
			await _select_unit(int(u["id"]))
			var reach: Array = selected_unit.get("reachable", [])
			if reach.size() > 1:
				var target: Dictionary = reach[-1]
				await click_tile(Vector2i(int(target["x"]), int(target["y"])))
				print("SMOKE: moved warrior, status: ", _status_text)
			break
	for i in 3:
		await end_turn()
		print("SMOKE: ", _status_text.split("\n")[0])
	print("SMOKE: hover text for capital: ", hex_map.describe_tile(Vector2i(int(state["cities"][0]["x"]), int(state["cities"][0]["y"]))) if not state.get("cities", []).is_empty() else "")
	print("SMOKE: done")
	if not options.has("screenshot"):
		get_tree().quit()


# region HUD ------------------------------------------------------------------------------

func _set_status(text: String) -> void:
	_status_text = text
	print(text)
	_update_hud()


func _update_hud() -> void:
	var lines: Array[String] = []
	if not state.is_empty():
		var p: Dictionary = state.get("player", {})
		var year := int(state.get("year", 0))
		var year_text := "%d BC" % -year if year < 0 else "%d AD" % year
		lines.append("%s  -  Turn %d (%s)   Gold %d (%+d)   Science %+d   Happiness %d" % [
			state.get("playerCiv", "?"), int(state.get("turn", 0)), year_text,
			int(p.get("gold", 0)), int(p.get("goldPerTurn", 0)), int(p.get("science", 0)), int(p.get("happiness", 0))])
		if p.get("currentTech") != null:
			lines.append("Researching: %s" % p["currentTech"])
	if not selected_unit.is_empty():
		var actions: Array = selected_unit.get("actions", []).filter(func(a: Dictionary) -> bool: return a.get("enabled", false))
		lines.append("Selected: %s  (%s/%d moves, %d HP)" % [selected_unit["name"],
			str(snappedf(float(selected_unit["movement"]), 0.1)), int(selected_unit["maxMovement"]), int(selected_unit["health"])])
		lines.append("  can: " + ", ".join(actions.map(func(a: Dictionary) -> String: return a["title"])))
	if _hover_text != "":
		lines.append(_hover_text)
	lines.append("")
	lines.append(_status_text)
	var text := "\n".join(lines)
	if _hud_label:
		_hud_label.text = text
	if _hud_label_3d:
		_hud_label_3d.text = text


func _setup_hud() -> void:
	if _xr_mode:
		_hud_label_3d = Label3D.new()
		_hud_label_3d.pixel_size = 0.0008
		_hud_label_3d.font_size = 32
		_hud_label_3d.outline_size = 6
		_hud_label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_hud_label_3d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_hud_label_3d.width = 900
		_hud_label_3d.autowrap_mode = TextServer.AUTOWRAP_WORD
		# A floating panel above the far edge of the table, tilted towards the player
		_hud_label_3d.position = VR_TABLE_POSITION + Vector3(-0.35, 0.55, -0.75)
		_hud_label_3d.rotation_degrees = Vector3(-10, 0, 0)
		add_child(_hud_label_3d)
	else:
		var layer := CanvasLayer.new()
		add_child(layer)
		var panel := PanelContainer.new()
		panel.position = Vector2(12, 12)
		layer.add_child(panel)
		_hud_label = Label.new()
		_hud_label.add_theme_font_size_override("font_size", 16)
		panel.add_child(_hud_label)
	_update_hud()


# region scene setup ----------------------------------------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.11, 0.12, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.95)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)


func _add_table_top() -> void:
	var top := MeshInstance3D.new()
	top.name = "TableTop"
	var mesh := CylinderMesh.new()
	mesh.top_radius = TABLE_HALF_SIZE * 1.2
	mesh.bottom_radius = TABLE_HALF_SIZE * 1.2
	mesh.height = 0.04
	mesh.radial_segments = 48
	top.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.22, 0.14)
	material.roughness = 0.8
	top.material_override = material
	top.position = Vector3(0, -0.021, 0)
	table.add_child(top)


func _try_start_xr() -> bool:
	if options.has("smoke-test") or DisplayServer.get_name() == "headless":
		return false
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		print("OpenXR is running - VR mode")
		return true
	print("No OpenXR session - desktop mode")
	return false


func _setup_xr_rig() -> void:
	var origin := XROrigin3D.new()
	add_child(origin)
	var cam := XRCamera3D.new()
	origin.add_child(cam)

	_left_hand = _make_controller("left_hand")
	_right_hand = _make_controller("right_hand")
	origin.add_child(_left_hand)
	origin.add_child(_right_hand)
	_left_hand.button_pressed.connect(func(button: String) -> void: _on_xr_button(false, button))
	_right_hand.button_pressed.connect(func(button: String) -> void: _on_xr_button(true, button))

	# laser on the right hand
	var laser := MeshInstance3D.new()
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(0.003, 0.003, 2.0)
	laser.mesh = laser_mesh
	laser.position = Vector3(0, 0, -1.0)
	var laser_material := StandardMaterial3D.new()
	laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_material.albedo_color = Color(0.4, 0.9, 1.0, 0.6)
	laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser.material_override = laser_material
	_right_hand.add_child(laser)

	_pointer_dot = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.008
	dot.height = 0.016
	_pointer_dot.mesh = dot
	_pointer_dot.material_override = laser_material
	_pointer_dot.visible = false
	add_child(_pointer_dot)


func _make_controller(tracker: String) -> XRController3D:
	var controller := XRController3D.new()
	controller.tracker = tracker
	controller.pose = "aim"
	var model := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, 0.1)
	model.mesh = box
	controller.add_child(model)
	return controller


func _setup_desktop_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 50
	_camera.near = 0.01
	add_child(_camera)
	_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	_pitch = clampf(_pitch, deg_to_rad(15), deg_to_rad(89))
	_distance = clampf(_distance, 0.2, 5.0)
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	var target := table.global_position + _focus
	_camera.position = target + dir * _distance
	_camera.look_at(target)


# region input ----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _xr_mode:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_yaw -= motion.relative.x * 0.005
			_pitch += motion.relative.y * 0.005
			_update_camera()
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(Vector2(-motion.relative.x, -motion.relative.y) * 0.0015 * _distance)
		_update_hover(_pick_mouse(motion.position))
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				var key: Variant = _pick_mouse(button.position)
				if key != null:
					click_tile(key)
			MOUSE_BUTTON_WHEEL_UP:
				_distance *= 0.9
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance *= 1.1
				_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE, KEY_ENTER:
				end_turn()
			KEY_F:
				found_city()
			KEY_N, KEY_TAB:
				_select_next_unit()
			KEY_ESCAPE:
				_deselect()
			KEY_R:
				refresh()


func _process(delta: float) -> void:
	if _xr_mode:
		_process_xr(delta)
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): pan.y -= 1
	if Input.is_key_pressed(KEY_S): pan.y += 1
	if Input.is_key_pressed(KEY_A): pan.x -= 1
	if Input.is_key_pressed(KEY_D): pan.x += 1
	if pan != Vector2.ZERO:
		_pan(pan * delta * 0.8 * _distance)


func _pan(amount: Vector2) -> void:
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
	_focus += right * amount.x - forward * amount.y
	_update_camera()


func _pick_mouse(screen_position: Vector2) -> Variant:
	if _camera == null or hex_map.tiles.is_empty():
		return null
	return hex_map.pick(_camera.project_ray_origin(screen_position), _camera.project_ray_normal(screen_position))


func _update_hover(key: Variant) -> void:
	if key == null:
		hex_map.set_hover(Vector2i(999999, 999999))
		if _hover_text != "":
			_hover_text = ""
			_update_hud()
		return
	hex_map.set_hover(key)
	var text := hex_map.describe_tile(key)
	if text != _hover_text:
		_hover_text = text
		_update_hud()


func _process_xr(delta: float) -> void:
	if _right_hand == null or hex_map.tiles.is_empty():
		return
	var origin := _right_hand.global_position
	var direction := -_right_hand.global_transform.basis.z
	var key: Variant = hex_map.pick(origin, direction)
	_update_hover(key)
	_pointer_dot.visible = key != null
	if key != null:
		_pointer_dot.global_position = hex_map.to_global(hex_map.tile_local_center(key))

	# Left stick: x rotates the table, y scales it
	var stick := _left_hand.get_vector2("primary")
	if absf(stick.x) > 0.2:
		table.rotate_y(-stick.x * delta * 1.2)
	if absf(stick.y) > 0.2:
		var s := clampf(table.scale.x * (1.0 + stick.y * delta), 0.3, 6.0)
		table.scale = Vector3(s, s, s)


func _on_xr_button(is_right: bool, button: String) -> void:
	if is_right:
		match button:
			"trigger_click":
				var key: Variant = hex_map.pick(_right_hand.global_position, -_right_hand.global_transform.basis.z)
				if key != null:
					click_tile(key)
			"ax_button":
				end_turn()
			"by_button":
				found_city()
	else:
		match button:
			"ax_button":
				_select_next_unit()
			"by_button":
				refresh()
