# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
## Either way, holding the trigger (or the mouse button) on a tile aims the selected unit there even when
## one of your own units is standing on it - a plain click would select that unit instead.

# Loaded by path rather than class_name, so the project runs even before the editor has scanned it
const BridgeClient := preload("res://scripts/bridge_client.gd")
const HexMap := preload("res://scripts/hex_map.gd")
const ActionMenu := preload("res://scripts/action_menu.gd")
const WorldPanel := preload("res://scripts/world_panel.gd")
const Backgrounds := preload("res://scripts/backgrounds.gd")
const TableModel := preload("res://scripts/table_model.gd")
const BridgeLauncher := preload("res://scripts/bridge_launcher.gd")
const BRIDGE_PROTOCOL := 19   # the bridge protocol version this client is written for (BridgeMain.PROTOCOL_VERSION)
const Minimap := preload("res://scripts/minimap.gd")
const InfoPanel := preload("res://scripts/info_panel.gd")
const BigScreen := preload("res://scripts/big_screen.gd")
const CityBoard := preload("res://scripts/city_boards.gd")
const OverviewBoard := preload("res://scripts/overview_board.gd")
const Keyboard := preload("res://scripts/keyboard.gd")
const SettingsBoard := preload("res://scripts/settings_board.gd")
const OVERVIEW_METRES := Vector2(1.6, 0.9778)   # same aspect ratio as OverviewBoard.SIZE
const SETTINGS_METRES := Vector2(1.3, 0.833)    # same aspect ratio as SettingsBoard.SIZE
const KEYBOARD_METRES := Vector2(0.34, 0.1507)   # same aspect ratio as Keyboard.SIZE
const CITY_BOARD_METRES := Vector2(0.7, 1.0013)   # same aspect ratio as CityBoard.SIZE
const BIG_SCREEN_METRES := Vector2(2.0, 0.875)
const INFO_PANEL_PIXELS := Vector2i(420, 640)
const INFO_PANEL_METRES := Vector2(0.44, 0.67)

## Holding the trigger (or the left mouse button) on a tile this long aims at it instead of clicking it.
const LONG_PRESS_MS := 400
## How long the game may sit "busy" with nothing to wait for before it lets go (see _watch_busy).
const BUSY_WATCHDOG_MS := 25000
## Our own "unit action" on the card: pick a tile to move to (not one of Unciv's UnitActionTypes).
const MOVE_ACTION := "MoveHere"

const TABLE_HALF_SIZE := 0.7   # metres: the map is scaled so its half-width fits this
# Maps bigger than this (in map units, about a Tiny map) are shown through a window that slides
# over the map, so hexes stay big enough to point at. Grip + stick up / down zooms the window.
const VIEW_RADIUS_DEFAULT := 14.0
const VIEW_RADIUS_MIN := 5.0   # zoomed all the way in; all the way out shows the whole map
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
	["recenter", "Recenter", Color(0.35, 0.35, 0.38), 90.0],
	["settings", "Settings", Color(0.35, 0.35, 0.38), 110.0],
	["exit_city", "Exit city", Color(0.8, 0.12, 0.1), 65.0],   # only in the city view, where End turn usually is
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
var _replaced_old_bridge := false
var _auto_selecting := false
var _trigger_scrollbar: ScrollBar = null   # VR: the scrollbar the held trigger is moving
const DECISION_CARDS := ["alert", "alert_tile", "great_person", "vote"]   # VR popups that wait for an answer
var backgrounds: Backgrounds
## Player settings, saved in user://settings.cfg. auto_move: "end" (units move when you end your turn) or "start".
var settings := {"background": "Mountains", "table": "OrnateOak", "auto_move": "end", "tileset": "LowPoly", "unitset": "tileset",
	# Unciv's Options > Gameplay / Automation / Advanced (see SettingsBoard.GAMEPLAY and AUTOMATION)
	"checkForDueUnits": false, "autoUnitCycle": true, "alternateUnitCycleOrder": false, "confirmNextTurn": false,
	"orderTradeOffersByAmount": true, "autoAssignCityProduction": true, "autoBuildingRoads": true,
	"automatedWorkersReplaceImprovements": true, "stopAutomatedWorkersRemoveVegetation": false,
	"automatedUnitsCanUpgrade": false, "automatedUnitsChoosePromotions": false, "citiesAutoBombardAtEndOfTurn": false,
	"autoAssignSpecialistsInNewCities": true, "notificationsLogMaxTurns": 5, "turnsBetweenAutosaves": 1,
	# What the world looks like: folders in backgrounds/, tables/, tilesets/ (or ~/.unciv-vr/...)
	# Where you've dragged the overview and the info board, relative to the table: [x, y, z, yaw degrees]
	"minimap_pose": [], "info_pose": [], "wide_pose": [], "city_info_pose": [], "city_prod_pose": [], "overview_pose": [], "settings_pose": [],
	# Unciv's map overlays (the round buttons beside the overview); Unciv's defaults
	"overlays": {"movement": false, "yields": false, "worked": false, "resources": true, "improvements": true, "unit_icons": true},
	# Other players' turns: "normal" (play back the moves and battles you could see), "fast" or "off"
	"playback": "normal"}
var _pointed_overlay := ""        # overlay button the laser is on
# City view: the table zooms onto one city and two boards replace the world boards (Unciv's city screen)
var city_info_board: CityBoard
var city_prod_board: CityBoard
var _city_info_holder: Node     # WorldPanel (VR) or CanvasLayer (desktop)
var _city_prod_holder: Node
var _city_view := false
var city_view_data: Dictionary = {}  # getCity result for the city on the table
var _saved_view: Array = []         # [view_center, view_radius] to go back to on leaving
var _big_was_shown := false
var _city_tile_armed := Vector2i(999999, 999999)
var overview_board: OverviewBoard    # Unciv's Empire Overview (stats and info)
var settings_board: SettingsBoard    # Settings (Unciv's Options)
var _settings_holder: Node           # WorldPanel (VR) or CanvasLayer (desktop)
var _uncivVersion := ""
var _bridge_protocol := 0
var _overview_holder: Node           # WorldPanel (VR) or CanvasLayer (desktop)
var keyboard: Keyboard               # on-screen keyboard for names (see open_keyboard)
var _keyboard_holder: Node           # WorldPanel (VR: on the left wrist or floating) or CanvasLayer (desktop)
var _keyboard_on_submit := Callable()
var _overview_was_shown := false   # a buyable tile clicked once (the next click buys it)
var _pick: Dictionary = {}          # waiting for a tile click: {kind: unit_action / bombard / move, targets, ...}
# Pressing on a tile: a short press clicks it, a long one aims at it (see _hold_tile_press)
var _press_ms := 0                  # when the trigger / left mouse button went down
var _press_key: Variant = null      # the tile it went down on, or null (it went down somewhere else)
var _long_pressed := false          # the press has already aimed, so letting go mustn't click as well
var _forced_aim := HexMap.NO_TILE   # a tile a long press aimed at: a click there moves, whoever stands on it
var _move_hint_shown := false       # the "hold to move onto a tile" hint has been shown once
var _busy_since := 0                # when `busy` went true with no request out (0: not waiting)
var _city_place: Dictionary = {}    # city view: a building that creates an improvement waits for its tile
var _alert_shown_key := ""          # the Unciv popup (alert) on show, by key
var alert_menu: ActionMenu          # desktop: a card in the middle of the window for Unciv's popups and pickers
var _alert_layer: CanvasLayer
var _end_turn_armed_until := 0      # "Ask for confirmation when ending the turn": a second press before this ends it
var _yields_pending := false      # a getYields request is out
var _yields_again := false        # the view changed while it was out
var _table_buttons: Array[Dictionary] = []   # {id, node, material, color}
var _hovered_button := ""
var table_model: TableModel   # the table's top, column and feet (tables/<Name>)
var _launched_bridge := false
var _initialized := false
var _state_revision := -1          # getState revision we last merged; -1 = ask for everything
var _tile_cache: Dictionary = {}   # Vector2i -> tile, kept up to date from getState deltas
var _last_tiles_received := 0
var _in_lobby := false            # the main menu is up (no game on the table)
var _lobby_info: Dictionary = {}
var _setup: Dictionary = {}       # new-game choices being edited (getSetup fields)
var _setup_options: Dictionary = {}   # listOptions
var _setup_tab := "you"
var _saves: Array = []

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
var minimap: Minimap
var info_panel: InfoPanel
var big_screen: BigScreen
var _big_holder: Node                # the WorldPanel (VR) or CanvasLayer (desktop) showing big_screen
var _info_holder: Node              # the WorldPanel (VR) or CanvasLayer (desktop) showing info_panel
var _info_key: Variant = null       # tile shown in the info panel
var _info_wait := 0.0               # seconds the pointer has rested on _info_key
var _info_requested := false        # getTile already asked for _info_key
var _pointed_minimap: Variant = null   # world point (wx, wy) the laser is on in the overview, or null
var _grab_last := {}
var _right_trigger_used_for_zoom := false

# Dragging the overview or the info board to a new spot (VR: right trigger; desktop: left mouse)
const MINIMAP_HOME := [0.0, 0.25, -0.95, 0.0]
const INFO_HOME := [0.56, 0.36, -0.82, -16.0]
const WIDE_HOME := [0.0, 1.0, -1.05, 0.0]   # the big screen, above the other two
const CITY_INFO_HOME := [-0.98, 0.45, -0.45, 34.0]    # city view: the city's board, left of the table
const CITY_PROD_HOME := [0.98, 0.45, -0.45, -34.0]    # ... and the production board on the right
const OVERVIEW_HOME := [1.4, 0.55, 0.8, -88.0]       # the empire overview: off to your right (look right to read it)
const SETTINGS_HOME := [0.0, 0.47, -0.45, 0.0]       # settings: floating over the far half of the table
const BOARD_TILT := {"minimap": -20.0, "info": -18.0, "wide": 8.0, "city_info": 0.0, "city_prod": 0.0, "overview": 0.0, "settings": -8.0}
var _drag_id := ""               # "minimap" or "info" while one is held
var _drag_distance := 0.0        # along the pointer ray, from where it was grabbed
var _drag_offset := Vector3.ZERO # grab point -> board origin, in global space
var _drag_start := Vector3.ZERO
var _drag_moved := false
var _view_tween: Tween   # hand -> its last global position while its grip drags the map
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
var _playback_active := false   # other players' moves and battles are being played back (End turn skips them)
var _skip_playback := false
const PLAYBACK_SPEEDS := {"normal": 1.0, "fast": 2.5}


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
	if options.has("tileset"):   # dev aid for screenshots (--tileset=LowPoly or classic); not saved
		settings["tileset"] = options["tileset"]
	hex_map.set_tileset(str(settings["tileset"]))
	if options.has("unitset"):   # dev aid (--unitset=none, tileset or a tileset folder); not saved
		settings["unitset"] = options["unitset"]
	hex_map.set_unitset(str(settings["unitset"]))
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
	if options.has("table"):   # dev aid for screenshots (--table=OrnateOak); not saved
		settings["table"] = options["table"]
	table_model = TableModel.new()
	table_model.name = "TableModel"
	add_child(table_model)
	table_model.apply(str(settings["table"]), table)
	_update_pedestal()
	minimap = Minimap.new()
	minimap.name = "Minimap"
	table.add_child(minimap)
	minimap.setup(hex_map)
	# Stands at the far edge of the table, leaning back a little so it faces you
	minimap.visible = false
	var defaults := {"movement": false, "yields": false, "worked": false, "resources": true, "improvements": true, "unit_icons": true}
	if not settings["overlays"] is Dictionary:
		settings["overlays"] = defaults
	for id: String in defaults:
		if not settings["overlays"].has(id):
			settings["overlays"][id] = defaults[id]
	if options.has("overlays"):   # dev aid for screenshots (--overlays=all or e.g. movement,yields); not saved
		var wanted: Array = defaults.keys() if options["overlays"] == "all" else str(options["overlays"]).split(",")
		settings["overlays"] = {}
		for id: String in defaults:
			settings["overlays"][id] = id in wanted
	minimap.set_overlay_states(settings["overlays"])
	hex_map.set_overlay_flags(settings["overlays"])
	hex_map.view_rebuilt.connect(_on_view_rebuilt)
	_setup_info_panel()
	_setup_big_screen()
	_setup_city_boards()
	_setup_overview_board()
	_setup_settings_board()
	_setup_keyboard()
	_apply_board_poses()

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
	if bridge.is_bridge_connected() or (_launched_bridge and OS.is_process_running(launcher.pid)):
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


## Stops an out-of-date bridge we found already running and starts a fresh one from the current code.
func _replace_old_bridge(protocol: int, game_running: bool) -> void:
	_set_status("An older Unciv bridge (protocol v%d) was still running - restarting it with the current code..." % protocol)
	if game_running:   # keep the game it was running: it's what "Continue" offers next
		await bridge.request("saveGame", {"name": "Autosave"})
	bridge.send_shutdown()
	var deadline := Time.get_ticks_msec() + 5000
	while bridge.is_connection_open() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	# Let its Gradle launcher finish too, so the log file is free for the new one
	await get_tree().create_timer(3.0).timeout
	if bridge.is_bridge_connected():
		# Still there (shutdown not supported, or it's somebody else's): use it as it is
		_set_status("Couldn't stop the old bridge - carrying on with it. Some things may not work.")
		return
	_maybe_launch_bridge()


func _exit_tree() -> void:
	# Only stop a bridge we started; one started by hand keeps running for the next session
	# (--stop-bridge stops whichever bridge we're connected to - a dev aid for cleaning up after tests).
	if _launched_bridge or options.has("stop-bridge"):
		bridge.send_shutdown()
		# Give the bridge a moment to receive the message and exit on its own before the Gradle
		# launcher is killed (killing it first can cut the bridge off mid-way).
		var deadline := Time.get_ticks_msec() + 4000   # it saves the game before exiting
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
		if _in_lobby:
			await open_lobby()
		else:
			await _send_bridge_settings()
			await refresh()
		return
	var ping := await bridge.request("ping")
	if not ping.ok:
		_set_status("Bridge error: %s" % ping.error)
		return
	var protocol := int(ping.result.get("protocol", 0))
	if protocol != BRIDGE_PROTOCOL:
		# Most likely a bridge left running by an earlier session (force-stopped from the editor, or a crash),
		# still serving old code. Replace it with one built from the current code - once; if that doesn't
		# match either, the two repos are out of step and we carry on with a warning.
		if not options.has("no-launch") and not _replaced_old_bridge:
			_replaced_old_bridge = true
			await _replace_old_bridge(protocol, bool(ping.result.get("gameRunning", false)))
			return
		_set_status("Warning: the bridge speaks protocol v%d but this client expects v%d - update both repos together. Some things may not work." % [protocol, BRIDGE_PROTOCOL])
		await get_tree().create_timer(3.0).timeout
	_set_status("Connected to Unciv %s" % ping.result.uncivVersion)
	_uncivVersion = str(ping.result.uncivVersion)
	_bridge_protocol = protocol

	# Dev shortcuts skip the main menu; so does a game the bridge is already running (one started by hand)
	if options.has("load"):   # a test save; res:// paths work (tests/saves/...), and it never replaces your autosave
		var load_path := str(options["load"])
		if load_path.begins_with("res://"):
			load_path = ProjectSettings.globalize_path(load_path)
		var loaded := await bridge.request("loadGame", {"path": load_path, "remember": false})
		if not loaded.ok:
			_set_status("Couldn't load the save: %s" % loaded.error)
			return
		await _enter_game()
	elif options.has("new-game") or options.has("smoke-test"):
		var params := {
			"mapSize": options.get("map-size", "Tiny"),
			"aiPlayers": int(options.get("ai", 3)),
			"cityStates": 4,
			"civ": options.get("civ", "Random"),
		}
		params["remember"] = false   # dev shortcut: don't change Quick start or the autosave
		if options.has("smoke-test"):
			params["seed"] = 42
		if not await _start_new_game(params):
			return
	elif ping.result.gameRunning and not options.has("lobby"):
		await _enter_game()
	else:
		await open_lobby()

	if options.has("smoke-test"):
		await _run_smoke_test()
	if options.has("scenario"):   # dev aid: see dev_scenarios.gd (needs a bridge started with --debug)
		var scenarios: RefCounted = load("res://scripts/dev_scenarios.gd").new(self)
		await scenarios.run(str(options["scenario"]))
		for step: String in str(options.get("then", "")).split(",", false):
			var bits := step.split(":")
			if bits.size() > 1:
				await scenarios.call(bits[0], bits[1])
			else:
				await scenarios.call(bits[0])
	match options.get("show", ""):   # dev aid for screenshots: --show=city or --show=research
		"overview-cities", "overview-stats", "overview-trades", "overview-units", "overview-politics", "overview-diagram", "overview-resources", "overview-religion", "overview-wonders", "overview-notifications":
			var ov_tab: String = str(options["show"]).trim_prefix("overview-")
			if ov_tab == "diagram":
				ov_tab = "politics"
				overview_board.show_diagram = true
			_set_overview_visible(true)
			overview_board.show_tab(ov_tab)
			await _refresh_overview()
		"cityview", "cityview-tile":
			if not state.get("cities", []).is_empty():
				await enter_city_view(str(state["cities"][0]["name"]))
				var queue: Array = city_view_data.get("queue", [])
				var pick: String = queue[0]["name"] if not queue.is_empty() else "Monument"
				await _select_city_construction(pick, 0 if not queue.is_empty() else -1)
				if options["show"] == "cityview-tile":
					for t: Dictionary in city_view_data.get("tiles", []):
						if t["state"] == "buyable":
							await city_view_click(Vector2i(int(t["x"]), int(t["y"])))
							break
				else:
					for t: Dictionary in city_view_data.get("tiles", []):
						if t["state"] == "worked":
							city_info_board.select_tile(Vector2i(int(t["x"]), int(t["y"])), hex_map.tiles.get(Vector2i(int(t["x"]), int(t["y"])), {}))
							break
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
		"keyboard":
			if not state.get("units", []).is_empty():
				await _select_unit(int(state["units"][0]["id"]))
				await rename_unit(int(state["units"][0]["id"]))
			if keyboard_shown():
				for character in "scout bo":
					keyboard._type(character)   # something in the field for the screenshot
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
		"setup", "setup-world", "setup-rules":
			_setup_tab = {"setup": "you", "setup-world": "world", "setup-rules": "rules"}[options["show"]]
			_show_lobby_card("setup")
		"saves":
			_show_lobby_card("saves")
		"tech", "policies", "diplomacy":
			await show_big_screen(options["show"])
			if options["show"] == "tech":
				var open_techs: Array = big_screen._techs.get("techs", []).filter(func(t: Dictionary) -> bool: return t.get("researchable", false))
				if not open_techs.is_empty():
					await _on_big_screen_chosen("tech_select", open_techs[0]["name"])
			if options["show"] == "policies" and not big_screen._policies.get("branches", []).is_empty():
				await _on_big_screen_chosen("policy_select", big_screen._policies["branches"][0]["name"])
		"trade":
			await show_big_screen("diplomacy")
			var majors: Array = big_screen._diplomacy.get("civs", []).filter(func(c: Dictionary) -> bool: return not c.get("isCityState", false))
			if not majors.is_empty():
				await _on_big_screen_chosen("trade_open", majors[0]["name"])
				var their: Array = big_screen._trade_options.get("theirs", [])
				var ours: Array = big_screen._trade_options.get("ours", [])
				if their.size() > 1:
					big_screen._move_trade_item(their[1], big_screen.trade_theirs, true)
				if not ours.is_empty():
					big_screen._move_trade_item(ours[0], big_screen.trade_ours, true)
				await get_tree().create_timer(0.5).timeout
	if options.has("screenshot"):
		await get_tree().create_timer(1.0).timeout   # let the table recenter and cards lay out
		if options.has("fake-look") and _xr_camera != null:   # dev aid: turn the fake head after recentering
			_xr_camera.rotation_degrees.y += float(options["fake-look"])
			await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png(options["screenshot"])
		print("Saved screenshot to %s" % options["screenshot"])
		get_tree().quit()


## Puts whatever game the bridge is running on the table and starts play.
func _enter_game() -> void:
	_in_lobby = false
	action_menu.lobby_mode = false
	if popup_menu != null:
		popup_menu.lobby_mode = false
	_deselect()
	hex_map.forget_unit_positions()   # unit ids in another game are other units
	_state_revision = -1   # a different game: fetch every tile
	_tile_cache.clear()
	hex_map.visible = true
	_set_table_buttons_visible(true)
	_set_info_visible(true)
	_set_big_visible(_xr_mode)   # VR: always up; desktop: opened with T / P / G
	_set_overview_visible(_xr_mode)   # VR: off to your right; desktop: E opens it
	await _send_bridge_settings()
	var rules := await bridge.request("getRuleset")
	if rules.ok:
		hex_map.set_ruleset(rules.result)
	await refresh()
	_setup_view()
	_fit_table()
	_initialized = true
	_set_status("Your move.")
	if _xr_mode:
		# Give tracking a moment to settle, then put the table in front of wherever the player is
		get_tree().create_timer(0.5).timeout.connect(recenter_table)
	await _select_next_unit()
	await _prompt_research_if_needed()


## newGame with [param params]; on success the game goes on the table. Returns whether it worked.
func _start_new_game(params: Dictionary) -> bool:
	_set_status("Starting a new game... (bigger maps take a little longer)")
	_show_lobby_status("Starting a new game...")
	var started := await bridge.request("newGame", params)
	if not started.ok:
		_set_status("Couldn't start a game: %s" % started.error)
		if _in_lobby:
			_show_lobby_card("lobby")
		return false
	await _enter_game()
	return true


# region main menu (lobby) -----------------------------------------------------------------

## The main menu: Resume / Continue / Quick start / New game / Load, floating over an empty table.
func open_lobby() -> void:
	_in_lobby = true
	action_menu.lobby_mode = true
	if popup_menu != null:
		popup_menu.lobby_mode = true
	# Nothing of the game stays up over the menu: popups come back (from the game's state) on Resume
	if _city_view:
		await exit_city_view()
	if keyboard_shown():
		_close_keyboard()
	_close_alert_card()
	_deselect()
	hex_map.visible = false
	minimap.visible = false
	_set_table_buttons_visible(false)
	_set_info_visible(false)
	_set_big_visible(false)
	_set_overview_visible(false)
	_info_key = null
	var ping := await bridge.request("ping")
	var saves_reply := await bridge.request("listSaves")
	var setup_reply := await bridge.request("getSetup")
	_saves = saves_reply.result.get("saves", []) if saves_reply.ok else []
	if setup_reply.ok:
		_setup = setup_reply.result.get("setup", {})
	if _setup_options.is_empty():
		var options_reply := await bridge.request("listOptions", {"ruleset": _setup.get("ruleset", "")} if _setup.has("ruleset") else {})
		if options_reply.ok:
			_setup_options = options_reply.result
	var autosave := ""
	var autosave_text := ""
	for save: Dictionary in _saves:
		if save.get("autosave", false):
			autosave = save["name"]
			autosave_text = "saved " + ActionMenu.local_time_text(float(save.get("modified", 0)))
			break
	var running: bool = ping.ok and ping.result.get("gameRunning", false) and _initialized and not state.is_empty()
	_lobby_info = {
		"running": running,
		"running_text": "%s, turn %d" % [state.get("playerCiv", "?"), int(state.get("turn", 0))] if running else "",
		"autosave": autosave,
		"autosave_text": autosave_text,
		"quick_text": _describe_setup(_setup),
		"has_saves": not _saves.is_empty(),
	}
	_set_status("Main menu")
	if _xr_mode:
		action_menu.show_lobby({"busy": true, "quick_text": "Main menu: point at the card over the table."})
	_show_lobby_card("lobby")


func _describe_setup(setup: Dictionary) -> String:
	if setup.is_empty():
		return ""
	return "%s on a %s %s map, %s, %d AI, %d city-states" % [
		"A random civilization" if setup.get("civ", "Random") == "Random" else str(setup["civ"]),
		setup.get("mapSize", "?"), setup.get("mapType", ""), setup.get("difficulty", "?"),
		int(setup.get("aiPlayers", 0)), int(setup.get("cityStates", 0))]


## Shows one of the main-menu cards: "lobby", "setup" or "saves" (over the table in VR, the side card on desktop).
func _show_lobby_card(kind: String) -> void:
	var menu: ActionMenu = popup_menu if _xr_mode else action_menu
	match kind:
		"lobby":
			menu.show_lobby(_lobby_info)
		"setup":
			menu.show_setup(_setup, _setup_options, _setup_tab)
		"saves":
			menu.show_saves(_saves)
	if _xr_mode:
		_popup_kind = "lobby"
		_update_popup_panel()


## A one-line card while something slow happens (starting or loading a game).
func _show_lobby_status(text: String) -> void:
	if not _in_lobby:
		return
	var menu: ActionMenu = popup_menu if _xr_mode else action_menu
	menu.show_lobby({"quick_text": text, "busy": true})


func _on_lobby_choice(kind: String, value: String) -> void:
	match kind:
		"lobby":
			_show_lobby_card("lobby")
		"lobby_resume":
			await _enter_game()
		"lobby_continue", "load_save":
			_show_lobby_status("Loading %s..." % value)
			var loaded := await bridge.request("loadGame", {"name": value})
			if not loaded.ok:
				_set_status("Couldn't load %s: %s" % [value, loaded.error])
				_show_lobby_card("lobby")
				return
			await _enter_game()
		"lobby_quick":
			await _start_new_game(_setup)
		"lobby_new":
			_setup_tab = "you"
			_show_lobby_card("setup")
		"lobby_load":
			_show_lobby_card("saves")
		"setup_tab":
			_setup_tab = value
			_show_lobby_card("setup")
		"setup_set":
			_keep_card_scroll()
			var parts := value.split("|", true, 1)
			_setup[parts[0]] = parts[1]
			_show_lobby_card("setup")
		"setup_toggle":
			_keep_card_scroll()
			if value.begins_with("victory|"):
				var victory := value.substr(8)
				var picked: Array = _setup.get("victoryTypes", []).duplicate()
				if picked.is_empty():
					picked = _setup_options.get("victoryTypes", []).duplicate()   # empty means all
				if victory in picked:
					picked.erase(victory)
				else:
					picked.append(victory)
				_setup["victoryTypes"] = picked
			else:
				_setup[value] = not _setup.get(value, false)
			_show_lobby_card("setup")
		"setup_step":
			_keep_card_scroll()
			var parts := value.split("|")
			var limits := {"aiPlayers": Vector2i(1, maxi(1, _setup_options.get("nations", []).size() - 1)),
				"cityStates": Vector2i(0, int(_setup_options.get("cityStatesAvailable", 0)))}
			var bounds: Vector2i = limits.get(parts[0], Vector2i(0, 99))
			_setup[parts[0]] = clampi(int(_setup.get(parts[0], 0)) + int(parts[1]), bounds.x, bounds.y)
			_show_lobby_card("setup")
		"setup_start":
			await _start_new_game(_setup)
		"quit":
			get_tree().quit()


## The next rebuild of the main-menu card keeps its scroll position (changing an option shouldn't jump to the top).
func _keep_card_scroll() -> void:
	(popup_menu if _xr_mode else action_menu).keep_scroll_once = true


## Desktop: T / P / G open the big screen on that tab, or close it if it's already showing that tab.
func _toggle_big_screen(tab: String) -> void:
	if _big_screen_shown() and big_screen.tab == tab and not _xr_mode:
		_set_big_visible(false)
	else:
		await show_big_screen(tab)


## Shows / hides the table rim buttons. The city view has only its red Exit city button; the map has the rest.
func _set_table_buttons_visible(shown: bool) -> void:
	for button: Dictionary in _table_buttons:
		var city_only: bool = button["id"] == "exit_city"
		(button["node"] as Node3D).visible = shown and city_only == _city_view


func refresh() -> void:
	# Ask only for what changed since the last update (the bridge sends every tile when it can't tell)
	var params := {}
	if _state_revision >= 0:
		params["since"] = _state_revision
	var reply := await bridge.request("getState", params)
	if not reply.ok:
		_set_status("getState failed: %s" % reply.error)
		return
	var new_state: Dictionary = reply.result
	if new_state.get("full", true):
		_tile_cache.clear()
	_last_tiles_received = new_state.get("tiles", []).size()
	for tile: Dictionary in new_state.get("tiles", []):
		_tile_cache[Vector2i(int(tile["x"]), int(tile["y"]))] = tile
	new_state["tiles"] = _tile_cache.values()
	_state_revision = int(new_state.get("revision", -1))
	state = new_state
	hex_map.build(state)
	action_menu.civ_colors = hex_map.civ_colors
	var civ_info := {}
	for civ: Dictionary in state.get("civs", []):
		civ_info[civ["name"]] = civ
	action_menu.civ_info = civ_info
	if popup_menu != null:
		popup_menu.civ_colors = hex_map.civ_colors
		popup_menu.civ_info = civ_info
	if alert_menu != null:
		alert_menu.civ_info = civ_info
	_update_minimap()
	_refresh_big_screen()   # not awaited: the screen catches up a moment later
	_refresh_overview()
	if info_panel != null:
		info_panel.show_civ(state, hex_map.civ_colors)
		if _info_key != null:   # the tile may have changed (a unit moved in, a road got built...)
			var key: Variant = _info_key
			_info_key = null
			_show_tile_info(key)
	if not selected_unit.is_empty():
		await _select_unit(int(selected_unit["id"]), false)
	_update_turn_button()
	_maybe_show_alert()
	_update_hud()


## Big maps start with a window centred on your capital (or first unit); Tiny ones show whole.
## Either way trigger + stick zooms between the two.
func _setup_view() -> void:
	if hex_map.full_extent <= 20.0:   # Tiny maps fit whole
		hex_map.set_view(hex_map.full_center, hex_map.full_extent)
		_update_minimap()
		return
	var home := Vector2i(999999, 999999)
	if not state.get("cities", []).is_empty():
		home = Vector2i(int(state["cities"][0]["x"]), int(state["cities"][0]["y"]))
	elif not state.get("units", []).is_empty():
		home = Vector2i(int(state["units"][0]["x"]), int(state["units"][0]["y"]))
	hex_map.set_view(hex_map._world_of(home) if hex_map.tiles.has(home) else hex_map.full_center, VIEW_RADIUS_DEFAULT)
	_update_minimap()


## The colourful board with your civ's numbers and the pointed-at tile: next to the overview in VR,
## bottom-left on the desktop.
func _setup_info_panel() -> void:
	info_panel = InfoPanel.new()
	if _xr_mode:
		var panel := WorldPanel.new()
		panel.name = "InfoPanel"
		panel.setup(info_panel, INFO_PANEL_PIXELS, INFO_PANEL_METRES)
		table.add_child(panel)   # placed by _apply_board_poses: at the far edge, right of the overview
		# Hang the board from its bottom edge so it doesn't float in mid-air when it's short
		info_panel.resized.connect(func() -> void:
			info_panel.position = Vector2(0, INFO_PANEL_PIXELS.y - info_panel.size.y))
		_info_holder = panel
	else:
		var layer := CanvasLayer.new()
		add_child(layer)
		layer.add_child(info_panel)
		var place := func() -> void:
			info_panel.reset_size()
			info_panel.position = Vector2(12, get_viewport().get_visible_rect().size.y - info_panel.size.y - 12)
		info_panel.resized.connect(place)
		get_viewport().size_changed.connect(place)
		_info_holder = layer
	_set_info_visible(false)


# region movable boards ----------------------------------------------------------------------

## Puts the overview and the info board where you last left them (or their default spots).
func _apply_board_poses() -> void:
	for id: String in ["minimap", "info", "wide", "city_info", "city_prod", "overview", "settings"]:
		var node := _board_node(id)
		if node == null:
			continue
		var pose: Array = settings.get(id + "_pose", [])
		if pose.size() != 4:
			pose = {"minimap": MINIMAP_HOME, "info": INFO_HOME, "wide": WIDE_HOME,
				"city_info": CITY_INFO_HOME, "city_prod": CITY_PROD_HOME, "overview": OVERVIEW_HOME, "settings": SETTINGS_HOME}[id]
		node.position = Vector3(float(pose[0]), float(pose[1]), float(pose[2]))
		node.rotation_degrees = Vector3(BOARD_TILT[id], float(pose[3]), 0)


func _board_node(id: String) -> Node3D:
	match id:
		"minimap":
			return minimap
		"wide":
			return _big_holder as Node3D if _big_holder is Node3D else null
		"city_info":
			return _city_info_holder as Node3D if _city_info_holder is Node3D else null
		"city_prod":
			return _city_prod_holder as Node3D if _city_prod_holder is Node3D else null
		"overview":
			return _overview_holder as Node3D if _overview_holder is Node3D else null
		"settings":
			return _settings_holder as Node3D if _settings_holder is Node3D else null
	return _info_holder as Node3D if _info_holder is Node3D else null


## The board a pointer ray is on: [id, global hit point], or [] if none. The nearer one wins.
func _board_at(origin: Vector3, direction: Vector3) -> Array:
	var best: Array = []
	var best_distance := INF
	var hits := {}
	if minimap != null:
		hits["minimap"] = minimap.ray_hit_point(origin, direction)
	if _info_holder is WorldPanel and (_info_holder as Node3D).is_visible_in_tree():
		var hit: Variant = (_info_holder as WorldPanel).ray_hit(origin, direction)
		hits["info"] = hit[0] if hit != null else null
	if _big_holder is WorldPanel and (_big_holder as Node3D).is_visible_in_tree():
		# The big screen is full of buttons, so only its handle strip along the top grabs it
		var hit: Variant = (_big_holder as WorldPanel).ray_hit(origin, direction)
		hits["wide"] = hit[0] if hit != null and big_screen.grab_bar_contains(hit[1]) else null
	for pair: Array in [["city_info", _city_info_holder, city_info_board], ["city_prod", _city_prod_holder, city_prod_board],
			["overview", _overview_holder, overview_board], ["settings", _settings_holder, settings_board]]:
		if pair[1] is WorldPanel and (pair[1] as Node3D).is_visible_in_tree():
			var hit: Variant = (pair[1] as WorldPanel).ray_hit(origin, direction)
			hits[pair[0]] = hit[0] if hit != null and pair[2].grab_bar_contains(hit[1]) else null
	for id: String in hits:
		if hits[id] != null and origin.distance_to(hits[id]) < best_distance:
			best_distance = origin.distance_to(hits[id])
			best = [id, hits[id]]
	return best


func _begin_board_drag(origin: Vector3, direction: Vector3) -> bool:
	var hit := _board_at(origin, direction)
	if hit.is_empty():
		return false
	_drag_id = hit[0]
	_drag_start = hit[1]
	_drag_distance = origin.distance_to(hit[1])
	_drag_offset = _board_node(_drag_id).global_position - _drag_start
	_drag_moved = false
	return true


## Moves the held board along with the pointer; it keeps facing you (yaw only) as it goes.
func _update_board_drag(origin: Vector3, direction: Vector3) -> void:
	if _drag_id == "":
		return
	var point := origin + direction.normalized() * _drag_distance
	if not _drag_moved and point.distance_to(_drag_start) < 0.02:
		return   # still just a click
	_drag_moved = true
	var node := _board_node(_drag_id)
	node.global_position = point + _drag_offset
	var viewer := _xr_camera.global_position if _xr_mode else _camera.global_position
	var to_viewer := table.to_local(viewer) - node.position
	node.rotation_degrees = Vector3(BOARD_TILT[_drag_id], rad_to_deg(atan2(to_viewer.x, to_viewer.z)), 0)


## Lets go of the board. Returns true if it was moved (a drag), false if it was just a click.
func _end_board_drag() -> bool:
	if _drag_id == "":
		return false
	var moved := _drag_moved
	if moved:
		var node := _board_node(_drag_id)
		settings[_drag_id + "_pose"] = [node.position.x, node.position.y, node.position.z, node.rotation_degrees.y]
		_save_settings()
	_drag_id = ""
	_drag_moved = false
	return moved


func reset_board_poses() -> void:
	settings["minimap_pose"] = []
	settings["info_pose"] = []
	settings["wide_pose"] = []
	settings["city_info_pose"] = []
	settings["city_prod_pose"] = []
	settings["overview_pose"] = []
	settings["settings_pose"] = []
	_save_settings()
	_apply_board_poses()
	_set_status("The overview, info board and big screen are back in their usual spots.")


## The big wide screen with the tech tree, policies and diplomacy: above the overview in VR; on the desktop
## a window in the middle that T / P / G open and Esc closes.
func _setup_big_screen() -> void:
	big_screen = BigScreen.new()
	big_screen.chosen.connect(_on_big_screen_chosen)
	if _xr_mode:
		var panel := WorldPanel.new()
		panel.name = "BigScreen"
		panel.setup(big_screen, Vector2i(BigScreen.SIZE), BIG_SCREEN_METRES)
		table.add_child(panel)   # placed by _apply_board_poses
		_big_holder = panel
	else:
		var layer := CanvasLayer.new()
		layer.layer = 2
		add_child(layer)
		layer.add_child(big_screen)
		var place := func() -> void:
			var window := get_viewport().get_visible_rect().size
			var fit := minf(1.0, (window.x - 40.0) / BigScreen.SIZE.x)
			big_screen.scale = Vector2(fit, fit)
			big_screen.position = Vector2((window.x - BigScreen.SIZE.x * fit) / 2.0, 70)
		get_viewport().size_changed.connect(place)
		place.call()
		_big_holder = layer
	_set_big_visible(false)


func _set_big_visible(shown: bool) -> void:
	if _big_holder is CanvasLayer:
		(_big_holder as CanvasLayer).visible = shown
	elif _big_holder != null:
		(_big_holder as Node3D).visible = shown


func _big_screen_shown() -> bool:
	if _big_holder is CanvasLayer:
		return (_big_holder as CanvasLayer).visible
	return _big_holder != null and (_big_holder as Node3D).visible


## Switches the big screen to a tab (tech / policies / diplomacy), shows it, and loads that tab's data.
func show_big_screen(tab: String) -> void:
	if _in_lobby or big_screen == null:
		return
	_set_big_visible(true)
	big_screen.show_tab(tab)
	await _refresh_big_screen()


## Reloads the data on the big screen's current tab (after anything that may have changed it).
func _refresh_big_screen() -> void:
	if big_screen == null or _in_lobby or not _big_screen_shown():
		return
	match big_screen.tab:
		"tech":
			var reply := await bridge.request("getTechs")
			if reply.ok:
				big_screen.set_techs(reply.result)
		"policies":
			var reply := await bridge.request("getPolicies")
			if reply.ok:
				big_screen.set_policies(reply.result)
		"diplomacy":
			var reply := await bridge.request("getDiplomacy")
			if reply.ok:
				big_screen.set_diplomacy(reply.result)
		"religion":
			var reply := await bridge.request("getReligionChoices")
			if reply.ok:
				big_screen.set_religion(reply.result)
		"victory":
			var reply := await bridge.request("getVictory")
			if reply.ok:
				big_screen.set_victory(reply.result)


func _on_big_screen_chosen(kind: String, value: String) -> void:
	match kind:
		"big_tab":
			big_screen.war_armed = ""
			big_screen.diplo_armed = ""
			big_screen.trade_civ = ""
			big_screen.civ_detail = ""
			await show_big_screen(value)
		"civ_open":
			big_screen.civ_detail = value
			big_screen.diplo_armed = ""
			big_screen.set_diplomacy(big_screen._diplomacy)
		"civ_close":
			big_screen.civ_detail = ""
			big_screen.diplo_armed = ""
			big_screen.set_diplomacy(big_screen._diplomacy)
		"diplo_arm":
			big_screen.diplo_armed = value
			big_screen.set_diplomacy(big_screen._diplomacy)
		"diplo_action":
			await diplomacy_action(value)
		"look_at":
			var xy := value.split(",")
			_look_at_tile(Vector2i(int(xy[0]), int(xy[1])))
		"religion_slot":
			big_screen.religion_slot = int(value)
			big_screen.set_religion(big_screen._religion)
		"religion_belief":
			var slot: int = big_screen.religion_slot
			if slot < big_screen.religion_picks.size():
				big_screen.religion_picks[slot] = value
				# move on to the next empty slot
				var next: int = big_screen.religion_picks.find("")
				if next >= 0:
					big_screen.religion_slot = next
			big_screen.set_religion(big_screen._religion)
		"religion_icon":
			big_screen.religion_icon = value
			if big_screen.religion_name == "":
				big_screen.religion_name = value
			big_screen.set_religion(big_screen._religion)
		"religion_name":
			open_keyboard("Name your religion", big_screen.religion_name, func(text: String) -> void:
				if text != "":
					big_screen.religion_name = text
					big_screen.set_religion(big_screen._religion))
		"religion_confirm":
			var reply := await _order("chooseReligion", big_screen.religion_choice())
			if reply.has("_busy"):
				return
			if not reply.ok:
				_set_status(reply.error)
				return
			_set_status("%s: %s" % [reply.result.get("displayName", "Your religion"), ", ".join(big_screen.religion_picks)])
			big_screen._religion = {}
			big_screen.set_religion(reply.result)
			await refresh()
		"victory_page":
			big_screen.victory_page = value
			big_screen.set_victory(big_screen._victory)
		"chart_type":
			big_screen.chart_type = value
			big_screen.set_victory(big_screen._victory)
		"one_more_turn":
			var reply := await _order("oneMoreTurn")
			if reply.has("_busy"):
				return
			if reply.ok:
				big_screen.set_victory(reply.result)
				_set_big_visible(false)
				_set_status("One more turn...!")
				await refresh()
		"main_menu":
			_set_big_visible(false)
			await open_lobby()
		"tech_select":
			big_screen.selected_tech = value
			big_screen._tech_description = ""
			big_screen.set_techs(big_screen._techs)
			var described := await bridge.request("describeTech", {"tech": value})
			if described.ok:
				big_screen.set_tech_detail(value, str(described.result.get("description", "")))
		"research":
			var reply := await bridge.request("setResearch", {"tech": value})
			if not reply.ok:
				_set_status(reply.error)
				return
			_set_status("Researching %s." % reply.result.get("current", value))
			big_screen.set_techs(reply.result)
			await refresh()
		"policy_select":
			big_screen.selected_policy = value
			big_screen.set_policies(big_screen._policies)
		"adopt_policy":
			var reply := await _order("adoptPolicy", {"policy": value})
			if reply.has("_busy"):
				return
			if not reply.ok:
				_set_status(reply.error)
				return
			_set_status("Adopted %s." % value)
			big_screen.set_policies(reply.result)
			await refresh()
		"war_arm":
			big_screen.war_armed = value   # the button now asks for a second click to confirm
			big_screen.set_diplomacy(big_screen._diplomacy)
		"declare_war":
			big_screen.war_armed = ""
			var reply := await _order("declareWar", {"civ": value})
			if reply.has("_busy"):
				return
			if not reply.ok:
				_set_status(reply.error)
				return
			_set_status("You declared war on %s!" % value)
			big_screen.set_diplomacy(reply.result)
			await refresh()
		"trade_open":
			big_screen.order_trade_by_amount = settings.get("orderTradeOffersByAmount", true)
			var reply := await bridge.request("getTradeOptions", {"civ": value})
			if not reply.ok:
				_set_status(reply.error)
				return
			big_screen.open_trade(reply.result)
		"trade_changed":
			if big_screen.trade_ours.is_empty() and big_screen.trade_theirs.is_empty():
				big_screen.set_trade_verdict({})
				return
			var reply := await bridge.request("evaluateTrade", _trade_params())
			big_screen.set_trade_verdict(reply.result if reply.ok else {"message": reply.error})
		"trade_propose":
			var reply := await _order("proposeTrade", _trade_params())
			if reply.has("_busy"):
				return
			if not reply.ok:
				big_screen.set_trade_verdict({"message": reply.error})
				return
			_set_status(reply.result.get("message", ""))
			if reply.result.get("accepted", false):
				big_screen._diplomacy = reply.result.get("diplomacy", big_screen._diplomacy)
				big_screen.close_trade()
				await refresh()
			elif reply.result.get("counteroffer", false):
				# Their counteroffer comes up as one of their trade requests (accept / decline / change it)
				big_screen._diplomacy = reply.result.get("diplomacy", big_screen._diplomacy)
				big_screen.close_trade()
				await refresh()
			else:
				big_screen.set_trade_verdict({"message": reply.result.get("message", ""), "accepted": false})
		"offer_peace":
			var reply := await _order("offerPeace", {"civ": value})
			if reply.has("_busy"):
				return
			if not reply.ok:
				_set_status(reply.error)
				return
			_set_status(reply.result.get("message", ""))
			big_screen.set_diplomacy(reply.result.get("diplomacy", {}))
			await refresh()


## A request that changes the game, from a button: ignored while another one is under way, so a double click
## (or a bounce of the trigger) can't buy, trade or adopt twice. Returns {"_busy": true} when ignored.
func _order(method: String, params: Dictionary = {}) -> Dictionary:
	if busy:
		return {"ok": false, "_busy": true, "error": "busy"}
	busy = true
	var reply := await bridge.request(method, params)
	busy = false
	return reply


## [param value]: "civ|action|param" from a civ's diplomacy page.
func diplomacy_action(value: String) -> void:
	if busy:
		return
	var parts := value.split("|")
	var civ := parts[0]
	var action := parts[1]
	var param := parts[2] if parts.size() > 2 else ""
	big_screen.diplo_armed = ""
	var params := {"civ": civ, "action": action}
	match action:
		"giftGold":
			params["gold"] = int(param)
		"giftImprovement":
			var bits := param.split(",")
			params["x"] = int(bits[0])
			params["y"] = int(bits[1])
			params["improvement"] = bits[2]
		"tribute":
			params["kind"] = param
		"makeDemand":
			params["demand"] = param
	busy = true
	var reply: Dictionary
	if action == "peace":
		reply = await bridge.request("offerPeace", {"civ": civ})
	else:
		reply = await bridge.request("diplomacyAction", params)
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		big_screen.set_diplomacy(big_screen._diplomacy)
		return
	_set_status(ActionMenu._plain(str(reply.result.get("message", ""))))
	big_screen.set_diplomacy(reply.result.get("diplomacy", big_screen._diplomacy))
	await refresh()


func _trade_params() -> Dictionary:
	return {"civ": big_screen.trade_civ, "ours": big_screen.trade_items(big_screen.trade_ours),
		"theirs": big_screen.trade_items(big_screen.trade_theirs)}


func _set_info_visible(shown: bool) -> void:
	if _info_holder is CanvasLayer:
		(_info_holder as CanvasLayer).visible = shown
	elif _info_holder != null:
		(_info_holder as Node3D).visible = shown


## Shows a tile in the info panel straight away from what we already know, then asks the bridge for
## its yields once the pointer rests on it for a moment (see _process_info_panel).
func _show_tile_info(key: Variant) -> void:
	if info_panel == null or key == null or key == _info_key:
		return
	_info_key = key
	_info_wait = 0.0
	_info_requested = false
	info_panel.show_tile(hex_map.tiles.get(key, {}), _target_at(key))


func _process_info_panel(delta: float) -> void:
	if _info_key == null or _info_requested or _in_lobby:
		return
	_info_wait += delta
	if _info_wait < 0.15:
		return
	_info_requested = true
	var key: Vector2i = _info_key
	var reply := await bridge.request("getTile", {"x": key.x, "y": key.y})
	if reply.ok and _info_key == key:
		info_panel.show_tile(reply.result, _target_at(key))


# region map overlays ------------------------------------------------------------------------

## Turns one of Unciv's map overlays on or off (the round buttons beside the overview).
func toggle_overlay(id: String) -> void:
	var overlays: Dictionary = settings["overlays"]
	if not overlays.has(id):
		return
	overlays[id] = not overlays[id]
	_save_settings()
	minimap.set_overlay_states(overlays)
	hex_map.set_overlay_flags(overlays)
	var names := {"movement": "Unit movements", "yields": "Tile yields", "worked": "Worked tiles",
		"resources": "Resources and improvements", "improvements": "Improvement pictures", "unit_icons": "Unit icons"}
	_set_status("%s: %s" % [names.get(id, id), "on" if overlays[id] else "off"])
	if id == "yields" and overlays[id]:
		_refresh_yields()


func _on_view_rebuilt() -> void:
	if settings["overlays"].get("yields", false):
		_refresh_yields()


## Asks the bridge for the yields of the tiles on the table (only one request at a time).
func _refresh_yields() -> void:
	if bridge == null or not bridge.is_bridge_connected() or _in_lobby:
		return
	if _yields_pending:
		_yields_again = true
		return
	_yields_pending = true
	var reply := await bridge.request("getYields", {"tiles": hex_map.shown_explored_tiles()})
	_yields_pending = false
	if reply.ok and settings["overlays"].get("yields", false):
		hex_map.show_yields(reply.result.get("tiles", []))
	if _yields_again:
		_yields_again = false
		_refresh_yields()


func _update_minimap() -> void:
	if minimap == null:
		return
	# Always up during a game: it holds the overlay buttons (on small maps it's just an overview)
	minimap.visible = not _in_lobby and not _city_view and not hex_map.tiles.is_empty()
	if minimap.visible:
		minimap.redraw(state.get("units", []), state.get("cities", []))


## Slides the map window so [param key] is comfortably inside it (only when it's near the rim or off it).
func _bring_into_view(key: Vector2i) -> void:
	if not hex_map.is_windowed() or not hex_map.tiles.has(key):
		return
	var target := hex_map._world_of(key)
	if target.distance_to(hex_map.view_center) < hex_map.view_radius * 0.55:
		return
	_glide_view_to(target)


## Smoothly slides the map window so [param target] (world coords) is under the table centre.
func _glide_view_to(target: Vector2) -> void:
	if _view_tween != null and _view_tween.is_valid():
		_view_tween.kill()
	_view_tween = create_tween()
	_view_tween.tween_method(func(c: Vector2) -> void: hex_map.set_view(c, hex_map.view_radius),
		hex_map.view_center, target, 0.35).set_trans(Tween.TRANS_SINE)


## Zooms the map on the table: factor < 1 shows fewer, bigger hexes; > 1 more of the map, up to all of it.
func _zoom_view(factor: float) -> void:
	if hex_map.tiles.is_empty():
		return
	var current := hex_map.full_extent if hex_map.shows_whole_map() else hex_map.view_radius
	var radius := clampf(current * factor, VIEW_RADIUS_MIN, hex_map.full_extent)
	hex_map.set_view(hex_map.view_center, radius)
	_fit_table()


## Converts a movement in global space to map units on the table (x = east, y = north).
func _global_to_map_delta(delta: Vector3) -> Vector2:
	var local := hex_map.global_transform.basis.inverse() * delta
	return Vector2(local.x, -local.z)


func _fit_table() -> void:
	var s := TABLE_HALF_SIZE / hex_map.map_extent
	hex_map.scale = Vector3(s, s, s)
	pass


## The trigger (or the left mouse button) went down on tile [param key] (null: somewhere else). The click
## itself waits for the release, so that holding it can do something else - see _hold_tile_press.
func _begin_tile_press(key: Variant) -> void:
	_press_ms = Time.get_ticks_msec()
	_press_key = key
	_long_pressed = false


## Called every frame while it's held down: once it has been long enough, aim at the tile under the pointer.
func _hold_tile_press(key: Variant) -> void:
	if _long_pressed or _press_key == null or key == null or key != _press_key:
		return
	if Time.get_ticks_msec() - _press_ms < LONG_PRESS_MS:
		return
	_long_pressed = true   # the release won't click as well
	await _long_press_tile(key)


## Holding on a tile aims the selected unit there even when one of your own units is standing on it, which
## a click can't do: that selects the unit instead. The click that follows moves, like any other aimed move,
## so holding by mistake costs nothing.
func _long_press_tile(key: Vector2i) -> void:
	var aimable := not (busy or state.is_empty() or _in_lobby or _city_view) and _pick.is_empty() \
		and not selected_unit.is_empty() and key != _selected_key()
	if not aimable:
		await click_tile(key)   # nothing to aim: the hold is just a slow click
		return
	await _aim_at(key, true)


func click_tile(key: Vector2i) -> void:
	if busy or state.is_empty() or _in_lobby:
		return
	if not _pick.is_empty() and not _city_view:
		await _pick_tile(key)
		return
	if _city_view:
		await city_view_click(key)
		return
	var own_units := _own_units_at(key)
	var selected_key := _selected_key()

	# A long press aimed at this tile: the click goes there, even if one of your units is standing on it
	if key == _forced_aim and key == hex_map.aim_key() and not selected_unit.is_empty() and key != selected_key:
		_forced_aim = HexMap.NO_TILE
		hex_map.clear_aim()
		if hex_map.is_target(key):
			await attack(key)
		else:
			await move_selected_to(key)
		return

	# Clicking one of your units selects it (clicking the selected tile again cycles through its stack)
	if not own_units.is_empty() and (selected_unit.is_empty() or key != selected_key or own_units.size() > 1):
		var pick: Dictionary = own_units[0]
		if key == selected_key and own_units.size() > 1:
			var index := own_units.find_custom(func(u: Dictionary) -> bool: return int(u["id"]) == int(selected_unit["id"]))
			# On your city, clicking past the last unit of the stack opens the city (the next click starts over)
			if index == own_units.size() - 1 and not _own_city_at(key).is_empty():
				await open_city(key)
				return
			pick = own_units[(index + 1) % own_units.size()]
		# Clicking another of your units is how you select it, so say how to move onto it instead
		var hint := not selected_unit.is_empty() and key != selected_key and not _move_hint_shown \
			and float(selected_unit.get("movement", 0)) > 0.0
		await _select_unit(int(pick["id"]))
		if hint:
			_move_hint_shown = true
			_set_status("Hold %s on a tile to move a unit onto it." % ("the trigger" if _xr_mode else "the mouse button"))
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
## [param forced]: from a long press, so the click that follows moves there even with your own unit on the tile.
func _aim_at(key: Vector2i, forced := false) -> void:
	_forced_aim = HexMap.NO_TILE
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
	# Your own units on the tile: moving in shares it (Unciv allows a civilian and a military unit together,
	# more in a city), and when it doesn't, swapping places is usually what you meant
	var sharing := ", ".join(_own_units_at(key).map(func(u: Dictionary) -> String: return str(u.get("name", "a unit"))))
	# canStay false with a unit of yours there: the tile is full, so the unit could only pass through it
	# (a path to a tile held by someone else may still be worth taking - it can clear before you arrive)
	var full: bool = sharing != "" and not bool(result.get("canStay", true))
	if not result.get("canReach", false) or full:
		var blocked := "Can't get there"
		if sharing != "":
			blocked = "No room on this tile\n%s %s already there" % [sharing,
				"is" if _own_units_at(key).size() == 1 else "are"]
			if _can_swap_with(key):
				blocked += "\nSwap places on the card"
		hex_map.set_aim(key, [], blocked, AIM_BLOCKED_COLOR)
		return
	var stops: Array[Vector2i] = []
	for s: Dictionary in result.get("stops", []):
		stops.append(Vector2i(int(s["x"]), int(s["y"])))
	var turns := int(result.get("turns", 1))
	var text := "Move here" if turns <= 1 else "Move here: %d turns" % turns
	if sharing != "":
		text += "\nsharing the tile with %s" % sharing
	_forced_aim = key if forced else HexMap.NO_TILE
	hex_map.set_aim(key, stops, text + "\nclick again to go", AIM_MOVE_COLOR)


## True when the selected unit's "Swap places" action offers [param key] (its occupant swaps with it).
func _can_swap_with(key: Vector2i) -> bool:
	for t: Dictionary in _unit_action_entry("SwapUnits", "").get("targets", []):
		if int(t["x"]) == key.x and int(t["y"]) == key.y:
			return true
	return false


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
		await _after_order()


func found_city() -> void:
	if _in_lobby:
		return
	await unit_action("FoundCity")


func attack(key: Vector2i) -> void:
	if busy or selected_unit.is_empty():
		return
	busy = true
	var reply := await bridge.request("attack", {"unitId": int(selected_unit["id"]), "x": key.x, "y": key.y})
	if not reply.ok:
		busy = false
		_set_status(reply.error)
		return
	var r: Dictionary = reply.result
	if r.get("attacked", false):
		await hex_map.animate_attack(int(selected_unit["id"]), str(selected_unit["name"]), key, r)
	busy = false
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
		await _after_order()


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
	await _after_order()


func _on_menu_chosen(kind: String, value: String) -> void:
	if kind.begins_with("lobby") or kind.begins_with("setup_") or kind in ["load_save", "quit"]:
		await _on_lobby_choice(kind, value)
		return
	match kind:
		"action":
			await unit_action(value)
		"improvement":
			await build_improvement(value)
		"end_turn":
			await end_turn()
		"next_idle":
			await _select_next_unit(false)
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
		"city_view":
			await enter_city_view(value)
		"close":
			if _in_lobby:
				_show_lobby_card("lobby")   # e.g. closing Settings opened from the main menu
				return
			_close_popup()
			selected_city = {}
			action_menu.show_unit(selected_unit)
		"promotion_card":
			open_promotions()
		"settings_card":
			open_settings()
		"save_game":
			await save_game()
		"rename_unit":
			if not selected_unit.is_empty():
				await rename_unit(int(selected_unit["id"]))
		"main_menu":
			await open_lobby()
		"reset_boards":
			reset_board_poses()
		"background", "table", "auto_move", "setting_toggle", "tileset", "unitset", "playback":
			await change_setting(kind, value)
		"action_arm":
			_arm_unit_action(value)
		"pick_cancel":
			await cancel_pick()
		"bombard":
			_start_bombard_pick()
		"alert_answer":
			await answer_alert(value)
		"great_person":
			await choose_great_person(value)
		"vote":
			await cast_vote(value)
		"promote":
			await promote(value)


## Smoke test: everything the city view's boards and table clicks do, through the same handlers they use.
func _smoke_city_view(city_name: String) -> void:
	await enter_city_view(city_name)
	var data := city_view_data
	print("SMOKE: city view %s: shown=%s, minimap hidden=%s, %d tiles (%s), focus %s, free %d, stats %s" % [city_name, _city_view,
		not minimap.visible, data.get("tiles", []).size(),
		", ".join(data.get("tiles", []).map(func(t: Dictionary) -> String: return str(t["state"])).reduce(
			func(acc: Array, v: String) -> Array: return acc if v in acc else acc + [v], [])),
		data.get("focus"), int(data.get("freePopulation", -1)), data.get("stats", {})])
	var worked: Array = data.get("tiles", []).filter(func(t: Dictionary) -> bool: return t["state"] == "worked")
	if not worked.is_empty():
		var key := Vector2i(int(worked[0]["x"]), int(worked[0]["y"]))
		await city_view_click(key)
		print("SMOKE: clicked a worked tile -> %s, free %d" % [_city_view_tile(key).get("state"), int(city_view_data.get("freePopulation", -1))])
		await city_view_click(key)
		print("SMOKE: clicked it again -> %s" % _city_view_tile(key).get("state"))
		await _on_city_board_chosen("city_tile", "%d,%d|lock" % [key.x, key.y])
		print("SMOKE: lock -> %s" % _city_view_tile(key).get("state"))
	await _on_city_board_chosen("city_focus", "ProductionFocus")
	print("SMOKE: focus -> %s" % city_view_data.get("focus"))
	await _on_city_board_chosen("city_focus", "NoFocus")
	await _on_city_board_chosen("city_avoid_growth", "true")
	print("SMOKE: avoid growth -> %s" % city_view_data.get("avoidGrowth"))
	await _on_city_board_chosen("city_avoid_growth", "false")
	await _on_city_board_chosen("city_reset", "")
	var buildable: Array = city_view_data.get("options", []).filter(func(o: Dictionary) -> bool: return o.get("buildable", false) and o["kind"] != "perpetual")
	if buildable.size() >= 2:
		await _on_city_board_chosen("city_queue", buildable[0]["name"])
		await _on_city_board_chosen("city_queue", buildable[1]["name"])
		var before: Array = city_view_data.get("queue", []).map(func(q: Dictionary) -> String: return q["name"])
		await _on_city_board_chosen("city_move", "%d|up" % (before.size() - 1))
		print("SMOKE: queue %s -> moved last up -> %s" % [before, city_view_data.get("queue", []).map(func(q: Dictionary) -> String: return q["name"])])
		await _on_city_board_chosen("city_move", "%d|remove" % (city_view_data.get("queue", []).size() - 1))
		await _select_city_construction(buildable[0]["name"], -1)
		print("SMOKE: description of %s: %s" % [buildable[0]["name"], city_prod_board.construction_description.left(70).replace("\n", " / ")])
	var buyable: Array = city_view_data.get("tiles", []).filter(func(t: Dictionary) -> bool: return t["state"] == "buyable")
	print("SMOKE: %d buyable tiles, first costs %s" % [buyable.size(), buyable[0].get("buyCost") if not buyable.is_empty() else "-"])
	print("SMOKE: specialists %s, great people %s, buildings %s" % [city_view_data.get("specialists", []).map(func(x: Dictionary) -> String: return "%s %d/%d" % [x["name"], int(x["assigned"]), int(x["max"])]),
		city_view_data.get("greatPeople", []).map(func(x: Dictionary) -> String: return x["name"]),
		city_view_data.get("buildingDetails", []).map(func(x: Dictionary) -> String: return x["name"])])
	# Rename through the keyboard (typed a key at a time, as the laser would), then put the old name back
	_on_city_board_chosen("city_rename", "")
	print("SMOKE: keyboard for city rename: shown=%s, holder %s" % [keyboard_shown(), _keyboard_holder.get_parent().name if _keyboard_holder is Node3D else "canvas"])
	keyboard._backspace()
	keyboard._type("x")
	keyboard.submitted.emit(keyboard.text)
	await _smoke_wait(func() -> bool: return str(city_view_data.get("name")) != city_name)
	print("SMOKE: renamed %s -> %s (keyboard closed=%s)" % [city_name, city_view_data.get("name"), not keyboard_shown()])
	rename_city()
	keyboard.submitted.emit(city_name)
	await _smoke_wait(func() -> bool: return str(city_view_data.get("name")) == city_name)
	print("SMOKE: renamed back -> %s" % city_view_data.get("name"))
	var shown_buttons := _table_buttons.filter(func(b: Dictionary) -> bool: return (b["node"] as Node3D).visible).map(func(b: Dictionary) -> String: return b["id"])
	print("SMOKE: table buttons in city view: %s" % [shown_buttons])
	await press_table_button("exit_city")
	print("SMOKE: after Exit city: table buttons %s" % [_table_buttons.filter(func(b: Dictionary) -> bool: return (b["node"] as Node3D).visible).map(func(b: Dictionary) -> String: return b["id"])])
	var boards_up: bool = (_city_info_holder as CanvasLayer).visible if _city_info_holder is CanvasLayer else (_city_info_holder as Node3D).visible
	print("SMOKE: left city view: boards hidden=%s, minimap back=%s" % [not boards_up, minimap.visible])


## Smoke test: answers Unciv's popups the way a hurried player would (first option), and reports them.
func _smoke_answer_alerts() -> void:
	var guard := 0
	while not state.get("alerts", []).is_empty() and guard < 20:
		guard += 1
		var alert: Dictionary = state["alerts"][0]
		print("SMOKE: message %s '%s' -> %s" % [alert["type"], alert.get("title", ""), alert["options"][0]["id"]])
		await answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])


## Smoke test: waits (up to 5 s) for something a keyboard callback does in the background.
func _smoke_wait(done: Callable) -> void:
	var until := Time.get_ticks_msec() + 5000
	while not done.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame


## Smoke test: names a unit with the keyboard, then takes the name off again.
func _smoke_rename_unit(unit_id: int) -> void:
	await _select_unit(unit_id, false)
	await rename_unit(unit_id)
	keyboard.submitted.emit("Smoky")
	await _smoke_wait(func() -> bool: return selected_unit.get("instanceName", "") == "Smoky")
	print("SMOKE: unit %d named -> %s; card title %s" % [unit_id, selected_unit.get("instanceName", "(none)"), action_menu._title.text])
	await rename_unit(unit_id)
	keyboard.cancelled.emit()
	print("SMOKE: keyboard cancel closes it: %s" % (not keyboard_shown()))
	await rename_unit(unit_id)
	keyboard.submitted.emit("")
	await _smoke_wait(func() -> bool: return not selected_unit.has("instanceName"))
	print("SMOKE: unit name cleared -> %s" % selected_unit.get("instanceName", "(none)"))


# region empire overview ----------------------------------------------------------------------

## Unciv's Empire Overview: in VR a big board off to your right; on the desktop a window that E opens.
# region keyboard ------------------------------------------------------------------------

func _setup_keyboard() -> void:
	keyboard = Keyboard.new()
	keyboard.submitted.connect(_on_keyboard_submitted)
	keyboard.cancelled.connect(_close_keyboard)
	if _xr_mode:
		var panel := WorldPanel.new()
		panel.name = "Keyboard"
		panel.setup(keyboard, Vector2i(Keyboard.SIZE), KEYBOARD_METRES)
		add_child(panel)   # moved onto the wrist or in front of you by open_keyboard
		_keyboard_holder = panel
	else:
		var layer := CanvasLayer.new()
		layer.layer = 8   # above everything else
		add_child(layer)
		layer.add_child(keyboard)
		var place := func() -> void:
			var window := get_viewport().get_visible_rect().size
			var fit := minf(1.0, (window.x - 40.0) / Keyboard.SIZE.x)
			keyboard.scale = Vector2(fit, fit)
			keyboard.position = Vector2((window.x - Keyboard.SIZE.x * fit) / 2.0, window.y - Keyboard.SIZE.y * fit - 30.0)
		get_viewport().size_changed.connect(place)
		place.call()
		_keyboard_holder = layer
	_set_keyboard_visible(false)


func _set_keyboard_visible(shown: bool) -> void:
	if _keyboard_holder is CanvasLayer:
		(_keyboard_holder as CanvasLayer).visible = shown
	elif _keyboard_holder != null:
		(_keyboard_holder as Node3D).visible = shown


func keyboard_shown() -> bool:
	if _keyboard_holder is CanvasLayer:
		return (_keyboard_holder as CanvasLayer).visible
	return _keyboard_holder != null and (_keyboard_holder as Node3D).visible


## Asks for a name: [param title] above the field, [param initial] already typed. [param on_submit] gets the text
## (stripped; it may be empty) when you press OK; Cancel just closes the keyboard.
## VR: it pops up on the left wrist (in place of the wrist card) when the left controller is tracked, otherwise it
## floats in front of you.
func open_keyboard(title: String, initial: String, on_submit: Callable) -> void:
	if keyboard == null:
		return
	_keyboard_on_submit = on_submit
	keyboard.open(title, initial)
	if _xr_mode:
		var panel := _keyboard_holder as WorldPanel
		var where: String = options.get("keyboard", "")   # dev aid: --keyboard=wrist or --keyboard=float
		var on_wrist := _left_hand != null and _left_hand.get_has_tracking_data()
		if where != "":
			on_wrist = where == "wrist"
		if on_wrist:
			panel.reparent(_left_hand, false)
			# Where the wrist card is, shifted right so it sits over the back of the hand rather than off to the left
			panel.position = Vector3(0.09, 0.08, 0.04)
			panel.rotation_degrees = Vector3(-50, 0, 0)
			if _wrist_panel != null:
				_wrist_panel.visible = false
		else:
			panel.reparent(self, false)
			var head := _xr_camera.global_transform
			var forward := -head.basis.z
			forward.y = 0.0
			if forward.length() < 0.01:
				forward = Vector3.FORWARD
			# Half a metre ahead and a bit below the eyes, turned to face you
			panel.global_position = head.origin + forward.normalized() * 0.5 + Vector3.DOWN * 0.2
			panel.look_at(head.origin, Vector3.UP, true)
	_set_keyboard_visible(true)


func _close_keyboard() -> void:
	_set_keyboard_visible(false)
	_keyboard_on_submit = Callable()
	if _wrist_panel != null:
		_wrist_panel.visible = true


func _on_keyboard_submitted(text: String) -> void:
	var on_submit := _keyboard_on_submit
	_close_keyboard()
	if on_submit.is_valid():
		on_submit.call(text)


## The rename prompts (city view header, unit card, overview units tab).
func rename_city() -> void:
	if city_view_data.is_empty():
		return
	var old_name := str(city_view_data["name"])
	open_keyboard("Rename %s" % old_name, old_name, func(text: String) -> void:
		if text == "" or text == old_name:
			return
		if await _city_request("renameCity", {"newName": text}, "%s is now called %s." % [old_name, text]):
			await _refresh_city_view())


func rename_unit(unit_id: int) -> void:
	var reply := await bridge.request("getUnit", {"unitId": unit_id})
	if not reply.ok:
		_set_status(reply.error)
		return
	var unit: Dictionary = reply.result
	open_keyboard("Name your %s (empty: no name)" % unit.get("name", "unit"), str(unit.get("instanceName", "")), func(text: String) -> void:
		var renamed := await bridge.request("renameUnit", {"unitId": unit_id, "newName": text})
		if not renamed.ok:
			_set_status(renamed.error)
			return
		_set_status("Renamed to %s." % text if text != "" else "Name removed.")
		if not selected_unit.is_empty() and int(selected_unit["id"]) == unit_id:
			await _select_unit(unit_id, false)
		await _refresh_overview())


func _setup_overview_board() -> void:
	overview_board = OverviewBoard.new()
	overview_board.chosen.connect(_on_overview_chosen)
	if _xr_mode:
		var panel := WorldPanel.new()
		panel.name = "OverviewBoard"
		panel.setup(overview_board, Vector2i(OverviewBoard.SIZE), OVERVIEW_METRES)
		table.add_child(panel)   # placed by _apply_board_poses
		_overview_holder = panel
	else:
		var layer := CanvasLayer.new()
		layer.layer = 4
		add_child(layer)
		layer.add_child(overview_board)
		var place := func() -> void:
			var window := get_viewport().get_visible_rect().size
			var fit := minf(1.0, minf((window.x - 40.0) / OverviewBoard.SIZE.x, (window.y - 70.0) / OverviewBoard.SIZE.y))
			overview_board.scale = Vector2(fit, fit)
			overview_board.position = Vector2((window.x - OverviewBoard.SIZE.x * fit) / 2.0, 50)
		get_viewport().size_changed.connect(place)
		place.call()
		_overview_holder = layer
	_set_overview_visible(false)


func _set_overview_visible(shown: bool) -> void:
	if _overview_holder is CanvasLayer:
		(_overview_holder as CanvasLayer).visible = shown
	elif _overview_holder != null:
		(_overview_holder as Node3D).visible = shown


func _overview_shown() -> bool:
	if _overview_holder is CanvasLayer:
		return (_overview_holder as CanvasLayer).visible
	return _overview_holder != null and (_overview_holder as Node3D).visible


## Reloads the overview's current tab (after anything that may have changed it).
func _refresh_overview() -> void:
	if overview_board == null or _in_lobby or not _overview_shown() or bridge == null or not bridge.is_bridge_connected():
		return
	var tab := overview_board.tab
	var reply := await bridge.request("getOverview", {"tab": tab})
	if reply.ok and overview_board.tab == tab:
		overview_board.set_data(reply.result, int(state.get("player", {}).get("gold", 0)))
	elif not reply.ok:
		_set_status(reply.error)


func _on_overview_chosen(kind: String, value: String) -> void:
	match kind:
		"ov_spy_select":
			overview_board.selected_spy = "" if overview_board.selected_spy == value else value
			overview_board.armed = ""
			overview_board._rebuild()
			return
		"ov_spy_move", "ov_spy_coup":
			var parts := value.split("|")
			var params := {"spy": parts[0], "confirm": true}
			if kind == "ov_spy_move" and parts.size() > 1 and parts[1] != "":
				params["city"] = parts[1]
			overview_board.armed = ""
			var reply := await bridge.request("moveSpy" if kind == "ov_spy_move" else "stageCoup", params)
			if not reply.ok:
				_set_status(reply.error)
			else:
				_set_status("%s: on the way." % parts[0] if kind == "ov_spy_move" else "%s: coup orders given." % parts[0])
				overview_board.selected_spy = ""
			await _refresh_overview()
			await refresh()
			return
		"ov_tab":
			overview_board.show_tab(value)
			await _refresh_overview()
		"ov_city":
			await enter_city_view(value)
		"ov_city_card":
			var xy := value.split(",")
			var key := Vector2i(int(xy[0]), int(xy[1]))
			_look_at_tile(key)
			if not _own_city_at(key).is_empty():
				await open_city(key)
		"ov_goto":
			var xy := value.split(",")
			var key := Vector2i(int(xy[0]), int(xy[1]))
			_look_at_tile(key)
			if not _own_units_at(key).is_empty():
				await _select_unit(int(_own_units_at(key)[0]["id"]))
		"ov_unit":
			await _select_unit(int(value))
			if not selected_unit.is_empty():
				_look_at_tile(_selected_key())
				_set_status("Selected %s." % selected_unit.get("name", "the unit"))
		"ov_promote":
			await _select_unit(int(value))
			if not selected_unit.is_empty():
				_look_at_tile(_selected_key())
				open_promotions()
		"ov_rename":
			await rename_unit(int(value))
		"ov_upgrade":
			var parts := value.split("|")
			var reply := await bridge.request("upgradeUnit", {"unitId": int(parts[0]), "to": parts[1]})
			if not reply.ok:
				_set_status(reply.error)
				return
			_set_status("Upgraded to %s." % parts[1])
			await refresh()
			overview_board.set_data(reply.result, int(state.get("player", {}).get("gold", 0)))
		"ov_gold_science":
			var reply := await bridge.request("setGoldToScience", {"percent": value})
			if reply.ok:
				overview_board.set_data(reply.result, int(state.get("player", {}).get("gold", 0)))
				await refresh()
			else:
				_set_status(reply.error)
		"ov_big":
			await show_big_screen(value)


## Slides the map so [param key] is on the table and rings it (for "go there" clicks from the overview).
func _look_at_tile(key: Vector2i) -> void:
	if not hex_map.tiles.has(key):
		return
	if hex_map.is_windowed():
		_glide_view_to(hex_map._world_of(key))
	if selected_unit.is_empty():
		hex_map.set_selection(key, [], [])


# region city view ----------------------------------------------------------------------------

## The two city boards: on stands left and right of the table in VR; down the sides of the window on desktop.
func _setup_city_boards() -> void:
	city_info_board = CityBoard.new()
	city_info_board.mode = "info"
	city_prod_board = CityBoard.new()
	city_prod_board.mode = "production"
	for board: CityBoard in [city_info_board, city_prod_board]:
		board.chosen.connect(_on_city_board_chosen)
	if _xr_mode:
		var holders: Array[Node] = []
		for board: CityBoard in [city_info_board, city_prod_board]:
			var panel := WorldPanel.new()
			panel.name = "CityInfoBoard" if board == city_info_board else "CityProductionBoard"
			panel.setup(board, Vector2i(CityBoard.SIZE), CITY_BOARD_METRES)
			table.add_child(panel)   # placed by _apply_board_poses
			holders.append(panel)
		_city_info_holder = holders[0]
		_city_prod_holder = holders[1]
	else:
		var layer := CanvasLayer.new()
		layer.layer = 3
		add_child(layer)
		layer.add_child(city_info_board)
		layer.add_child(city_prod_board)
		var place := func() -> void:
			var window := get_viewport().get_visible_rect().size
			var fit := minf(1.0, minf((window.y - 54.0) / CityBoard.SIZE.y, (window.x * 0.3) / CityBoard.SIZE.x))
			for board: CityBoard in [city_info_board, city_prod_board]:
				board.scale = Vector2(fit, fit)
			city_info_board.position = Vector2(10, 44)   # under the status line
			city_prod_board.position = Vector2(window.x - CityBoard.SIZE.x * fit - 10, 44)
		get_viewport().size_changed.connect(place)
		place.call()
		_city_info_holder = layer
		_city_prod_holder = layer
	_set_city_boards_visible(false)


func _set_city_boards_visible(shown: bool) -> void:
	for holder: Node in [_city_info_holder, _city_prod_holder]:
		if holder is CanvasLayer:
			(holder as CanvasLayer).visible = shown
		elif holder != null:
			(holder as Node3D).visible = shown


## Turns the table into the city view of [param city_name]: the map zooms onto the city with Unciv's city
## screen marks on its tiles, the world boards make way for the two city boards.
func enter_city_view(city_name: String) -> void:
	if _in_lobby or busy:
		return
	var reply := await bridge.request("getCity", {"name": city_name})
	if not reply.ok:
		_set_status(reply.error)
		return
	if not _city_view:
		_saved_view = [hex_map.view_center, hex_map.view_radius]
		_big_was_shown = _big_screen_shown()
		_overview_was_shown = _overview_shown()
	_city_view = true
	_deselect()
	_close_popup()
	selected_city = {}
	hex_map.clear_aim()
	_city_tile_armed = Vector2i(999999, 999999)
	minimap.visible = false
	_set_info_visible(false)
	_set_big_visible(false)
	_set_overview_visible(false)
	_set_table_buttons_visible(true)   # just the red Exit city button
	_set_city_boards_visible(true)
	if not _xr_mode:
		action_menu.visible = false
	_show_city_view(reply.result, true)
	_set_status("City view: %s. Click tiles to work them; Exit city (or B / Esc) goes back to the map." % city_name)


## Shows a getCity result on the table and both boards. [param recentre]: move the map window onto it.
func _show_city_view(data: Dictionary, recentre := false) -> void:
	var previous_name: String = city_view_data.get("name", "")
	city_view_data = data
	var key := Vector2i(int(data["x"]), int(data["y"]))
	if recentre or previous_name != data.get("name", ""):
		var radius := float(int(data.get("viewRange", 3)) + 1) * 1.75 + 0.6
		hex_map.set_view(hex_map._world_of(key), minf(radius, hex_map.full_extent))
		_fit_table()
	hex_map.show_city(data)
	hex_map.set_selection(key, [], [])
	var player: Dictionary = state.get("player", {})
	city_info_board.show_city(data, int(player.get("gold", 0)), int(player.get("faithPoints", 0)))
	city_prod_board.show_city(data, int(player.get("gold", 0)), int(player.get("faithPoints", 0)))
	if city_info_board.selected_tile != Vector2i(999999, 999999):
		city_info_board.select_tile(city_info_board.selected_tile, hex_map.tiles.get(city_info_board.selected_tile, {}))


func exit_city_view() -> void:
	if not _city_view:
		return
	_city_view = false
	_city_place = {}
	city_view_data = {}
	hex_map.show_city({})
	hex_map.clear_aim()
	hex_map.clear_selection()
	_set_city_boards_visible(false)
	_set_info_visible(true)
	_set_table_buttons_visible(true)
	if not _xr_mode:
		action_menu.visible = true
	_set_big_visible(_big_was_shown or _xr_mode)
	_set_overview_visible(_overview_was_shown or _xr_mode)
	if _saved_view.size() == 2:
		hex_map.set_view(_saved_view[0], _saved_view[1])
		_fit_table()
	await refresh()   # worked tiles, bought tiles and production show on the map again
	_update_minimap()
	_set_status("Back to the map.")
	await _select_next_unit()


## A click on the table in the city view, like a click on Unciv's city screen: works / stops working the tile,
## buys it (second click), or switches to another of your cities.
## A building that creates an improvement (Unciv's "CreatesOneImprovement") asks where the improvement goes, like
## Unciv's city screen. Returns true when it now waits for that tile (city_view_click finishes the order).
func _needs_place_tile(construction: String, method: String, params: Dictionary, queue_index: int) -> bool:
	if queue_index >= 0:
		var queue: Array = city_view_data.get("queue", [])
		if queue_index < queue.size() and (queue[queue_index] as Dictionary).has("tile"):
			return false   # queued with its tile already
	for option: Dictionary in city_view_data.get("options", []):
		if option["name"] != construction or not option.get("needsTile", false):
			continue
		var tiles: Array[Vector2i] = []
		for t: Dictionary in option.get("placeTiles", []):
			tiles.append(Vector2i(int(t["x"]), int(t["y"])))
		if tiles.is_empty():
			_set_status("There's nowhere in %s to put the %s." % [city_view_data.get("name", "the city"), option.get("improvement", "improvement")])
			return true
		_city_place = {"method": method, "params": params, "tiles": tiles, "name": construction}
		hex_map.set_selection(Vector2i(int(city_view_data["x"]), int(city_view_data["y"])), [], tiles)
		_set_status("Pick the tile for the %s (red rings), or Esc / B to cancel." % option.get("improvement", construction))
		return true
	return false


func _cancel_city_place() -> void:
	_city_place = {}
	hex_map.clear_selection()
	_set_status("Cancelled.")


func city_view_click(key: Vector2i) -> void:
	if not _city_place.is_empty():
		var place := _city_place
		var tiles: Array[Vector2i] = place["tiles"]
		if key not in tiles:
			_set_status("Pick one of the ringed tiles (Esc / B cancels).")
			return
		_city_place = {}
		hex_map.clear_selection()
		var params: Dictionary = (place["params"] as Dictionary).duplicate()
		params["tileX"] = key.x
		params["tileY"] = key.y
		if await _city_request(place["method"], params, "%s: the improvement goes there." % place["name"]):
			city_prod_board.select_construction("", -1, "")
			await _refresh_city_view()
		return
	var tile := _city_view_tile(key)
	var tile_state := str(tile.get("state", ""))
	city_info_board.select_tile(key, hex_map.tiles.get(key, {}))
	if tile.is_empty():
		var other := _own_city_at(key)
		if not other.is_empty() and other["name"] != city_view_data.get("name"):
			await enter_city_view(other["name"])
		return
	if tile_state == "center":
		hex_map.clear_aim()
		return
	if tile_state == "buyable":
		if _city_tile_armed == key:
			_city_tile_armed = Vector2i(999999, 999999)
			hex_map.clear_aim()
			await _city_request("cityTile", {"tileX": key.x, "tileY": key.y, "action": "buy"}, "Bought the tile for %d gold." % int(tile.get("buyCost", 0)))
			await refresh()   # the border moved
			_show_city_view(city_view_data)
		else:
			_city_tile_armed = key
			var afford: bool = tile.get("canAfford", false)
			hex_map.set_aim(key, [], ("Buy for %d gold\nclick again to buy" if afford else "Costs %d gold\n(not enough gold)") % int(tile.get("buyCost", 0)),
				AIM_MOVE_COLOR if afford else AIM_BLOCKED_COLOR)
		return
	_city_tile_armed = Vector2i(999999, 999999)
	hex_map.clear_aim()
	if tile_state in ["worked", "locked", "notWorked"]:
		await _city_request("cityTile", {"tileX": key.x, "tileY": key.y, "action": "toggle"})


func _city_view_tile(key: Vector2i) -> Dictionary:
	for t: Dictionary in city_view_data.get("tiles", []):
		if int(t["x"]) == key.x and int(t["y"]) == key.y:
			return t
	return {}


## Sends a city action (the city is added to [param params]) and shows the updated city. Returns success.
func _city_request(method: String, params: Dictionary, success_text := "") -> bool:
	if city_view_data.is_empty() or busy:
		return false
	params["name"] = city_view_data["name"]
	busy = true
	var reply := await bridge.request(method, params)
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return false
	if success_text != "":
		_set_status(success_text)
	if reply.result is Dictionary and (reply.result as Dictionary).has("tiles"):
		_show_city_view(reply.result)
	return true


## Gold / faith / the city list changed: refresh the state, then the city.
func _refresh_city_view() -> void:
	await refresh()
	var reply := await bridge.request("getCity", {"name": city_view_data.get("name", "")})
	if reply.ok:
		_show_city_view(reply.result)


func _on_city_board_chosen(kind: String, value: String) -> void:
	if not _city_view:
		return
	var parts := value.split("|")
	match kind:
		"city_exit":
			await exit_city_view()
		"city_rename":
			rename_city()
		"city_prev", "city_next":
			var names: Array = city_view_data.get("cities", [])
			if names.size() > 1:
				var index := names.find(city_view_data.get("name"))
				var step := -1 if kind == "city_prev" else 1
				await enter_city_view(str(names[(index + step + names.size()) % names.size()]))
		"city_focus":
			await _city_request("setCityFocus", {"focus": value})
		"city_reassign":
			await _city_request("resetCitizens", {})
		"city_reset":
			await _city_request("resetCitizens", {}, "Citizens reassigned (locks cleared).")
		"city_avoid_growth":
			await _city_request("setAvoidGrowth", {"avoid": value == "true"})
		"city_manual_specialists":
			await _city_request("setManualSpecialists", {"manual": value == "true"})
		"city_specialist":
			await _city_request("setSpecialist", {"specialist": parts[0], "delta": int(parts[1])})
		"city_tile":
			var xy := parts[0].split(",")
			var action := parts[1]
			if await _city_request("cityTile", {"tileX": int(xy[0]), "tileY": int(xy[1]), "action": action}) and action == "buy":
				await _refresh_city_view()
		"city_arm":
			if value.begins_with("buy:") or value.begins_with("sell:"):
				city_prod_board.arm(value)
			else:
				city_info_board.arm(value)
		"city_raze":
			await _city_request("setRazing", {"raze": value == "true"})
		"city_annex":
			if await _city_request("annexCity", {}, "Annexed."):
				await _refresh_city_view()
		"city_select":
			await _select_city_construction(value, -1)
		"city_select_queue":
			var index := int(value)
			var queue: Array = city_view_data.get("queue", [])
			if index < queue.size():
				await _select_city_construction(str(queue[index]["name"]), index)
		"city_build_now":
			if _needs_place_tile(value, "setProduction", {"construction": value, "mode": "now"}, -1):
				return
			await _city_request("setProduction", {"construction": value, "mode": "now"}, "%s will build %s next." % [city_view_data.get("name", ""), value])
		"city_queue":
			if _needs_place_tile(value, "setProduction", {"construction": value, "mode": "queue"}, -1):
				return
			await _city_request("setProduction", {"construction": value, "mode": "queue"}, "%s added to the queue." % value)
		"city_move":
			var index := int(parts[0])
			if parts[1] == "remove":
				await _city_request("removeFromQueue", {"index": index})
				city_prod_board.select_construction("", -1, "")
			else:
				await _city_request("moveInQueue", {"index": index, "to": parts[1]})
		"city_buy":
			if _needs_place_tile(parts[0], "buyConstruction", {"construction": parts[0], "stat": parts[1], "queueIndex": int(parts[2])}, int(parts[2])):
				return
			if await _city_request("buyConstruction", {"construction": parts[0], "stat": parts[1], "queueIndex": int(parts[2])},
					"Bought %s." % parts[0]):
				city_prod_board.select_construction("", -1, "")
				await _refresh_city_view()
		"city_sell":
			if await _city_request("sellBuilding", {"building": value}, "Sold the %s." % value):
				city_prod_board.select_construction("", -1, "")
				await _refresh_city_view()
		"city_show_unavailable":
			city_prod_board.show_unavailable = value == "true"
			city_prod_board.show_city(city_view_data, city_prod_board.gold, city_prod_board.faith)


## Picks a construction on the production board (and fetches Unciv's description of it).
func _select_city_construction(construction: String, queue_index: int) -> void:
	city_prod_board.select_construction(construction, queue_index, "")
	var reply := await bridge.request("describeConstruction", {"name": city_view_data.get("name", ""), "construction": construction})
	if reply.ok and city_prod_board.selected_construction == construction:
		city_prod_board.select_construction(construction, queue_index, str(reply.result.get("description", "")))


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
	var city := selected_city
	var key := Vector2i(int(city["x"]), int(city["y"]))
	await refresh()
	var fresh := await bridge.request("getCity", {"name": city["name"]})
	selected_city = fresh.result if fresh.ok else city
	if selected_unit.is_empty():
		hex_map.set_selection(key, [], [])
	_show_city_card()


func open_research() -> void:
	if _in_lobby:
		return
	if big_screen != null:
		await show_big_screen("tech")   # the tech tree on the big screen
		return
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
	selected_unit = _with_move_action(reply.result)
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


## Puts the Policies tab up when you have the culture for a new policy (unless research needs picking first).
func _prompt_policy_if_ready() -> void:
	var p: Dictionary = state.get("player", {})
	if p.get("canResearch", false) and p.get("currentTech") == null:
		return
	if p.has("cultureForNextPolicy") and int(p.get("culturePoints", 0)) >= int(p["cultureForNextPolicy"]):
		_set_status("You can adopt a new policy - see the Policies tab on the big screen.")
		await show_big_screen("policies")


## Steps through all your units in a stable order (dir = 1 next, -1 previous).
func cycle_unit(dir: int) -> void:
	if _in_lobby:
		return
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


## Adds our own "Move here" to a unit's actions, next to Unciv's "Swap places". The map click alone can't
## move onto a tile that one of your units is on (it selects that unit), so the card offers it too.
func _with_move_action(unit: Dictionary) -> Dictionary:
	if unit.is_empty():
		return unit
	var actions: Array = (unit.get("actions", []) as Array).duplicate()
	actions = actions.filter(func(a: Dictionary) -> bool: return str(a.get("type", "")) != MOVE_ACTION)
	var entry := {"type": MOVE_ACTION, "title": "Move here", "target": "tile",
		"enabled": not (unit.get("reachable", []) as Array).is_empty(), "targets": unit.get("reachable", [])}
	var swap := actions.find_custom(func(a: Dictionary) -> bool: return str(a.get("type", "")) == "SwapUnits")
	if swap < 0:
		actions.append(entry)
	else:
		actions.insert(swap, entry)
	unit["actions"] = actions
	return unit


## [param value]: "type|title" from the unit card ("|confirm" appended once a risky action is confirmed), or just a type.
func unit_action(value: String) -> void:
	if _in_lobby or busy or selected_unit.is_empty():
		return
	var parts := value.split("|")
	var type := parts[0]
	if type == MOVE_ACTION:
		_start_move_pick()
		return
	var title := parts[1] if parts.size() > 1 else ""
	var confirmed := parts.size() > 2 and parts[2] == "confirm"
	var action := _unit_action_entry(type, title)
	if type == "ShowUnitDestination" and action.has("destination"):
		var where := Vector2i(int(action["destination"]["x"]), int(action["destination"]["y"]))
		_look_at_tile(where)
		hex_map.set_aim(where, [], "%s is heading here" % selected_unit.get("name", "The unit"), AIM_MOVE_COLOR)
		return
	if action.get("target", "") == "tile":
		_start_unit_pick(action)
		return
	var params := {"unitId": int(selected_unit["id"]), "action": type, "confirm": confirmed}
	if title != "":
		params["title"] = title
	busy = true
	var reply := await bridge.request("unitAction", params)
	busy = false
	await _finish_unit_action(reply, action)


func _finish_unit_action(reply: Dictionary, action: Dictionary) -> void:
	_clear_armed_action()
	if not reply.ok:
		_set_status(reply.error)
		await refresh()
		return
	if not reply.result.get("done", true):
		_set_status(str(reply.result.get("confirm", "Are you sure?")))
		return
	_set_status("%s: %s" % [selected_unit.get("name", "Unit"), _clean_title(str(action.get("title", action.get("type", "done"))))])
	if not reply.result.get("unitStillExists", true):
		_deselect()
	await refresh()
	if selected_unit.is_empty() or not selected_unit.get("idle", true) or float(selected_unit.get("movement", 0)) <= 0.0 \
			or not selected_unit.get("due", true):
		await _after_order()


## The getUnit action entry with this type (and title, when there are several), or {}.
func _unit_action_entry(type: String, title: String) -> Dictionary:
	var fallback := {}
	for a: Dictionary in selected_unit.get("actions", []):
		if a["type"] != type:
			continue
		if title == "" or str(a.get("title", "")) == title:
			return a
		fallback = a
	return fallback


static func _clean_title(text: String) -> String:
	return ActionMenu._plain(text.replace("{", "").replace("}", "").replace("[", "").replace("]", ""))


## After a unit has its orders: Unciv's "Auto unit cycle" moves on to the next unit that needs some.
func _after_order() -> void:
	if settings.get("autoUnitCycle", true):
		await _select_next_unit()


## A risky action's first click (disband, pillage...): both unit cards show it waiting for a second click.
func _arm_unit_action(key: String) -> void:
	action_menu.armed_action = key
	if popup_menu != null:
		popup_menu.armed_action = key
	var entry := _unit_action_entry(key.split("|")[0], key.split("|")[1] if key.split("|").size() > 1 else "")
	_set_status(str(entry.get("confirm", "Click again to confirm.")))
	_reshow_unit_cards()


func _clear_armed_action() -> void:
	action_menu.armed_action = ""
	if popup_menu != null:
		popup_menu.armed_action = ""


func _reshow_unit_cards() -> void:
	if selected_unit.is_empty():
		return
	if _xr_mode or selected_city.is_empty():
		action_menu.show_unit(selected_unit)
	if _xr_mode and _popup_kind == "unit":
		_open_unit_popup()


# region picking a tile (swap with, road to, bombard...) ----------------------------------------

## A unit action that needs a tile: highlight the choices and wait for a click on one (or Cancel).
func _start_unit_pick(action: Dictionary) -> void:
	var targets: Array[Vector2i] = []
	for t: Dictionary in action.get("targets", []):
		targets.append(Vector2i(int(t["x"]), int(t["y"])))
	var title := _clean_title(str(action.get("title", action["type"])))
	_pick = {"kind": "unit_action", "type": action["type"], "title": str(action.get("title", "")), "targets": targets,
		"any": not action.has("targets"), "text": title}
	hex_map.clear_aim()
	hex_map.set_selection(_selected_key(), [], targets)
	_set_pick_text("%s: click a %stile" % [title, "highlighted " if not targets.is_empty() else ""])
	_set_status("%s - click the tile on the map (or Cancel on the card)." % title)


## "Move here" on the unit card: where it can get this turn is ringed, but any tile will do (a far one
## becomes a move it carries on with next turn), including a tile with your own units on it.
func _start_move_pick() -> void:
	if selected_unit.is_empty():
		return
	var reachable: Array[Vector2i] = []
	for t: Dictionary in selected_unit.get("reachable", []):
		reachable.append(Vector2i(int(t["x"]), int(t["y"])))
	_pick = {"kind": "move", "targets": reachable, "any": true}
	hex_map.clear_aim()
	hex_map.set_selection(_selected_key(), reachable, [])
	_set_pick_text("Move here: click a tile")
	_set_status("Move %s - click a tile on the map (or Cancel on the card)." % selected_unit.get("name", "the unit"))


## The city's guns: pick one of the enemies in range.
func _start_bombard_pick() -> void:
	if selected_city.is_empty():
		return
	var targets: Array[Vector2i] = []
	for t: Dictionary in selected_city.get("bombardTargets", []):
		targets.append(Vector2i(int(t["x"]), int(t["y"])))
	if targets.is_empty():
		_set_status("No enemies in range of %s." % selected_city.get("name", "the city"))
		return
	_pick = {"kind": "bombard", "city": str(selected_city["name"]), "targets": targets, "any": false,
		"key": Vector2i(int(selected_city["x"]), int(selected_city["y"]))}
	hex_map.clear_aim()
	hex_map.set_selection(_pick["key"], [], targets)
	_close_popup()
	_set_status("Bombard from %s: click a red-ringed enemy (click the city to cancel)." % selected_city["name"])


func _set_pick_text(text: String) -> void:
	action_menu.picking_text = text
	if popup_menu != null:
		popup_menu.picking_text = text
	_reshow_unit_cards()


func cancel_pick() -> void:
	if _pick.is_empty():
		return
	var was := _pick
	_pick = {}
	_set_pick_text("")
	if was["kind"] != "bombard" and not selected_unit.is_empty():
		await _select_unit(int(selected_unit["id"]), false)
	else:
		hex_map.clear_selection()
	_set_status("Cancelled.")


## A click on the map while picking a tile.
func _pick_tile(key: Vector2i) -> void:
	var pick := _pick
	var targets: Array[Vector2i] = pick.get("targets", [] as Array[Vector2i])
	if not pick.get("any", false) and key not in targets:
		if pick["kind"] == "bombard" and key == pick["key"]:
			await cancel_pick()
		else:
			_set_status("Pick one of the highlighted tiles (or Cancel).")
		return
	_pick = {}
	_set_pick_text("")
	match pick["kind"]:
		"move":
			if not selected_unit.is_empty():
				await move_selected_to(key)
		"unit_action":
			if selected_unit.is_empty():
				return
			var params := {"unitId": int(selected_unit["id"]), "action": pick["type"], "x": key.x, "y": key.y}
			if str(pick.get("title", "")) != "":
				params["title"] = pick["title"]
			busy = true
			var reply := await bridge.request("unitAction", params)
			busy = false
			await _finish_unit_action(reply, {"type": pick["type"], "title": pick.get("text", pick["type"])})
		"bombard":
			busy = true
			var reply := await bridge.request("cityAttack", {"name": pick["city"], "tileX": key.x, "tileY": key.y})
			if reply.ok:
				for c: Dictionary in state.get("cities", []):
					if c["name"] == pick["city"]:
						await hex_map.animate_bombard(Vector2i(int(c["x"]), int(c["y"])), key, reply.result)
			busy = false
			if not reply.ok:
				_set_status(reply.error)
			else:
				var r: Dictionary = reply.result
				_set_status("%s bombarded %s: %d damage%s." % [pick["city"], r.get("defender", "?"), int(r.get("damageToDefender", 0)),
					"  Destroyed!" if r.get("defenderDefeated", false) else ""])
			hex_map.clear_selection()
			await refresh()


func end_turn() -> void:
	if _playback_active:   # End turn (button, A, Space) during playback skips the rest of it
		_skip_playback = true
		return
	if _in_lobby or busy:
		return
	# Like Unciv's next-turn button: first whatever still needs deciding (research, production, a message...)
	busy = true
	await refresh()
	busy = false
	var blockers: Array = state.get("blockers", [])
	if not blockers.is_empty():
		await _handle_blocker(blockers[0])
		return
	if settings.get("confirmNextTurn", false) and Time.get_ticks_msec() > _end_turn_armed_until:
		_end_turn_armed_until = Time.get_ticks_msec() + 5000
		_set_status("End the turn? Press End turn again to confirm.")
		return
	_end_turn_armed_until = 0
	busy = true
	await cancel_pick()
	_deselect()
	_set_status("Ending turn - the AI players are moving...")
	hex_map.clear_aim()
	var reply := await bridge.request("endTurn")
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		await refresh()
		return
	var result: Dictionary = reply.result
	var lines: Array[String] = ["Turn %d" % int(result["turn"])]
	if result.get("gameOver", false):
		lines.append("GAME OVER - %s wins (%s victory)" % [result.get("winner", "?"), result.get("victoryType", "?")])
	var notes: Array = result.get("notifications", [])
	for i in mini(notes.size(), 5):
		lines.append("- " + str(notes[i]["text"]))
	_set_status("\n".join(lines))
	var events: Array = result.get("events", [])
	var playback := str(settings.get("playback", "normal"))
	if playback != "off" and not events.is_empty():
		await _play_turn_events(events, float(PLAYBACK_SPEEDS.get(playback, 1.0)))
	elif not events.is_empty():
		for e: Dictionary in events:   # not shown: the units just appear where they ended up
			if e.get("type") == "move":
				hex_map.note_unit_at(int(e.get("unit", -1)), Vector2i(int(e["to"][0]), int(e["to"][1])))
	await refresh()
	if result.get("gameOver", false) or result.get("defeated", false):
		await show_big_screen("victory")
		return
	await _select_next_unit()
	await _prompt_research_if_needed()
	await _prompt_policy_if_ready()


## Plays back what the other players did that you could see (bridge endTurn "events"), in order; End turn
## (or A / Space) skips the rest. The view glides to fights happening outside the table's window.
func _play_turn_events(events: Array, speed: float) -> void:
	_playback_active = true
	_skip_playback = false
	busy = true
	hex_map.motion.speed = speed
	_set_turn_button_text("Skip")
	for i in events.size():
		var e: Dictionary = events[i]
		if _skip_playback or _in_lobby:
			for rest: Dictionary in events.slice(i):   # where the rest of the moves ended, so they don't glide afterwards
				if rest.get("type") == "move":
					hex_map.note_unit_at(int(rest.get("unit", -1)), Vector2i(int(rest["to"][0]), int(rest["to"][1])))
			break
		if e.get("type") == "attack" and hex_map.is_windowed():
			var to := Vector2i(int(e["to"][0]), int(e["to"][1]))
			if not hex_map.is_shown(to) and hex_map.tiles.has(to):
				_glide_view_to(hex_map._world_of(to))
				await get_tree().create_timer(0.45).timeout
		if options.has("scenario"):   # tests: what's being played back
			print("PLAYBACK: %s %s %s -> %s%s" % [e.get("type"), e.get("name", ""), e.get("from"), e.get("to"),
				"" if e.get("type") != "attack" else " vs %s, damage %s, died %s" % [e.get("defenderName", "-"), e.get("damage", 0), e.get("defenderDied", false)]])
		await hex_map.play_event(e)
	_playback_active = false
	_skip_playback = false
	busy = false
	hex_map.motion.speed = 1.0
	_update_turn_button()


func _set_turn_button_text(text: String) -> void:
	for button: Dictionary in _table_buttons:
		if button["id"] == "end_turn":
			var label: Label3D = button["label"]
			label.text = text
			label.font_size = 44


# region turn blockers, Unciv's popups and pickers ---------------------------------------------

## The End turn button says what's still to do (Unciv's next-turn button: "Pick a tech", "Pick construction"...).
func _update_turn_button() -> void:
	var blockers: Array = state.get("blockers", [])
	for button: Dictionary in _table_buttons:
		if button["id"] != "end_turn":
			continue
		var label: Label3D = button["label"]
		var material: StandardMaterial3D = button["material"]
		if blockers.is_empty():
			label.text = "End turn"
			label.font_size = 44
			material.albedo_color = button["color"]
		else:
			label.text = ActionMenu._plain(str(blockers[0]["text"]))
			label.font_size = 32
			material.albedo_color = Color(0.25, 0.45, 0.8)
	action_menu.end_turn_text = "End turn" if blockers.is_empty() else ActionMenu._plain(str(blockers[0]["text"]))


## Opens whatever the blocker asks for (End turn pressed while something is undecided).
func _handle_blocker(blocker: Dictionary) -> void:
	_set_status(ActionMenu._plain(str(blocker.get("text", ""))))
	match str(blocker.get("type", "")):
		"AnswerAlerts":
			_alert_shown_key = ""
			_maybe_show_alert()
		"PickGreatPerson":
			await open_great_people()
		"PickConstruction":
			var key := Vector2i(int(blocker["x"]), int(blocker["y"]))
			_look_at_tile(key)
			await open_city(key)
		"PickTech":
			await show_big_screen("tech")
		"PickPolicy":
			await bridge.request("dismissBlocker", {"type": "PickPolicy"})
			await show_big_screen("policies")
			await refresh()
		"MoveSpies":
			await bridge.request("dismissBlocker", {"type": "MoveSpies"})
			_set_overview_visible(true)
			overview_board.show_tab("espionage")
			await _refresh_overview()
			await refresh()
		"FoundPantheon", "ExpandPantheon", "FoundReligion", "EnhanceReligion", "ReformReligion":
			await show_big_screen("religion")
		"WorldCongressVote":
			await open_vote()
		"NextUnit":
			if blocker.has("unitId"):
				await _select_unit(int(blocker["unitId"]))


## Shows the oldest of Unciv's popups waiting for you (getState alerts), unless one is on show already.
func _maybe_show_alert() -> void:
	if _in_lobby or state.is_empty():
		return
	var alerts: Array = state.get("alerts", [])
	if alerts.is_empty():
		if _alert_shown_key != "":
			_close_alert_card()
		return
	if _city_view or keyboard_shown() or not _pick.is_empty() or busy:
		return
	var alert: Dictionary = alerts[0]
	if str(alert["key"]) == _alert_shown_key and _alert_card_visible():
		return
	_alert_shown_key = str(alert["key"])
	if alert.has("x"):
		_look_at_tile(Vector2i(int(alert["x"]), int(alert["y"])))
	_show_center_card(func(menu: ActionMenu) -> void: menu.show_alert(alert, alerts.size() - 1), "alert",
		Vector2i(int(alert["x"]), int(alert["y"])) if alert.has("x") else Vector2i(999999, 999999))


func _alert_card_visible() -> bool:
	if _xr_mode:
		return _popup_kind in ["alert", "alert_tile"]
	return _alert_layer != null and _alert_layer.visible


## A card for a popup or picker: floating over the table (or above [param tile]) in VR, mid-window on the desktop.
func _show_center_card(fill: Callable, kind: String, tile := Vector2i(999999, 999999)) -> void:
	if _xr_mode:
		_popup_kind = kind + ("_tile" if tile.x != 999999 and kind == "alert" else "")
		_popup_key = tile
		_popup_unit_id = -1
		fill.call(popup_menu)
		_update_popup_panel()
	else:
		_ensure_alert_menu()
		fill.call(alert_menu)
		_alert_layer.visible = true


func _close_alert_card() -> void:
	_alert_shown_key = ""
	if _xr_mode:
		if _popup_kind in ["alert", "alert_tile", "great_person", "vote"]:
			_close_popup()
			if not selected_unit.is_empty():
				_open_unit_popup()
	elif _alert_layer != null:
		_alert_layer.visible = false


func _ensure_alert_menu() -> void:
	if alert_menu != null:
		return
	_alert_layer = CanvasLayer.new()
	_alert_layer.layer = 6
	add_child(_alert_layer)
	alert_menu = ActionMenu.new()
	alert_menu.compact = true
	alert_menu.custom_minimum_size = Vector2(460, 0)
	alert_menu.chosen.connect(_on_menu_chosen)
	_alert_layer.add_child(alert_menu)
	var place := func() -> void:
		await get_tree().process_frame
		alert_menu.reset_size()
		var window := get_viewport().get_visible_rect().size
		alert_menu.position = Vector2((window.x - alert_menu.size.x) / 2.0, 90)
	alert_menu.layout_changed.connect(place)
	get_viewport().size_changed.connect(place)
	alert_menu.civ_info = action_menu.civ_info


## [param value]: "<alert key>|<option id>" (the key has a "|" of its own, so the option is after the last one).
func answer_alert(value: String) -> void:
	if busy:
		return
	var at := value.rfind("|")
	var key := value.left(at)
	var option := value.substr(at + 1)
	busy = true
	var reply := await bridge.request("answerAlert", {"key": key, "option": option})
	busy = false
	_alert_shown_key = ""
	_close_alert_card()
	if not reply.ok:
		_set_status(reply.error)
		await refresh()
		return
	var result: Dictionary = reply.result
	if str(result.get("message", "")) != "":
		_set_status(str(result["message"]))
	if option == "victory":
		await show_big_screen("victory")
	elif option == "counter" and result.has("civ"):
		# "How about something else...": their offer goes on the trade table, to change and propose back
		await show_big_screen("diplomacy")
		var options_reply := await bridge.request("getTradeOptions", {"civ": result["civ"]})
		if options_reply.ok:
			big_screen.open_trade(options_reply.result)
			big_screen.stage_trade(result.get("ours", []), result.get("theirs", []))
			await _on_big_screen_chosen("trade_changed", "")
	await refresh()
	if _city_view:
		await _refresh_city_view()


## Unciv's free great person picker.
func open_great_people() -> void:
	var reply := await bridge.request("getGreatPersonChoices")
	if not reply.ok:
		_set_status(reply.error)
		return
	_show_center_card(func(menu: ActionMenu) -> void: menu.show_great_people(reply.result), "great_person")


func choose_great_person(unit_name: String) -> void:
	if busy:
		return
	busy = true
	var reply := await bridge.request("chooseGreatPerson", {"unit": unit_name})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	_close_alert_card()
	_set_status("A %s has been born!" % unit_name)
	await refresh()
	for u: Dictionary in state.get("units", []):
		if u["name"] == unit_name:
			await _select_unit(int(u["id"]))


## The World Congress vote for world leader.
func open_vote() -> void:
	var reply := await bridge.request("getVoteChoices")
	if not reply.ok:
		_set_status(reply.error)
		return
	_show_center_card(func(menu: ActionMenu) -> void: menu.show_vote(reply.result), "vote")


func cast_vote(civ_name: String) -> void:
	if busy:
		return
	busy = true
	var reply := await bridge.request("vote", {"civ": civ_name} if civ_name != "" else {})
	busy = false
	if not reply.ok:
		_set_status(reply.error)
		return
	_close_alert_card()
	_set_status("You voted for %s." % civ_name if civ_name != "" else "You abstained.")
	await refresh()


func _select_unit(unit_id: int, focus := true) -> void:
	var reply := await bridge.request("getUnit", {"unitId": unit_id})
	if not reply.ok:
		_deselect()
		return
	if selected_unit.is_empty() or int(selected_unit["id"]) != unit_id:
		hex_map.clear_aim()
		_forced_aim = HexMap.NO_TILE
		# Picking a different unit (Next unit, a click...) abandons a half-done tile pick of the old one,
		# or a city's bombard - otherwise the next map click would do it with the wrong unit
		if focus and not _pick.is_empty():
			_pick = {}
			action_menu.picking_text = ""
			if popup_menu != null:
				popup_menu.picking_text = ""
	selected_unit = _with_move_action(reply.result)
	var reachable: Array[Vector2i] = []
	for t: Dictionary in selected_unit.get("reachable", []):
		reachable.append(Vector2i(int(t["x"]), int(t["y"])))
	var targets: Array[Vector2i] = []
	for t: Dictionary in selected_unit.get("targets", []):
		targets.append(Vector2i(int(t["x"]), int(t["y"])))
	hex_map.set_selection(_selected_key(), reachable, targets)
	if focus:
		selected_city = {}
	# A refresh (focus = false) mustn't close an open city card - on the desktop that card is this same panel
	if focus or _xr_mode or selected_city.is_empty():
		action_menu.show_unit(selected_unit)
	if focus and _auto_selecting and _popup_kind in DECISION_CARDS:
		pass   # chosen automatically: the waiting popup stays up (the wrist card shows the unit)
	elif focus:
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
	if focus:
		_bring_into_view(_selected_key())
	if focus and not _xr_mode and not hex_map.is_windowed():
		_focus = hex_map.to_global(hex_map.tile_local_center(_selected_key())) - table.global_position
		_update_camera()
	_update_hud()


## [param automatic]: chosen for the player (after an order, a new turn...) rather than asked for with Next idle.
## In VR an automatic pick doesn't cover a popup that's waiting for an answer (there's one floating card).
func _select_next_unit(automatic := true) -> void:
	if _in_lobby:
		return
	_auto_selecting = automatic
	var units: Array = state.get("units", [])
	var candidates := units.filter(func(u: Dictionary) -> bool:
		return u.get("idle", false) and float(u.get("movement", 0)) > 0.0)
	if candidates.is_empty():
		_auto_selecting = false
		_deselect()
		return
	var start := 0
	if not selected_unit.is_empty():
		var current := candidates.find_custom(func(u: Dictionary) -> bool: return int(u["id"]) == int(selected_unit["id"]))
		start = (current + 1) % candidates.size()
		if settings.get("alternateUnitCycleOrder", false) and candidates.size() > 1:
			# Unciv's "Cycle idle units by distance": the nearest one that isn't this one
			var here := _selected_key()
			var best := -1
			var best_distance := INF
			for i in candidates.size():
				if int(candidates[i]["id"]) == int(selected_unit["id"]):
					continue
				var d := Vector2(int(candidates[i]["x"]) - here.x, int(candidates[i]["y"]) - here.y).length()
				if d < best_distance:
					best_distance = d
					best = i
			if best >= 0:
				start = best
	await _select_unit(int(candidates[start]["id"]))
	_auto_selecting = false


func _deselect() -> void:
	if not _pick.is_empty():
		_pick = {}
		_set_pick_text("")
	_clear_armed_action()
	hex_map.clear_aim()
	_forced_aim = HexMap.NO_TILE
	selected_unit = {}
	selected_city = {}
	if _popup_kind not in DECISION_CARDS:   # a popup waiting for an answer isn't about the selection
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
	if hex_map.is_windowed():
		var start := hex_map.view_center
		print("SMOKE: windowed map: extent %.1f, window r=%.1f, drawn %d of %d tiles" % [hex_map.full_extent, hex_map.view_radius, hex_map._shown.size(), hex_map.tiles.size()])
		for i in 20:
			hex_map.pan_view(Vector2(0.5, 0.25))
		print("SMOKE: panned %s -> %s, drawn %d" % [start, hex_map.view_center, hex_map._shown.size()])
		_zoom_view(2.0)
		print("SMOKE: zoomed out to r=%.1f, drawn %d, table scale %.4f" % [hex_map.view_radius, hex_map._shown.size(), hex_map.scale.x])
		_zoom_view(0.5)
		var t0 := Time.get_ticks_usec()
		hex_map.set_view(hex_map.view_center + Vector2(5, 0), hex_map.view_radius)
		print("SMOKE: one rebuild took %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		t0 = Time.get_ticks_usec()
		for i in 60:
			hex_map.tile_at_global(hex_map.global_position)
		print("SMOKE: 60 picks took %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		hex_map.set_view(start, hex_map.view_radius)
		# Point at the overview's centre from a metre in front of it: should land near the map's centre
		var face := minimap.global_transform
		var spot: Variant = minimap.ray_hit(face.origin + face.basis.z * 1.0, -face.basis.z)
		print("SMOKE: overview centre -> world %s (map centre %s)" % [spot, hex_map.full_center])
		var grabbed_overview := _begin_board_drag(face.origin + face.basis.z * 1.0, -face.basis.z)
		print("SMOKE: overview grab=%s, released without moving counts as a click: %s" % [grabbed_overview, not _end_board_drag()])
	# Zoom: all the way in, then all the way out (the whole map), then back to the start
	var start_radius := hex_map.view_radius
	_zoom_view(0.01)
	print("SMOKE: zoomed in: r=%.1f, whole=%s, drawn %d" % [hex_map.view_radius, hex_map.shows_whole_map(), hex_map._shown.size()])
	var t_zoom := Time.get_ticks_usec()
	_zoom_view(100.0)
	print("SMOKE: zoomed out: whole=%s, drawn %d of %d in %.0f ms" % [hex_map.shows_whole_map(), hex_map._shown.size(), hex_map.tiles.size(), (Time.get_ticks_usec() - t_zoom) / 1000.0])
	hex_map.set_view(hex_map.view_center, start_radius)
	_fit_table()
	# Boards: grab the info board from a metre in front of it, drag it 20 cm sideways, let go
	if _info_holder is WorldPanel:
		var saved_settings := settings.duplicate(true)
		var board_node := _info_holder as Node3D
		var front := board_node.global_position - board_node.global_transform.basis.y * 0.27 + board_node.global_transform.basis.z * 1.0   # the board hangs from the bottom of its panel
		var grabbed := _begin_board_drag(front, -board_node.global_transform.basis.z)
		var before := board_node.position
		_update_board_drag(front + table.global_transform.basis.x * 0.2, -board_node.global_transform.basis.z)
		var moved := _end_board_drag()
		print("SMOKE: board drag: grabbed=%s moved=%s from %s to %s, saved pose %s" % [grabbed, moved, before, board_node.position, settings["info_pose"]])
		settings = saved_settings
		_save_settings()
		_apply_board_poses()
	# Info panel: point at the first unit's tile and wait for the bridge's details
	if not state.get("units", []).is_empty():
		var info_key := Vector2i(int(state["units"][0]["x"]), int(state["units"][0]["y"]))
		_update_hover(info_key)
		await get_tree().create_timer(0.6).timeout
		print("SMOKE: info panel: %s | %s" % [info_panel._tile_title.text, info_panel._civ_header.text])
	print("SMOKE: state turn=%s tiles=%d units=%d" % [state.get("turn"), state.get("tiles", []).size(), state.get("units", []).size()])
	var t_refresh := Time.get_ticks_usec()
	await refresh()
	print("SMOKE: delta refresh took %.0f ms (fps %d)" % [(Time.get_ticks_usec() - t_refresh) / 1000.0, Engine.get_frames_per_second()])
	print("SMOKE: delta refresh: %d tiles resent, %d in cache, full=%s" % [_last_tiles_received, _tile_cache.size(), state.get("full")])
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
	# Moving onto a tile one of your own units is on: a click there selects that unit, so hold (long press)
	# to aim at it, then click to go. The card's "Move here" picks a tile for the same thing.
	var stacked_onto := false
	var no_room := ""
	for u: Dictionary in state.get("units", []):
		if stacked_onto:
			break
		await _select_unit(int(u["id"]))
		var mover_id := int(selected_unit["id"])
		var from := _selected_key()
		for t: Dictionary in selected_unit.get("reachable", []):
			var key := Vector2i(int(t["x"]), int(t["y"]))
			if key == from or _own_units_at(key).is_empty():
				continue
			var occupants := ", ".join(_own_units_at(key).map(func(o: Dictionary) -> String: return str(o["name"])))
			await click_tile(key)
			var selected_other := int(selected_unit.get("id", 0)) != mover_id
			await _select_unit(mover_id)
			await _long_press_tile(key)
			if _forced_aim != key:   # no room for it on that tile: the aim says so and a click won't move
				if no_room == "":
					no_room = "SMOKE: no room on %s (%s): aimed %s, armed %s" % [key, occupants,
						hex_map.aim_key() == key, _forced_aim == key]
				continue
			await click_tile(key)
			var mover: Array = state.get("units", []).filter(func(m: Dictionary) -> bool: return int(m["id"]) == mover_id)
			var landed: Variant = Vector2i(int(mover[0]["x"]), int(mover[0]["y"])) if not mover.is_empty() else null
			print("SMOKE: %s is on %s: a click there selects it (%s), holding aims instead, and the click after it moved %s %s -> %s; %d units on the tile" % [
				occupants, key, selected_other, u["name"], from, landed, _own_units_at(key).size()])
			# The same move from the card: "Move here", then a tile click
			await _select_unit(mover_id)
			await unit_action(MOVE_ACTION)
			print("SMOKE: Move here picks a tile: kind %s, %d ringed" % [_pick.get("kind", "-"), (_pick.get("targets", []) as Array).size()])
			await cancel_pick()
			print("SMOKE: pick cancelled: %s" % _pick.is_empty())
			stacked_onto = true
			break
	if no_room != "":
		print(no_room)
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
		# Buying from the city card while a unit is still selected (the refresh used to drop the city)
		for u: Dictionary in state.get("units", []):
			if Vector2i(int(u["x"]), int(u["y"])) != capital_key:
				await _select_unit(int(u["id"]))
				break
		await click_tile(capital_key)
		if not options.is_empty() and not selected_unit.is_empty():
			await city_command("buy", options[0]["name"])
			print("SMOKE: bought %s with %s selected -> city card '%s', status '%s'" % [options[0]["name"], selected_unit.get("name", "-"), selected_city.get("name", "-"), _status_text])
		await _smoke_city_view(str(selected_city.get("name", "")))
	if not state.get("units", []).is_empty():
		await _smoke_rename_unit(int(state["units"][0]["id"]))
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
	for id: String in ["settings", "settings", "next_unit", "prev_unit", "next_idle", "recenter"]:
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
		await _smoke_answer_alerts()
		var turn_before := int(state.get("turn", 0))
		await end_turn()
		if int(state.get("turn", 0)) == turn_before:
			print("SMOKE: End turn waited for: %s (status '%s')" % [state.get("blockers", []).map(func(b: Dictionary) -> String: return b["type"]), _status_text])
			await _smoke_answer_alerts()
			await end_turn()
		var where: Array = state.get("units", []).filter(func(u: Dictionary) -> bool: return int(u["id"]) == explorer_id)
		print("SMOKE: ", _status_text.split("\n")[0], "  explorer at ",
			"(%d,%d)" % [int(where[0]["x"]), int(where[0]["y"])] if not where.is_empty() else "-")
	print("SMOKE: hover text for capital: ", hex_map.describe_tile(Vector2i(int(state["cities"][0]["x"]), int(state["cities"][0]["y"]))) if not state.get("cities", []).is_empty() else "")
	# Map overlays: turn each one on, count what got drawn, then put them back as they were
	var saved_overlays: Dictionary = settings["overlays"].duplicate()
	for id: String in saved_overlays:
		if not settings["overlays"][id]:
			toggle_overlay(id)
	await get_tree().create_timer(0.5).timeout
	var layers := hex_map.overlays
	print("SMOKE: overlays all on: %d symbol groups, %d models, %d yield groups, arrows %s, buttons %s" % [
		layers._decals.get_child_count(), layers._models.get_child_count(), layers._yield_layer.get_child_count(),
		layers._arrows.mesh != null, minimap._button_states])
	for id: String in saved_overlays:
		if settings["overlays"][id] != saved_overlays[id]:
			toggle_overlay(id)
	print("SMOKE: overlays restored: ", settings["overlays"])
	# Empire overview: every tab
	_set_overview_visible(true)
	for t: Array in OverviewBoard.TABS:
		overview_board.show_tab(t[0])
		var ov_reply := await bridge.request("getOverview", {"tab": t[0]})
		if ov_reply.ok:
			overview_board.set_data(ov_reply.result, int(state.get("player", {}).get("gold", 0)))
			var summary: Array = []
			for key: String in ov_reply.result:
				if key in ["tabs", "tab", "turn"]:
					continue
				var v: Variant = ov_reply.result[key]
				summary.append("%s=%s" % [key, str(v.size()) if v is Array or v is Dictionary else str(v)])
			print("SMOKE: overview %s: %s" % [t[0], ", ".join(summary)])
		else:
			print("SMOKE: overview %s FAILED: %s" % [t[0], ov_reply.error])
	_set_overview_visible(_xr_mode)
	# Big screen: each tab, research from the tree, a policy, and (on test games only) diplomacy
	await show_big_screen("tech")
	var researchable: Array = big_screen._techs.get("techs", []).filter(func(t: Dictionary) -> bool: return t.get("researchable", false))
	if not researchable.is_empty():
		await _on_big_screen_chosen("research", researchable[-1]["name"])
	print("SMOKE: big screen tech: %d techs, current %s, shown=%s" % [big_screen._techs.get("techs", []).size(), big_screen._techs.get("current"), _big_screen_shown()])
	await _on_big_screen_chosen("big_tab", "policies")
	var branches: Array = big_screen._policies.get("branches", [])
	print("SMOKE: big screen policies: %d branches, culture %s/%s" % [branches.size(), big_screen._policies.get("culture"), big_screen._policies.get("cultureNeeded")])
	if not branches.is_empty():
		await _on_big_screen_chosen("policy_select", branches[0]["name"])
		if branches[0].get("pickable", false):
			await _on_big_screen_chosen("adopt_policy", branches[0]["name"])
			print("SMOKE: adopted %s: %s" % [branches[0]["name"], _status_text])
	await _on_big_screen_chosen("big_tab", "diplomacy")
	var met: Array = big_screen._diplomacy.get("civs", [])
	print("SMOKE: big screen diplomacy: met %s" % [met.map(func(c: Dictionary) -> String: return "%s(%s)" % [c["name"], c.get("status")])])
	var majors := met.filter(func(c: Dictionary) -> bool: return not c.get("isCityState", false) and c.get("alive", true))
	if not majors.is_empty():
		await _on_big_screen_chosen("trade_open", majors[0]["name"])
		var opts: Dictionary = big_screen._trade_options
		print("SMOKE: trade with %s: we could offer %d things, they %d" % [big_screen.trade_civ, opts.get("ours", []).size(), opts.get("theirs", []).size()])
		var their_gold: Array = opts.get("theirs", []).filter(func(o: Dictionary) -> bool: return o["type"] == "Gold" and int(o["amount"]) > 0)
		if not their_gold.is_empty():
			big_screen._move_trade_item(their_gold[0], big_screen.trade_theirs, true)   # ask for some of their gold
			await get_tree().create_timer(0.5).timeout
			print("SMOKE: asking for %s gold for nothing -> %s" % [big_screen.trade_theirs[0]["amount"], big_screen._trade_verdict])
		big_screen.close_trade()
	await _on_big_screen_chosen("big_tab", "tech")
	# Main menu round trip: open it, set up a new game, start it, then go back and resume
	await _on_menu_chosen("main_menu", "")
	print("SMOKE: lobby open=%s, info=%s" % [_in_lobby, _lobby_info])
	await _on_menu_chosen("lobby_new", "")
	await _on_menu_chosen("setup_set", "mapSize|Small")
	await _on_menu_chosen("setup_step", "aiPlayers|1")
	await _on_menu_chosen("setup_toggle", "victory|Science")
	print("SMOKE: setup now ", _setup)
	print("SMOKE: %d nations, %d saves listed" % [_setup_options.get("nations", []).size(), _saves.size()])
	await _on_menu_chosen("lobby_resume", "")
	print("SMOKE: resumed: lobby=%s, tiles=%d, table buttons shown=%s" % [_in_lobby, hex_map.tiles.size(), (_table_buttons[0]["node"] as Node3D).visible])
	# The watchdog that lets go when an order is cut short, so the game doesn't ignore every click after it
	busy = true
	_busy_since = Time.get_ticks_msec() - BUSY_WATCHDOG_MS - 1
	_watch_busy()
	print("SMOKE: busy watchdog after an order that never finished: busy=%s, status '%s'" % [busy, _status_text])
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
	if info_panel != null and not _in_lobby:
		# The info panel shows your civ's numbers and the pointed-at tile; the HUD keeps attacks and messages
		if _hover_text.begins_with("ATTACK"):
			lines.append(_hover_text)
		lines.append(_status_text)
		_set_hud_text("\n".join(lines))
		return
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
	_set_hud_text("\n".join(lines))


func _set_hud_text(text: String) -> void:
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
	action_menu.in_vr = _xr_mode
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
	popup_menu.in_vr = true
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
		"settings", "research", "lobby", "alert", "great_person", "vote":
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
	var size_factor := 1.5 if _in_lobby else 1.0   # the main menu is the only thing to look at: make it bigger
	var card_height := popup_menu.size.y / POPUP_PANEL_PIXELS.y * POPUP_PANEL_METRES.y * size_factor
	_popup_panel.global_position = base + up * (lift + card_height - POPUP_PANEL_METRES.y * size_factor / 2.0)
	if head.distance_to(_popup_panel.global_position) > 0.05:
		# Face the eyes squarely (tilting back as needed) so the text isn't skewed when you look down at it.
		# use_model_front = true: the quad's front (+Z) is what turns towards the head.
		_popup_panel.look_at(head, Vector3.UP, true)
	_popup_panel.scale = Vector3.ONE * size_factor


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
	var params := {"automatedUnitsMoveOnTurnStart": settings["auto_move"] == "start"}
	for key: String in BRIDGE_SETTINGS:
		params[key] = bool(settings.get(key, false))
	for key: String in INT_SETTINGS:
		params[key] = int(settings.get(key, 1))
	var reply := await bridge.request("setSettings", params)
	if not reply.ok:
		push_warning("setSettings failed: %s" % reply.error)


## Unciv options with a number (sent with setSettings too)
const INT_SETTINGS := ["notificationsLogMaxTurns", "turnsBetweenAutosaves"]
## Unciv options the game engine itself reads (sent with setSettings)
const BRIDGE_SETTINGS := ["checkForDueUnits", "autoUnitCycle", "alternateUnitCycleOrder", "autoAssignCityProduction",
	"autoBuildingRoads", "automatedWorkersReplaceImprovements", "stopAutomatedWorkersRemoveVegetation",
	"automatedUnitsCanUpgrade", "automatedUnitsChoosePromotions", "citiesAutoBombardAtEndOfTurn", "autoAssignSpecialistsInNewCities"]


func change_setting(key: String, value: String) -> void:
	if key == "setting_toggle":
		settings[value] = not bool(settings.get(value, false))
		_save_settings()
		if value in BRIDGE_SETTINGS:
			await _send_bridge_settings()
			await refresh()   # e.g. "Check for idle units" changes what End turn waits for
		_refresh_settings()
		return
	if key in INT_SETTINGS:
		settings[key] = int(value)
	else:
		settings[key] = value
	_save_settings()
	match key:
		"background":
			backgrounds.apply(value)
		"table":
			table_model.apply(value, table)
			_update_pedestal()
		"unitset":
			hex_map.set_unitset(value)
		"tileset":
			hex_map.set_tileset(value)   # redraws the map (and the overlays follow via view_rebuilt)
		"auto_move", "notificationsLogMaxTurns", "turnsBetweenAutosaves":
			await _send_bridge_settings()
	_refresh_settings()   # so the new choice shows


## Saves the running game in the bridge's save folder, under a name you type ("<civ> - turn <n>" to start with).
func save_game() -> void:
	var default_name := "%s - turn %d" % [state.get("playerCiv", "Game"), int(state.get("turn", 0))]
	open_keyboard("Save game as", default_name, func(text: String) -> void:
		var save_name := text if text != "" else default_name
		var reply := await bridge.request("saveGame", {"name": save_name})
		_set_status("Saved as \"%s\"." % save_name if reply.ok else "Couldn't save: %s" % reply.error))


func open_settings() -> void:
	if _xr_mode and _popup_kind != "":
		_close_popup()   # nothing floats in front of the board (the main menu card comes back when it closes)
	_set_settings_visible(true)
	_refresh_settings()


func _setup_settings_board() -> void:
	settings_board = SettingsBoard.new()
	settings_board.chosen.connect(_on_settings_chosen)
	if _xr_mode:
		var panel := WorldPanel.new()
		panel.name = "SettingsBoard"
		panel.setup(settings_board, Vector2i(SettingsBoard.SIZE), SETTINGS_METRES)
		table.add_child(panel)   # placed by _apply_board_poses
		_settings_holder = panel
	else:
		var layer := CanvasLayer.new()
		layer.layer = 6
		add_child(layer)
		layer.add_child(settings_board)
		var place := func() -> void:
			var window := get_viewport().get_visible_rect().size
			var fit := minf(1.0, minf((window.x - 40.0) / SettingsBoard.SIZE.x, (window.y - 60.0) / SettingsBoard.SIZE.y))
			settings_board.scale = Vector2(fit, fit)
			settings_board.position = Vector2((window.x - SettingsBoard.SIZE.x * fit) / 2.0, (window.y - SettingsBoard.SIZE.y * fit) / 2.0)
		get_viewport().size_changed.connect(place)
		place.call()
		_settings_holder = layer
	_set_settings_visible(false)


func _set_settings_visible(shown: bool) -> void:
	if _settings_holder is CanvasLayer:
		(_settings_holder as CanvasLayer).visible = shown
	elif _settings_holder != null:
		(_settings_holder as Node3D).visible = shown


func settings_shown() -> bool:
	if _settings_holder is CanvasLayer:
		return (_settings_holder as CanvasLayer).visible
	return _settings_holder != null and (_settings_holder as Node3D).visible


func close_settings() -> void:
	if not settings_shown():
		return
	_set_settings_visible(false)
	if _in_lobby:
		_show_lobby_card("lobby")


## Shows the current settings (and what's running) on the settings board, if it's up.
func _refresh_settings() -> void:
	if settings_board == null or not settings_shown():
		return
	var game := {}
	if not _in_lobby and not state.is_empty():
		game = (state.get("game", {}) as Dictionary).duplicate() if state.get("game") is Dictionary else {}
		game["civ"] = state.get("playerCiv", "?")
		game["turn"] = int(state.get("turn", 0))
	var home := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	settings_board.update(settings, {"in_vr": _xr_mode, "in_lobby": _in_lobby, "unciv_version": _uncivVersion,
		"protocol": _bridge_protocol, "client_protocol": BRIDGE_PROTOCOL, "game": game,
		"saves_folder": home.replace("\\", "/").path_join(".unciv-vr/SaveFiles")})


func _on_settings_chosen(kind: String, value: String) -> void:
	match kind:
		"setting":
			var bits := value.split("|", true, 1)
			if bits.size() == 2:
				await change_setting(bits[0], bits[1])
		"setting_toggle":
			await change_setting("setting_toggle", value)
		"overlay":
			toggle_overlay(value)
			_refresh_settings()
		"reset_boards":
			reset_board_poses()
		"save_game":
			close_settings()
			await save_game()
		"main_menu":
			_set_settings_visible(false)
			await open_lobby()
		"close":
			close_settings()


## A row of round buttons along the near rim of the table, each with a floating label.
func _setup_table_buttons() -> void:
	var count := TABLE_BUTTONS.size()
	for i in count:
		var spec: Array = TABLE_BUTTONS[i]
		var big: bool = spec[0] in ["end_turn", "exit_city"]
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
		node.visible = false   # shown once a game is on the table (never over the main menu)
		table.add_child(node)
		var label := Label3D.new()
		label.text = spec[1]
		label.font_size = 44 if big else 36
		label.pixel_size = 0.0006
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 0.035, 0)
		node.add_child(label)
		_table_buttons.append({"id": spec[0], "node": node, "material": material, "radius": mesh.bottom_radius,
			"label": label, "color": spec[2]})


## The id of the table button a ray points at, or "".
func _table_button_at(origin: Vector3, direction: Vector3) -> String:
	var best := ""
	var best_along := INF
	var dir := direction.normalized()
	for button: Dictionary in _table_buttons:
		var node: MeshInstance3D = button["node"]
		if not node.is_visible_in_tree():
			continue
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
			await _select_next_unit(false)
		"research":
			await open_research()
		"end_turn":
			await end_turn()
		"exit_city":
			await exit_city_view()
		"recenter":
			recenter_table()
		"settings":
			if settings_shown():
				close_settings()
			else:
				open_settings()


## Keeps the table's column and feet under the table top as it moves (hidden when floating in space).
func _update_pedestal() -> void:
	if table_model != null:
		table_model.follow(table, backgrounds.global_position.y, backgrounds.has_floor)


# region scene setup ----------------------------------------------------------------------

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
	_right_hand.button_released.connect(func(button: String) -> void: _on_xr_button_released(true, button))

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
	if event is InputEventKey and keyboard_shown():
		keyboard.handle_key(event as InputEventKey)   # typing a name: the game's key shortcuts are off
		get_viewport().set_input_as_handled()
		return
	if _xr_mode:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _drag_id != "" and _camera != null:
			_update_board_drag(_camera.project_ray_origin(motion.position), _camera.project_ray_normal(motion.position))
			return
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_yaw -= motion.relative.x * 0.005
			_pitch += motion.relative.y * 0.005
			_update_camera()
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(Vector2(-motion.relative.x, -motion.relative.y) * 0.0015 * _distance)
		_update_hover(_pick_mouse(motion.position))
		if _camera != null and minimap != null:
			minimap.show_hover(minimap.ray_hit(_camera.project_ray_origin(motion.position), _camera.project_ray_normal(motion.position)))
			minimap.hover_button(minimap.overlay_button_at(_camera.project_ray_origin(motion.position), _camera.project_ray_normal(motion.position)))
		if _camera != null:
			_highlight_table_button(_table_button_at(_camera.project_ray_origin(motion.position), _camera.project_ray_normal(motion.position)))
	elif event is InputEventMouseButton and not event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var released := event as InputEventMouseButton
		var was_overview := _drag_id == "minimap"
		var pressed_key: Variant = _press_key
		var long_pressed := _long_pressed
		_press_key = null
		_long_pressed = false
		if not _end_board_drag() and was_overview and _camera != null:
			var spot: Variant = minimap.ray_hit(_camera.project_ray_origin(released.position), _camera.project_ray_normal(released.position))
			if spot != null:
				_glide_view_to(spot)
		# A click on the map happens here, so that holding the button can aim instead (see _hold_tile_press)
		elif pressed_key != null and not long_pressed and _pick_mouse(released.position) == pressed_key:
			click_tile(pressed_key)
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if _camera != null and minimap != null:
					var overlay := minimap.overlay_button_at(_camera.project_ray_origin(button.position), _camera.project_ray_normal(button.position))
					if overlay != "":
						toggle_overlay(overlay)
						return
				if _camera != null and _begin_board_drag(_camera.project_ray_origin(button.position), _camera.project_ray_normal(button.position)):
					return   # a click (jump there) or a drag (move the board) - decided on release
				var pressed := _table_button_at(_camera.project_ray_origin(button.position), _camera.project_ray_normal(button.position)) if _camera != null else ""
				if pressed != "":
					press_table_button(pressed)
					return
				var key: Variant = _pick_mouse(button.position)
				if key != null:
					_begin_tile_press(key)   # clicked when you let go, or aimed at if you hold it
			MOUSE_BUTTON_WHEEL_UP:
				if button.ctrl_pressed:
					_zoom_view(0.9)   # Ctrl + wheel zooms the map itself
				else:
					_distance *= 0.9
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.ctrl_pressed:
					_zoom_view(1.1)
				else:
					_distance *= 1.1
					_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE, KEY_ENTER:
				end_turn()
			KEY_F:
				found_city()
			KEY_N:
				_select_next_unit(false)
			KEY_TAB:
				cycle_unit(-1 if (event as InputEventKey).shift_pressed else 1)
			KEY_T:
				_toggle_big_screen("tech")
			KEY_P:
				_toggle_big_screen("policies")
			KEY_G:
				_toggle_big_screen("diplomacy")
			KEY_E:
				if _overview_shown():
					_set_overview_visible(false)
				elif not _in_lobby and not _city_view:
					_set_overview_visible(true)
					_refresh_overview()
			KEY_O:
				if settings_shown():
					close_settings()
				else:
					open_settings()
			KEY_ESCAPE:
				if settings_shown():
					close_settings()
				elif not _pick.is_empty():
					await cancel_pick()
				elif not _city_place.is_empty():
					_cancel_city_place()
				elif _city_view:
					exit_city_view()
				elif not _xr_mode and _overview_shown():
					_set_overview_visible(false)
				elif not _xr_mode and _big_screen_shown():
					_set_big_visible(false)
				else:
					_deselect()
			KEY_R:
				refresh()
			KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
				_zoom_view(0.8)   # show fewer, bigger hexes
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
				_zoom_view(1.25)


func _process(delta: float) -> void:
	_update_pedestal()
	_watch_busy()
	_process_info_panel(delta)
	if minimap != null and minimap.visible:
		minimap.update_window()
	if _xr_mode:
		_process_xr(delta)
		return
	# Holding the mouse button still on a tile aims at it (a click there selects whoever stands on it instead)
	if _press_key != null:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_hold_tile_press(_pick_mouse(get_viewport().get_mouse_position()))
		else:
			_press_key = null   # the release went somewhere else (another window, a popup...)
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): pan.y -= 1
	if Input.is_key_pressed(KEY_S): pan.y += 1
	if Input.is_key_pressed(KEY_A): pan.x -= 1
	if Input.is_key_pressed(KEY_D): pan.x += 1
	if pan != Vector2.ZERO:
		if hex_map.is_windowed():
			# Slide the map under the table instead of moving the camera
			var right := Vector3(cos(_yaw), 0, -sin(_yaw))
			var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
			var move := (right * pan.x - forward * pan.y) * delta * 0.5
			hex_map.pan_view(_global_to_map_delta(move))
		else:
			_pan(pan * delta * 0.8 * _distance)


## While an order is under way the game ignores clicks (so a double click can't buy twice). If one is ever
## cut short - a script error in the middle of it, a reply that never comes - nothing would clear `busy` and
## the game would look frozen from then on. Nothing should sit here this long with no request out and no
## playback running, so let go and say so instead of leaving the player stuck in a headset.
func _watch_busy() -> void:
	if not busy or _playback_active or bridge == null or bridge.pending > 0:
		_busy_since = 0
		return
	if _busy_since == 0:
		_busy_since = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - _busy_since < BUSY_WATCHDOG_MS:
		return
	busy = false
	_busy_since = 0
	push_warning("Busy for %.0f seconds with nothing to wait for - letting go" % (BUSY_WATCHDOG_MS / 1000.0))
	_set_status("Something didn't finish - carry on. (If it keeps happening, the log says why.)")


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
	_show_tile_info(key)
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
	var panels: Array[WorldPanel] = [_popup_panel, _wrist_panel]
	if keyboard_shown():
		panels.push_front(_keyboard_holder as WorldPanel)   # the keyboard is in front of everything while typing
	if _big_holder is WorldPanel:
		panels.append(_big_holder as WorldPanel)
	if _settings_holder is WorldPanel:
		panels.push_front(_settings_holder as WorldPanel)   # in front of the boards behind it
	for holder: Node in [_city_info_holder, _city_prod_holder, _overview_holder]:
		if holder is WorldPanel:
			panels.append(holder as WorldPanel)
	for panel: WorldPanel in panels:
		var hit: Variant = panel.ray_hit(origin, direction)
		if hit != null:
			_pointed_panel = panel
			_pointed_pixel = hit[1]
			_pointer_dot.visible = true
			_pointer_dot.global_position = hit[0]
			panel.hover(_pointed_pixel)
			_update_hover(null)
			break
	_pointed_minimap = minimap.ray_hit(origin, direction) if _pointed_panel == null and minimap != null else null
	if minimap != null:
		minimap.show_hover(_pointed_minimap)
	_pointed_overlay = minimap.overlay_button_at(origin, direction) if _pointed_panel == null and _pointed_minimap == null and minimap != null else ""
	if minimap != null:
		minimap.hover_button(_pointed_overlay)
	var board := _board_at(origin, direction) if _pointed_panel == null and _pointed_minimap == null and _pointed_overlay == "" else []
	var button := _table_button_at(origin, direction) if _pointed_panel == null and _pointed_minimap == null and _pointed_overlay == "" and board.is_empty() else ""
	_highlight_table_button(button)
	if _pointed_minimap != null:
		_pointer_dot.visible = false
		_update_hover(null)
	elif _pointed_overlay != "":
		_pointer_dot.visible = true
		_pointer_dot.global_position = minimap.button_global_position(_pointed_overlay)
		_update_hover(null)
	elif not board.is_empty():   # on the info board (or the overview's frame): grab it with the trigger to move it
		_pointer_dot.visible = true
		_pointer_dot.global_position = board[1]
	elif button != "":
		_pointer_dot.visible = true
		_pointer_dot.global_position = _table_button_position(button)
		_update_hover(null)
	elif _pointed_panel == null and not hex_map.tiles.is_empty():
		var key: Variant = hex_map.pick(origin, direction)
		_update_hover(key)
		_pointer_dot.visible = key != null
		if key != null:
			_pointer_dot.global_position = hex_map.to_global(hex_map.tile_local_center(key))

	# Trigger held + that hand's stick up / down zooms the map. The right trigger's click waits for the
	# release, so a zoom doesn't also click whatever you're pointing at.
	var right_stick := _right_hand.get_vector2("primary")
	var left_stick := _left_hand.get_vector2("primary")
	var right_trigger := _right_hand.get_float("trigger") > 0.6
	var left_trigger := _left_hand.get_float("trigger") > 0.6
	if _drag_id != "":
		# Holding a board: the right stick pushes it away / pulls it closer
		if absf(right_stick.y) > 0.25:
			_drag_distance = clampf(_drag_distance + right_stick.y * delta * 0.8, 0.25, 3.0)
			_drag_moved = true
		_update_board_drag(_right_hand.global_position, -_right_hand.global_transform.basis.z)
	elif right_trigger and _pointed_panel != null and (_trigger_scrollbar != null or _pointed_panel.scrollbar_at(_pointed_pixel) != null):
		# Trigger held on a scrollbar: its handle follows the pointer (and letting go doesn't click)
		if _trigger_scrollbar == null:
			_trigger_scrollbar = _pointed_panel.scrollbar_at(_pointed_pixel)
		WorldPanel.scroll_to(_trigger_scrollbar, _pointed_pixel)
		_right_trigger_used_for_zoom = true
	elif right_trigger and absf(right_stick.y) > 0.25:
		_zoom_view(1.0 - right_stick.y * delta * 1.2)   # up = zoom in
		_right_trigger_used_for_zoom = true
	if not right_trigger:
		_trigger_scrollbar = null
	if left_trigger and absf(left_stick.y) > 0.25:
		_zoom_view(1.0 - left_stick.y * delta * 1.2)
	# Trigger held still on the map: aim at that tile (a click there selects whoever stands on it instead)
	if right_trigger and not _right_trigger_used_for_zoom and _drag_id == "" and _pointed_panel == null \
			and _pointed_minimap == null and _pointed_overlay == "" and button == "":
		_hold_tile_press(hex_map.pick(origin, direction))
	elif not right_trigger:
		_press_key = null

	# Right stick: scrolls the card you're pointing at; otherwise raises / lowers the table
	_right_grip_down = _right_hand.get_float("grip") > 0.6
	if right_trigger or _drag_id != "":
		pass
	elif _pointed_panel != null and not _right_grip_down:
		if _pointed_panel == _big_holder:
			if right_stick.length() > 0.3:   # the big screen scrolls both ways (the tech tree is wide)
				big_screen.scroll_by(Vector2(right_stick.x, -right_stick.y) * delta * 900.0)
		elif _pointed_panel == _settings_holder:
			if absf(right_stick.y) > 0.3:
				settings_board.scroll_by(-right_stick.y * delta * 700.0)
		elif _pointed_panel == _overview_holder:
			if right_stick.length() > 0.3:   # wide tables scroll sideways too
				overview_board.scroll_by(Vector2(right_stick.x, -right_stick.y) * delta * 900.0)
		elif _pointed_panel == _city_info_holder or _pointed_panel == _city_prod_holder:
			if absf(right_stick.y) > 0.3:
				var city_board: CityBoard = city_info_board if _pointed_panel == _city_info_holder else city_prod_board
				city_board.scroll_by(-right_stick.y * delta * 700.0)
		elif absf(right_stick.y) > 0.3:
			var menu: ActionMenu = popup_menu if _pointed_panel == _popup_panel else action_menu
			menu.scroll_by(-right_stick.y * delta * 600.0)
	else:
		_stick_moves_table(right_stick, _right_grip_down, delta)

	# Left stick works like the right one: height, or with the grip held, rotate (x) / scale (y)
	if not left_trigger:
		_stick_moves_table(left_stick, _left_hand.get_float("grip") > 0.6, delta)

	# Big maps: hold a grip and move that hand to drag the map across the table
	for hand: XRController3D in [_left_hand, _right_hand]:
		if hand.get_float("grip") > 0.6 and hex_map.is_windowed():
			if _grab_last.has(hand):
				hex_map.pan_view(-_global_to_map_delta(hand.global_position - _grab_last[hand]))
			_grab_last[hand] = hand.global_position
		else:
			_grab_last.erase(hand)


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


## Right trigger released: click what's pointed at, unless the trigger was held to zoom or to aim at a tile.
func _on_xr_button_released(is_right: bool, button: String) -> void:
	if not is_right or button != "trigger_click":
		return
	var long_pressed := _long_pressed
	_long_pressed = false
	_press_key = null
	if _end_board_drag():
		return   # that was a drag, not a click
	if _right_trigger_used_for_zoom:
		_right_trigger_used_for_zoom = false
		return
	if _pointed_panel != null:
		_pointed_panel.click(_pointed_pixel)
		return
	if _pointed_minimap != null:
		_glide_view_to(_pointed_minimap)
		return
	if _pointed_overlay != "":
		toggle_overlay(_pointed_overlay)
		return
	if not _board_at(_right_hand.global_position, -_right_hand.global_transform.basis.z).is_empty():
		return   # a click on the info board does nothing (grab and drag moves it)
	if _hovered_button != "":
		press_table_button(_hovered_button)
		return
	var key: Variant = hex_map.pick(_right_hand.global_position, -_right_hand.global_transform.basis.z)
	if key != null and not long_pressed:
		click_tile(key)


func _on_xr_button(is_right: bool, button: String) -> void:
	if is_right:
		match button:
			"trigger_click":
				_right_trigger_used_for_zoom = false   # the click itself happens on release
				if not _begin_board_drag(_right_hand.global_position, -_right_hand.global_transform.basis.z):
					_begin_tile_press(hex_map.pick(_right_hand.global_position, -_right_hand.global_transform.basis.z))
			"ax_button":
				end_turn()
			"by_button":
				if keyboard_shown():
					_close_keyboard()
				elif not _pick.is_empty():
					await cancel_pick()
				elif not _city_place.is_empty():
					_cancel_city_place()
				elif _city_view:
					await exit_city_view()
				else:
					found_city()
	else:
		match button:
			"ax_button":   # X
				cycle_unit(1)
			"by_button":   # Y
				cycle_unit(-1)
			"primary_click":
				recenter_table()
