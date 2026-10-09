# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## The big wide screen above the overview: switches between the technology tree, policies and diplomacy.
## Everything is clickable with the laser (or mouse); the strip along the top is the handle for moving it.
##
## Emits chosen(kind, value):
##   "big_tab" (tech/policies/diplomacy), "tech_select" (tech name: show it, fetch its description),
##   "research" (tech name),
##   "policy_select" (name), "adopt_policy" (name),
##   "war_arm" (civ - first click on Declare war), "declare_war" (civ - the confirming second click),
##   "offer_peace" (civ), "trade_open" (civ), "trade_changed" (the deal on the table changed: get a verdict),
##   "trade_propose" (offer the deal on the table)
signal chosen(kind: String, value: String)

const Icons := preload("res://scripts/icons.gd")

const SIZE := Vector2(1600, 700)
const GRAB_HEIGHT := 34.0
const TABS := [["tech", "Technologies"], ["policies", "Policies"], ["diplomacy", "Diplomacy"]]

# Tech tree layout (pixels)
const COLUMN_WIDTH := 272.0
const ROW_HEIGHT := 66.0
const NODE_SIZE := Vector2(246, 60)
const TREE_TOP := 36.0

const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.66, 0.7, 0.78)
const GOOD := Color(0.45, 0.85, 0.4)
const BAD := Color(1.0, 0.42, 0.32)
const CULTURE := Color(0.8, 0.5, 0.98)
const SCIENCE := Color(0.4, 0.72, 1.0)

var tab := "tech"
var selected_policy := ""       # shown in the details strip on the Policies tab
var selected_tech := ""         # shown in the details bar under the tech tree
var _tech_description := ""     # describeTech text for selected_tech
var war_armed := ""             # civ whose "Declare war" was clicked once (the next click confirms)

# Trading (on the Diplomacy tab): the deal being put together with trade_civ
var trade_civ := ""
var trade_ours: Array = []      # [{name, type, label, amount, countable}] you give
var trade_theirs: Array = []    # ... they give
var _trade_options: Dictionary = {}   # getTradeOptions
var _trade_verdict: Dictionary = {}   # evaluateTrade / proposeTrade message

var _techs: Dictionary = {}
var _policies: Dictionary = {}
var _diplomacy: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _header: Label
var _scroll: ScrollContainer
var _body: Control
var _footer: VBoxContainer      # the tech tab's details bar, under the scrolling tree


## Draws the arrows between techs underneath the tech buttons.
class TreeCanvas extends Control:
	var lines: Array = []   # [from: Vector2, to: Vector2, color]

	func _draw() -> void:
		for line: Array in lines:
			var a: Vector2 = line[0]
			var b: Vector2 = line[1]
			var mid := (a.x + b.x) / 2.0
			draw_polyline(PackedVector2Array([a, Vector2(mid, a.y), Vector2(mid, b.y), b]), line[2], 3.0, true)


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.96)
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
	grab.text = "=====   hold the trigger here and drag to move this screen   ====="
	grab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grab.custom_minimum_size = Vector2(0, GRAB_HEIGHT)
	grab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grab.add_theme_font_size_override("font_size", 15)
	grab.add_theme_color_override("font_color", DIM)
	box.add_child(grab)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	box.add_child(bar)
	for t: Array in TABS:
		var id: String = t[0]
		var button := _button(t[1], func() -> void: chosen.emit("big_tab", id), Color(0.2, 0.22, 0.3), 22)
		button.custom_minimum_size = Vector2(220, 46)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bar.add_child(button)
		_tab_buttons[id] = button
	_header = Label.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header.add_theme_font_size_override("font_size", 20)
	bar.add_child(_header)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_footer = VBoxContainer.new()
	box.add_child(_footer)
	show_tab(tab)


## True when [param pixel] (in this screen's own pixels) is on the move handle along the top.
func grab_bar_contains(pixel: Vector2) -> bool:
	return pixel.y >= position.y and pixel.y < position.y + GRAB_HEIGHT


func scroll_by(amount: Vector2) -> void:
	_scroll.scroll_horizontal += int(amount.x)
	_scroll.scroll_vertical += int(amount.y)


func show_tab(id: String) -> void:
	tab = id
	for key: String in _tab_buttons:
		_restyle(_tab_buttons[key], Color(0.22, 0.42, 0.66) if key == id else Color(0.2, 0.22, 0.3))
	_rebuild()


func set_techs(data: Dictionary) -> void:
	_techs = data
	if tab == "tech":
		_rebuild()


func set_policies(data: Dictionary) -> void:
	_policies = data
	if tab == "policies":
		_rebuild()


func set_diplomacy(data: Dictionary) -> void:
	_diplomacy = data
	if tab == "diplomacy":
		_rebuild()


func _rebuild() -> void:
	if _scroll == null:
		return
	var keep := Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical)
	if _body != null:
		_body.queue_free()
	match tab:
		"tech":
			_body = _build_tech()
		"policies":
			_body = _build_policies()
		_:
			_body = _build_diplomacy()
	_scroll.add_child(_body)
	if tab == "tech":
		_build_tech_details()
	else:
		for child in _footer.get_children():
			child.queue_free()
	await get_tree().process_frame
	_scroll.scroll_horizontal = int(keep.x)
	_scroll.scroll_vertical = int(keep.y)


# region technologies ------------------------------------------------------------------------
# Like Unciv's tech picker: each tech shows its symbol, name and turns, with little icons of what it
# unlocks underneath; clicking one shows everything about it along the bottom, with a Research button.

func _build_tech() -> Control:
	var canvas := TreeCanvas.new()
	var techs: Array = _techs.get("techs", [])
	if techs.is_empty():
		_header.text = "Loading the technology tree..."
		return canvas
	var current: Variant = _techs.get("current")
	_header.text = ("Researching %s" % current if current != null else "Pick something to research!") + \
		"     Science %+d per turn" % int(_techs.get("sciencePerTurn", 0))
	_header.add_theme_color_override("font_color", SCIENCE if current != null else BAD)

	var positions := {}
	var max_column := 0
	var max_row := 0
	for tech: Dictionary in techs:
		positions[tech["name"]] = Vector2(int(tech["column"]) * COLUMN_WIDTH + 10, TREE_TOP + (int(tech["row"]) - 1) * ROW_HEIGHT)
		max_column = maxi(max_column, int(tech["column"]))
		max_row = maxi(max_row, int(tech["row"]))
	canvas.custom_minimum_size = Vector2((max_column + 1) * COLUMN_WIDTH + 20, TREE_TOP + max_row * ROW_HEIGHT + 10)

	# Era names over their first column
	var era_seen := {}
	for tech: Dictionary in techs:
		var era: String = tech.get("era", "")
		var x: float = positions[tech["name"]].x
		if not era_seen.has(era) or x < era_seen[era]:
			era_seen[era] = x
	for era: String in era_seen:
		var label := Label.new()
		label.text = era
		label.position = Vector2(era_seen[era], 4)
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		canvas.add_child(label)

	var current_x := 0.0
	for tech: Dictionary in techs:
		var tech_name: String = tech["name"]
		var at: Vector2 = positions[tech_name]
		if int(tech.get("queueIndex", -1)) == 0:
			current_x = at.x
		var node := _tech_node(tech)
		node.position = at
		canvas.add_child(node)
		for prerequisite: String in tech.get("prerequisites", []):
			if positions.has(prerequisite):
				var from: Vector2 = positions[prerequisite] + Vector2(NODE_SIZE.x, NODE_SIZE.y / 2.0)
				var to := at + Vector2(0, NODE_SIZE.y / 2.0)
				var line_color := Color(0.35, 0.6, 0.38) if tech.get("researched", false) else Color(0.38, 0.42, 0.52)
				canvas.lines.append([from, to, line_color])
	canvas.queue_redraw()
	# Start with the current research in view
	if current_x > 0.0 and _scroll.scroll_horizontal == 0:
		_scroll_to_x.call_deferred(current_x - 300.0)
	return canvas


func _tech_color(tech: Dictionary) -> Color:
	var queue_index := int(tech.get("queueIndex", -1))
	if tech.get("researched", false):
		return Color(0.16, 0.38, 0.2)
	if queue_index == 0:
		return Color(0.2, 0.46, 0.85)
	if queue_index > 0:
		return Color(0.17, 0.3, 0.5)
	if tech.get("researchable", false):
		return Color(0.2, 0.32, 0.4)
	return Color(0.15, 0.16, 0.2)   # locked


## One tech: its symbol, name, turns (or queue place), and a row of what it unlocks.
func _tech_node(tech: Dictionary) -> Button:
	var tech_name: String = tech["name"]
	var color := _tech_color(tech)
	var button := _button("", func() -> void: chosen.emit("tech_select", tech_name), color, 16)
	button.size = NODE_SIZE
	button.custom_minimum_size = NODE_SIZE
	if tech_name == selected_tech:
		var style := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		style.border_color = Color(1, 1, 1)
		style.set_border_width_all(3)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)

	button.add_child(_icon_disc(Icons.get_icon("tech", tech_name), 48.0, Color(0.08, 0.09, 0.13), Vector2(6, 7), tech_name.left(2)))
	var title := Label.new()
	var queue_index := int(tech.get("queueIndex", -1))
	title.text = ("%d. " % (queue_index + 1) if queue_index > 0 else "") + tech_name
	title.position = Vector2(60, 3)
	title.size = Vector2(NODE_SIZE.x - 64, 22)
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(title)
	if not tech.get("researched", false) and str(tech.get("turns", "")).is_valid_int():
		var turns := Label.new()
		turns.text = "%s turns" % tech["turns"]   # (no number while you have no science yet)
		turns.position = Vector2(NODE_SIZE.x - 66, 36)
		turns.add_theme_font_size_override("font_size", 13)
		turns.add_theme_color_override("font_color", DIM)
		turns.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(turns)
	# Little icons of what it unlocks, like the ones on Unciv's tech buttons
	var x := 60.0
	for unlock: Dictionary in tech.get("unlocks", []):
		if x > NODE_SIZE.x - 96:
			break
		var texture := _unlock_icon(unlock)
		if texture == null:
			continue
		var back := Color(0.55, 0.15, 0.12) if unlock.get("kind") == "obsolete" else Color(0.08, 0.09, 0.13)
		button.add_child(_icon_disc(texture, 24.0, back, Vector2(x, 29)))
		x += 26.0
	return button


static func _unlock_icon(unlock: Dictionary) -> Texture2D:
	var unlock_name: String = unlock.get("name", "")
	match unlock.get("kind", ""):
		"unit":
			return Icons.get_icon("unit", unlock_name)
		"building", "wonder":
			return Icons.get_icon("building", unlock_name)
		"resource":
			return Icons.get_icon("resource", unlock_name)
		"improvement":
			return Icons.get_icon("improvement", unlock_name)
		"obsolete":
			var icon := Icons.construction(unlock_name)
			if icon == null:
				icon = Icons.get_icon("improvement", unlock_name)
			return icon if icon != null else Icons.get_icon("resource", unlock_name)
	return null


## A round dark disc with an icon on it (or [param fallback] letters when the icon is missing).
func _icon_disc(texture: Texture2D, diameter: float, back: Color, at: Vector2, fallback := "") -> Control:
	var disc := Panel.new()
	disc.position = at
	disc.size = Vector2(diameter, diameter)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = back
	style.set_corner_radius_all(int(diameter / 2.0))
	disc.add_theme_stylebox_override("panel", style)
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.position = Vector2(diameter, diameter) * 0.14
		image.size = Vector2(diameter, diameter) * 0.72
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(image)
	elif fallback != "":
		var letters := Label.new()
		letters.text = fallback
		letters.size = Vector2(diameter, diameter)
		letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letters.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(letters)
	return disc


## The bar under the tree: the selected tech's symbol, name, status, Unciv's full description, and Research.
func _build_tech_details() -> void:
	for child in _footer.get_children():
		child.queue_free()
	var tech: Dictionary = {}
	for t: Dictionary in _techs.get("techs", []):
		if t["name"] == selected_tech:
			tech = t
	var bar := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", style)
	bar.custom_minimum_size = Vector2(0, 150)
	_footer.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	if tech.is_empty():
		var hint := Label.new()
		hint.text = "Click a tech to see what it does and what it lets you build. The little icons under each tech are what it unlocks."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", DIM)
		row.add_child(hint)
		return
	var symbol_holder := Control.new()
	symbol_holder.custom_minimum_size = Vector2(80, 80)
	symbol_holder.add_child(_icon_disc(Icons.get_icon("tech", selected_tech), 80.0, _tech_color(tech), Vector2.ZERO, selected_tech.left(2)))
	row.add_child(symbol_holder)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title := Label.new()
	var status := "researched"
	if not tech.get("researched", false):
		status = "%s turns" % tech["turns"] if str(tech.get("turns", "")).is_valid_int() else "needs science"
		if int(tech.get("queueIndex", -1)) == 0:
			status = "researching now, " + status
	title.text = "%s   (%s, %d science)" % [selected_tech, status, int(tech.get("cost", 0))]
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	text.add_child(title)
	# Unlocks as icon + name chips
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 10)
	text.add_child(chips)
	for unlock: Dictionary in tech.get("unlocks", []):
		var chip := HBoxContainer.new()
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(26, 26)
		var obsolete: bool = unlock.get("kind") == "obsolete"
		holder.add_child(_icon_disc(_unlock_icon(unlock), 26.0, Color(0.55, 0.15, 0.12) if obsolete else Color(0.08, 0.09, 0.13), Vector2.ZERO))
		chip.add_child(holder)
		var chip_name := Label.new()
		chip_name.text = str(unlock["name"]) + (" (obsolete)" if obsolete else "")
		chip_name.add_theme_font_size_override("font_size", 15)
		chip_name.add_theme_color_override("font_color", BAD if obsolete else TEXT)
		chip.add_child(chip_name)
		chips.add_child(chip)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	text.add_child(scroll)
	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override("font_color", TEXT)
	description.text = _plain(_tech_description) if _tech_description != "" else "..."
	scroll.add_child(description)
	if not tech.get("researched", false):
		var research := _button("Research", func() -> void: chosen.emit("research", selected_tech), Color(0.2, 0.46, 0.85), 22)
		research.custom_minimum_size = Vector2(200, 64)
		research.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(research)


## The bridge's describeTech text for the selected tech.
func set_tech_detail(tech_name: String, description: String) -> void:
	if tech_name != selected_tech:
		return
	_tech_description = description
	if tab == "tech":
		_build_tech_details()


func _scroll_to_x(x: float) -> void:
	await get_tree().process_frame
	_scroll.scroll_horizontal = int(maxf(0.0, x))


# region policies --------------------------------------------------------------------------
# Like Unciv's policy screen: each branch is a box of policy symbols laid out on its grid, with lines to
# what they require; the selected policy's name and effects (and the Adopt button) are along the bottom.

const BRANCH_BOX := Vector2(306, 226)
const POLICY_ICON := 54.0

func _build_policies() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var branches: Array = _policies.get("branches", [])
	if branches.is_empty():
		_header.text = "Loading policies..."
		return box
	var culture := int(_policies.get("culture", 0))
	var needed := int(_policies.get("cultureNeeded", 0))
	_header.text = "Culture %d / %d  (%+d per turn)%s" % [culture, needed, int(_policies.get("culturePerTurn", 0)),
		"     You can adopt a policy!" if _policies.get("canAdopt", false) else ""]
	_header.add_theme_color_override("font_color", CULTURE)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for branch: Dictionary in branches:
		grid.add_child(_branch_box(branch))
	box.add_child(_policy_details())
	return box


## One branch: its symbol and name on top, its policies on the grid below.
func _branch_box(branch: Dictionary) -> Control:
	var canvas := TreeCanvas.new()
	canvas.custom_minimum_size = BRANCH_BOX
	var complete := false
	for policy: Dictionary in branch.get("policies", []):
		if policy.get("isComplete", false) and policy.get("adopted", false):
			complete = true
	var frame := Panel.new()
	frame.size = BRANCH_BOX
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.17)
	style.border_color = Color(0.95, 0.78, 0.3) if complete else (Color(0.3, 0.6, 0.35) if branch.get("adopted", false) else Color(0.25, 0.28, 0.38))
	style.set_border_width_all(3 if complete else 2)
	style.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", style)
	canvas.add_child(frame)

	var head := _policy_symbol(branch, "branch", 46.0)
	head.position = Vector2(10, 8)
	canvas.add_child(head)
	var title := Label.new()
	title.text = str(branch["name"]) + ("  - complete!" if complete else "")
	title.position = Vector2(64, 8)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45) if complete else TEXT)
	canvas.add_child(title)
	var era := Label.new()
	era.text = str(branch.get("era", ""))
	era.position = Vector2(64, 32)
	era.add_theme_font_size_override("font_size", 14)
	era.add_theme_color_override("font_color", DIM)
	canvas.add_child(era)

	# Unciv's grid: columns 1-5 (symbols sit on half steps), rows 1-3
	var step_x := (BRANCH_BOX.x - 24.0 - POLICY_ICON) / 4.0
	var centres := {}
	for policy: Dictionary in branch.get("policies", []):
		if policy.get("isComplete", false):
			continue
		var at := Vector2(12.0 + (int(policy.get("column", 1)) - 1) * step_x, 62.0 + (int(policy.get("row", 1)) - 1) * 54.0)
		centres[policy["name"]] = at + Vector2(POLICY_ICON / 2.0, POLICY_ICON / 2.0)
		var symbol := _policy_symbol(policy, "policy", POLICY_ICON)
		symbol.position = at
		canvas.add_child(symbol)
	for policy: Dictionary in branch.get("policies", []):
		for required: String in policy.get("requires", []):
			if centres.has(required) and centres.has(policy["name"]):
				var from: Vector2 = centres[required] + Vector2(0, POLICY_ICON / 2.0)
				var to: Vector2 = centres[policy["name"]] - Vector2(0, POLICY_ICON / 2.0)
				canvas.lines.append([from, to, Color(0.4, 0.75, 0.45) if policy.get("adopted", false) else Color(0.42, 0.46, 0.56)])
	canvas.queue_redraw()
	return canvas


## A round button with the policy's symbol, coloured by state; clicking it shows it in the details bar.
func _policy_symbol(policy: Dictionary, kind: String, diameter: float) -> Button:
	var policy_name: String = policy["name"]
	var color := Color(0.17, 0.18, 0.23)          # not available yet
	if policy.get("adopted", false):
		color = Color(0.2, 0.55, 0.28)
	elif policy.get("pickable", false):
		color = Color(0.85, 0.6, 0.12)            # can adopt right now
	elif policy.get("available", false):
		color = Color(0.25, 0.36, 0.6)            # allowed, once you have the culture
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(diameter, diameter)
	button.size = Vector2(diameter, diameter)
	var texture := Icons.get_icon(kind, policy_name)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", int(diameter * 0.62))
		var locked: bool = not policy.get("adopted", false) and not policy.get("available", false)
		button.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.45 if locked else 1.0))
	else:
		button.text = policy_name.left(2)   # no icon files: the first letters
		button.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.2) if state == "hover" else color
		style.set_corner_radius_all(int(diameter / 2.0))
		style.border_color = Color(1, 1, 1) if policy_name == selected_policy else color.lightened(0.35)
		style.set_border_width_all(3 if policy_name == selected_policy else 1)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(func() -> void: chosen.emit("policy_select", policy_name))
	return button


## The bar along the bottom: the selected policy's symbol, name and effects, and Adopt when you can.
func _policy_details() -> Control:
	var bar := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	var picked := _find_policy(selected_policy)
	if picked.is_empty():
		var hint := Label.new()
		hint.text = "Click a symbol to see that policy. Open a branch (its big symbol) before adopting the policies in it."
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", DIM)
		row.add_child(hint)
		return bar
	var is_branch := false
	for branch: Dictionary in _policies.get("branches", []):
		if branch["name"] == picked["name"]:
			is_branch = true
	var big_symbol := _policy_symbol(picked, "branch" if is_branch else "policy", 64.0)
	big_symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(big_symbol)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title := Label.new()
	var status := "adopted" if picked.get("adopted", false) else ("ready to adopt" if picked.get("pickable", false) else \
		("needs more culture" if picked.get("available", false) else "not available yet"))
	title.text = "%s   (%s)" % [picked["name"], status]
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	text.add_child(title)
	var effects := Label.new()
	var lines: Array[String] = []
	for line: String in _plain(str(picked.get("description", ""))).split("\n", false):
		if line.strip_edges() != "" and line.strip_edges() != picked["name"]:
			lines.append(line.strip_edges())
	effects.text = "\n".join(lines) if not lines.is_empty() else "(no special effects)"
	effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effects.add_theme_font_size_override("font_size", 17)
	effects.add_theme_color_override("font_color", TEXT)
	text.add_child(effects)
	if picked.get("pickable", false):
		var policy_name: String = picked["name"]
		var adopt := _button("Adopt", func() -> void: chosen.emit("adopt_policy", policy_name), Color(0.6, 0.4, 0.1), 22)
		adopt.custom_minimum_size = Vector2(200, 64)
		adopt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(adopt)
	return bar


func _find_policy(policy_name: String) -> Dictionary:
	if policy_name == "":
		return {}
	for branch: Dictionary in _policies.get("branches", []):
		if branch["name"] == policy_name:
			return branch
		for policy: Dictionary in branch.get("policies", []):
			if policy["name"] == policy_name:
				return policy
	return {}


# region diplomacy -------------------------------------------------------------------------

func _build_diplomacy() -> Control:
	if trade_civ != "":
		return _build_trade()
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	flow.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	var civs: Array = _diplomacy.get("civs", [])
	_header.text = "Your score: %d" % int(_diplomacy.get("yourScore", 0))
	_header.add_theme_color_override("font_color", TEXT)
	if civs.is_empty():
		var none := Label.new()
		none.text = "You haven't met anyone yet. Explore to find other civilizations and city-states." if not _diplomacy.is_empty() else "Loading..."
		none.add_theme_font_size_override("font_size", 20)
		none.add_theme_color_override("font_color", DIM)
		flow.add_child(none)
		return flow
	for civ: Dictionary in civs:
		flow.add_child(_civ_card(civ))
	return flow


func _civ_card(civ: Dictionary) -> PanelContainer:
	var outer := Color.html(str(civ.get("outerColor", "ffffffff")))
	var inner := Color.html(str(civ.get("innerColor", "333333ff")))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(370, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = inner.darkened(0.6)
	style.border_color = outer
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	var civ_name: String = civ["name"]
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	box.add_child(title_row)
	var emblem := Icons.civ_badge(civ)
	if emblem != null:   # Unciv's nation (or city-state type) symbol in the civ's colours
		var picture := TextureRect.new()
		picture.texture = emblem
		picture.custom_minimum_size = Vector2(52, 52)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title_row.add_child(picture)
	var title := Label.new()
	title.text = civ_name + ("   (city-state)" if civ.get("isCityState", false) else "")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", outer.lightened(0.55) if outer.get_luminance() < 0.35 else outer.lightened(0.2))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(title)
	_card_line(box, str(civ.get("leader", "")), DIM)
	if not civ.get("alive", true):
		_card_line(box, "Destroyed", DIM)
		return card
	if civ.get("atWar", false):
		_card_line(box, "AT WAR", BAD)
	else:
		_card_line(box, "At peace" + ("  (treaty: %d more turns)" % int(civ["turnsOfPeaceTreatyLeft"]) if int(civ.get("turnsOfPeaceTreatyLeft", 0)) > 0 else ""), GOOD)
	var relationship := str(civ.get("relationship", ""))
	if civ.get("isCityState", false):
		_card_line(box, "%s, %s - influence %d%s" % [civ.get("cityStateType", ""), relationship, int(civ.get("influence", 0)),
			"   allied with %s" % civ["ally"] if civ.has("ally") else ""], _mood_color(relationship))
	else:
		_card_line(box, "Feels %s about you%s" % [relationship.to_lower(),
			" (%+d)" % int(civ["opinionOfYou"]) if civ.has("opinionOfYou") else ""], _mood_color(relationship))
	_card_line(box, "Score %d    Cities %d" % [int(civ.get("score", 0)), int(civ.get("cities", 0))], TEXT)

	if not civ.get("isCityState", false):
		box.add_child(_button("Trade", func() -> void: chosen.emit("trade_open", civ_name), Color(0.2, 0.32, 0.5), 18))
	if civ.get("canOfferPeace", false):
		box.add_child(_button("Offer peace", func() -> void: chosen.emit("offer_peace", civ_name), Color(0.2, 0.42, 0.25), 18))
	if civ.get("canDeclareWar", false):
		if war_armed == civ_name:
			box.add_child(_button("Click again to declare war on %s" % civ_name, func() -> void: chosen.emit("declare_war", civ_name),
				Color(0.7, 0.15, 0.12), 17))
		else:
			box.add_child(_button("Declare war", func() -> void: chosen.emit("war_arm", civ_name), Color(0.42, 0.16, 0.14), 18))
	return card


func _mood_color(level: String) -> Color:
	match level:
		"Unforgivable", "Enemy":
			return BAD
		"Afraid", "Competitor":
			return Color(1.0, 0.8, 0.35)
		"Favorable", "Friend", "Ally":
			return GOOD
	return TEXT


func _card_line(parent: Container, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


# region trade ------------------------------------------------------------------------------

## Starts a trade screen with a getTradeOptions result.
func open_trade(options: Dictionary) -> void:
	_trade_options = options
	trade_civ = str(options.get("civ", ""))
	trade_ours = []
	trade_theirs = []
	_trade_verdict = {}
	show_tab("diplomacy")


func _clear_trade() -> void:
	trade_ours = []
	trade_theirs = []
	_trade_verdict = {}
	chosen.emit("trade_changed", "")


func close_trade() -> void:
	trade_civ = ""
	_trade_options = {}
	_rebuild()


func set_trade_verdict(verdict: Dictionary) -> void:
	_trade_verdict = verdict
	if trade_civ != "":
		_rebuild()


## The deal in the form the bridge takes: [{name, type, amount}]
func trade_items(side: Array) -> Array:
	return side.map(func(item: Dictionary) -> Dictionary: return {"name": item["name"], "type": item["type"], "amount": int(item["amount"])})


func _build_trade() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	_header.text = "Trading with %s     Your gold %d, theirs %d" % [trade_civ, int(_trade_options.get("yourGold", 0)), int(_trade_options.get("theirGold", 0))]
	_header.add_theme_color_override("font_color", TEXT)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	box.add_child(columns)
	columns.add_child(_trade_column("You can offer", _trade_options.get("ours", []), trade_ours, true))
	columns.add_child(_trade_column("You give", trade_ours, trade_ours, false))
	columns.add_child(_trade_column("You get", trade_theirs, trade_theirs, false))
	columns.add_child(_trade_column("They can offer", _trade_options.get("theirs", []), trade_theirs, true))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)
	for spec: Array in [["< Back", close_trade], ["Clear", _clear_trade]]:
		var small := _button(spec[0], spec[1], Color(0.25, 0.25, 0.3), 19)
		small.custom_minimum_size = Vector2(140, 52)
		bottom.add_child(small)
	var verdict := Label.new()
	verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict.add_theme_font_size_override("font_size", 20)
	if _trade_verdict.has("message"):
		verdict.text = str(_trade_verdict["message"])
		verdict.add_theme_color_override("font_color", GOOD if _trade_verdict.get("accepted", false) else BAD)
	elif trade_ours.is_empty() and trade_theirs.is_empty():
		verdict.text = "Click items on the outside columns to put them on the table; click them again to take them off."
		verdict.add_theme_color_override("font_color", DIM)
	elif _trade_verdict.get("acceptable", false):
		verdict.text = "%s would accept this." % trade_civ
		verdict.add_theme_color_override("font_color", GOOD)
	else:
		var value := int(_trade_verdict.get("value", 0))
		verdict.text = "%s wants more for this%s." % [trade_civ, " (about %d gold's worth)" % -value if value > -100000 and value < 0 else ""]
		verdict.add_theme_color_override("font_color", BAD)
	bottom.add_child(verdict)
	var propose := _button("Propose deal", func() -> void: chosen.emit("trade_propose", ""), Color(0.55, 0.35, 0.1), 21)
	propose.custom_minimum_size = Vector2(260, 52)
	propose.disabled = trade_ours.is_empty() and trade_theirs.is_empty()
	bottom.add_child(propose)
	return box


## One column. Available columns show what's left to offer; clicking moves a chunk onto the table.
## Table columns show the deal; clicking takes a chunk back off.
func _trade_column(title: String, items: Array, table: Array, available: bool) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(370, 0)
	column.add_theme_constant_override("separation", 4)
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	column.add_child(header)
	var shown := 0
	for item: Dictionary in items:
		var on_table := _staged_amount(table, item)
		var amount := int(item.get("amount", 1))
		if available:
			amount -= on_table
			if amount <= 0 and item.get("countable", false):
				continue
			if not item.get("countable", false) and on_table > 0:
				continue
		var text := str(item.get("label", item["name"]))
		if item.get("countable", false):
			text += "  (%d)" % amount
		if int(item.get("duration", -1)) > 0:
			text += "  %d turns" % int(item["duration"])
		var color := Color(0.2, 0.24, 0.32) if available else Color(0.24, 0.36, 0.28)
		var picked := item
		var button := _button(text, func() -> void: _move_trade_item(picked, table, available), color, 17)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		column.add_child(button)
		shown += 1
	if shown == 0:
		var none := Label.new()
		none.text = "(nothing)" if available else "-"
		none.add_theme_color_override("font_color", DIM)
		column.add_child(none)
	return column


func _staged_amount(table: Array, item: Dictionary) -> int:
	for staged: Dictionary in table:
		if staged["name"] == item["name"] and staged["type"] == item["type"]:
			return int(staged["amount"])
	return 0


## Puts a chunk of [param item] on the table (from an available column) or takes one off.
## Gold goes in fifths of what's available, other countable things one at a time.
func _move_trade_item(item: Dictionary, table: Array, adding: bool) -> void:
	_trade_verdict = {}
	var full := _full_amount(item)
	var chunk := 1
	if item["type"] in ["Gold", "Gold_Per_Turn"]:
		chunk = maxi(1, int(round(full / 5.0)))
	for staged: Dictionary in table:
		if staged["name"] == item["name"] and staged["type"] == item["type"]:
			if adding:
				staged["amount"] = mini(full, int(staged["amount"]) + chunk)
			else:
				staged["amount"] = int(staged["amount"]) - chunk
				if int(staged["amount"]) <= 0 or not staged.get("countable", false):
					table.erase(staged)
			chosen.emit("trade_changed", "")
			return
	if adding:
		var entry := item.duplicate()
		entry["amount"] = mini(full, chunk) if item.get("countable", false) else int(item.get("amount", 1))
		table.append(entry)
		chosen.emit("trade_changed", "")


## How much of an item there is in total (from the options, not the table).
func _full_amount(item: Dictionary) -> int:
	for side: String in ["ours", "theirs"]:
		for option: Dictionary in _trade_options.get(side, []):
			if option["name"] == item["name"] and option["type"] == item["type"]:
				return int(option.get("amount", 1))
	return int(item.get("amount", 1))


# region helpers --------------------------------------------------------------------------

## Drops Unciv's icon characters (private-use code points our font doesn't have) and tidies the spaces.
static func _plain(text: String) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 0xE000 or code > 0xF8FF:
			out += text[i]
	return out.replace("  ", " ")


func _button(text: String, on_press: Callable, color: Color, font_size := 17) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	button.clip_text = true
	_restyle(button, color)
	button.pressed.connect(on_press)
	return button


func _restyle(button: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.15) if state == "hover" else (color.darkened(0.2) if state == "pressed" else color)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, style)
