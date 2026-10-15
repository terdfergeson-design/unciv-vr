# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node
## Desktop: boards that pop out of the game's window into windows of their own, for a second (or third) monitor.
##
## Every desktop board is a Control on a CanvasLayer inside the one game window (main.gd's _register_desktop_window).
## A small ↗ button on a board's top strip moves the board into a native OS window of its own: the map keeps the game
## window, the tech tree or the empire overview goes on the other monitor. The board scales with its window (resize it
## freely, the board keeps its shape), shows and hides whenever the game shows or hides it, and the game's key
## shortcuts still work while that window has the keyboard. Closing the window, or its "Put back" button, returns the
## board to the game window. Which boards are out, on which monitor, where and how big, is remembered in the settings
## ("desktop_popouts"); a board whose monitor is gone (a laptop undocked) simply stays in the game window.

const POPPABLE := ["wide", "overview", "city_info", "city_prod", "settings", "pedia"]   # and every "panel:<folder>"
const TITLES := {
	"wide": "Tech tree, policies, diplomacy",
	"overview": "Empire overview",
	"city_info": "City",
	"city_prod": "City",
	"settings": "Settings",
	"pedia": "Civilopedia",
}
const Lang := preload("res://scripts/lang.gd")
const SETTING := "desktop_popouts"
const BUTTON_SIZE := Vector2(30, 24)
const NO_WINDOWS_HINT := "Boards can't get windows of their own while the game runs inside the Godot editor. In its Game tab, open the ⋮ menu and untick \"Embed Game on Next Play\", then run it again."

var main: Node
var _out: Dictionary = {}          # id -> {window, control, layer, last_rect: Rect2i, shown: bool}
var _buttons: Dictionary = {}      # id -> the ↗ Button over the board in the game window
var _button_layer: CanvasLayer
var _dirty_since := -1.0           # a window moved or was resized: save once it has settled


func _init(owner_main: Node) -> void:
	main = owner_main


func _ready() -> void:
	_button_layer = CanvasLayer.new()
	_button_layer.name = "PopOutButtons"
	_button_layer.layer = 125   # over every board, however they've been raised
	add_child(_button_layer)


## Whether this desktop can open more native windows at all (not in single-window mode, not on the headset).
static func supported() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS) and not OS.has_feature("android")


static func poppable(id: String) -> bool:
	return id in POPPABLE or id.begins_with("panel:")


## Whether [param point] (game-window pixels) is on one of the ↗ buttons - main.gd's board dragging leaves those
## clicks alone (the buttons sit on the boards' top strips, which are otherwise drag handles).
func button_at(point: Vector2) -> bool:
	for id: String in _buttons:
		var button: Button = _buttons[id]
		if button.visible and Rect2(button.position, button.size).grow(2.0).has_point(point):
			return true
	return false


## The ↗ button of board [param id] (tests), or null.
func button_of(id: String) -> Button:
	return _buttons.get(id)


func is_out(id: String) -> bool:
	return _out.has(id)


func window_of(id: String) -> Window:
	return _out[id]["window"] if _out.has(id) else null


## main.gd registered a desktop board: give it its ↗ button, and put it back out if it was out last time.
func registered(id: String, control: Control, layer: CanvasLayer) -> void:
	if not poppable(id) or not supported():
		return
	var button := Button.new()
	button.text = "↗"
	button.tooltip_text = "Pop out into its own window"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = BUTTON_SIZE
	button.size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 16)
	button.visible = false
	button.pressed.connect(func() -> void: pop_out(id))
	_button_layer.add_child(button)
	_buttons[id] = button
	var saved: Variant = (main.settings.get(SETTING, {}) as Dictionary).get(id)
	if saved is Dictionary:
		var rect := Rect2i(Vector2i(int(saved.get("x", 0)), int(saved.get("y", 0))), Vector2i(int(saved.get("w", 0)), int(saved.get("h", 0))))
		if rect.size.x > 50 and rect.size.y > 50 and _on_some_screen(rect):
			_pop_out_now.call_deferred(id, control, layer, rect)
		else:
			_forget(id)   # its monitor isn't there any more: it stays in the game window


## Moves board [param id] into a window of its own: on another monitor if there is one, else next to the game.
func pop_out(id: String) -> void:
	if _out.has(id) or not main._desktop_windows.has(id):
		return
	var entry: Dictionary = main._desktop_windows[id]
	var control: Control = entry["control"]
	_pop_out_now(id, control, entry["layer"], _first_rect(control))
	_save()
	var window := window_of(id)
	if window != null:   # the player asked for it: it comes up in front, with the keyboard
		window.grab_focus.call_deferred()


func _pop_out_now(id: String, control: Control, layer: CanvasLayer, rect: Rect2i) -> void:
	if _out.has(id) or not is_instance_valid(control):
		return
	var window := Window.new()
	window.visible = false       # a window can only be made native while it's hidden
	window.name = "PopOut_" + id.replace(":", "_")
	window.title = "Unciv VR - " + Lang.t(_title(id, control))
	window.force_native = true   # a real OS window, even though the game window embeds its others
	window.transient = true      # stays above the game window (a tool window): clicking the map doesn't bury it
	window.wrap_controls = false
	window.min_size = Vector2i(240, 160)
	# The board keeps its design size and shape however big the window is made (and whatever the monitor's scaling)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = Vector2i(_design_size(control))
	window.size = rect.size
	window.position = rect.position
	main.add_child(window)
	control.reparent(window, false)
	if control.has_method("fit_height") and "size_pixels" in control:
		control.call("fit_height", float(control.get("size_pixels").y))   # out here a panel gets its full height
	control.scale = Vector2.ONE
	control.position = Vector2.ZERO
	var back := Button.new()
	back.text = "Put back"
	back.tooltip_text = "Put back in the main window"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 15)
	back.pressed.connect(func() -> void: pop_back(id))
	window.add_child(back)
	back.size = back.get_combined_minimum_size()
	back.position = Vector2(_design_size(control).x - back.size.x - 6, 4)
	window.close_requested.connect(func() -> void: pop_back(id))
	window.window_input.connect(_forward_input)
	window.size_changed.connect(_mark_dirty)
	window.focus_exited.connect(_mark_dirty)
	_out[id] = {"window": window, "control": control, "layer": layer, "back": back, "last_rect": rect, "shown": false}
	_sync_one(id)
	if window.is_embedded():
		# No real OS window to be had - the game is running inside the Godot editor's Game tab, which keeps every
		# window inside it. Put the board straight back and say how to get real windows.
		pop_back(id)
		main._set_status(NO_WINDOWS_HINT)


## Back into the game window, where it was before (main.gd's saved spot for it).
func pop_back(id: String) -> void:
	if not _out.has(id):
		return
	var out: Dictionary = _out[id]
	_out.erase(id)
	var control: Control = out["control"]
	var layer: CanvasLayer = out["layer"]
	var window: Window = out["window"]
	if is_instance_valid(control) and is_instance_valid(layer):
		control.reparent(layer, false)
	if is_instance_valid(window):
		window.queue_free()
	_forget(id)
	main._refit_desktop_board(id)
	main.get_window().grab_focus()


## Keeps every popped-out window in step with its board: shown when the game shows the board, hidden when it
## hides it. Places the ↗ buttons on the boards still in the game window. Saves moved windows once they settle.
func _process(_delta: float) -> void:
	for id: String in _out.keys():
		_sync_one(id)
	for id: String in _buttons:
		var button: Button = _buttons[id]
		var entry: Dictionary = main._desktop_windows.get(id, {})
		var control: Control = entry.get("control")
		var layer: CanvasLayer = entry.get("layer")
		var up: bool = not _out.has(id) and is_instance_valid(control) and is_instance_valid(layer) \
			and layer.visible and control.is_visible_in_tree()
		button.visible = up
		if up:
			var rect := control.get_global_rect()
			button.position = Vector2(rect.end.x - BUTTON_SIZE.x - 6.0, rect.position.y + 4.0)
	if _dirty_since >= 0.0 and Time.get_ticks_msec() / 1000.0 - _dirty_since > 1.0:
		_dirty_since = -1.0
		_save()


func _sync_one(id: String) -> void:
	var out: Dictionary = _out[id]
	var window: Window = out["window"]
	var control: Control = out["control"]
	var layer: CanvasLayer = out["layer"]
	if not is_instance_valid(window) or not is_instance_valid(control):
		_out.erase(id)
		return
	control.scale = Vector2.ONE       # main.gd's fit-to-the-game-window sizing doesn't apply out here
	control.position = Vector2.ZERO
	var design := Vector2(window.content_scale_size)
	if control.size != design:
		control.size = design
	var wanted: bool = is_instance_valid(layer) and layer.visible and control.visible
	if wanted != window.visible:
		window.visible = wanted
		if wanted and window.is_inside_tree() and not window.has_focus():
			main.get_window().grab_focus.call_deferred()   # the game opened it (T, E...): it shows on top, the keyboard stays with the game
	var rect := Rect2i(window.position, window.size)
	if wanted and rect != out["last_rect"]:
		out["last_rect"] = rect
		_mark_dirty()


## The game's key shortcuts (End turn, T, E, Esc...) work while a popped-out window has the keyboard.
func _forward_input(event: InputEvent) -> void:
	if event is InputEventKey:
		main.get_window().push_input.call_deferred(event)


func _mark_dirty() -> void:
	_dirty_since = Time.get_ticks_msec() / 1000.0


func _save() -> void:
	var saved: Dictionary = (main.settings.get(SETTING, {}) as Dictionary).duplicate()
	for id: String in _out:
		var rect: Rect2i = _out[id]["last_rect"]
		var window: Window = _out[id]["window"]
		if is_instance_valid(window) and window.visible:
			rect = Rect2i(window.position, window.size)
		saved[id] = {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y,
			"screen": DisplayServer.get_screen_from_rect(Rect2(rect))}
	main.settings[SETTING] = saved
	main._save_settings()


func _forget(id: String) -> void:
	var saved: Dictionary = (main.settings.get(SETTING, {}) as Dictionary).duplicate()
	if saved.has(id):
		saved.erase(id)
		main.settings[SETTING] = saved
		main._save_settings()


## Where a board first pops out to: centred on a monitor the game isn't on, if there is one, at a size that fits it.
func _first_rect(control: Control) -> Rect2i:
	var game_screen := main.get_window().current_screen
	var screen := game_screen
	for s in DisplayServer.get_screen_count():
		if s != game_screen:
			screen = s
			break
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var design := _design_size(control)
	var scale_by := minf(1.0, minf(usable.size.x * 0.9 / design.x, usable.size.y * 0.9 / design.y))
	var window_size := Vector2i(design * scale_by)
	var at := usable.position + (usable.size - window_size) / 2
	if screen == game_screen:   # one monitor: offset it, so it doesn't land exactly on top of where it was
		at += Vector2i(40, 40)
	return Rect2i(at, window_size)


static func _design_size(control: Control) -> Vector2:
	# A board's own SIZE is what it's drawn for (its Control can report more: the tech tree grows to hold the
	# whole tree and shows a 1600 x 700 window of it); panels give theirs as size_pixels.
	var design := control.size
	var script: Script = control.get_script()
	var constants: Dictionary = script.get_script_constant_map() if script != null else {}
	if constants.get("SIZE") is Vector2:
		design = constants["SIZE"]
	elif "size_pixels" in control:
		design = Vector2(control.get("size_pixels"))
	return Vector2(maxf(design.x, 100.0), maxf(design.y, 100.0))


func _title(id: String, control: Control) -> String:
	if TITLES.has(id):
		return TITLES[id]
	if "spec" in control and control.get("spec") is Dictionary:
		return str(control.get("spec").get("name", id.trim_prefix("panel:")))
	return id.trim_prefix("panel:")


static func _on_some_screen(rect: Rect2i) -> bool:
	var probe := rect.position + Vector2i(mini(60, rect.size.x / 2), 12)   # the title bar has to be reachable
	for s in DisplayServer.get_screen_count():
		if Rect2i(DisplayServer.screen_get_position(s), DisplayServer.screen_get_size(s)).has_point(probe):
			return true
	return false
