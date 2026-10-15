# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## One panel (see panels.gd and panels/README.md) as a board: a strip along the top to grab it by in VR, its
## title, then a scrolling list with a row per item - an icon, a line of text, a dimmer line under it, a short
## text on the right and an optional bar. Rows are buttons when the panel says what a click does.
##
## Emits clicked(action): the panel's "click" filled in from the row ({"do": "select_unit", "id": "12"}).

signal clicked(action: Dictionary)

const Panels := preload("res://scripts/panels.gd")
var _grab_caption: Label
const Icons := preload("res://scripts/icons.gd")

const GRAB_HEIGHT := 26.0
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.64, 0.68, 0.76)
const HEADER := Color(0.98, 0.85, 0.45)
const ROW := Color(0.13, 0.15, 0.21)
const ROW_HOVER := Color(0.19, 0.22, 0.3)
const SELECTED := Color(0.22, 0.42, 0.66)
const BAR_GOOD := Color(0.3, 0.75, 0.35)
const BAR_HURT := Color(0.9, 0.7, 0.2)
const BAR_BAD := Color(0.85, 0.3, 0.25)
## Unciv's pictures for these are dark or coloured art, so they sit on a light disc as they do elsewhere
const LIGHT_DISC := ["building", "improvement", "resource"]
## What a city can "build" forever, turning production into a stat; Unciv's stat icons show them
const PERPETUAL := ["Gold", "Science", "Culture", "Faith"]

var spec: Dictionary
var size_pixels: Vector2
var civ_colors: Dictionary = {}   # civ name -> {inner, outer}, for unit badges in their civ's colours

var _title: Label
var _icon: TextureRect
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array = []
var _height := 0.0    # desktop: the height it was given (fit_height); 0 for its own


func _init(panel_spec: Dictionary) -> void:
	spec = panel_spec
	var metres: Array = spec.get("size", Panels.SIZE)
	var width := float(spec.get("width", Panels.WIDTH))
	size_pixels = Vector2(width, roundf(width * float(metres[1]) / float(metres[0])))


func _ready() -> void:
	custom_minimum_size = Vector2(size_pixels.x, _height if _height > 0.0 else size_pixels.y)
	size = custom_minimum_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.94)
	style.border_color = Color(0.32, 0.4, 0.58)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var grab := _label("=====   %s   =====" % tr(str(spec.get("name", "Panel"))), 13, DIM)
	_grab_caption = grab
	grab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grab.custom_minimum_size = Vector2(0, GRAB_HEIGHT)
	grab.clip_text = true
	box.add_child(grab)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(30, 30)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture = _texture(spec.get("icon"), {})
	_icon.visible = _icon.texture != null
	top.add_child(_icon)
	_title = _label(str(spec.get("name", "")), 22, HEADER)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Icons.thick_scrollbars(_scroll)
	box.add_child(_scroll)
	# The scrollbar is drawn over the list rather than beside it, so keep the rows clear of it
	var room := MarginContainer.new()
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room.add_theme_constant_override("margin_right", 22)
	_scroll.add_child(room)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	room.add_child(_list)


## Desktop: the board keeps its width and takes [param height] pixels (the list scrolls), rather than shrinking.
func fit_height(height: float) -> void:
	_height = height
	custom_minimum_size = Vector2(size_pixels.x, height)
	size = custom_minimum_size


func grab_bar_contains(pixel: Vector2) -> bool:
	return pixel.y >= 0.0 and pixel.y <= GRAB_HEIGHT + 4.0


func scroll_by(pixels: float) -> void:
	_scroll.scroll_vertical += int(pixels)


## Shows [param rows] (from Panels.rows). [param selected]: {"unit": id, "city": name} - what to highlight.
func show_rows(rows: Array, selected: Dictionary) -> void:
	_rows = rows
	if _list == null:
		return
	var keep := _scroll.scroll_vertical
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var count := rows.filter(func(r: Dictionary) -> bool: return not r.has("_group")).size()
	_title.text = Panels.display(str(spec.get("title", spec.get("name", ""))), {}, {"count": count})
	_grab_caption.text = "=====   %s   =====" % tr(str(spec.get("name", "Panel")))
	if count == 0:
		var empty := _label(str(spec.get("empty", "Nothing to show.")), 16, DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	for row: Dictionary in rows:
		if row.has("_group"):
			var heading := _label(str(row["_group"]), 16, HEADER)
			heading.clip_text = true
			_list.add_child(heading)
		else:
			_list.add_child(_make_row(row, _is_selected(row, selected)))
	_restore_scroll.call_deferred(keep)


func _restore_scroll(value: int) -> void:
	if _scroll != null:
		_scroll.scroll_vertical = value


## The row that's the selected unit (or city) stands out, when the panel's "selected" says which to match.
func _is_selected(row: Dictionary, selected: Dictionary) -> bool:
	match str(spec.get("selected", "")):
		"unit":
			return selected.has("unit") and str(row.get("id", "")) == str(selected["unit"])
		"city":
			return selected.has("city") and str(row.get("name", "")) == str(selected["city"])
	return false


func _make_row(row: Dictionary, highlighted: bool) -> Control:
	var look: Dictionary = spec.get("row", {}) if spec.get("row") is Dictionary else {}
	var action := Panels.click_for(spec, row)
	var holder: Control
	if action.is_empty():
		var plain := PanelContainer.new()
		plain.add_theme_stylebox_override("panel", _style(SELECTED if highlighted else ROW))
		holder = plain
	else:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _style(SELECTED if highlighted else ROW))
		button.add_theme_stylebox_override("hover", _style(SELECTED.lightened(0.1) if highlighted else ROW_HOVER))
		button.add_theme_stylebox_override("pressed", _style(SELECTED.lightened(0.2)))
		button.pressed.connect(func() -> void: clicked.emit(action))
		holder = button

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_texture := _texture(look.get("icon"), row)
	if icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var text := _label(Panels.display(str(look.get("text", "{name}")), row), 17, TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(text)
	var detail := Panels.display(str(look.get("detail", "")), row)
	if detail != "":
		var under := _label(detail, 13, DIM)
		under.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(under)
	var bar := _bar(look.get("bar"), row)
	if bar != null:
		words.add_child(bar)
	var right := Panels.display(str(look.get("right", "")), row)
	if right != "":
		var side := _label(right, 15, DIM)
		side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(side)
	holder.add_child(line)
	holder.custom_minimum_size = Vector2(0, 50)
	if holder is Button:
		# A button isn't a container: stretch the row's contents over it by hand
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 6
		line.offset_right = -8
		line.offset_top = 3
		line.offset_bottom = -3
		line.minimum_size_changed.connect(func() -> void:
			holder.custom_minimum_size.y = maxf(50, line.get_combined_minimum_size().y + 6))
	return holder


## "bar": {"value": "{health}", "max": 100, "hideWhenFull": true} - a thin bar under the text, green when
## (nearly) full, yellow, then red.
func _bar(bar_spec: Variant, row: Dictionary) -> Control:
	if not bar_spec is Dictionary:
		return null
	var value := Panels.fill(str(bar_spec.get("value", "")), row)
	var most := Panels.fill(str(bar_spec.get("max", "100")), row)
	if not value.is_valid_float() or not most.is_valid_float() or float(most) <= 0.0:
		return null
	var fraction := clampf(float(value) / float(most), 0.0, 1.0)
	if fraction >= 1.0 and bool(bar_spec.get("hideWhenFull", true)):
		return null
	var back := ColorRect.new()
	back.color = Color(0.05, 0.05, 0.07)
	back.custom_minimum_size = Vector2(0, 5)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = BAR_GOOD if fraction > 0.66 else (BAR_HURT if fraction > 0.33 else BAR_BAD)
	fill.anchor_bottom = 1.0
	fill.anchor_right = fraction
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return back


## An icon from a spec: "kind:name" or {"kind", "name", "civ"} with templates; a unit with a civ is a badge in
## its civ's colours, like the unit card's.
func _texture(icon_spec: Variant, row: Dictionary) -> Texture2D:
	var kind := ""
	var name := ""
	var civ := ""
	if icon_spec is String and ":" in str(icon_spec):
		var bits := str(icon_spec).split(":", true, 1)
		kind = bits[0]
		name = Panels.fill(bits[1], row)
	elif icon_spec is Dictionary:
		kind = str(icon_spec.get("kind", ""))
		name = Panels.fill(str(icon_spec.get("name", "")), row)
		civ = Panels.fill(str(icon_spec.get("civ", "")), row)
	if kind == "" or name == "":
		return null
	if kind == "unit" and civ != "":
		var colours: Dictionary = civ_colors.get(civ, {})
		return Icons.badge("unit", name, colours.get("inner", Color(0.2, 0.25, 0.35)), colours.get("outer", Color.WHITE))
	if kind == "construction":   # whatever a city builds: a unit, a building, or gold / science / culture / faith
		return Icons.get_icon("stat", name) if name in PERPETUAL else Icons.construction(name)
	if kind in LIGHT_DISC:
		return Icons.badge(kind, name, Color(0.86, 0.84, 0.78), Color.WHITE, 0.78)
	return Icons.get_icon(kind, name)


func _style(colour: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
