extends PanelContainer
## The unit card: what the selected unit is, what it can do, and turn controls.
## Used as-is on the desktop HUD, and rendered into a SubViewport on the left wrist in VR.

## kind is "action" (value = UnitActionType name), "improvement" (value = improvement name),
## "end_turn" or "next_unit".
signal chosen(kind: String, value: String)
## Emitted after the card's contents change, so whoever places it can re-fit it.
signal layout_changed

const WIDTH := 360

var _title: Label
var _info: Label
var _buttons: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	box.add_child(HSeparator.new())

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 4)
	box.add_child(_buttons)

	box.add_child(HSeparator.new())
	var turn_row := HBoxContainer.new()
	turn_row.add_theme_constant_override("separation", 6)
	box.add_child(turn_row)
	turn_row.add_child(_make_button("Next unit", func() -> void: chosen.emit("next_unit", ""), Color(0.25, 0.3, 0.4)))
	turn_row.add_child(_make_button("End turn", func() -> void: chosen.emit("end_turn", ""), Color(0.55, 0.35, 0.1)))
	show_unit({})


## Rebuilds the card for a getUnit result (or an empty Dictionary for "nothing selected").
func show_unit(unit: Dictionary) -> void:
	if _buttons == null:
		return
	for child in _buttons.get_children():
		child.queue_free()

	if unit.is_empty():
		_title.text = "No unit selected"
		_info.text = "Point at one of your units to select it."
		layout_changed.emit()
		return

	_title.text = str(unit.get("name", "?"))
	var lines: Array[String] = []
	lines.append("Moves %s/%d   Health %d" % [str(snappedf(float(unit.get("movement", 0)), 0.1)),
		int(unit.get("maxMovement", 0)), int(unit.get("health", 100))])
	if int(unit.get("strength", 0)) > 0:
		var strength := "Strength %d" % int(unit["strength"])
		if int(unit.get("rangedStrength", 0)) > 0:
			strength += "   Ranged %d (range %d)" % [int(unit["rangedStrength"]), int(unit.get("range", 1))]
		lines.append(strength)
	var work: Dictionary = unit.get("tileWork", {})
	if work.get("inProgress") != null:
		lines.append("Building %s: %d turns left" % [work["inProgress"], int(work.get("turnsLeft", 0))])
	var targets: Array = unit.get("targets", [])
	if not targets.is_empty():
		lines.append("%d target(s) in reach - shown in red" % targets.size())
	_info.text = "\n".join(lines)

	for action: Dictionary in unit.get("actions", []):
		if not action.get("enabled", false):
			continue
		var type: String = action["type"]
		var title: String = action.get("title", type)
		if action.get("current", false):
			title += "  (active)"
		_buttons.add_child(_make_button(title, func() -> void: chosen.emit("action", type)))

	var improvements: Array = unit.get("improvements", [])
	if not improvements.is_empty():
		var header := Label.new()
		header.text = "Build here:"
		header.add_theme_font_size_override("font_size", 15)
		_buttons.add_child(header)
		for imp: Dictionary in improvements:
			var imp_name: String = imp["name"]
			var turns := int(imp.get("turns", 0))
			var label := imp_name if turns <= 0 else "%s  (%d turns)" % [imp_name, turns]
			_buttons.add_child(_make_button(label, func() -> void: chosen.emit("improvement", imp_name), Color(0.2, 0.35, 0.2)))
	layout_changed.emit()


func _make_button(text: String, on_press: Callable, color := Color(0.2, 0.22, 0.28)) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	button.custom_minimum_size = Vector2(0, 36)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.15) if state == "hover" else (color.darkened(0.2) if state == "pressed" else color)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(on_press)
	return button
