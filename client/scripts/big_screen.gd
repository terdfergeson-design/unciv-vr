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
##   "civ_open" (civ: its full diplomacy page), "civ_close", "diplo_arm" ("civ|action|param": first click on a
##   risky one), "diplo_action" ("civ|action|param": giftGold|250, giftImprovement|x,y,improvement, pledgeProtection,
##   revokeProtection, tribute|gold/worker, marriage, denounce, offerFriendship, makeDemand|<Demand>), "look_at" ("x,y")
##   "religion_slot" (index), "religion_belief" (name), "religion_icon" (icon), "religion_name" (opens the keyboard),
##   "religion_confirm"
##   "victory_page" (ours/global/rankings/charts/demographics), "chart_type" (ranking type), "one_more_turn",
##   "main_menu"
signal chosen(kind: String, value: String)

const Lang := preload("res://scripts/lang.gd")

const Icons := preload("res://scripts/icons.gd")

const SIZE := Vector2(1600, 700)
const GRAB_HEIGHT := 34.0
const TABS := [["tech", "Technologies"], ["policies", "Policies"], ["diplomacy", "Diplomacy"], ["religion", "Religion"], ["victory", "Victory"]]

# Tech tree layout (pixels)
const COLUMN_WIDTH := 272.0
const ROW_HEIGHT := 92.0
const NODE_SIZE := Vector2(246, 86)
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
var order_trade_by_amount := true      # Unciv's "Order trade offers by amount"

# Diplomacy: one civ's full page (Unciv's diplomacy screen right side)
var civ_detail := ""
var diplo_armed := ""          # "civ|action|param" clicked once (the next click confirms)

# Religion: the picker (getReligionChoices) and what's been picked so far
var _religion: Dictionary = {}
var religion_slot := 0
var religion_picks: Array = []     # belief name per slot ("" = not yet)
var religion_icon := ""
var religion_name := ""

# Victory screen (getVictory)
var _victory: Dictionary = {}
var victory_page := "ours"
var map_replay_turn := 0
var map_replay_active := false
var map_replay_playing := false
var _map_replay_slider: HSlider
var _map_replay_turn_label: Label
var _map_replay_play_button: Button
var chart_type := "Score"

var _techs: Dictionary = {}
var _policies: Dictionary = {}
var _diplomacy: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _header: Label
var _scroll: ScrollContainer
var _body: Control
var _footer: VBoxContainer      # the tech tab's details bar, under the scrolling tree


## A line chart of the civs' history for one ranking type (Unciv's victory screen charts).
class LineChart extends Control:
	var series: Array = []   # [{name, color, points: [Vector2(turn, value)]}]

	func _draw() -> void:
		var area := Rect2(Vector2(70, 10), size - Vector2(90, 50))
		draw_rect(area, Color(0.1, 0.12, 0.17))
		var max_turn := 1.0
		var min_turn := 0.0
		var max_value := 1.0
		var min_value := 0.0
		var first := true
		for line: Dictionary in series:
			for point: Vector2 in line["points"]:
				if first:
					min_turn = point.x
					max_turn = point.x
					first = false
				min_turn = minf(min_turn, point.x)
				max_turn = maxf(max_turn, point.x)
				max_value = maxf(max_value, point.y)
				min_value = minf(min_value, point.y)
		var font := get_theme_default_font()
		if first:   # no points at all: Unciv records these at the end of each turn
			draw_string(font, area.get_center() - Vector2(260, 0), tr("No history yet - the charts fill in as turns go by."),
				HORIZONTAL_ALIGNMENT_LEFT, 600, 20, Color(0.7, 0.74, 0.82))
			return
		if max_turn <= min_turn:
			max_turn = min_turn + 1.0
		# Whole-number gridlines at a round step (1, 2, 5, 10, 20, 50...)
		var step := 1.0
		while (max_value - min_value) / step > 5.0:
			step *= 2.0 if str(int(step))[0] == "1" or str(int(step))[0] == "5" else 2.5
		min_value = floorf(min_value / step) * step
		max_value = maxf(min_value + step, ceilf(max_value / step) * step)
		var value := min_value
		while value <= max_value + 0.001:
			var y := area.end.y - (value - min_value) / (max_value - min_value) * area.size.y
			draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(0.25, 0.28, 0.35), 1.0)
			draw_string(font, Vector2(4, y + 6), str(int(value)), HORIZONTAL_ALIGNMENT_RIGHT, 60, 15, Color(0.7, 0.74, 0.82))
			value += step
		var turn_step := maxf(1.0, ceilf((max_turn - min_turn) / 6.0))
		var turn := min_turn
		while turn <= max_turn + 0.001:
			var x := area.position.x + (turn - min_turn) / (max_turn - min_turn) * area.size.x
			draw_string(font, Vector2(x - 14, area.end.y + 22), str(int(turn)), HORIZONTAL_ALIGNMENT_LEFT, 60, 15, Color(0.7, 0.74, 0.82))
			turn += turn_step
		draw_string(font, Vector2(area.end.x - 40, area.end.y + 40), tr("turn"), HORIZONTAL_ALIGNMENT_LEFT, 60, 14, Color(0.55, 0.6, 0.68))
		var order := series.duplicate()
		order.reverse()   # the first line (yours) is drawn last, on top
		for line: Dictionary in order:
			var points := PackedVector2Array()
			for point: Vector2 in line["points"]:
				points.append(Vector2(area.position.x + (point.x - min_turn) / (max_turn - min_turn) * area.size.x,
					area.end.y - (point.y - min_value) / maxf(0.001, max_value - min_value) * area.size.y))
			if points.size() == 1:
				draw_circle(points[0], 4.0, line["color"])
			elif points.size() > 1:
				draw_polyline(points, line["color"], 3.0, true)


## Draws the arrows between techs underneath the tech buttons.
class TreeCanvas extends Control:
	# Fixed coordinates and drawn connectors share one unmirrored coordinate system.
	func _init() -> void:
		layout_direction = Control.LAYOUT_DIRECTION_LTR

	func place(control: Control, at: Vector2) -> void:
		control.set_meta("diagram_position", at)
		add_child(control)
		control.position = at

	func _ready() -> void:
		# Detached Controls calculate offsets using the window locale. Reapply after
		# entering the tree, when the fixed canvas direction is actually inherited.
		for child: Control in get_children():
			if child.has_meta("diagram_position"):
				child.position = child.get_meta("diagram_position")

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
	_header.clip_text = true   # a long header must never make the screen wider than its board
	_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(_header)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Icons.thick_scrollbars(_scroll)
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


func set_religion(data: Dictionary) -> void:
	var mode_changed: bool = str(data.get("mode", "")) != str(_religion.get("mode", "")) or data.get("slots", []).size() != religion_picks.size()
	_religion = data
	if mode_changed:
		religion_slot = 0
		religion_picks = []
		for i in data.get("slots", []).size():
			religion_picks.append("")
		religion_icon = ""
		religion_name = ""
	if tab == "religion":
		_rebuild()


func set_victory(data: Dictionary) -> void:
	_victory = data
	if tab == "victory":
		_rebuild()


func set_map_replay_position(turn: int, playing: bool) -> void:
	map_replay_turn = turn
	map_replay_active = true
	map_replay_playing = playing
	if is_instance_valid(_map_replay_slider):
		_map_replay_slider.set_value_no_signal(turn)
	if is_instance_valid(_map_replay_turn_label):
		_map_replay_turn_label.text = Lang.format("Turn %d of %d", [turn, int(_victory.get("mapReplay", {}).get("endTurn", turn))])
	if is_instance_valid(_map_replay_play_button):
		_map_replay_play_button.text = "Pause" if playing else "Play"


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
		"religion":
			_body = _build_religion()
		"victory":
			_body = _build_victory()
		_:
			_body = _build_diplomacy()
	_scroll.add_child(_body)
	if tab == "tech":
		_build_tech_details()
	else:
		for child in _footer.get_children():
			child.queue_free()
		if tab == "religion":
			_build_religion_footer()
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
	_header.text = (Lang.format("Researching %s", current) if current != null else Lang.t("Pick something to research!")) + \
		Lang.format("     Science %+d per turn", int(_techs.get("sciencePerTurn", 0)))
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
		label.layout_direction = Control.LAYOUT_DIRECTION_LTR
		label.text = era
		label.position = Vector2(era_seen[era], 4)
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		canvas.place(label, Vector2(era_seen[era], 4))

	var current_x := 0.0
	for tech: Dictionary in techs:
		var tech_name: String = tech["name"]
		var at: Vector2 = positions[tech_name]
		if int(tech.get("queueIndex", -1)) == 0:
			current_x = at.x
		var node := _tech_node(tech)
		node.position = at
		canvas.place(node, at)
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
	button.layout_direction = Control.LAYOUT_DIRECTION_LTR
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
	title.layout_direction = Control.LAYOUT_DIRECTION_LTR
	var queue_index := int(tech.get("queueIndex", -1))
	title.text = ("%d. " % (queue_index + 1) if queue_index > 0 else "") + Lang.t(tech_name)
	button.tooltip_text = title.text
	title.position = Vector2(60, 3)
	# Reserve two lines for translated names, above the unlocks and turn count.
	# Keep the tree geometry LTR, but shape the label using its own text direction.
	title.text_direction = Control.TEXT_DIRECTION_AUTO
	title.size = Vector2(NODE_SIZE.x - 68, 48)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(title)
	if not tech.get("researched", false) and str(tech.get("turns", "")).is_valid_int():
		var turns := Label.new()
		turns.layout_direction = Control.LAYOUT_DIRECTION_LTR
		turns.text = Lang.format("%s turns", tech["turns"])   # (no number while you have no science yet)
		turns.position = Vector2(NODE_SIZE.x - 96, 62)
		turns.size = Vector2(92, 20)
		turns.clip_text = true
		turns.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		turns.tooltip_text = turns.text
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
		button.add_child(_icon_disc(texture, 24.0, _unlock_back(unlock), Vector2(x, 55)))
		x += 26.0
	return button


## The disc behind an unlock's icon: Unciv's unit icons are white silhouettes (dark disc); building, wonder,
## improvement and resource pictures are dark line art or colour (light disc, as Unciv shows them); obsolete is red.
static func _unlock_back(unlock: Dictionary) -> Color:
	match unlock.get("kind", ""):
		"obsolete": return Color(0.55, 0.15, 0.12)
		"unit": return Color(0.08, 0.09, 0.13)
	return Color(0.86, 0.84, 0.78)


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
	disc.layout_direction = Control.LAYOUT_DIRECTION_LTR
	disc.position = at
	disc.size = Vector2(diameter, diameter)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = back
	style.set_corner_radius_all(int(diameter / 2.0))
	disc.add_theme_stylebox_override("panel", style)
	if texture != null:
		var image := TextureRect.new()
		image.layout_direction = Control.LAYOUT_DIRECTION_LTR
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.position = Vector2(diameter, diameter) * 0.14
		image.size = Vector2(diameter, diameter) * 0.72
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_child(image)
	elif fallback != "":
		var letters := Label.new()
		letters.layout_direction = Control.LAYOUT_DIRECTION_LTR
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
		status = Lang.format("%s turns", tech["turns"]) if str(tech.get("turns", "")).is_valid_int() else "needs science"
		if int(tech.get("queueIndex", -1)) == 0:
			status = Lang.t("researching now, ") + Lang.t(status)
	title.text = Lang.format("%s   (%s, %d science)", [selected_tech, status, int(tech.get("cost", 0))])
	title.clip_text = true
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
		holder.add_child(_icon_disc(_unlock_icon(unlock), 26.0, _unlock_back(unlock), Vector2.ZERO))
		chip.add_child(holder)
		var chip_name := Label.new()
		chip_name.text = Lang.t(str(unlock["name"])) + (Lang.t(" (obsolete)") if obsolete else "")
		chip_name.add_theme_font_size_override("font_size", 15)
		chip_name.add_theme_color_override("font_color", BAD if obsolete else TEXT)
		chip.add_child(chip_name)
		chips.add_child(chip)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Icons.thick_scrollbars(scroll)
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
	_header.text = Lang.format("Culture %d / %d  (%+d per turn)%s", [culture, needed, int(_policies.get("culturePerTurn", 0)),
		"     You can adopt a policy!" if _policies.get("canAdopt", false) else ""])
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
	frame.layout_direction = Control.LAYOUT_DIRECTION_LTR
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
	canvas.place(head, Vector2(10, 8))
	var title := Label.new()
	title.layout_direction = Control.LAYOUT_DIRECTION_LTR
	title.text = Lang.t(str(branch["name"])) + (Lang.t("  - complete!") if complete else "")
	title.position = Vector2(64, 8)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45) if complete else TEXT)
	canvas.place(title, Vector2(64, 8))
	var era := Label.new()
	era.layout_direction = Control.LAYOUT_DIRECTION_LTR
	era.text = str(branch.get("era", ""))
	era.position = Vector2(64, 32)
	era.add_theme_font_size_override("font_size", 14)
	era.add_theme_color_override("font_color", DIM)
	canvas.place(era, Vector2(64, 32))

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
		canvas.place(symbol, at)
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
	button.layout_direction = Control.LAYOUT_DIRECTION_LTR
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
	title.text = Lang.format("%s   (%s)", [picked["name"], status])
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	text.add_child(title)
	var effects := Label.new()
	var lines: Array[String] = []
	for line: String in _plain(str(picked.get("description", ""))).split("\n", false):
		if line.strip_edges() != "" and line.strip_edges() != picked["name"]:
			lines.append(line.strip_edges())
	effects.text = Lang.join("\n", lines) if not lines.is_empty() else "(no special effects)"
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
	if civ_detail != "":
		for civ: Dictionary in _diplomacy.get("civs", []):
			if civ["name"] == civ_detail:
				return _build_civ_page(civ)
		civ_detail = ""
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	flow.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	var civs: Array = _diplomacy.get("civs", [])
	_header.text = Lang.format("Your score: %d", int(_diplomacy.get("yourScore", 0)))
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
	title.text = Lang.t(civ_name) + (Lang.t("   (city-state)") if civ.get("isCityState", false) else "")
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
		_card_line(box, Lang.t("At peace") + (Lang.format("  (treaty: %d more turns)", int(civ["turnsOfPeaceTreatyLeft"])) if int(civ.get("turnsOfPeaceTreatyLeft", 0)) > 0 else ""), GOOD)
	var relationship := str(civ.get("relationship", ""))
	if civ.get("isCityState", false):
		_card_line(box, Lang.format("%s, %s - influence %d%s", [civ.get("cityStateType", ""), relationship, int(civ.get("influence", 0)),
			Lang.format("   allied with %s", civ["ally"]) if civ.has("ally") else ""]), _mood_color(relationship))
	else:
		_card_line(box, Lang.format("Feels %s about you%s", [relationship,
			" (%+d)" % int(civ["opinionOfYou"]) if civ.has("opinionOfYou") else ""]), _mood_color(relationship))
	_card_line(box, Lang.format("Score %d    Cities %d", [int(civ.get("score", 0)), int(civ.get("cities", 0))]), TEXT)

	var more := _button("Diplomacy...", func() -> void: chosen.emit("civ_open", civ_name), Color(0.3, 0.3, 0.4), 18)
	box.add_child(more)
	if not civ.get("isCityState", false) and civ.get("canTrade", true) and not civ.get("atWar", false):
		box.add_child(_button("Trade", func() -> void: chosen.emit("trade_open", civ_name), Color(0.2, 0.32, 0.5), 18))
	if civ.get("canOfferPeace", false):
		box.add_child(_button("Offer peace", func() -> void: chosen.emit("offer_peace", civ_name), Color(0.2, 0.42, 0.25), 18))
	if civ.get("canDeclareWar", false):
		if war_armed == civ_name:
			box.add_child(_button(Lang.format("Click again to declare war on %s", civ_name), func() -> void: chosen.emit("declare_war", civ_name),
				Color(0.7, 0.15, 0.12), 17))
		else:
			box.add_child(_button("Declare war", func() -> void: chosen.emit("war_arm", civ_name), Color(0.42, 0.16, 0.14), 18))
	return card


## One civ's whole diplomacy page: what Unciv's diplomacy screen offers for it (gifts, tribute, protection,
## quests, friendship, denouncing, demands, promises, how they feel about you), plus trade / peace / war.
func _build_civ_page(civ: Dictionary) -> Control:
	var civ_name: String = civ["name"]
	var outer := Color.html(str(civ.get("outerColor", "ffffffff")))
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	page.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	_header.text = Lang.format("%s%s", [civ_name, "  (city-state)" if civ.get("isCityState", false) else "  -  " + str(civ.get("leader", ""))])
	_header.add_theme_color_override("font_color", outer.lightened(0.3))

	# Left: who they are and how things stand
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 4)
	page.add_child(left)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var emblem := Icons.civ_badge(civ)
	if emblem != null:
		var picture := TextureRect.new()
		picture.texture = emblem
		picture.custom_minimum_size = Vector2(84, 84)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		top.add_child(picture)
	var hello := Label.new()
	hello.text = _plain(str(civ.get("hello", ""))) if str(civ.get("hello", "")) != "" else civ_name
	hello.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hello.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hello.add_theme_font_size_override("font_size", 19)
	hello.add_theme_color_override("font_color", TEXT)
	top.add_child(hello)
	left.add_child(top)
	var back := _button("< All civilizations", func() -> void: chosen.emit("civ_close", ""), Color(0.25, 0.25, 0.3), 18)
	back.custom_minimum_size = Vector2(0, 44)
	left.add_child(back)
	var relationship := str(civ.get("relationship", ""))
	if civ.get("atWar", false):
		_card_line(left, Lang.t("AT WAR") + (Lang.format("  (no peace talks for %d more turns)", int(civ["peaceBlockedTurns"])) if civ.has("peaceBlockedTurns") else ""), BAD)
	if civ.get("isCityState", false):
		_card_line(left, Lang.format("Type: %s    Personality: %s", [civ.get("cityStateType", ""), civ.get("personality", "")]), TEXT)
		_card_line(left, Lang.format("Our relationship: %s (influence %d)", [relationship, int(civ.get("influence", 0))]), _mood_color(relationship))
		if str(civ.get("nextLevel", "")) != "":
			_card_line(left, str(civ["nextLevel"]), DIM)
		if civ.has("allyName"):
			_card_line(left, Lang.format("Ally: %s with %d influence", [civ["allyName"], int(civ.get("allyInfluence", 0))]), TEXT)
		if not civ.get("protectors", []).is_empty():
			_card_line(left, Lang.t("Protected by: ") + Lang.join(", ", civ["protectors"]), TEXT)
		if civ.has("relationshipChangeTurns"):
			_card_line(left, Lang.format("Relationship changes in another %d turns", int(civ["relationshipChangeTurns"])), DIM)
		if not civ.get("resources", []).is_empty():
			_card_line(left, Lang.t("Resources: ") + Lang.join(", ", civ["resources"].map(func(r: Dictionary) -> String: return Lang.format("%s %d", [r["name"], int(r["amount"])]))), TEXT)
		for group: Array in [["friendBonuses", "When Friends:"], ["allyBonuses", "When Allies:"]]:
			var bonuses: Array = civ.get(group[0], [])
			if bonuses.is_empty():
				continue
			_card_line(left, group[1], Color(0.95, 0.82, 0.45))
			for bonus: Dictionary in bonuses:
				_card_line(left, "  " + _plain(str(bonus["text"])), GOOD if bonus.get("active", false) else DIM)
		if civ.has("uniqueUnit"):
			_card_line(left, _plain(str(civ["uniqueUnit"])), DIM)
	else:
		_card_line(left, Lang.format("Feels %s about you%s", [relationship, " (%+d)" % int(civ["opinionOfYou"]) if civ.has("opinionOfYou") else ""]), _mood_color(relationship))
		if civ.get("friends", false):
			_card_line(left, "You have a declaration of friendship.", GOOD)
		if civ.get("denounced", false):
			_card_line(left, "You have denounced them.", BAD)
		for promise: String in civ.get("promises", []):
			_card_line(left, _plain(promise), DIM)
		for modifier: Dictionary in civ.get("modifiers", []):
			var value := int(modifier["value"])
			_card_line(left, Lang.format("%s %s%d", [_plain(str(modifier["text"])), "+" if value > 0 else "", value]), GOOD if value > 0 else BAD)
	_card_line(left, Lang.format("Score %d    Cities %d", [int(civ.get("score", 0)), int(civ.get("cities", 0))]), TEXT)

	# Right: what you can do
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	page.add_child(right)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	right.add_child(actions)
	var add_action := func(text: String, action: String, color: Color, enabled: bool, confirm := "") -> void:
		var key := "%s|%s" % [civ_name, action]
		var label := text
		var colour := color
		if confirm != "" and diplo_armed == key:
			label = confirm
			colour = Color(0.7, 0.18, 0.12)
		var button := _button(label, func() -> void:
			if confirm != "" and diplo_armed != key:
				chosen.emit("diplo_arm", key)
			else:
				chosen.emit("diplo_action", key), colour, 18)
		button.custom_minimum_size = Vector2(300, 50)
		button.clip_text = false   # in a wrapping row: as wide as its text needs
		button.disabled = not enabled
		actions.add_child(button)
	if civ.has("capital"):
		var at := "%d,%d" % [int(civ["capital"]["x"]), int(civ["capital"]["y"])]
		var go := _button("Go to on map", func() -> void: chosen.emit("look_at", at), Color(0.22, 0.3, 0.4), 18)
		go.custom_minimum_size = Vector2(300, 50)
		actions.add_child(go)
	if civ.get("isCityState", false):
		for gift: Dictionary in civ.get("goldGifts", []):
			add_action.call(Lang.format("Gift %d gold (+%d influence)", [int(gift["gold"]), int(gift["influence"])]), "giftGold|%d" % int(gift["gold"]),
				Color(0.5, 0.4, 0.1), gift.get("enabled", false))
		for gift: Dictionary in civ.get("improvementGifts", []):
			add_action.call(Lang.format("Build %s on %s (200 gold)", [gift["improvement"], gift.get("resource", "")]),
				"giftImprovement|%d,%d,%s" % [int(gift["x"]), int(gift["y"]), gift["improvement"]], Color(0.3, 0.4, 0.2), gift.get("enabled", false))
		if civ.get("isProtector", false):
			add_action.call("Revoke protection", "revokeProtection", Color(0.4, 0.28, 0.2), civ.get("canRevoke", false), "Click again: revoke protection?")
		else:
			add_action.call("Pledge to protect", "pledgeProtection", Color(0.2, 0.36, 0.5), civ.get("canPledge", false), "Click again: declare protection?")
		var tribute: Dictionary = civ.get("tribute", {})
		add_action.call(Lang.format("Take %d gold (-15 influence)", int(tribute.get("gold", 0))), "tribute|gold", Color(0.45, 0.3, 0.12), tribute.get("canTakeGold", false))
		add_action.call("Take worker (-50 influence)", "tribute|worker", Color(0.45, 0.3, 0.12), tribute.get("canTakeWorker", false))
		if civ.has("marriage"):
			add_action.call(Lang.format("Diplomatic marriage (%d gold)", int(civ["marriage"]["cost"])), "marriage", Color(0.5, 0.35, 0.5),
				civ["marriage"].get("enabled", false), "Click again: they join your empire")
		if civ.get("atWar", false) and civ.has("canMakePeace"):
			add_action.call("Negotiate peace", "peace", Color(0.2, 0.42, 0.25), civ.get("canMakePeace", false), "Click again: make peace?")
	else:
		if civ.get("canTrade", false):
			var trade := _button("Trade", func() -> void: chosen.emit("trade_open", civ_name), Color(0.2, 0.32, 0.5), 18)
			trade.custom_minimum_size = Vector2(300, 50)
			actions.add_child(trade)
		if civ.get("showFriendship", false):
			add_action.call("Friendship offered - waiting for their answer" if civ.get("friendshipOffered", false) else "Offer declaration of friendship (30 turns)",
				"offerFriendship", Color(0.2, 0.42, 0.3), civ.get("canOfferFriendship", false))
		if civ.get("showDenounce", false):
			add_action.call("Denounce (30 turns)", "denounce", Color(0.45, 0.25, 0.12), civ.get("canDenounce", false), Lang.format("Click again: denounce %s?", civ_name))
		if civ.get("canOfferPeace", false):
			var peace := _button("Negotiate peace", func() -> void: chosen.emit("offer_peace", civ_name), Color(0.2, 0.42, 0.25), 18)
			peace.custom_minimum_size = Vector2(300, 50)
			actions.add_child(peace)
	if civ.get("canDeclareWar", false):
		if war_armed == civ_name:
			var war := _button("Click again to declare war", func() -> void: chosen.emit("declare_war", civ_name), Color(0.7, 0.15, 0.12), 18)
			war.custom_minimum_size = Vector2(300, 50)
			actions.add_child(war)
		else:
			var war := _button("Declare war", func() -> void: chosen.emit("war_arm", civ_name), Color(0.42, 0.16, 0.14), 18)
			war.custom_minimum_size = Vector2(300, 50)
			actions.add_child(war)
	if not civ.get("isCityState", false) and not civ.get("demands", []).is_empty():
		_card_line(right, "Demands:", Color(0.95, 0.82, 0.45))
		var demands := HFlowContainer.new()
		demands.add_theme_constant_override("h_separation", 8)
		demands.add_theme_constant_override("v_separation", 8)
		right.add_child(demands)
		for demand: Dictionary in civ["demands"]:
			var text := _plain(str(demand["text"]))
			match str(demand.get("status", "")):
				"asked": text += Lang.t("  (asked)")
				"agreed": text += Lang.t("  (they agreed)")
			var key := "%s|makeDemand|%s" % [civ_name, demand["id"]]
			var button := _button(text, func() -> void: chosen.emit("diplo_action", key), Color(0.3, 0.26, 0.2), 16)
			button.custom_minimum_size = Vector2(470, 46)
			button.disabled = not demand.get("enabled", false)
			demands.add_child(button)
	if civ.get("isCityState", false):
		var tribute: Dictionary = civ.get("tribute", {})
		if not tribute.get("modifiers", []).is_empty():
			_card_line(right, "Tribute willingness (at least 0 to take gold, at least 30 and a size 4 city for a worker):", Color(0.95, 0.82, 0.45))
			for modifier: Dictionary in tribute["modifiers"]:
				_card_line(right, Lang.format("  %s  %d", [_plain(str(modifier["text"])), int(modifier["value"])]), GOOD if int(modifier["value"]) >= 0 else BAD)
		for quest: Dictionary in civ.get("quests", []):
			_card_line(right, Lang.format("%s%s", [_plain(str(quest["name"])), Lang.format("  (+%d influence)", int(quest["influence"])) if int(quest.get("influence", 0)) > 0 else ""]), Color(0.95, 0.82, 0.45))
			_card_line(right, "  " + _plain(str(quest.get("description", ""))), TEXT)
			if quest.has("turns"):
				_card_line(right, Lang.format("  %d turns remaining", int(quest["turns"])), DIM)
			if quest.has("leader"):
				_card_line(right, "  " + _plain(str(quest["leader"])), DIM)
			if quest.has("progress"):
				_card_line(right, "  " + _plain(str(quest["progress"])), DIM)
	return page


func _mood_color(level: String) -> Color:
	match level:
		"Unforgivable", "Enemy":
			return BAD
		"Afraid", "Competitor":
			return Color(1.0, 0.8, 0.35)
		"Favorable", "Friend", "Ally":
			return GOOD
	return TEXT


## [param wrap]: only where the parent gives the line a width (a column with a minimum width, a full-width box);
## in a grid or a row nothing does, and a wrapping label there shrinks to one letter per line.
func _card_line(parent: Container, text: String, color: Color, wrap := true, font_size := 17) -> void:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


# region religion ---------------------------------------------------------------------------
# Unciv's pantheon picker and religious beliefs picker: the slots to fill on the left, the beliefs that fit
# the selected slot on the right, and (when founding) the symbol and name of your religion.

const BELIEF_COLORS := {"Pantheon": Color("#44c6cc"), "Founder": Color("#c00000"), "Follower": Color("#ccaa44"),
	"Enhancer": Color("#72cc45"), "Any": Color(0.7, 0.7, 0.75)}


## The bar under the religion picker: what you've picked so far and the confirm button, always in view.
func _build_religion_footer() -> void:
	var mode := str(_religion.get("mode", "")) if _religion.get("mode") != null else ""
	if mode == "" or not _religion.get("enabled", true):
		return
	var bar := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", style)
	_footer.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	var missing := religion_picks.count("")
	var summary := Label.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.clip_text = true
	summary.add_theme_font_size_override("font_size", 19)
	var picked := religion_picks.filter(func(p: String) -> bool: return p != "")
	if missing > 0:
		summary.text = Lang.format("Beliefs still to choose: %d%s", [missing, (Lang.format("  (so far: %s)", Lang.join(", ", picked))) if not picked.is_empty() else ""])
		summary.add_theme_color_override("font_color", DIM)
	elif mode == "found" and religion_icon == "":
		summary.text = "Now pick a symbol for your religion (above)."
		summary.add_theme_color_override("font_color", DIM)
	else:
		summary.text = Lang.join(", ", picked)
		summary.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	row.add_child(summary)
	var ready := missing == 0 and (mode != "found" or religion_icon != "")
	var confirm_text: String = {"pantheon": "Follow this pantheon", "found": Lang.format("Found %s", (religion_name if religion_name != "" else religion_icon)),
		"enhance": Lang.format("Enhance %s", _religion.get("displayName", "")), "reform": "Reform"}.get(mode, "Confirm")
	var confirm := _button(confirm_text, func() -> void: chosen.emit("religion_confirm", ""), Color(0.55, 0.35, 0.1), 21)
	confirm.custom_minimum_size = Vector2(340, 58)
	confirm.disabled = not ready
	row.add_child(confirm)


func _build_religion() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	var mode := str(_religion.get("mode", "")) if _religion.get("mode") != null else ""
	_header.add_theme_color_override("font_color", TEXT)
	if _religion.is_empty():
		_header.text = "Loading..."
		return page
	if not _religion.get("enabled", true):
		_header.text = "Religion is off in this game."
		return page
	_header.text = str({"pantheon": "Choose a pantheon belief", "found": "Found your religion", "enhance": "Enhance your religion",
		"reform": "Reform your religion"}.get(mode, str(_religion.get("displayName", "No religion yet"))))

	# What you believe now
	var current: Array = _religion.get("currentBeliefs", [])
	if not current.is_empty():
		var have := HFlowContainer.new()
		have.add_theme_constant_override("h_separation", 8)
		var label := Label.new()
		label.text = Lang.format("%s:", _religion.get("displayName", "Your beliefs"))
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		have.add_child(label)
		for belief: Dictionary in current:
			var chip := _button(Lang.format("%s (%s)", [belief["name"], belief["type"]]), func() -> void: pass, BELIEF_COLORS.get(belief["type"], DIM).darkened(0.55), 16)
			chip.clip_text = false
			have.add_child(chip)
		page.add_child(have)
	if mode == "":
		var note := Label.new()
		note.text = "Nothing to choose right now. Earn faith to found a pantheon; a Great Prophet founds (and later enhances) a religion in one of your cities."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 19)
		note.add_theme_color_override("font_color", DIM)
		page.add_child(note)
		return page

	if mode == "found":
		var icons_row := HFlowContainer.new()
		icons_row.add_theme_constant_override("h_separation", 6)
		icons_row.add_theme_constant_override("v_separation", 6)
		var prompt := Label.new()
		prompt.text = "Symbol:"
		prompt.add_theme_font_size_override("font_size", 19)
		prompt.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		icons_row.add_child(prompt)
		for icon: Dictionary in _religion.get("icons", []):
			var icon_name: String = icon["name"]
			var picked := icon_name == religion_icon
			var button := _button(icon_name, func() -> void: chosen.emit("religion_icon", icon_name),
				Color(0.22, 0.42, 0.66) if picked else Color(0.2, 0.22, 0.3), 15)
			button.icon = Icons.get_icon("religion", icon_name)
			button.add_theme_constant_override("icon_max_width", 30)
			button.disabled = not icon.get("available", true)
			button.clip_text = false
			icons_row.add_child(button)
		page.add_child(icons_row)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		name_label.text = Lang.format("Name: %s", (religion_name if religion_name != "" else (religion_icon if religion_icon != "" else "(pick a symbol)")))
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", TEXT)
		name_row.add_child(name_label)
		var rename := _button("Rename...", func() -> void: chosen.emit("religion_name", ""), Color(0.25, 0.28, 0.38), 17)
		rename.disabled = religion_icon == ""
		rename.custom_minimum_size = Vector2(150, 40)
		name_row.add_child(rename)
		page.add_child(name_row)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	page.add_child(columns)
	# Left: one button per belief to choose
	var slots_box := VBoxContainer.new()
	slots_box.custom_minimum_size = Vector2(430, 0)
	slots_box.add_theme_constant_override("separation", 6)
	columns.add_child(slots_box)
	var slots: Array = _religion.get("slots", [])
	for i in slots.size():
		var index := i
		var type := str(slots[i])
		var picked: String = religion_picks[i] if i < religion_picks.size() else ""
		var text := picked if picked != "" else ("Choose any belief!" if type == "Any" else Lang.format("Choose a %s belief!", type))
		var colour: Color = BELIEF_COLORS.get(type, DIM).darkened(0.45 if i == religion_slot else 0.65)
		var button := _button(Lang.format("%s:  %s", [type, text]), func() -> void: chosen.emit("religion_slot", str(index)), colour, 18)
		button.icon = Icons.get_icon("religion", type)
		button.add_theme_constant_override("icon_max_width", 30)
		button.custom_minimum_size = Vector2(0, 52)
		if i == religion_slot:
			var style := StyleBoxFlat.new()
			style.bg_color = colour
			style.border_color = Color(0.95, 0.85, 0.45)
			style.set_border_width_all(3)
			style.set_corner_radius_all(6)
			style.set_content_margin_all(6)
			button.add_theme_stylebox_override("normal", style)
		slots_box.add_child(button)
	# (the confirm button is in the bar along the bottom - _build_religion_footer - so it never scrolls away)

	# Right: the beliefs that fit the selected slot
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	columns.add_child(list)
	var slot_type := str(slots[religion_slot]) if religion_slot < slots.size() else ""
	for belief: Dictionary in _religion.get("beliefs", []):
		var type := str(belief["type"])
		if slot_type != "Any" and type != slot_type:
			continue
		var belief_name: String = belief["name"]
		var taken_here := religion_picks.has(belief_name) and religion_picks.find(belief_name) != religion_slot
		var available: bool = belief.get("available", false) and not taken_here
		var row := VBoxContainer.new()
		var why := ""
		match str(belief.get("why", "")):
			"taken": why = "  (another religion has it)"
			"yours": why = "  (you have it)"
			"blocked": why = "  (not available)"
		if taken_here:
			why = "  (picked for another slot)"
		var button := _button(Lang.format("%s%s%s", ["> " if religion_picks.find(belief_name) == religion_slot and religion_picks.has(belief_name) else "", belief_name, why]),
			func() -> void: chosen.emit("religion_belief", belief_name), BELIEF_COLORS.get(type, DIM).darkened(0.6) if available else Color(0.16, 0.16, 0.18), 18)
		button.disabled = not available
		row.add_child(button)
		var effects := Label.new()
		effects.text = _plain(str(belief.get("effects", "")))
		effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effects.add_theme_font_size_override("font_size", 15)
		effects.add_theme_color_override("font_color", TEXT if available else DIM)
		row.add_child(effects)
		list.add_child(row)
	return page


## What the religion picker has: {beliefs: [...], icon, name} for chooseReligion.
func religion_choice() -> Dictionary:
	return {"beliefs": religion_picks.duplicate(), "icon": religion_icon, "name": religion_name if religion_name != "" else religion_icon}


# region victory ------------------------------------------------------------------------------
# Unciv's victory screen: our status, everyone's progress, rankings, charts and demographics.

const CHART_COLORS := [Color(0.95, 0.75, 0.25), Color(0.4, 0.72, 1.0), Color(0.9, 0.35, 0.35), Color(0.45, 0.85, 0.4),
	Color(0.8, 0.5, 0.98), Color(0.95, 0.55, 0.25), Color(0.6, 0.9, 0.9), Color(0.9, 0.9, 0.9)]


func _build_victory() -> Control:
	_map_replay_slider = null
	_map_replay_turn_label = null
	_map_replay_play_button = null
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	_header.add_theme_color_override("font_color", TEXT)
	if _victory.is_empty():
		_header.text = "Loading..."
		return page
	_header.text = Lang.format("Turn %d   %s speed   %s%s", [int(_victory.get("turn", 0)), _victory.get("speed", ""), _victory.get("difficulty", ""),
		Lang.format("   max %d turns", int(_victory["maxTurns"])) if _victory.has("maxTurns") else ""])
	# Who won (or that you lost), with Unciv's choices
	if _victory.has("winner") or _victory.has("defeatText"):
		var banner := VBoxContainer.new()
		var title := Label.new()
		var winner: Dictionary = _victory.get("winner", {})
		if not winner.is_empty():
			title.text = Lang.format("You have won a %s Victory!", winner["victoryType"]) if winner.get("isYou", false) else Lang.format("%s has won a %s Victory!", [winner["civ"], winner["victoryType"]])
		else:
			title.text = "You have been defeated."
		title.add_theme_font_size_override("font_size", 28)
		title.add_theme_color_override("font_color", GOOD if winner.get("isYou", false) else BAD)
		banner.add_child(title)
		var text := Label.new()
		text.text = str(winner.get("text", _victory.get("defeatText", "")))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 18)
		text.add_theme_color_override("font_color", TEXT)
		banner.add_child(text)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 12)
		if not _victory.get("oneMoreTurnMode", false) and not winner.is_empty():
			var more := _button("One more turn...!", func() -> void: chosen.emit("one_more_turn", ""), Color(0.2, 0.42, 0.25), 20)
			more.custom_minimum_size = Vector2(280, 52)
			buttons.add_child(more)
		var menu := _button("Main menu (start a new game)", func() -> void: chosen.emit("main_menu", ""), Color(0.3, 0.3, 0.4), 20)
		menu.custom_minimum_size = Vector2(360, 52)
		buttons.add_child(menu)
		banner.add_child(buttons)
		page.add_child(banner)
	# Pages
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 8)
	var available := [["ours", "Our status"], ["global", "Global status"]]
	if _victory.get("showRankings", false):
		available.append(["rankings", "Rankings"])
	if _victory.get("showCharts", false):
		available.append(["charts", "Charts"])
	if _victory.get("showDemographics", false):
		available.append(["demographics", "Demographics"])
	var map_replay: Dictionary = _victory.get("mapReplay", {})
	if (_victory.has("winner") or _victory.has("defeatText")) and int(map_replay.get("startTurn", -1)) >= 0 and not map_replay.get("tiles", []).is_empty():
		available.append(["replay", "Map replay"])
	if available.filter(func(p: Array) -> bool: return p[0] == victory_page).is_empty():
		victory_page = "ours"
	for p: Array in available:
		var id: String = p[0]
		var button := _button(p[1], func() -> void: chosen.emit("victory_page", id), Color(0.22, 0.42, 0.66) if id == victory_page else Color(0.2, 0.22, 0.3), 18)
		button.custom_minimum_size = Vector2(200, 44)
		pages.add_child(button)
	page.add_child(pages)
	match victory_page:
		"ours":
			var columns := HBoxContainer.new()
			columns.add_theme_constant_override("separation", 14)
			for victory: Dictionary in _victory.get("ourStatus", []):
				var column := VBoxContainer.new()
				column.custom_minimum_size = Vector2(300, 0)
				column.add_theme_constant_override("separation", 4)
				_card_line(column, Lang.format("%s Victory", victory["name"]), Color(0.95, 0.82, 0.45))
				_card_line(column, _plain(str(victory.get("header", ""))), DIM)
				for milestone: Dictionary in victory.get("milestones", []):
					var status := str(milestone.get("status", ""))
					_card_line(column, ("[done] " if status == "completed" else "") + _plain(str(milestone["text"])),
						GOOD if status == "completed" else (TEXT if status == "partial" else DIM))
					for step: Dictionary in milestone.get("steps", []):
						_card_line(column, "   " + ("[x] " if step.get("done", false) else "[  ] ") + _plain(str(step["text"])), GOOD if step.get("done", false) else DIM)
				columns.add_child(column)
			page.add_child(columns)
		"global":
			var columns := HBoxContainer.new()
			columns.add_theme_constant_override("separation", 14)
			for victory: Dictionary in _victory.get("global", []):
				var column := VBoxContainer.new()
				column.custom_minimum_size = Vector2(300, 0)
				_card_line(column, Lang.format("%s Victory", victory["name"]), Color(0.95, 0.82, 0.45))
				for civ: Dictionary in victory.get("civs", []):
					_card_line(column, Lang.format("%s: %s", [civ["name"], _plain(str(civ.get("next", "")))]),
						DIM if civ.get("defeated", false) else (GOOD if civ.get("isYou", false) else TEXT))
				columns.add_child(column)
			page.add_child(columns)
		"rankings":
			var grid := GridContainer.new()
			var rankings: Array = _victory.get("rankings", [])
			grid.columns = maxi(1, rankings.size())
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 4)
			var cell_font := 17 if rankings.size() <= 6 else 15
			for ranking: Dictionary in rankings:
				_card_line(grid, str(ranking.get("label", ranking["type"])), Color(0.95, 0.82, 0.45), false, cell_font)
			var rows := 0
			for ranking: Dictionary in rankings:
				rows = maxi(rows, ranking.get("civs", []).size())
			for r in rows:
				for ranking: Dictionary in rankings:
					var civs: Array = ranking.get("civs", [])
					if r < civs.size():
						_card_line(grid, Lang.format("%s %d", [civs[r]["name"], int(civs[r]["value"])]), GOOD if civs[r].get("isYou", false) else TEXT, false, cell_font)
					else:
						grid.add_child(Control.new())
			page.add_child(grid)
		"charts":
			var types := HFlowContainer.new()
			types.add_theme_constant_override("h_separation", 6)
			for type: String in _victory.get("rankingTypes", []):
				var t := type
				var button := _button(type, func() -> void: chosen.emit("chart_type", t), Color(0.22, 0.42, 0.66) if type == chart_type else Color(0.2, 0.22, 0.3), 16)
				button.clip_text = false
				types.add_child(button)
			page.add_child(types)
			var chart := LineChart.new()
			chart.custom_minimum_size = Vector2(1100, 380)
			var legend := VBoxContainer.new()
			var i := 0
			for civ: Dictionary in _victory.get("history", []):
				var points: Array[Vector2] = []
				var turns: Dictionary = civ.get("turns", {})
				var keys := turns.keys()
				keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
				for turn: Variant in keys:
					var values: Dictionary = turns[turn]
					if values.has(chart_type):
						points.append(Vector2(float(turn), float(values[chart_type])))
				var colour: Color = CHART_COLORS[i % CHART_COLORS.size()]
				chart.series.append({"name": civ["name"], "color": colour, "points": points})
				_card_line(legend, civ["name"], colour, false)
				i += 1
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			row.add_child(chart)
			row.add_child(legend)
			page.add_child(row)
		"demographics":
			var grid := GridContainer.new()
			grid.columns = 5
			grid.add_theme_constant_override("h_separation", 24)
			grid.add_theme_constant_override("v_separation", 4)
			for heading: String in ["", "Rank", "Value", "Best", "Average / Worst"]:
				_card_line(grid, heading, Color(0.95, 0.82, 0.45), false)
			for row: Dictionary in _victory.get("demographics", []):
				_card_line(grid, str(row.get("label", row["type"])), TEXT, false)
				_card_line(grid, "#%d" % int(row.get("rank", 0)), TEXT, false)
				_card_line(grid, str(int(row.get("value", 0))), GOOD, false)
				_card_line(grid, Lang.format("%d (%s)", [int(row.get("best", 0)), row.get("bestCiv", {}).get("name", "?")]), TEXT, false)
				_card_line(grid, Lang.format("%d / %d (%s)", [int(row.get("average", 0)), int(row.get("worst", 0)), row.get("worstCiv", {}).get("name", "?")]), DIM, false)
			page.add_child(grid)
		"replay":
			var replay: Dictionary = _victory.get("mapReplay", {})
			var start_turn := int(replay.get("startTurn", 0))
			var end_turn := int(replay.get("endTurn", start_turn))
			_card_line(page, "Map replay", Color(0.95, 0.82, 0.45), false, 24)
			_card_line(page, "The map is zoomed out to show its full extent. Ownership and city locations update as the turns play.", DIM, false, 17)
			var controls := HBoxContainer.new()
			controls.add_theme_constant_override("separation", 10)
			var start_button := _button("Start replay", func() -> void: chosen.emit("replay_start", ""), Color(0.2, 0.42, 0.25), 18)
			start_button.custom_minimum_size = Vector2(190, 48)
			controls.add_child(start_button)
			var play_label := "Pause" if map_replay_playing else "Play"
			var play_button := _button(play_label, func() -> void: chosen.emit("replay_toggle", ""), Color(0.22, 0.42, 0.66), 18)
			_map_replay_play_button = play_button
			play_button.custom_minimum_size = Vector2(140, 48)
			play_button.disabled = not map_replay_active
			controls.add_child(play_button)
			var end_button := _button("Return to game", func() -> void: chosen.emit("replay_end", ""), Color(0.3, 0.3, 0.4), 18)
			end_button.custom_minimum_size = Vector2(200, 48)
			end_button.disabled = not map_replay_active
			controls.add_child(end_button)
			page.add_child(controls)
			var slider := HSlider.new()
			_map_replay_slider = slider
			slider.min_value = start_turn
			slider.max_value = maxf(start_turn, end_turn)
			slider.step = 1
			slider.value = clampf(map_replay_turn, start_turn, end_turn)
			slider.custom_minimum_size = Vector2(760, 40)
			slider.value_changed.connect(func(value: float) -> void: chosen.emit("replay_seek", str(roundi(value))))
			page.add_child(slider)
			_map_replay_turn_label = Label.new()
			_map_replay_turn_label.text = Lang.format("Turn %d of %d", [map_replay_turn if map_replay_active else start_turn, end_turn])
			_map_replay_turn_label.add_theme_color_override("font_color", TEXT)
			_map_replay_turn_label.add_theme_font_size_override("font_size", 18)
			page.add_child(_map_replay_turn_label)
	return page


# region trade ------------------------------------------------------------------------------

## Starts a trade screen with a getTradeOptions result.
func open_trade(options: Dictionary) -> void:
	_trade_options = options
	trade_civ = str(options.get("civ", ""))
	trade_ours = []
	trade_theirs = []
	_trade_verdict = {}
	show_tab("diplomacy")


## Puts a deal on the table (e.g. their counteroffer, to change and propose back): offers as getTradeOptions items.
func stage_trade(ours: Array, theirs: Array) -> void:
	trade_ours = []
	trade_theirs = []
	for pair: Array in [[ours, trade_ours], [theirs, trade_theirs]]:
		for offer: Dictionary in pair[0]:
			var entry: Dictionary = offer.duplicate()
			(pair[1] as Array).append(entry)
	_trade_verdict = {}
	if trade_civ != "":
		_rebuild()


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
	_header.text = Lang.format("Trading with %s     Your gold %d, theirs %d", [trade_civ, int(_trade_options.get("yourGold", 0)), int(_trade_options.get("theirGold", 0))])
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
		verdict.text = Lang.format("%s would accept this.", trade_civ)
		verdict.add_theme_color_override("font_color", GOOD)
	else:
		var value := int(_trade_verdict.get("value", 0))
		verdict.text = Lang.format("%s wants more for this%s.", [trade_civ, Lang.format(" (about %d gold's worth)", -value) if value > -100000 and value < 0 else ""])
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
	var sorted := items.duplicate()
	if available:
		# Unciv groups offers by kind; "Order trade offers by amount" puts the biggest first within a kind
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["type"] != b["type"]:
				return str(a["type"]) < str(b["type"])
			if order_trade_by_amount and int(a.get("amount", 0)) != int(b.get("amount", 0)):
				return int(a.get("amount", 0)) > int(b.get("amount", 0))
			return str(a.get("label", a["name"])) < str(b.get("label", b["name"])))
	for item: Dictionary in sorted:
		var on_table := _staged_amount(table, item)
		var amount := int(item.get("amount", 1))
		if available:
			amount -= on_table
			if amount <= 0 and item.get("countable", false):
				continue
			if not item.get("countable", false) and on_table > 0:
				continue
		var text := Lang.t(str(item.get("label", item["name"])))
		if item.get("countable", false):
			text += "  (%d)" % amount
		if int(item.get("duration", -1)) > 0:
			text += Lang.format("  %d turns", int(item["duration"]))
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
