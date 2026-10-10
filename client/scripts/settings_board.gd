# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## The settings board, after Unciv's Options popup: pages down the left (Look, Gameplay, Automation, Controls,
## Game, About), and on each page one row per setting with what it does. Choices with several options (the
## background, table, tileset...) open a list in place, with each option's description, rather than a popup
## window, so they work the same with the VR laser as with the mouse.
## In VR it floats over the table (the strip along the top moves it); on the desktop it's a window in the middle.
##
## Emits chosen(kind, value):
##   "setting" ("key|value"), "setting_toggle" (key), "overlay" (map overlay id), "save_game", "main_menu",
##   "reset_boards", "panel_toggle" (panel folder), "reset_panels", "close"

signal chosen(kind: String, value: String)

const Icons := preload("res://scripts/icons.gd")
const Tileset := preload("res://scripts/tileset.gd")
const ModFolders := preload("res://scripts/mod_folders.gd")
const Sounds := preload("res://scripts/sounds.gd")

const SIZE := Vector2(1280, 820)
const GRAB_HEIGHT := 30.0
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.64, 0.68, 0.76)
const HEADER := Color(0.98, 0.85, 0.45)
const BUTTON := Color(0.2, 0.22, 0.3)
const SELECTED := Color(0.22, 0.42, 0.66)
const ON := Color(0.2, 0.5, 0.32)
const OFF := Color(0.3, 0.2, 0.2)
const ROW_A := Color(0.1, 0.12, 0.17)
const ROW_B := Color(0.12, 0.14, 0.2)
const CONTROL_WIDTH := 400.0

## [id, caption, icon kind, icon name]
const PAGES := [
	["look", "Look", "other", "Terrains"],
	["gameplay", "Gameplay", "other", "Options"],
	["automation", "Automation", "other", "Timer"],
	["sound", "Sound", "other", "Speaker"],
	["panels", "Panels", "other", "MenuIcon"],
	["controls", "Controls", "other", "Keyboard"],
	["game", "Game and saves", "other", "Score"],
	["about", "About", "other", "Question"],
]

## Unciv's Options > Gameplay that apply here: [settings key, label, what it does, default]
const GAMEPLAY := [
	["checkForDueUnits", "Check for idle units", "End turn first takes you to every unit that still has no orders.", false],
	["autoUnitCycle", "Auto unit cycle", "After you give a unit its orders, the next unit waiting for orders is selected.", true],
	["alternateUnitCycleOrder", "Cycle idle units by distance", "Next / previous unit go to the nearest unit rather than in a fixed order.", false],
	["confirmNextTurn", "Ask for confirmation when ending the turn", "End turn needs a second press.", false],
	["orderTradeOffersByAmount", "Order trade offers by amount", "On the trade table, the biggest offers come first.", true],
]
## Unciv's Options > Automation: [settings key, label, what it does, default]
const AUTOMATION := [
	["autoAssignCityProduction", "Auto-assign city production", "A city that finishes building something picks what to build next itself.", true],
	["autoBuildingRoads", "Auto-build roads", "Automated workers build roads between your cities.", true],
	["automatedWorkersReplaceImprovements", "Automated workers replace improvements", "Automated workers may swap an improvement for a better one.", true],
	["stopAutomatedWorkersRemoveVegetation", "Stop automated workers from removing vegetation", "Automated workers leave forests, jungles and marshes alone.", false],
	["automatedUnitsCanUpgrade", "Automated units can upgrade", "Automated military units upgrade themselves when you can afford it.", false],
	["automatedUnitsChoosePromotions", "Automated units choose promotions", "Automated units pick their own promotions.", false],
	["citiesAutoBombardAtEndOfTurn", "Cities auto-bombard at end of turn", "Cities that can still fire shoot at enemies in range when you end the turn.", false],
	["autoAssignSpecialistsInNewCities", "Auto-assign specialists in new cities", "New cities put their citizens into specialist slots themselves.", true],
]
## The map overlays (Unciv's Display > Visual hints, and the round buttons beside the overview): [id, label, what]
const OVERLAYS := [
	["movement", "Show unit movement arrows", "Where units have just moved and who attacked whom."],
	["yields", "Show tile yields", "Food, production, gold... on every tile."],
	["worked", "Show worked tiles", "Which tiles your cities' citizens work."],
	["resources", "Show resources and improvements", "Resource and improvement symbols on the tiles."],
	["improvements", "Show improvement pictures", "Farms, mines, roads and the like as models."],
	["unit_icons", "Show unit icons", "The small Unciv icon above each unit model."],
]
const PLAYBACK := [["normal", "Show the moves and battles I can see", "Played back in order; the view glides to fights."],
	["fast", "Show them, fast", "The same, at two and a half times the speed."],
	["off", "Don't show them", "The map just updates."]]
const AUTO_MOVE := [["end", "When I end my turn", "Explorers, automated workers and units on long moves go as you end the turn."],
	["start", "At the start of my turn", "They go as your turn starts (Unciv's \"Automated units move on turn start\")."]]
const AUTOSAVE_TURNS := [1, 2, 5, 10, 20, 50, 100, 1000]

## [what, desktop, VR]
const CONTROLS := [
	["Select a unit", "Left-click it", "Point + right trigger: its card pops up above it"],
	["Move / attack", "Click a tile to aim, again to go", "The same with the laser"],
	["Open a city", "Click it", "Point + right trigger: its card floats above the city"],
	["Scroll a card", "Mouse wheel", "Point at it + right stick"],
	["Move the view", "Right-drag orbits, wheel zooms, WASD / middle-drag pans", "Grip + stick: left / right turns the table, up / down scales it"],
	["Table height", "-", "Either stick up / down (the right one when not pointing at a card)"],
	["Zoom the map", "+ / - or Ctrl + wheel", "Hold a trigger + that hand's stick up / down"],
	["Slide the map", "WASD, or click the overview", "Hold a grip and drag; or point at the overview + trigger"],
	["Move a board", "-", "Hold the trigger on its top strip (or on the info board) and move"],
	["End turn", "Space", "A, or the End turn button on the table"],
	["Found a city", "F", "B"],
	["Next / previous unit", "Tab / Shift+Tab", "X / Y"],
	["Idle unit", "N", "The Idle unit button on the table"],
	["Tech tree, policies, diplomacy", "T, P, G", "The wrist card, or the buttons on the boards"],
	["Empire overview", "E", "Always up, off to your right"],
	["Settings", "O", "The Settings button on the table"],
	["Close / deselect", "Esc", "B closes the keyboard and the city view"],
	["Recenter the table", "-", "Left stick click, or the Recenter button"],
]

var page := "look"
var settings: Dictionary = {}
var info: Dictionary = {}           # in_vr, in_lobby, unciv_version, protocol, client_protocol, game{}
var _open_choice := ""              # the choice whose list is open
var _page_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _body: VBoxContainer
var _title: Label
var _row_index := 0


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 1.0)
	style.border_color = Color(0.32, 0.4, 0.58)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var grab := Label.new()
	grab.text = "=====   Settings  -  hold the trigger here and drag to move   ====="
	grab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grab.custom_minimum_size = Vector2(0, GRAB_HEIGHT)
	grab.add_theme_font_size_override("font_size", 15)
	grab.add_theme_color_override("font_color", DIM)
	box.add_child(grab)

	var top := HBoxContainer.new()
	box.add_child(top)
	var icon := TextureRect.new()
	icon.texture = Icons.get_icon("other", "Settings")
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(icon)
	_title = _label("Settings", 28, HEADER)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var saved := _label("Saved on this PC between sessions", 15, DIM)
	saved.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(saved)
	var close := _button("Close", func() -> void: chosen.emit("close", ""), Color(0.42, 0.2, 0.2), 20)
	close.custom_minimum_size = Vector2(140, 46)
	top.add_child(close)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	box.add_child(columns)
	var pages := VBoxContainer.new()
	pages.custom_minimum_size = Vector2(230, 0)
	pages.add_theme_constant_override("separation", 6)
	columns.add_child(pages)
	for p: Array in PAGES:
		var id: String = p[0]
		var button := _button(p[1], func() -> void: show_page(id), BUTTON, 20)
		button.icon = Icons.get_icon(p[2], p[3])
		button.add_theme_constant_override("icon_max_width", 30)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 56)
		pages.add_child(button)
		_page_buttons[id] = button

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	_scroll.add_child(_body)
	_rebuild()


## Shows the current values. [param new_info]: in_vr, in_lobby, unciv_version, protocol, client_protocol, game.
func update(new_settings: Dictionary, new_info: Dictionary) -> void:
	settings = new_settings
	info = new_info
	_rebuild(true)


func show_page(id: String) -> void:
	page = id
	_open_choice = ""
	_rebuild()


func scroll_by(pixels: float) -> void:
	_scroll.scroll_vertical += int(pixels)


func grab_bar_contains(pixel: Vector2) -> bool:
	return pixel.y >= 0.0 and pixel.y <= GRAB_HEIGHT + 4.0


# region pages --------------------------------------------------------------------------------

func _rebuild(keep_scroll := false) -> void:
	if _body == null:
		return
	var scroll := _scroll.scroll_vertical
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for id: String in _page_buttons:
		var button: Button = _page_buttons[id]
		_paint(button, SELECTED if id == page else BUTTON)
	_row_index = 0
	match page:
		"look": _look_page()
		"gameplay": _gameplay_page()
		"automation": _automation_page()
		"sound": _sound_page()
		"panels": _panels_page()
		"controls": _controls_page()
		"game": _game_page()
		"about": _about_page()
	if keep_scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = scroll
	else:
		_scroll.scroll_vertical = 0


func _look_page() -> void:
	_header("Around the table", "Backgrounds and tables are folders anyone can add: see backgrounds/README.md and tables/README.md.")
	_choice("background", "Background", "The world around the table: sky, light and scenery.", _folder_options("Backgrounds", "background.json"))
	_choice("table", "Table", "What the map lies on. In VR its column stretches to the height you set.", _folder_options("Tables", "table.json"))
	_header("The map", "")
	var tiles := _tileset_options()
	tiles.append(["classic", "Plain coloured hexes", "Flat hexes in Unciv's terrain colours, no models.", ""])
	_choice("tileset", "Tiles", "How terrain, wonders, resources and improvements look. Tilesets work like Unciv's: see tilesets/README.md.", tiles)
	var units: Array = [["tileset", "Same as the tiles", "The unit models that come with the tileset above (the tiles' fallback set fills any gaps).", ""]]
	for option: Array in _tileset_options(true):
		units.append(option)
	units.append(["none", "No models", "Round tokens with Unciv's unit icons.", ""])
	_choice("unitset", "Units", "How units look (Unciv's Unitset): any tileset with unit models (pieces/Units) can supply them.", units)
	_header("Visual hints", "Unciv's map overlays; the round buttons beside the overview turn them on and off too.")
	var overlays: Dictionary = settings.get("overlays", {})
	for overlay: Array in OVERLAYS:
		var id: String = overlay[0]
		_toggle_row(overlay[1], overlay[2], bool(overlays.get(id, false)), func() -> void: chosen.emit("overlay", id))


func _gameplay_page() -> void:
	_header("Turns", "")
	for option: Array in GAMEPLAY:
		_setting_toggle(option)
	var log_turns: Array = []
	for n in range(3, 16):
		log_turns.append([str(n), "%d turns" % n, "", ""])
	_choice("notificationsLogMaxTurns", "Notification log keeps", "How many turns of messages the overview's Notifications tab keeps.", log_turns)
	_header("Other players", "")
	_choice("playback", "Other players' turns", "What you see of the other players' turns after you end yours.", _simple_options(PLAYBACK))


func _automation_page() -> void:
	_header("Automation", "Unciv's own options for automated units and cities.")
	_choice("auto_move", "Automated and exploring units move", "When units on automation, exploring or on multi-turn moves take their steps.", _simple_options(AUTO_MOVE))
	for option: Array in AUTOMATION:
		_setting_toggle(option)


## Unciv's own sound effects, read from its folder when the game runs (see scripts/sounds.gd).
func _sound_page() -> void:
	_header("Sound", "Unciv's own sound effects. They are read from the Unciv folder next to this one when the game runs; put your own in ~/.unciv-vr/Sounds under the same names to replace them.")
	_choice("soundVolume", "Sound effects", "Buttons, moves, battles and the rest. In VR they come from where they happen on the table.", _volume_options())
	_choice("ambienceVolume", "City ambience", "The city noise that loops while you are in a city - Unciv has one for every era.", _volume_options())
	var found: int = (Sounds.available() as Array).size()
	_header("", "%d sounds found. Every unit's attack sound comes from the ruleset, like Unciv's." % found if found > 0
		else "No sounds found. They live in Unciv's android/assets/sounds, next to this folder.")


## Panels: the built-in ones and any in ~/.unciv-vr/Panels, each with an On / Off (panels.gd, panels/README.md).
func _panels_page() -> void:
	var panels: Array = info.get("panels", [])
	var builtin := panels.filter(func(p: Dictionary) -> bool: return p.get("builtin", false))
	var mods := panels.filter(func(p: Dictionary) -> bool: return not p.get("builtin", false))
	_header("Panels", "Boards with a list on them, built from what the game knows. In VR they stand around the table "
		+ "(hold the trigger on the strip along the top to move one); on the desktop they sit down the left side.")
	for panel: Dictionary in builtin:
		_panel_row(panel)
	var home := str(info.get("saves_folder", "")).get_base_dir()
	_header("Your own and mods'", "A panel is a folder with a panel.json - see panels/README.md. Put yours in %s." %
		(home.path_join("Panels") if home != "" else "~/.unciv-vr/Panels"))
	if mods.is_empty():
		_body.add_child(_label("None yet.", 17, DIM))
	for panel: Dictionary in mods:
		_panel_row(panel)
	if bool(info.get("in_vr", false)):
		_header("", "")
		_action_row("Put the panels back", "Every panel goes back to where its panel.json puts it.",
			"Put them back", func() -> void: chosen.emit("reset_panels", ""))


func _panel_row(panel: Dictionary) -> void:
	var folder := str(panel["folder"])
	var about := str(panel.get("description", ""))
	if str(panel.get("author", "")) != "":
		about += ("  " if about != "" else "") + "(by %s)" % panel["author"]
	_toggle_row(str(panel.get("name", folder)), about, bool(panel.get("shown", false)),
		func() -> void: chosen.emit("panel_toggle", folder))


## 0 to 100 in tens, for the volume drop-downs.
func _volume_options() -> Array:
	var options: Array = []
	for percent in range(0, 101, 10):
		options.append([str(percent), "Off" if percent == 0 else "%d%%" % percent, "", ""])
	return options


func _controls_page() -> void:
	_header("Controls", "The right trigger clicks when you let go of it, so holding it to zoom doesn't click anything.")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	for heading: String in ["", "Desktop", "VR"]:
		grid.add_child(_label(heading, 17, HEADER))
	for row: Array in CONTROLS:
		var what := _label(row[0], 16, TEXT)
		what.custom_minimum_size = Vector2(230, 0)
		grid.add_child(what)
		for i in [1, 2]:
			var cell := _label(row[i], 16, DIM)
			cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cell.custom_minimum_size = Vector2(350, 0)
			grid.add_child(cell)
	if bool(info.get("in_vr", false)):
		_header("Boards", "")
		_action_row("Put the boards back", "The overview, info board, big screen, city boards, empire overview and this board go back where they started.",
			"Put them back", func() -> void: chosen.emit("reset_boards", ""))


func _game_page() -> void:
	var game: Dictionary = info.get("game", {})
	if not bool(info.get("in_lobby", false)):
		_header("This game", _game_line(game) if not game.is_empty() else "")
		_action_row("Save game", "Saves it under a name you type, in the bridge's save folder.", "Save...", func() -> void: chosen.emit("save_game", ""))
		_action_row("Main menu", "Back to the main menu; the game keeps running and Resume brings you back.", "Main menu", func() -> void: chosen.emit("main_menu", ""))
	_header("Saves", "")
	var autosave: Array = []
	for n: int in AUTOSAVE_TURNS:
		autosave.append([str(n), "Every turn" if n == 1 else "Every %d turns" % n, "", ""])
	_choice("turnsBetweenAutosaves", "Autosave", "How often the game saves itself as \"Autosave\" (Continue in the main menu loads it).", autosave)
	_info_row("Save folder", str(info.get("saves_folder", "~/.unciv-vr/SaveFiles")))


func _about_page() -> void:
	_header("Unciv VR", "A virtual-reality table for Unciv, the open-source remake of Civilization V.")
	_info_row("Unciv", str(info.get("unciv_version", "not connected")))
	_info_row("Bridge protocol", "v%s (this client expects v%s)" % [info.get("protocol", "?"), info.get("client_protocol", "?")])
	var game: Dictionary = info.get("game", {})
	if not game.is_empty():
		_info_row("This game", _game_line(game))
		if not (game.get("mods", []) as Array).is_empty():
			_info_row("Mods", ", ".join(game["mods"]))
	_header("Your own tilesets, backgrounds and tables", "Put their folders here; they show up in Look.")
	var home := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	for kind: String in ["Tilesets", "Backgrounds", "Tables"]:
		_info_row(kind, home.replace("\\", "/").path_join(".unciv-vr").path_join(kind))
	_info_row("Settings file", ProjectSettings.globalize_path("user://settings.cfg"))
	_header("Licence and credits", "")
	_paragraph("Unciv VR is under the Mozilla Public License 2.0, like Unciv. The icons are Unciv's own, by many authors " +
		"under CC BY / CC BY-SA / CC0 licences (see CREDITS.md and Unciv's docs/Credits.md). The tile, unit, background " +
		"and table models are Unciv VR's own.")


## "Aztecs, turn 4 - Civ V - Gods & Kings, Prince, Standard speed, Small map"
func _game_line(game: Dictionary) -> String:
	var bits: Array = []
	for key: String in ["ruleset", "difficulty"]:
		if str(game.get(key, "")) != "":
			bits.append(str(game[key]))
	if str(game.get("speed", "")) != "":
		bits.append("%s speed" % game["speed"])
	if str(game.get("mapSize", "")) != "":
		bits.append("%s map" % game["mapSize"])
	return "%s, turn %s" % [game.get("civ", "?"), game.get("turn", "?")] + ("  -  " + ", ".join(bits) if not bits.is_empty() else "")


# region option lists -------------------------------------------------------------------------

## [value, title, description, author] for each folder of [param kind].
func _folder_options(kind: String, json_name: String) -> Array:
	var out: Array = []
	for dir_path: String in ModFolders.search_dirs(kind):
		_add_folders(out, dir_path, json_name, dir_path.begins_with("res://"))
	return out


## [param with_units]: only the sets that have unit models (pieces/Units).
func _tileset_options(with_units := false) -> Array:
	var out: Array = []
	for dir_path: String in Tileset.search_dirs():
		_add_folders(out, dir_path, "tileset.json", dir_path.begins_with("res://"), "pieces/Units" if with_units else "")
	return out


func _add_folders(out: Array, dir_path: String, json_name: String, built_in: bool, needs_files_in := "") -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		var json: Variant = ModFolders.read_json(dir_path.path_join(sub).path_join(json_name))
		if json == null:
			continue
		if needs_files_in != "":
			var models := DirAccess.open(dir_path.path_join(sub).path_join(needs_files_in))
			if models == null or models.get_files().is_empty():
				continue
		var author := str(json.get("author", ""))
		var by := ("by " + author if author != "" else "") + ("" if built_in else ("  (your own: %s)" % sub))
		out.append([sub, str(json.get("name", sub)), str(json.get("description", "")), by.strip_edges()])


func _simple_options(list: Array) -> Array:
	var out: Array = []
	for option: Array in list:
		out.append([option[0], option[1], option[2], ""])
	return out


# region rows ---------------------------------------------------------------------------------

func _header(text: String, note: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6 if _body.get_child_count() > 0 else 0)
	_body.add_child(gap)
	_body.add_child(_label(text, 22, HEADER))
	if note != "":
		var label := _label(note, 15, DIM)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(label)
	_row_index = 0


## A row: the setting's name and what it does on the left, [param control] on the right.
func _row(title: String, description: String, control: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_A if _row_index % 2 == 0 else ROW_B
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	_row_index += 1
	_body.add_child(panel)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	outer.add_child(line)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	line.add_child(text)
	text.add_child(_label(title, 19, TEXT))
	if description != "":
		var label := _label(description, 15, DIM)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(label)
	if control != null:
		control.custom_minimum_size = Vector2(CONTROL_WIDTH if control.custom_minimum_size.x == 0 else control.custom_minimum_size.x, 46)
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(control)
	return outer


func _toggle_row(title: String, description: String, on: bool, pressed: Callable) -> void:
	var button := _button("On" if on else "Off", pressed, ON if on else OFF, 19)
	button.custom_minimum_size = Vector2(140, 0)
	_row(title, description, button)


func _setting_toggle(option: Array) -> void:
	var key: String = option[0]
	_toggle_row(option[1], option[2], bool(settings.get(key, option[3])), func() -> void: chosen.emit("setting_toggle", key))


func _action_row(title: String, description: String, caption: String, pressed: Callable) -> void:
	var button := _button(caption, pressed, Color(0.22, 0.32, 0.42), 19)
	button.custom_minimum_size = Vector2(220, 0)
	_row(title, description, button)


func _info_row(title: String, value: String) -> void:
	var label := _label(value, 16, TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.custom_minimum_size = Vector2(640, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row(title, "", label)


func _paragraph(text: String) -> void:
	var label := _label(text, 16, DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)


## Presses the button whose text starts with [param caption] (for tests). Returns whether there was one.
func press(caption: String) -> bool:
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.text.strip_edges().begins_with(caption):
			button.pressed.emit()
			return true
	return false


## A drop-down: shows the chosen option; pressing it opens the list of [param options] ([value, title, description,
## author]) right under the row, and picking one emits "setting" "key|value".
func _choice(key: String, title: String, description: String, options: Array) -> void:
	var current := str(settings.get(key, ""))
	var current_option: Array = []
	for option: Array in options:
		if str(option[0]).to_lower() == current.to_lower():
			current_option = option
	var open := _open_choice == key
	var caption := (str(current_option[1]) if not current_option.is_empty() else current) + ("   ▲" if open else "   ▼")
	var button := _button(caption, func() -> void:
		_open_choice = "" if _open_choice == key else key
		_rebuild(true), SELECTED if open else Color(0.18, 0.26, 0.38), 19)
	button.clip_text = true
	var extra := ""
	if not current_option.is_empty() and (str(current_option[2]) != "" or str(current_option[3]) != ""):
		extra = "\n" + str(current_option[2]) + (("  -  " if str(current_option[2]) != "" else "") + str(current_option[3]) if str(current_option[3]) != "" else "")
	var outer := _row(title, description + extra, button)
	if not open:
		return
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	outer.add_child(list)
	for option: Array in options:
		var value := str(option[0])
		var chosen_now := value.to_lower() == current.to_lower()
		var text := ("✓  " if chosen_now else "     ") + str(option[1])
		if str(option[2]) != "":
			text += "  -  " + str(option[2])
		if str(option[3]) != "":
			text += "  (" + str(option[3]) + ")"
		var pick := _button(text, func() -> void:
			_open_choice = ""
			chosen.emit("setting", key + "|" + value), SELECTED if chosen_now else BUTTON, 17)
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.clip_text = true
		pick.custom_minimum_size = Vector2(0, 42)
		list.add_child(pick)


# region widgets ------------------------------------------------------------------------------

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, pressed: Callable, color: Color, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	_paint(button, color)
	button.pressed.connect(pressed)
	return button


func _paint(button: Button, color: Color) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color if state == "normal" else (color.lightened(0.15) if state == "hover" else color.darkened(0.15))
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		button.add_theme_stylebox_override(state, style)
