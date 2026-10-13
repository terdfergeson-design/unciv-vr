# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## Unciv's tutorial task card ("Move a unit!", "Found a city!"...): the first task Unciv's rules say is up now
## (getState tutorialTask). Unciv words its tasks for its own screens ("Click the city button twice"), so the
## ones that differ here say how to do it with the laser or the mouse instead; mods' tasks keep their own words.
## Hide puts it away until the next task comes up.
##
## Emits chosen(kind, value): "task_choice" ("<event name>|<choice index>"), "task_hide" (event name).

signal chosen(kind: String, value: String)

const CivilopediaBoard := preload("res://scripts/civilopedia_board.gd")
const Icons := preload("res://scripts/icons.gd")

const WIDTH := 520.0
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.64, 0.68, 0.76)

## How to do each of Unciv's tasks here: task -> [with the laser, with the mouse]
const HOW := {
	"Move unit": ["Point at one of your units and pull the trigger, then point at a tile and pull twice: once to aim, once to go.",
		"Click one of your units, then click a tile twice: once to aim, once to go."],
	"Found city": ["Select the Settler and press Found city on its card (or B).", "Select the Settler and press Found city on its card (or F)."],
	"Enter city screen": ["Point at one of your cities and pull the trigger, then press City view on its card.",
		"Click one of your cities, then press City view on its card."],
	"Pick technology": ["Open the tech tree from your wrist card and pick something to research.",
		"Open the tech tree (T) and pick something to research."],
	"Pick construction": ["Open one of your cities and pick something for it to build from its card.",
		"Click one of your cities and pick something for it to build from its card."],
	"Pass a turn": ["Give your units their orders, then press End turn on the table (or A).",
		"Give your units their orders, then press End turn (or Space)."],
	"Reassign worked tiles": ["In a city's view, point at one of its tiles and pull the trigger to work it, or to stop working it.",
		"In a city's view, click one of its tiles to work it, or to stop working it."],
	"Open the options table": ["Press Settings on the table.", "Press Settings on the table (or O)."],
	"Construct an improvement": ["Build a Worker, move it to a Plains or Grassland tile, press Construct improvement on its card and choose the Farm. Leave it there until the farm is finished.",
		"Build a Worker, move it to a Plains or Grassland tile, press Construct improvement on its card and choose the Farm. Leave it there until the farm is finished."],
	"Move an air unit": ["Select an air unit and move it to another of your cities in range.", "Select an air unit and move it to another of your cities in range."],
	"See your stats breakdown": ["Turn to the empire overview off to your right and open its Stats tab.",
		"Open the empire overview (E) and its Stats tab."],
}

var task: Dictionary = {}
var _box: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.13, 0.2, 0.96)
	style.border_color = Color(0.85, 0.7, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)


## Shows a getState tutorialTask. [param in_vr]: word it for the laser rather than the mouse.
func show_task(new_task: Dictionary, in_vr: bool) -> void:
	task = new_task
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var top := HBoxContainer.new()
	_box.add_child(top)
	var icon := TextureRect.new()
	icon.texture = Icons.get_icon("other", "ExclamationMark")
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(icon)
	var caption := Label.new()
	caption.text = "Tutorial task"
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", DIM)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(caption)
	var event_name := str(task.get("name", ""))
	top.add_child(_button("Hide", func() -> void: chosen.emit("task_hide", event_name), Color(0.3, 0.22, 0.22), 15))
	var lines := lines_for(task, in_vr).map(func(line: Dictionary) -> Dictionary:
		if line.has("text"):
			line = line.duplicate()
			line["text"] = tr(str(line["text"]))
		if line.get("centered", false) and not line.has("color"):   # the task's title, in the card's gold
			var title := line.duplicate()
			title["color"] = "#f5d77a"
			title["header"] = 5
			return title
		return line)
	CivilopediaBoard.render_lines(_box, lines, WIDTH - 40.0, func(_target: String) -> void: pass, 20, false)
	for choice: Dictionary in task.get("choices", []):
		var index := int(choice.get("index", 0))
		_box.add_child(_button(str(choice.get("text", "OK")), func() -> void: chosen.emit("task_choice", "%s|%d" % [event_name, index]),
			Color(0.2, 0.4, 0.28), 18))
	# The wrapped labels only know their height once they've been laid out at the card's width
	size = Vector2(WIDTH, 0)
	await get_tree().process_frame
	reset_size()


## The task's lines, with the instructions swapped for ours where Unciv's talk about its own screens.
static func lines_for(new_task: Dictionary, in_vr: bool) -> Array:
	var lines: Array = new_task.get("lines", [])
	var how: Array = HOW.get(str(new_task.get("task", "")), [])
	if how.is_empty():
		return lines
	var out: Array = []
	var replaced := false
	for line: Dictionary in lines:
		var plain_text: bool = line.has("text") and not line.get("centered", false) and not line.has("link")
		if plain_text:
			if not replaced:
				out.append({"text": how[0] if in_vr else how[1]})
				replaced = true
			continue
		out.append(line)
	if not replaced:
		out.append({"text": how[0] if in_vr else how[1]})
	return out


## The caption row along the top is the handle for moving the card in VR.
func grab_bar_contains(pixel: Vector2) -> bool:
	return pixel.y >= 0.0 and pixel.y <= 40.0 and pixel.x < size.x - 90.0   # not the Hide button


func _button(text: String, pressed: Callable, color: Color, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	for state: String in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color if state == "normal" else (color.lightened(0.15) if state == "hover" else color.darkened(0.15))
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(pressed)
	return button
