extends Node3D
## Unciv VR - phase 0 client.
## Connects to the bridge, starts (or resumes) a game, and draws it as a tabletop map.
## Runs in VR when an OpenXR runtime is active, otherwise in a desktop window.
##
## If no bridge is running, it starts one itself from ../unciv (log: logs/bridge.log)
## and shuts it down again on exit.
##
## Command-line options (after "--"):  --new-game  --civ=Rome  --map-size=Small  --ai=3
##   --load=C:/path/to/save  --port=8765  --no-launch (never start a bridge)
##   --smoke-test (scripted run that exits; for testing)  --screenshot=file.png
##
## Desktop: left-click select / move / attack (red rings) / open a city; the card on the right,
##   right-drag orbit, middle-drag or WASD pan, wheel zoom,
##   Space end turn, F found city, Tab / Shift+Tab next / previous unit, N next idle unit,
##   T research, Esc deselect, R refresh.
## VR: right controller points; its trigger selects / moves / attacks / opens cities and presses
##   buttons on the card strapped to your left wrist (right stick scrolls the card). A end turn,
##   B found city. Either stick raises / lowers the table; with that hand's grip held it rotates (x) /
##   scales (y) it instead. Left controller: X next unit, Y previous unit, stick click recenters the table.

# Loaded by path rather than class_name, so the project runs even before the editor has scanned it
const BridgeClient := preload("res://scripts/bridge_client.gd")
const HexMap := preload("res://scripts/hex_map.gd")
const ActionMenu := preload("res://scripts/action_menu.gd")
const WorldPanel := preload("res://scripts/world_panel.gd")
const Backgrounds := preload("res://scripts/backgrounds.gd")
const BridgeLauncher := preload("res://scripts/bridge_launcher.gd")

const TABLE_HALF_SIZE := 0.7   # metres: the map is scaled so its half-width fits this
const VR_TABLE_POSITION := Vector3(0, 0.8, -0.85)
const WRIST_PANEL_PIXELS := Vector2i(404, 720)
const WRIST_PANEL_METRES := Vector2(0.17, 0.303)   # same aspect ratio as the pixels
const POPUP_PANEL_PIXELS := Vector2i(404, 600)
const POPUP_PANEL_METRES := Vector2(0.30, 0.4455)
const TABLE_HEIGHT_RANGE := Vector2(0.2, 1.6)      # metres above the floor
const DESKTOP_FLOOR_Y := -0.8                      # on desktop the table sits at the origin
const SETTINGS_PATH := "user://settings.cfg"
## Buttons on the table rim: [id, label, colour, angle]. Angle 0 is the edge nearest the player, negative
## is to the left. They sit on the left and right sides, just outside the map, where they're easy to see
## and point at - so everything can be done with the right controller alone (or the mouse).
const TABLE_BUTTONS := [
	["next_idle", "Idle unit", Color(0.3, 0.36, 0.48), -80.0],
	["end_turn", "End turn", Color(0.75, 0.45, 0.12), 65.0],
	["research", "Research", Color(0.25, 0.4, 0.65), 87.0],
	["recenter", "Recenter", Color(0.35, 0.35, 0.38), 107.0],
	["settings", "Settings", Color(0.35, 0.35, 0.38), 125.0],
]
const TABLE_BUTTON_RADIUS := 0.785     # distance from the table centre (map half-size is 0.7, table top 0.84)
const AIM_MOVE_COLOR := Color(0.35, 1.0, 0.55)
const AIM_ATTACK_COLOR := Color(1.0, 0.35, 0.25)
const AIM_BLOCKED_COLOR := Color(0.6, 0.6, 0.6)
const LAUNCH_GRACE_SECONDS := 1.5

var bridge: BridgeClient
var hex_map: HexMap
var table: Node3D

var state: Dictionary = {}
var selected_unit: Dictionary = {}   # getUnit result, or empty
var selected_city: Dictionary = {}   # getCity result while the city card is open, or empty
var busy := false
var options := {}
var action_menu: ActionMenu
var launcher := BridgeLauncher.new()
var backgrounds: Backgrounds
## Player settings, saved in user://settings.cfg. auto_move: "end" (units move when you end your turn) or "start".
var settings := {"background": "studio", "auto_move": "end"}
var _table_buttons: Array[Dictionary] = []   # {id, node, material, color}
var _hovered_button := ""
var _pedestal: MeshInstance3D
var _launched_bridge := false
var _initialized := false

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
var _wrist_panel: WorldPanel
var _popup_panel: WorldPanel       # VR: a card floating above the map - a city's card or a promotion choice
var popup_menu: ActionMenu         # what's on the popup panel
var _popup_kind := ""              # "", "city" or "promotion"
var _popup_key := Vector2i.ZERO    # the tile it floats above
var _popup_unit_id := -1           # for promotions: which unit
var _promotion_prompted: Dictionary = {}   # unit id -> turn we last popped up its promotion choice
var _pointed_panel: WorldPanel     # the panel the laser is on right now, if any
var _pointed_pixel := Vector2.ZERO
var _right_grip_down := false
var _table_height_set := false   # after the first recenter, recentering keeps the height you chose
var _xr_camera: XRCamera3D


func _ready() -> void:
	options = _parse_args()
	_load_settings()
	if options.has("background"):   # dev aid for screenshots; not saved
		settings["background"] = options["background"]
	backgrounds = Backgrounds.new()
	backgrounds.name = "Backgrounds"
	add_child(backgrounds)

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
	_setup_action_menu()
	# The floor is at y=0 in VR (the play space) and below the table on desktop
	backgrounds.position.y = 0.0 if _xr_mode else DESKTOP_FLOOR_Y
	backgrounds.apply(settings["background"])
	_setup_table_buttons()
	_setup_pedestal()

	bridge = BridgeClient.new()
	bridge.port = int(options.get("port", 8765))
	add_child(bridge)
	bridge.connected.connect(_on_bridge_connected)
	bridge.disconnected.connect(func() -> void: _set_status("Lost connection to the bridge - retrying..."))
	bridge.connect_to_bridge()
	_set_status("Looking for the bridge on 127.0.0.1:%d..." % bridge.port)
	if not options.has("no-launch"):
		get_tree().create_timer(LAUNCH_GRACE_SECONDS).timeout.connect(_maybe_launch_bridge)


## Starts our own bridge if none answered within the grace period, then watches it until it connects.
func _maybe_launch_bridge() -> void:
	if bridge.is_bridge_connected():
		return
	if not launcher.launch(bridge.port):
		_set_status("Couldn't start the bridge: %s\nStart it by hand with:  gradlew :bridge:run" % launcher.error)
		return
	_launched_bridge = true
	_set_status("Starting the Unciv bridge... (rebuilds if its code changed - can take a minute)")
	while not bridge.is_bridge_connected():
		await get_tree().create_timer(2.0).timeout
		if bridge.is_bridge_connected():
			break
		if not OS.is_process_running(launcher.pid):
			_launched_bridge = false
			_set_status("The bridge stopped before it was ready. From %s:\n%s" % [launcher.log_path, launcher.log_tail()])
			return


func _exit_tree() -> void:
	# Only stop a bridge we started; one started by hand keeps running for the next session
	# (--stop-bridge stops whichever bridge we're connected to - a dev aid for cleaning up after tests).
	if _launched_bridge or options.has("stop-bridge"):
		bridge.send_shutdown()
		# Give the bridge a moment to receive the message and exit on its own before the Gradle
		# launcher is killed (killing it first can cut the bridge off mid-way).
		var deadline := Time.get_ticks_msec() + 1500
		while bridge.is_connection_open() and Time.get_ticks_msec() < deadline:
			OS.delay_msec(50)
			bridge.poll_now()
		launcher.stop()


func _parse_args() -> Dictionary:
	var result := {}
	var args := Array(OS.get_cmdline_user_args())
	# Developer hook: an override.cfg next to project.godot can add options, e.g.
	#   [unciv_vr]
	#   dev_args="--smoke-test"
	var dev_args: String = ProjectSettings.get_setting("unciv_vr/dev_args", "")
	if dev_args != "":
		args.append_array(dev_args.split(" ", false))
	for arg: String in args:
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1] if parts.size() > 1 else ""
	return result


# region game flow ------------------------------------------------------------------------

func _on_bridge_connected() -> void:
	if _initialized:
		# Reconnected (e.g. the bridge was restarted): just reload what it has.
		_set_status("Reconnected to the bridge.")
		await _send_bridge_settings()
		await refresh()
		return
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

	await _send_bridge_settings()
	var rules := await bridge.request("getRuleset")
	if rules.ok:
		hex_map.set_ruleset(rules.result)
	await refresh()
	_fit_table()
	_initialized = true
	_set_status("Your move.")
	if _xr_mode:
		# Give tracking a moment to settle, then put the table in front of wherever the player is
		get_tree().create_timer(0.5).timeout.connect(recenter_table)
	await _select_next_unit()
	await _prompt_research_if_needed()

	if options.has("smoke-test"):
		await _run_smoke_test()
	match options.get("show", ""):   # dev aid for screenshots: --show=city or --show=research
		"city":
			if not state.get("cities", []).is_empty():
				await open_city(Vector2i(int(state["cities"][0]["x"]), int(state["cities"][0]["y"])))
		"research":
			await open_research()
		"settings":
			open_settings()
		"unit":
			if not state.get("units", []).is_empty():
				await _select_unit(int(state["units"][0]["id"]))
		"aim":
			for u: Dictionary in state.get("units", []):
				if not u.get("civilian", false):
					await _select_unit(int(u["id"]))
					var reach: Array = selected_unit.get("reachable", [])
					if not reach.is_empty():
						await click_tile(Vector2i(int(reach[-1]["x"]), int(reach[-1]["y"])))
					break
		"promotion":
			for u: Dictionary in state.get("units", []):
				await _select_unit(int(u["id"]), false)
				if selected_unit.get("canPromote", false):
					open_promotions()
					break
	if options.has("screenshot"):
		await get_tree().create_timer(1.0).timeout   # let the table recenter and cards lay out
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
	if table.get_node_or_null("TableTop") == null:
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

	# With a unit selected, the first click on a tile aims there (path, turns or expected damage) and a
	# second click on the same tile moves / attacks. Your city's card also opens on the first click.
	if not selected_unit.is_empty() and key != selected_key:
		if hex_map.aim_key() == key:
			hex_map.clear_aim()
			if hex_map.is_target(key):
				await attack(key)
			else:
				await move_selected_to(key)
			return
		await _aim_at(key)
		if not _own_city_at(key).is_empty():
			await open_city(key, true)
		return

	if not _own_city_at(key).is_empty():
		await open_city(key)
		return

	_deselect()


## Shows where the selected unit would go (or what an attack would do) if you clicked [param key] again.
func _aim_at(key: Vector2i) -> void:
	if hex_map.is_target(key):
		var t := _target_at(key)
		hex_map.set_aim(key, [], "Attack %s\ndeal ~%d, take ~%d\nclick again to attack" % [t.get("name", "?"),
			int(t.get("expectedDamageToDefender", 0)), int(t.get("expectedDamageToAttacker", 0))], AIM_ATTACK_COLOR)
		return
	busy = true
	var reply := await bridge.request("previewMove", {"unitId": int(selected_unit["id"]), "x": key.x, "y": key.y})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	var result: Dictionary = reply.result
	if not result.get("canReach", false):
		hex_map.set_aim(key, [], "Can't get there", AIM_BLOCKED_COLOR)
		return
	var stops: Array[Vector2i] = []
	for s: Dictionary in result.get("stops", []):
		stops.append(Vector2i(int(s["x"]), int(s["y"])))
	var turns := int(result.get("turns", 1))
	var text := "Move here" if turns <= 1 else "Move here: %d turns" % turns
	hex_map.set_aim(key, stops, text + "\nclick again to go", AIM_MOVE_COLOR)


func move_selected_to(key: Vector2i) -> void:
	busy = true
	var reply := await bridge.request("moveUnit", {"unitId": int(selected_unit["id"]), "x": key.x, "y": key.y})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	if reply.result.get("queued", false):
		_set_status("%s is on its way - it keeps going next turn." % selected_unit["name"])
	await refresh()
	if not selected_unit.is_empty() and float(selected_unit.get("movement", 0)) <= 0.0:
		_select_next_unit()


func found_city() -> void:
	await unit_action("FoundCity")


func attack(key: Vector2i) -> void:
	if busy or selected_unit.is_empty():
		return
	busy = true
	var reply := await bridge.request("attack", {"unitId": int(selected_unit["id"]), "x": key.x, "y": key.y})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	var r: Dictionary = reply.result
	if not r.get("attacked", false):
		_set_status(r.get("message", "No attack happened."))
	else:
		var text := "%s attacked %s: dealt %d damage, took %d." % [selected_unit["name"], r["defender"],
			int(r["damageToDefender"]), int(r["damageToAttacker"])]
		if r.get("cityCaptured", false):
			text += "  City captured!"
		elif r.get("defenderDefeated", false):
			text += "  %s destroyed!" % r["defender"]
		if not r.get("attackerAlive", true):
			text += "  Your %s was lost." % selected_unit["name"]
			_deselect()
		_set_status(text)
	await refresh()
	if not selected_unit.is_empty() and float(selected_unit.get("movement", 0)) <= 0.0:
		_select_next_unit()


func build_improvement(improvement: String) -> void:
	if busy or selected_unit.is_empty():
		return
	busy = true
	var reply := await bridge.request("buildImprovement", {"unitId": int(selected_unit["id"]), "improvement": improvement})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	var r: Dictionary = reply.result
	if r.get("improvementInProgress") == null:
		_set_status("Improvement order cancelled.")
	else:
		_set_status("%s: building %s (%d turns)." % [selected_unit["name"], r["improvementInProgress"], int(r["turnsLeft"])])
	await refresh()
	_select_next_unit()


func _on_menu_chosen(kind: String, value: String) -> void:
	match kind:
		"action":
			await unit_action(value)
		"improvement":
			await build_improvement(value)
		"end_turn":
			await end_turn()
		"next_idle":
			await _select_next_unit()
		"next_unit":
			await cycle_unit(1)
		"prev_unit":
			await cycle_unit(-1)
		"recenter":
			recenter_table()
		"research_card":
			await open_research()
		"research":
			await set_research(value)
		"produce", "queue", "buy", "unqueue":
			await city_command(kind, value)
		"close":
			_close_popup()
			selected_city = {}
			action_menu.show_unit(selected_unit)
		"promotion_card":
			open_promotions()
		"settings_card":
			open_settings()
		"background", "auto_move":
			await change_setting(kind, value)
		"promote":
			await promote(value)


# region cities and research ----------------------------------------------------------------

func _own_city_at(key: Vector2i) -> Dictionary:
	for c: Dictionary in state.get("cities", []):
		if int(c["x"]) == key.x and int(c["y"]) == key.y:
			return c
	return {}


## [param keep_unit]: the selected unit stays selected (and aimed at the city), e.g. to march it in.
func open_city(key: Vector2i, keep_unit := false) -> void:
	var reply := await bridge.request("getCity", {"x": key.x, "y": key.y})
	if not reply.ok:
		_set_status(reply.error)
		return
	if not keep_unit:
		_deselect()
		hex_map.set_selection(key, [], [])
	selected_city = reply.result
	_show_city_card()


func _show_city_card() -> void:
	var gold := int(state.get("player", {}).get("gold", 0))
	if _xr_mode:
		_popup_kind = "city"
		_popup_key = Vector2i(int(selected_city["x"]), int(selected_city["y"]))
		popup_menu.show_city(selected_city, gold)   # floats above the city; the wrist keeps the unit card
		_update_popup_panel()
	else:
		action_menu.show_city(selected_city, gold)


## produce / queue / buy take a construction name; unqueue takes a queue index.
func city_command(kind: String, value: String) -> void:
	if busy or selected_city.is_empty():
		return
	var params := {"name": selected_city["name"]}
	var method := ""
	match kind:
		"produce":
			method = "setProduction"
			params["construction"] = value
			params["mode"] = "now"
		"queue":
			method = "setProduction"
			params["construction"] = value
			params["mode"] = "queue"
		"buy":
			method = "buyConstruction"
			params["construction"] = value
		"unqueue":
			method = "removeFromQueue"
			params["index"] = int(value)
	busy = true
	var reply := await bridge.request(method, params)
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	selected_city = reply.result
	match kind:
		"produce": _set_status("%s will build %s next." % [selected_city["name"], value])
		"queue": _set_status("%s added to %s's queue." % [value, selected_city["name"]])
		"buy": _set_status("Bought %s in %s." % [value, selected_city["name"]])
	var key := Vector2i(int(selected_city["x"]), int(selected_city["y"]))
	await refresh()
	selected_city = (await bridge.request("getCity", {"name": selected_city["name"]})).get("result", selected_city)
	if selected_unit.is_empty():
		hex_map.set_selection(key, [], [])
	_show_city_card()


func open_research() -> void:
	var reply := await bridge.request("getTechs")
	if not reply.ok:
		_set_status(reply.error)
		return
	selected_city = {}
	if _xr_mode:
		_popup_kind = "research"
		popup_menu.show_research(reply.result)
		_update_popup_panel()
	else:
		action_menu.show_research(reply.result)


## VR: the selected unit's card floats above it, so the right controller alone can give orders.
func _open_unit_popup() -> void:
	if not _xr_mode or selected_unit.is_empty():
		return
	_popup_kind = "unit"
	_popup_key = _selected_key()
	_popup_unit_id = int(selected_unit["id"])
	popup_menu.show_unit(selected_unit)
	_update_popup_panel()


func _close_popup() -> void:
	_popup_kind = ""
	_popup_unit_id = -1
	if _popup_panel != null:
		_popup_panel.visible = false


## Shows the selected unit's promotion choices: floating above the unit in VR, in the card on desktop.
func open_promotions() -> void:
	if selected_unit.is_empty():
		return
	_promotion_prompted[int(selected_unit["id"])] = int(state.get("turn", 0))
	if _xr_mode:
		_popup_kind = "promotion"
		_popup_key = _selected_key()
		_popup_unit_id = int(selected_unit["id"])
		popup_menu.show_promotions(selected_unit)
		_update_popup_panel()
	else:
		action_menu.show_promotions(selected_unit)


func promote(promotion: String) -> void:
	if busy or selected_unit.is_empty():
		return
	busy = true
	var reply := await bridge.request("promote", {"unitId": int(selected_unit["id"]), "promotion": promotion})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	_set_status("%s is now %s." % [selected_unit["name"], promotion])
	selected_unit = reply.result
	if selected_unit.get("canPromote", false):
		open_promotions()   # enough XP for another one
	else:
		_close_popup()
		action_menu.show_unit(selected_unit)
		_open_unit_popup()
	await refresh()


func set_research(tech: String) -> void:
	var reply := await bridge.request("setResearch", {"tech": tech})
	if not reply.ok:
		_set_status(reply.error)
		return
	_set_status("Researching %s." % reply.result.get("current", tech))
	await refresh()
	if _xr_mode:
		_popup_kind = "research"
		popup_menu.show_research(reply.result)
	else:
		action_menu.show_research(reply.result)


## Opens the research card when nothing is being researched (start of game, tech just finished).
func _prompt_research_if_needed() -> void:
	var p: Dictionary = state.get("player", {})
	if p.get("canResearch", false) and (p.get("currentTech") == null or int(p.get("freeTechs", 0)) > 0):
		_set_status("Pick something to research.")
		await open_research()


## Steps through all your units in a stable order (dir = 1 next, -1 previous).
func cycle_unit(dir: int) -> void:
	var units: Array = state.get("units", []).duplicate()
	if units.is_empty():
		return
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	var index := 0 if dir > 0 else units.size() - 1
	if not selected_unit.is_empty():
		var current := units.find_custom(func(u: Dictionary) -> bool: return int(u["id"]) == int(selected_unit["id"]))
		if current >= 0:
			index = posmod(current + dir, units.size())
	await _select_unit(int(units[index]["id"]))


## VR: puts the table in front of where you're looking now, at a comfortable height below your eyes.
func recenter_table() -> void:
	if not _xr_mode or _xr_camera == null:
		return
	var head := _xr_camera.global_transform
	var forward := -head.basis.z
	forward.y = 0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var height := head.origin.y - 0.45 if not _table_height_set else table.global_position.y
	_table_height_set = true
	table.global_position = Vector3(head.origin.x, 0, head.origin.z) + forward * 0.75
	table.global_position.y = clampf(height, TABLE_HEIGHT_RANGE.x, TABLE_HEIGHT_RANGE.y)
	table.rotation = Vector3(0, atan2(-forward.x, -forward.z), 0)
	_place_vr_hud()


## The floating status text sits above the far edge of the table, facing the player.
func _place_vr_hud() -> void:
	if _hud_label_3d == null:
		return
	var forward := -table.global_transform.basis.z.normalized()
	var right := table.global_transform.basis.x.normalized()
	_hud_label_3d.global_position = table.global_position + forward * 0.75 + Vector3(0, 0.55, 0) - right * 0.35
	_hud_label_3d.rotation = Vector3(deg_to_rad(-10), table.rotation.y, 0)


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
	if selected_unit.is_empty() or not selected_unit.get("idle", true) or float(selected_unit.get("movement", 0)) <= 0.0:
		_select_next_unit()


func end_turn() -> void:
	if busy:
		return
	busy = true
	_deselect()
	_set_status("Ending turn - the AI players are moving...")
	hex_map.clear_aim()
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
	await _select_next_unit()
	await _prompt_research_if_needed()


func _select_unit(unit_id: int, focus := true) -> void:
	var reply := await bridge.request("getUnit", {"unitId": unit_id})
	if not reply.ok:
		_deselect()
		return
	if selected_unit.is_empty() or int(selected_unit["id"]) != unit_id:
		hex_map.clear_aim()
	selected_unit = reply.result
	var reachable: Array[Vector2i] = []
	for t: Dictionary in selected_unit.get("reachable", []):
		reachable.append(Vector2i(int(t["x"]), int(t["y"])))
	var targets: Array[Vector2i] = []
	for t: Dictionary in selected_unit.get("targets", []):
		targets.append(Vector2i(int(t["x"]), int(t["y"])))
	hex_map.set_selection(_selected_key(), reachable, targets)
	selected_city = {}
	action_menu.show_unit(selected_unit)
	if focus:
		# You picked this unit: its card pops up above it (replacing any other popup), or its
		# promotion choice the first time this turn it has earned one
		if selected_unit.get("canPromote", false) and _promotion_prompted.get(unit_id, -1) != int(state.get("turn", 0)):
			open_promotions()
		else:
			_open_unit_popup()
	elif _popup_unit_id == unit_id:
		# A refresh: keep whatever is open for this unit, with fresh numbers
		match _popup_kind:
			"unit": _open_unit_popup()
			"promotion": popup_menu.show_promotions(selected_unit)
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
	await _select_unit(int(candidates[start]["id"]))


func _deselect() -> void:
	hex_map.clear_aim()
	selected_unit = {}
	selected_city = {}
	_close_popup()
	hex_map.clear_selection()
	action_menu.show_unit({})
	_update_hud()


func _target_at(key: Vector2i) -> Dictionary:
	for t: Dictionary in selected_unit.get("targets", []):
		if int(t["x"]) == key.x and int(t["y"]) == key.y:
			return t
	return {}


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
	# Combat: attack the first target any military unit can reach
	for u: Dictionary in state.get("units", []):
		if u.get("civilian", false):
			continue
		await _select_unit(int(u["id"]))
		var targets: Array = selected_unit.get("targets", [])
		print("SMOKE: %s has %d target(s)" % [u["name"], targets.size()])
		if not targets.is_empty():
			var t: Dictionary = targets[0]
			print("SMOKE: attack preview: ", t)
			var target_key := Vector2i(int(t["x"]), int(t["y"]))
			await click_tile(target_key)
			print("SMOKE: first click aims at %s (attacked: %s)" % [hex_map.aim_key(), _status_text.contains("attacked")])
			await click_tile(target_key)
			print("SMOKE: attack result: ", _status_text)
			break
	for u: Dictionary in state.get("units", []):
		if not u.get("civilian", false):
			await _select_unit(int(u["id"]))
			var reach: Array = selected_unit.get("reachable", [])
			if reach.size() > 1:
				var target: Dictionary = reach[-1]
				var move_key := Vector2i(int(target["x"]), int(target["y"]))
				var before := _selected_key()
				await click_tile(move_key)
				print("SMOKE: first click aims at %s, unit still at %s: %s" % [hex_map.aim_key(), before, _selected_key() == before])
				var mover_id := int(selected_unit["id"])
				await click_tile(move_key)
				var mover: Array = state.get("units", []).filter(func(m: Dictionary) -> bool: return int(m["id"]) == mover_id)
				print("SMOKE: moved warrior to %s (target %s), status: %s" % [
					Vector2i(int(mover[0]["x"]), int(mover[0]["y"])) if not mover.is_empty() else "-", move_key, _status_text])
			break
	# Workers: start the first improvement offered
	for u: Dictionary in state.get("units", []):
		if u["name"] != "Worker":
			continue
		await _select_unit(int(u["id"]))
		var offered: Array = selected_unit.get("improvements", [])
		print("SMOKE: worker can build ", offered.map(func(i: Dictionary) -> String: return "%s(%d)" % [i["name"], int(i["turns"])]))
		for imp: Dictionary in offered:
			if imp["name"] != "Cancel improvement order":
				await build_improvement(imp["name"])
				print("SMOKE: build result: ", _status_text)
				break
		break
	# Cities: open the capital, build something now, queue something, remove it again
	if not state.get("cities", []).is_empty():
		var capital: Dictionary = state["cities"][0]
		var capital_key := Vector2i(int(capital["x"]), int(capital["y"]))
		# Clicking the city with some other unit selected should still open it
		for u: Dictionary in state.get("units", []):
			if Vector2i(int(u["x"]), int(u["y"])) != capital_key:
				await _select_unit(int(u["id"]))
				break
		await click_tile(capital_key)
		print("SMOKE: city click with %s selected -> city '%s', popup '%s', aimed %s" % [selected_unit.get("name", "-"), selected_city.get("name", "-"), _popup_kind, hex_map.aim_key() == capital_key])
		await open_city(capital_key)
		var options: Array = selected_city.get("options", []).filter(func(o: Dictionary) -> bool: return o.get("buildable", false) and o["kind"] != "perpetual")
		print("SMOKE: %s can build %s" % [selected_city.get("name"), options.map(func(o: Dictionary) -> String: return "%s(%st)" % [o["name"], o["turns"]])])
		if options.size() >= 2:
			await city_command("produce", options[-1]["name"])
			await city_command("queue", options[0]["name"])
			print("SMOKE: queue now ", selected_city.get("queue", []).map(func(q: Dictionary) -> String: return q["name"]))
			await city_command("unqueue", str(selected_city.get("queue", []).size() - 1))
			print("SMOKE: after unqueue ", selected_city.get("queue", []).map(func(q: Dictionary) -> String: return q["name"]))
	# Research: pick the cheapest available tech
	var techs_reply := await bridge.request("getTechs")
	if techs_reply.ok:
		var available: Array = techs_reply.result["techs"].filter(func(t: Dictionary) -> bool: return t.get("researchable", false))
		print("SMOKE: researchable ", available.map(func(t: Dictionary) -> String: return t["name"]))
		if not available.is_empty():
			await set_research(available[0]["name"])
			print("SMOKE: ", _status_text)
	# Promotions: promote the first unit that has earned one
	for u: Dictionary in state.get("units", []):
		await _select_unit(int(u["id"]), false)
		if selected_unit.get("canPromote", false):
			var choices: Array = selected_unit.get("promotionChoices", [])
			print("SMOKE: %s can be promoted: %s" % [u["name"], choices.map(func(c: Dictionary) -> String: return c["name"])])
			if not choices.is_empty():
				await promote(choices[0]["name"])
				print("SMOKE: ", _status_text, " promotions now ", selected_unit.get("promotions"))
			break
	# Table buttons (what the right controller alone uses)
	for id: String in ["research", "research", "settings", "settings", "next_unit", "prev_unit", "next_idle", "recenter"]:
		await press_table_button(id)
		print("SMOKE: pressed %s -> popup '%s', selected %s" % [id, _popup_kind, selected_unit.get("name", "-")])
	# Cycling through all units
	await cycle_unit(1)
	print("SMOKE: cycled to ", selected_unit.get("name"))
	await cycle_unit(-1)
	print("SMOKE: cycled back to ", selected_unit.get("name"))
	# Explore: send a military unit exploring and watch it keep moving over the next turns
	var explorer_id := -1
	for u: Dictionary in state.get("units", []):
		if not u.get("civilian", false):
			await _select_unit(int(u["id"]), false)
			explorer_id = int(u["id"])
			await unit_action("Explore")
			break
	for i in 3:
		await end_turn()
		var where: Array = state.get("units", []).filter(func(u: Dictionary) -> bool: return int(u["id"]) == explorer_id)
		print("SMOKE: ", _status_text.split("\n")[0], "  explorer at ",
			"(%d,%d)" % [int(where[0]["x"]), int(where[0]["y"])] if not where.is_empty() else "-")
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


## The unit card: top-right of the window on desktop, strapped to the left wrist in VR.
func _setup_action_menu() -> void:
	action_menu = ActionMenu.new()
	action_menu.show_recenter = _xr_mode
	action_menu.chosen.connect(_on_menu_chosen)
	if not _xr_mode:
		var layer := CanvasLayer.new()
		add_child(layer)
		layer.add_child(action_menu)
		action_menu.layout_changed.connect(_place_desktop_menu)
		get_viewport().size_changed.connect(_place_desktop_menu)
		_place_desktop_menu()
		return

	action_menu.custom_minimum_size = Vector2(WRIST_PANEL_PIXELS.x, 0)
	_wrist_panel = WorldPanel.new()
	_wrist_panel.setup(action_menu, WRIST_PANEL_PIXELS, WRIST_PANEL_METRES)
	# Above the back of the left hand, tilted up towards your face like a wristwatch held up to read
	_wrist_panel.position = Vector3(0.0, 0.07, 0.06)
	_wrist_panel.rotation_degrees = Vector3(-50, 0, 0)
	_left_hand.add_child(_wrist_panel)

	# The city card gets its own bigger panel, which floats above whichever city is open
	popup_menu = ActionMenu.new()
	popup_menu.compact = true
	popup_menu.custom_minimum_size = Vector2(POPUP_PANEL_PIXELS.x, 0)
	popup_menu.chosen.connect(_on_menu_chosen)
	_popup_panel = WorldPanel.new()
	_popup_panel.setup(popup_menu, POPUP_PANEL_PIXELS, POPUP_PANEL_METRES)
	_popup_panel.visible = false
	add_child(_popup_panel)


## VR: keeps the popup card standing above its tile and turned towards your head.
func _update_popup_panel() -> void:
	if _popup_panel == null:
		return
	_popup_panel.visible = _popup_kind != ""
	if not _popup_panel.visible:
		return
	var head := _xr_camera.global_position
	var up := table.global_transform.basis.y.normalized()
	var base: Vector3
	var lift := 0.06   # gap between the anchor and the bottom of the card
	match _popup_kind:
		"settings", "research":
			base = table.to_global(Vector3(0, 0, 0))   # over the middle of the table
			lift = 0.12
		"unit", "promotion":
			# Above the unit and a little behind it, so the tiles around it stay visible and pointable
			base = hex_map.to_global(hex_map.tile_local_center(_popup_key))
			var away := base - head
			away.y = 0
			if away.length() > 0.01:
				base += away.normalized() * 0.08
			lift = 0.09
		_:
			base = hex_map.to_global(hex_map.tile_local_center(_popup_key))
	# The card fills only the top of the panel (it's sized to its contents); put the card's bottom edge
	# 'lift' above the anchor.
	var card_height := popup_menu.size.y / POPUP_PANEL_PIXELS.y * POPUP_PANEL_METRES.y
	_popup_panel.global_position = base + up * (lift + card_height - POPUP_PANEL_METRES.y / 2.0)
	if head.distance_to(_popup_panel.global_position) > 0.05:
		# Face the eyes squarely (tilting back as needed) so the text isn't skewed when you look down at it.
		# use_model_front = true: the quad's front (+Z) is what turns towards the head.
		_popup_panel.look_at(head, Vector3.UP, true)


## Keeps the desktop unit card snug in the top-right corner as its contents change.
func _place_desktop_menu() -> void:
	await get_tree().process_frame   # let removed buttons actually leave first
	action_menu.reset_size()
	var window := get_viewport().get_visible_rect().size
	action_menu.position = Vector2(window.x - action_menu.size.x - 12, 12)


# region settings -------------------------------------------------------------------------

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for key in settings.keys():
		settings[key] = config.get_value("settings", key, settings[key])


func _save_settings() -> void:
	var config := ConfigFile.new()
	for key in settings.keys():
		config.set_value("settings", key, settings[key])
	config.save(SETTINGS_PATH)


## Tells the bridge about settings that live in the game engine.
func _send_bridge_settings() -> void:
	var reply := await bridge.request("setSettings", {"automatedUnitsMoveOnTurnStart": settings["auto_move"] == "start"})
	if not reply.ok:
		push_warning("setSettings failed: %s" % reply.error)


func change_setting(key: String, value: String) -> void:
	settings[key] = value
	_save_settings()
	match key:
		"background":
			backgrounds.apply(value)
		"auto_move":
			await _send_bridge_settings()
	open_settings()   # refresh the card so the new choice is highlighted


func open_settings() -> void:
	if _xr_mode:
		_popup_kind = "settings"
		popup_menu.show_settings(settings)
		_update_popup_panel()
	else:
		action_menu.show_settings(settings)


## A row of round buttons along the near rim of the table, each with a floating label.
func _setup_table_buttons() -> void:
	var count := TABLE_BUTTONS.size()
	for i in count:
		var spec: Array = TABLE_BUTTONS[i]
		var big: bool = spec[0] == "end_turn"
		var node := MeshInstance3D.new()
		node.name = "Button_" + spec[0]
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.042 if big else 0.032
		mesh.bottom_radius = mesh.top_radius + 0.005
		mesh.height = 0.02
		mesh.radial_segments = 24
		node.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = spec[2]
		material.emission_enabled = true
		material.emission = Color(0, 0, 0)
		node.material_override = material
		var angle := deg_to_rad(float(spec[3]))   # +Z is towards the player
		node.position = Vector3(sin(angle) * TABLE_BUTTON_RADIUS, 0.01, cos(angle) * TABLE_BUTTON_RADIUS)
		table.add_child(node)
		var label := Label3D.new()
		label.text = spec[1]
		label.font_size = 44 if big else 36
		label.pixel_size = 0.0006
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 0.035, 0)
		node.add_child(label)
		_table_buttons.append({"id": spec[0], "node": node, "material": material, "radius": mesh.bottom_radius})


## The id of the table button a ray points at, or "".
func _table_button_at(origin: Vector3, direction: Vector3) -> String:
	var best := ""
	var best_along := INF
	var dir := direction.normalized()
	for button: Dictionary in _table_buttons:
		var node: MeshInstance3D = button["node"]
		var center := node.global_position
		var along := (center - origin).dot(dir)
		if along < 0 or along > best_along:
			continue
		var radius: float = (float(button["radius"]) + 0.015) * table.scale.x
		if (origin + dir * along).distance_to(center) < radius:
			best = button["id"]
			best_along = along
	return best


func _highlight_table_button(id: String) -> void:
	if id == _hovered_button:
		return
	_hovered_button = id
	for button: Dictionary in _table_buttons:
		var material: StandardMaterial3D = button["material"]
		material.emission = Color(0.4, 0.5, 0.75) if button["id"] == id else Color(0, 0, 0)


func _table_button_position(id: String) -> Vector3:
	for button: Dictionary in _table_buttons:
		if button["id"] == id:
			return (button["node"] as Node3D).global_position
	return Vector3.ZERO


func press_table_button(id: String) -> void:
	match id:
		"prev_unit":
			await cycle_unit(-1)
		"next_unit":
			await cycle_unit(1)
		"next_idle":
			await _select_next_unit()
		"research":
			if _popup_kind == "research":
				_close_popup()
			else:
				await open_research()
		"end_turn":
			await end_turn()
		"recenter":
			recenter_table()
		"settings":
			if _popup_kind == "settings":
				_close_popup()
			else:
				open_settings()


## A simple column from the floor up to the table (hidden when floating in space).
func _setup_pedestal() -> void:
	_pedestal = MeshInstance3D.new()
	_pedestal.name = "Pedestal"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.3
	mesh.height = 1.0
	mesh.radial_segments = 24
	_pedestal.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.26, 0.18, 0.12)
	material.roughness = 0.8
	_pedestal.material_override = material
	add_child(_pedestal)
	_update_pedestal()


func _update_pedestal() -> void:
	if _pedestal == null:
		return
	var floor_y := backgrounds.global_position.y
	var top := table.global_position.y - 0.04 * table.scale.y
	var height := top - floor_y
	_pedestal.visible = backgrounds.has_floor and height > 0.05
	if _pedestal.visible:
		_pedestal.scale = Vector3(1, height, 1)
		_pedestal.global_position = Vector3(table.global_position.x, floor_y + height / 2.0, table.global_position.z)


# region scene setup ----------------------------------------------------------------------

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
	if options.has("fake-xr"):
		# Dev aid: builds the VR scene (wrist card, city card, table placement) with a fixed fake
		# head and hands instead of a headset, so the VR layout can be tested and screenshotted.
		print("Fake XR mode - VR layout without a headset")
		return true
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
	_xr_camera = cam
	if options.has("fake-xr"):
		cam.position = Vector3(0, 1.45, 0.1)
		cam.rotation_degrees = Vector3(float(options.get("fake-pitch", -35)), 0, 0)
		cam.current = true

	_left_hand = _make_controller("left_hand")
	_right_hand = _make_controller("right_hand")
	origin.add_child(_left_hand)
	origin.add_child(_right_hand)
	if options.has("fake-xr"):
		for hand in [_left_hand, _right_hand]:
			hand.show_when_tracked = false
		_left_hand.position = Vector3(-0.2, 1.1, -0.25)
		_left_hand.rotation_degrees = Vector3(10, 25, 0)
		_right_hand.position = Vector3(0.18, 1.1, -0.2)
		_right_hand.rotation_degrees = Vector3(-40, 0, 0)
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
		if _camera != null:
			_highlight_table_button(_table_button_at(_camera.project_ray_origin(motion.position), _camera.project_ray_normal(motion.position)))
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				var pressed := _table_button_at(_camera.project_ray_origin(button.position), _camera.project_ray_normal(button.position)) if _camera != null else ""
				if pressed != "":
					press_table_button(pressed)
					return
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
			KEY_N:
				_select_next_unit()
			KEY_TAB:
				cycle_unit(-1 if (event as InputEventKey).shift_pressed else 1)
			KEY_T:
				open_research()
			KEY_O:
				open_settings()
			KEY_ESCAPE:
				_deselect()
			KEY_R:
				refresh()


func _process(delta: float) -> void:
	_update_pedestal()
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
	var target := _target_at(key)
	if not target.is_empty():
		text = "ATTACK %s (%s, %d/%d HP)" % [target.get("name", "?"), target.get("civ", "?"),
			int(target.get("health", 0)), int(target.get("maxHealth", 100))]
		if target.has("expectedDamageToDefender"):
			text += "\n  expected: deal %d, take %d" % [int(target["expectedDamageToDefender"]), int(target["expectedDamageToAttacker"])]
	if text != _hover_text:
		_hover_text = text
		_update_hud()


func _process_xr(delta: float) -> void:
	if _right_hand == null:
		return
	_update_popup_panel()
	var origin := _right_hand.global_position
	var direction := -_right_hand.global_transform.basis.z

	# Cards take priority over the map behind them; the city card is checked first
	_pointed_panel = null
	for panel: WorldPanel in [_popup_panel, _wrist_panel]:
		var hit: Variant = panel.ray_hit(origin, direction)
		if hit != null:
			_pointed_panel = panel
			_pointed_pixel = hit[1]
			_pointer_dot.visible = true
			_pointer_dot.global_position = hit[0]
			panel.hover(_pointed_pixel)
			_update_hover(null)
			break
	var button := _table_button_at(origin, direction) if _pointed_panel == null else ""
	_highlight_table_button(button)
	if button != "":
		_pointer_dot.visible = true
		_pointer_dot.global_position = _table_button_position(button)
		_update_hover(null)
	elif _pointed_panel == null and not hex_map.tiles.is_empty():
		var key: Variant = hex_map.pick(origin, direction)
		_update_hover(key)
		_pointer_dot.visible = key != null
		if key != null:
			_pointer_dot.global_position = hex_map.to_global(hex_map.tile_local_center(key))

	# Right stick: scrolls the card you're pointing at; otherwise raises / lowers the table
	var right_stick := _right_hand.get_vector2("primary")
	_right_grip_down = _right_hand.get_float("grip") > 0.6
	if _pointed_panel != null and not _right_grip_down:
		if absf(right_stick.y) > 0.3:
			var menu: ActionMenu = popup_menu if _pointed_panel == _popup_panel else action_menu
			menu.scroll_by(-right_stick.y * delta * 600.0)
	else:
		_stick_moves_table(right_stick, _right_grip_down, delta)

	# Left stick works like the right one: height, or with the grip held, rotate (x) / scale (y)
	_stick_moves_table(_left_hand.get_vector2("primary"), _left_hand.get_float("grip") > 0.6, delta)


## Shared stick handling for both hands. Grip held: x rotates and y scales the table.
## Otherwise y raises / lowers the table.
func _stick_moves_table(stick: Vector2, grip_held: bool, delta: float) -> void:
	if grip_held:
		if absf(stick.x) > 0.2:
			table.rotate_y(-stick.x * delta * 1.2)
			_place_vr_hud()
		if absf(stick.y) > 0.2:
			var new_scale := clampf(table.scale.x * (1.0 + stick.y * delta), 0.3, 6.0)
			table.scale = Vector3(new_scale, new_scale, new_scale)
	elif absf(stick.y) > 0.3:
		table.global_position.y = clampf(table.global_position.y + stick.y * delta * 0.4,
			TABLE_HEIGHT_RANGE.x, TABLE_HEIGHT_RANGE.y)
		_place_vr_hud()


func _on_xr_button(is_right: bool, button: String) -> void:
	if is_right:
		match button:
			"trigger_click":
				if _pointed_panel != null:
					_pointed_panel.click(_pointed_pixel)
					return
				if _hovered_button != "":
					press_table_button(_hovered_button)
					return
				var key: Variant = hex_map.pick(_right_hand.global_position, -_right_hand.global_transform.basis.z)
				if key != null:
					click_tile(key)
			"ax_button":
				end_turn()
			"by_button":
				found_city()
	else:
		match button:
			"ax_button":   # X
				cycle_unit(1)
			"by_button":   # Y
				cycle_unit(-1)
			"primary_click":
				recenter_table()
