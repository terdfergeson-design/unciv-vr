# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## Unciv's Empire Overview ("stats and info") as a board off to the player's right: the Cities, Stats, Trades,
## Units, Politics, Resources, Religion, Wonders and Notifications tabs, with the same content and clicks.
## The strip along the top is the handle for moving it.
##
## Emits chosen(kind, value):
##   "ov_tab" (tab id), "ov_city" (city name: open its city view), "ov_goto" ("x,y": look at that tile),
##   "ov_city_card" ("x,y": open that city's card), "ov_unit" (unit id: select it), "ov_promote" (unit id), "ov_rename" (unit id),
##   "ov_upgrade" ("unit id|unit to upgrade to"), "ov_gold_science" (0..1), "ov_big" (tech / policies / diplomacy)
signal chosen(kind: String, value: String)

const Lang := preload("res://scripts/lang.gd")

const Icons := preload("res://scripts/icons.gd")

const SIZE := Vector2(1440, 880)
const GRAB_HEIGHT := 32.0
## [id, caption, icon kind, icon name] in Unciv's order
const TABS := [
	["cities", "Cities", "other", "Cities"], ["stats", "Stats", "stat", "Gold"], ["trades", "Trades", "stat", "Acquire"],
	["units", "Units", "other", "Shield"], ["politics", "Politics", "other", "Politics"],
	["resources", "Resources", "stat", "Happiness"], ["religion", "Religion", "stat", "Faith"],
	["wonders", "Wonders", "other", "Wonders"], ["notifications", "Notifications", "other", "Notifications"],
	["espionage", "Espionage", "other", "Spy"],
]
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.66, 0.7, 0.78)
const HEADER := Color(0.98, 0.85, 0.45)
const GOOD := Color(0.45, 0.85, 0.4)
const BAD := Color(1.0, 0.42, 0.32)
const BUTTON := Color(0.2, 0.22, 0.3)
const SELECTED := Color(0.22, 0.42, 0.66)
const ROW_A := Color(0.1, 0.12, 0.17)
const ROW_B := Color(0.13, 0.15, 0.21)
const STAT_COLORS := {
	"food": Color(0.45, 0.85, 0.35), "production": Color(0.95, 0.55, 0.25), "gold": Color(0.98, 0.8, 0.25),
	"science": Color(0.4, 0.72, 1.0), "culture": Color(0.8, 0.5, 0.98), "happiness": Color(0.5, 0.9, 0.35),
	"faith": Color(0.75, 0.88, 1.0),
}
## Unciv's relationship colours for the politics diagram (roughly)
const RELATION_COLORS := {
	"War": Color(0.95, 0.15, 0.12), "DefensivePact": Color(0.7, 0.3, 0.85), "Unforgivable": Color(0.6, 0.05, 0.05),
	"Enemy": Color(0.95, 0.4, 0.2), "Afraid": Color(0.95, 0.8, 0.2), "Competitor": Color(0.95, 0.6, 0.25),
	"Neutral": Color(0.6, 0.6, 0.62), "Favorable": Color(0.6, 0.85, 0.45), "Friend": Color(0.3, 0.85, 0.3),
	"Ally": Color(0.3, 0.75, 1.0),
}

var tab := "cities"
var data: Dictionary = {}           # the getOverview result for [tab]
var gold := 0
var sort_by := {}                   # tab -> [column id, descending]
var show_diagram := false           # Politics: the "ball of yarn" instead of the table
var diagram_city_states := false
var selected_religion := ""
var closed_turns := {}              # Notifications: turns whose section is folded
var armed := ""                     # an upgrade clicked once; the next click confirms

var _tab_buttons: Dictionary = {}
var _header: Label
var _scroll: ScrollContainer
var _body: VBoxContainer


## Draws the politics diagram: everyone you know on a circle, a coloured line for each pair that knows each other.
class Diagram extends Control:
	func _ready() -> void:
		for child: Control in get_children():
			if child.has_meta("diagram_position"):
				child.position = child.get_meta("diagram_position")

	var civs: Array = []     # [{name, ...}]
	var lines: Array = []    # [{a, b, relation}]
	var positions := {}      # civ name -> Vector2
	var colors := {}         # relation -> Color

	func _draw() -> void:
		for line: Dictionary in lines:
			if positions.has(line["a"]) and positions.has(line["b"]):
				var colour: Color = colors.get(line["relation"], Color.GRAY)
				draw_line(positions[line["a"]], positions[line["b"]], colour, 3.0 if line["relation"] in ["War", "Ally", "DefensivePact"] else 2.0, true)


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
	grab.text = "=====   Empire overview  -  hold the trigger here and drag to move   ====="
	grab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grab.custom_minimum_size = Vector2(0, GRAB_HEIGHT)
	grab.add_theme_font_size_override("font_size", 15)
	grab.add_theme_color_override("font_color", DIM)
	box.add_child(grab)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	box.add_child(bar)
	for t: Array in TABS:
		var id: String = t[0]
		var button := _button(t[1], func() -> void: chosen.emit("ov_tab", id), BUTTON, 16)
		button.icon = Icons.get_icon(t[2], t[3])
		button.add_theme_constant_override("icon_max_width", 24)
		# All the tabs share the board's width (wider than that, the whole board would spill off its edge)
		button.custom_minimum_size = Vector2(0, 46)
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(button)
		_tab_buttons[id] = button
	# The tab's own summary line (turn, unit supply...) goes under the tabs, right-aligned
	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header.add_theme_font_size_override("font_size", 16)
	_header.add_theme_color_override("font_color", DIM)
	_header.clip_text = true
	box.add_child(_header)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Icons.thick_scrollbars(_scroll)
	box.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	show_tab(tab)


func grab_bar_contains(pixel: Vector2) -> bool:
	return pixel.y >= position.y and pixel.y < position.y + GRAB_HEIGHT


func scroll_by(amount: Vector2) -> void:
	_scroll.scroll_horizontal += int(amount.x)
	_scroll.scroll_vertical += int(amount.y)


func show_tab(id: String) -> void:
	if id != tab:
		armed = ""
		_scroll.scroll_vertical = 0
		_scroll.scroll_horizontal = 0
	tab = id
	for key: String in _tab_buttons:
		_restyle(_tab_buttons[key], SELECTED if key == id else BUTTON)


## A getOverview result (for its "tab"). [param gold_now]: your gold, for upgrade prices.
func set_data(result: Dictionary, gold_now: int) -> void:
	var same: bool = result.get("tab") == data.get("tab")
	var v := _scroll.scroll_vertical
	var h := _scroll.scroll_horizontal
	data = result
	gold = gold_now
	for t: Dictionary in result.get("tabs", []):
		if _tab_buttons.has(t["id"]):
			var button: Button = _tab_buttons[t["id"]]
			button.visible = t["state"] != "hidden"
			button.disabled = t["state"] == "disabled" and t["id"] != tab
	_rebuild()
	if same:
		await get_tree().process_frame
		_scroll.scroll_vertical = v
		_scroll.scroll_horizontal = h


func arm(key: String) -> void:
	armed = key
	_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	_header.text = Lang.format("Turn %d", int(data.get("turn", 0))) if data.has("turn") else ""
	if data.is_empty() or data.get("tab") != tab:
		_body.add_child(_label("Loading...", 20, DIM))
		return
	match tab:
		"cities": _build_cities()
		"stats": _build_stats()
		"trades": _build_trades()
		"units": _build_units()
		"politics": _build_politics()
		"resources": _build_resources()
		"religion": _build_religion()
		"wonders": _build_wonders()
		"notifications": _build_notifications()
		"espionage": _build_espionage()


# region espionage ----------------------------------------------------------------------------
# Unciv's espionage overview: pick a spy on the left, then where it should go on the right.

var selected_spy := ""


func _build_espionage() -> void:
	var spies: Array = data.get("spies", [])
	if spies.is_empty():
		_body.add_child(_label("You have no spies yet - they come with new eras.", 20, DIM))
		return
	if selected_spy != "" and spies.filter(func(s: Dictionary) -> bool: return s["name"] == selected_spy).is_empty():
		selected_spy = ""
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	_body.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 4)
	columns.add_child(left)
	left.add_child(_label("Spies (pick one, then where it goes)", 18, HEADER))
	for spy: Dictionary in spies:
		var spy_name: String = spy["name"]
		var text := Lang.format("%s  (rank %d)  -  %s  -  %s%s", [spy_name, int(spy.get("rank", 1)), spy.get("location", "?"), spy.get("action", ""),
			Lang.format("  %d turns", int(spy["turns"])) if spy.has("turns") else ""])
		var button := _button(text, func() -> void: chosen.emit("ov_spy_select", spy_name),
			SELECTED if spy_name == selected_spy else BUTTON, 16)
		button.disabled = not spy.get("alive", true)
		button.clip_text = true
		left.add_child(button)
		if spy.get("canCoup", false):
			var key := "coup:" + spy_name
			var coup_text := "Call off the coup" if spy.get("stagingCoup", false) else (
				Lang.format("Click again: stage a coup (%d%% chance)", int(spy.get("coupChance", 0))) if armed == key else Lang.format("Stage a coup (%d%% chance)", int(spy.get("coupChance", 0))))
			left.add_child(_button(coup_text, func() -> void:
				if spy.get("stagingCoup", false) or armed == key:
					chosen.emit("ov_spy_coup", spy_name)
				else:
					arm(key), Color(0.5, 0.2, 0.15) if armed == key else Color(0.35, 0.22, 0.2), 15))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 3)
	columns.add_child(right)
	right.add_child(_label("Where to" if selected_spy != "" else "Cities", 18, HEADER))
	if selected_spy != "":
		right.add_child(_button(Lang.format("Spy hideout (bring %s home)", selected_spy), func() -> void: chosen.emit("ov_spy_move", selected_spy + "|"), BUTTON, 16))
	for city: Dictionary in data.get("cities", []):
		var city_name: String = city["name"]
		var here: Array = city.get("spies", [])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _label(Lang.format("%s (%s)%s", [city_name, city.get("civ", ""), Lang.t("   spies: ") + Lang.join(", ", here) if not here.is_empty() else ""]), 16,
			GOOD if city.get("own", false) else TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		row.add_child(info)
		if selected_spy != "":
			var key := "spymove:%s|%s" % [selected_spy, city_name]
			var can: bool = selected_spy in city.get("canMoveHere", [])
			var warn := str(city.get("promiseWarning", ""))
			var move := _button(Lang.format("Click again (%s)", warn) if armed == key and warn != "" else "Move here", func() -> void:
				if warn != "" and armed != key:
					arm(key)
				else:
					chosen.emit("ov_spy_move", "%s|%s" % [selected_spy, city_name] + ("|confirm" if warn != "" else "")),
				Color(0.5, 0.3, 0.12) if armed == key else Color(0.2, 0.36, 0.24), 15)
			move.disabled = not can
			move.custom_minimum_size = Vector2(150 if armed != key else 420, 36)
			row.add_child(move)
		right.add_child(row)


# region cities -------------------------------------------------------------------------------

func _build_cities() -> void:
	var cities: Array = data.get("cities", []).duplicate()
	if cities.is_empty():
		_body.add_child(_label("You have no cities yet.", 20, DIM))
		return
	var religion: bool = data.get("religionEnabled", false)
	var cols: Array = [
		["name", "Name", 200.0, null], ["status", "", 44.0, Icons.get_icon("other", "CityStatus")],
		["construction", "Building", 250.0, null], ["population", "", 64.0, Icons.get_icon("stat", "Population")],
	]
	for stat: String in ["food", "gold", "science", "production", "culture", "happiness"] + (["faith"] if religion else []):
		cols.append([stat, "", 64.0, Icons.get_icon("stat", stat.capitalize())])
	cols.append(["wltk", "", 56.0, Icons.get_icon("other", "WLTKD")])
	cols.append(["garrison", "", 56.0, Icons.get_icon("other", "Shield")])
	cols.append(["defense", "Defence", 96.0, null])
	if religion:
		cols.append(["religion", "", 130.0, Icons.get_icon("religion", "Religion")])
	for r: String in data.get("cityWideResources", []):
		cols.append(["res:" + r, "", 56.0, Icons.badge("resource", r, Color(0.3, 0.3, 0.38))])
	_sort(cities, {"name": func(c: Dictionary) -> Variant: return str(c["name"]),
		"construction": func(c: Dictionary) -> Variant: return str(c.get("construction", "")),
		"status": func(c: Dictionary) -> Variant: return ["", "puppet", "resistance", "razing"].find(str(c.get("status", ""))),
		"wltk": func(c: Dictionary) -> Variant: return 1 if c.get("wltk", false) else 0,
		"garrison": func(c: Dictionary) -> Variant: return 1 if c.has("garrison") else 0,
		"religion": func(c: Dictionary) -> Variant: return str(c.get("religion", "")),
	}, func(c: Dictionary, key: String) -> Variant:
		return int(c.get("resources", {}).get(key.substr(4), 0)) if key.begins_with("res:") else int(c.get(key, 0)))
	_body.add_child(_header_row(cols))
	var i := 0
	for c: Dictionary in cities:
		var cells: Array = []
		var name: String = c["name"]
		var city_button := _button(("* " if c.get("isCapital", false) else "") + Lang.t(name), func() -> void: chosen.emit("ov_city", name), Color(0.25, 0.3, 0.42), 17)
		city_button.tooltip_text = "Open the city view"
		cells.append(city_button)
		var status_icon := {"razing": Icons.get_icon("other", "Fire"), "resistance": Icons.get_icon("stat", "Resistance"),
			"puppet": Icons.get_icon("other", "Puppet")}.get(str(c.get("status", "")), null) as Texture2D
		cells.append(_icon(status_icon, 28))
		var construction: String = c.get("construction", "")
		var turns := int(c.get("constructionTurns", -1))
		var building := HBoxContainer.new()
		building.add_theme_constant_override("separation", 6)
		if construction != "":
			building.add_child(_icon(Icons.construction(construction), 30))
		building.add_child(_label(Lang.t(construction) + ((Lang.format("  %d turns", turns)) if turns >= 0 else ""), 16, TEXT if construction != "" else DIM))
		cells.append(building)
		cells.append(_num(int(c.get("population", 0)), TEXT))
		for stat: String in ["food", "gold", "science", "production", "culture", "happiness"] + (["faith"] if religion else []):
			var value := int(c.get(stat, 0))
			cells.append(_num(value, BAD if value < 0 else STAT_COLORS[stat].lightened(0.2)))
		if c.get("wltk", false):
			cells.append(_label(Lang.format("%d t", int(c.get("wltkTurns", 0))), 15, GOOD))
		elif c.has("demanding"):
			var want := _icon(Icons.badge("resource", str(c["demanding"]), Color(0.3, 0.3, 0.38)), 30)
			want.tooltip_text = Lang.format("Demanding %s", c["demanding"])
			want.mouse_filter = Control.MOUSE_FILTER_PASS
			cells.append(want)
		else:
			cells.append(Control.new())
		if c.has("garrison"):
			var g: Dictionary = c["garrison"]
			var gid := str(int(g["id"]))
			var garrison := _icon_button(Icons.get_icon("unit", str(g["name"])), "", func() -> void: chosen.emit("ov_unit", gid), BUTTON)
			garrison.tooltip_text = str(g["name"])
			cells.append(garrison)
		else:
			cells.append(Control.new())
		cells.append(_label("%d/%d" % [int(c.get("defense", 0)), int(c.get("maxHealth", 0))], 16, TEXT))
		if religion:
			cells.append(_label(Lang.t(str(c.get("religion", ""))) + (Lang.t(" (holy)") if c.get("holyCity", false) else ""), 15, TEXT))
		for r: String in data.get("cityWideResources", []):
			var amount := int(c.get("resources", {}).get(r, 0))
			cells.append(_num(amount, TEXT) if amount != 0 else Control.new())
		_body.add_child(_row(cols, cells, i))
		i += 1
	# Totals
	var totals: Array = [_label(Lang.format("Total %d", cities.size()), 17, HEADER), Control.new(), Control.new()]
	var sum := func(key: String) -> int:
		var total := 0
		for c: Dictionary in cities:
			total += int(c.get(key, 0))
		return total
	totals.append(_num(sum.call("population"), HEADER))
	for stat: String in ["food", "gold", "science", "production", "culture", "happiness"] + (["faith"] if religion else []):
		totals.append(_num(sum.call(stat), HEADER))
	while totals.size() < cols.size():
		totals.append(Control.new())
	_body.add_child(HSeparator.new())
	_body.add_child(_row(cols, totals, 0, Color(0, 0, 0, 0)))


# region stats -------------------------------------------------------------------------------

func _build_stats() -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 18)
	_body.add_child(flow)
	flow.add_child(_breakdown_panel("Happiness", Icons.get_icon("stat", "Happiness"), data.get("happiness", {}), STAT_COLORS["happiness"]))
	for stat: String in ["gold", "science", "culture", "faith"]:
		if not data.has(stat):
			continue
		var panel := _breakdown_panel(stat.capitalize(), Icons.get_icon("stat", stat.capitalize()), data[stat], STAT_COLORS[stat])
		if stat == "gold" and data.has("goldToScience"):
			var percent := float(data["goldToScience"])
			var row := HBoxContainer.new()
			row.add_child(_label(Lang.format("Convert gold to science: %d%%", roundi(percent * 100)), 16, TEXT))
			for step: Array in [["-", -0.1], ["+", 0.1]]:
				var target := clampf(percent + float(step[1]), 0.0, 1.0)
				var b := _button(step[0], func() -> void: chosen.emit("ov_gold_science", str(target)), BUTTON, 18)
				b.custom_minimum_size = Vector2(40, 34)
				row.add_child(b)
			panel.get_child(0).add_child(row)
		flow.add_child(panel)

	# Great person points
	var gp := _panel_box("Great person points", Icons.get_icon("stat", "Specialist"), Color(0.45, 0.6, 1.0))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_child(Control.new())
	grid.add_child(_label("Points", 15, DIM))
	grid.add_child(_label("Per turn", 15, DIM))
	for p: Dictionary in data.get("greatPeople", []):
		var name_row := HBoxContainer.new()
		name_row.add_child(_icon(Icons.get_icon("unit", str(p["name"])), 24))
		name_row.add_child(_label(str(p["name"]), 16, TEXT))
		grid.add_child(name_row)
		grid.add_child(_label("%d/%d" % [int(p.get("points", 0)), int(p.get("needed", 0))], 16, TEXT))
		grid.add_child(_label("+%d" % int(p.get("perTurn", 0)), 16, GOOD))
	for p: Dictionary in data.get("greatGenerals", []):
		grid.add_child(_label(str(p["name"]), 16, TEXT))
		grid.add_child(_label("%d/%d" % [int(p.get("points", 0)), int(p.get("needed", 0))], 16, TEXT))
		grid.add_child(Control.new())
	gp.get_child(0).add_child(grid)
	flow.add_child(gp)
	flow.add_child(_breakdown_panel("Score", Icons.get_icon("other", "Score"), data.get("score", {}), Color(0.85, 0.3, 0.25)))


## A heading with an icon, one line per source with its value, and the total (like Unciv's stat tables).
func _breakdown_panel(title: String, icon: Texture2D, sources: Dictionary, colour: Color) -> PanelContainer:
	var panel := _panel_box(title, icon, colour)
	var box: VBoxContainer = panel.get_child(0)
	var total := 0.0
	for source: String in sources:
		var value := float(sources[source])
		total += value
		if roundi(value) == 0:
			continue
		box.add_child(_value_line(_plain(source.replace("[", "").replace("]", "")), roundi(value), TEXT))
	box.add_child(HSeparator.new())
	box.add_child(_value_line("Total", roundi(total), colour.lightened(0.25)))
	return panel


func _value_line(text: String, value: int, colour: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(text, 16, colour)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	row.add_child(_label(("%+d" % value) if value < 0 else str(value), 16, BAD if value < 0 else colour))
	return row


func _panel_box(title: String, icon: Texture2D, colour: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.16)
	style.border_color = colour.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(430, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_icon(icon, 30))
	head.add_child(_label(title, 22, colour.lightened(0.2)))
	box.add_child(head)
	box.add_child(HSeparator.new())
	return panel


# region trades ------------------------------------------------------------------------------

func _build_trades() -> void:
	var any := false
	for section: Array in [["pending", "Pending trades"], ["current", "Current trades"]]:
		var trades: Array = data.get(section[0], [])
		if trades.is_empty():
			continue
		any = true
		_body.add_child(_label(section[1], 24, HEADER))
		for trade: Dictionary in trades:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			row.add_child(_offers_panel("You", {}, trade.get("ours", []), Color(0.35, 0.45, 0.7)))
			row.add_child(_offers_panel(str(trade.get("civ", "?")), trade, trade.get("theirs", []), Color.html(str(trade.get("outerColor", "888888ff")))))
			_body.add_child(row)
	if not any:
		_body.add_child(_label("No trades going on. Make one from the Diplomacy tab of the big screen.", 20, DIM))


func _offers_panel(title: String, civ: Dictionary, offers: Array, colour: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = colour.darkened(0.7)
	style.border_color = colour
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(500, 0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	if not civ.is_empty():
		head.add_child(_icon(Icons.civ_badge(civ), 34))
	head.add_child(_label(title, 20, colour.lightened(0.3)))
	box.add_child(head)
	box.add_child(HSeparator.new())
	for offer: String in offers:
		box.add_child(_label(_plain(offer.replace("[", "").replace("]", "")).replace("\n", "  "), 17, TEXT))
	if offers.is_empty():
		box.add_child(_label("(nothing)", 16, DIM))
	return panel


# region units -------------------------------------------------------------------------------

func _build_units() -> void:
	var supply: Dictionary = data.get("supply", {})
	var deficit := int(supply.get("deficit", 0))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	top.add_child(_label(Lang.format("Unit supply: %d of %d used  (base %d, cities %d, population %d)", [int(supply.get("inUse", 0)), int(supply.get("total", 0)),
		int(supply.get("base", 0)), int(supply.get("cities", 0)), int(supply.get("population", 0))]), 17, BAD if deficit > 0 else TEXT))
	if deficit > 0:
		top.add_child(_label(Lang.format("Deficit %d: %d%% production in every city. Increase your supply or disband units.", [deficit, int(supply.get("productionPenalty", 0))]), 17, BAD))
	_body.add_child(top)
	var units: Array = data.get("units", []).duplicate()
	var cols: Array = [["name", "Name", 230.0, null], ["action", "Doing", 170.0, null],
		["strength", "", 64.0, Icons.get_icon("stat", "Strength")], ["rangedStrength", "", 64.0, Icons.get_icon("stat", "RangedStrength")],
		["movement", "", 90.0, Icons.get_icon("stat", "Movement")], ["closestCity", "Closest city", 160.0, null],
		["promotions", "Promotions", 220.0, null], ["upgrade", "Upgrade", 200.0, null], ["health", "Health", 80.0, null], ["xp", "XP", 90.0, null]]
	_sort(units, {"name": func(u: Dictionary) -> Variant: return str(u["name"]),
		"action": func(u: Dictionary) -> Variant: return str(u.get("action", "")),
		"movement": func(u: Dictionary) -> Variant: return int(u.get("maxMovement", 0)),
		"closestCity": func(u: Dictionary) -> Variant: return str(u.get("closestCity", "")),
		"promotions": func(u: Dictionary) -> Variant: return (10000 if u.get("canPromote", false) else 0) + u.get("promotions", []).size(),
		"upgrade": func(u: Dictionary) -> Variant: return str(u["upgrades"][0]["to"]) if not u.get("upgrades", []).is_empty() else "",
	}, func(u: Dictionary, key: String) -> Variant: return int(u.get(key, 0)))
	_body.add_child(_header_row(cols))
	var i := 0
	for u: Dictionary in units:
		var id := str(int(u["id"]))
		var cells: Array = []
		var name_button := _icon_button(Icons.get_icon("unit", str(u.get("baseUnit", u["name"]))), str(u["name"]),
			func() -> void: chosen.emit("ov_unit", id), Color(0.25, 0.3, 0.42) if u.get("idle", false) else BUTTON)
		name_button.clip_text = true
		name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_cell := HBoxContainer.new()
		name_cell.add_theme_constant_override("separation", 3)
		name_cell.add_child(name_button)
		var rename := _button("Rename", func() -> void: chosen.emit("ov_rename", id), Color(0.24, 0.26, 0.34), 13)
		rename.custom_minimum_size = Vector2(62, 0)
		name_cell.add_child(rename)
		cells.append(name_cell)
		cells.append(_label(_plain(str(u.get("action", ""))), 15, TEXT))
		cells.append(_num(int(u.get("strength", 0)), TEXT) if int(u.get("strength", 0)) > 0 else Control.new())
		cells.append(_num(int(u.get("rangedStrength", 0)), TEXT) if int(u.get("rangedStrength", 0)) > 0 else Control.new())
		cells.append(_label(_plain(str(u.get("movement", ""))), 15, TEXT))
		if u.has("closestCity"):
			var at := "%d,%d" % [int(u["x"]), int(u["y"])]
			cells.append(_button(str(u["closestCity"]), func() -> void: chosen.emit("ov_goto", at),
				Color(0.18, 0.32, 0.2) if u.get("inCity", false) else BUTTON, 15))
		else:
			cells.append(Control.new())
		var promos := HBoxContainer.new()
		promos.add_theme_constant_override("separation", 1)
		for p: String in u.get("promotions", []).slice(0, 6):
			var found := Icons.promotion(p)
			var rect := _icon(found[0], 24)
			rect.tooltip_text = p
			rect.mouse_filter = Control.MOUSE_FILTER_PASS
			promos.add_child(rect)
		if u.get("canPromote", false):
			var star := _icon_button(Icons.get_icon("other", "Star"), "Promote", func() -> void: chosen.emit("ov_promote", id), Color(0.5, 0.38, 0.08))
			promos.add_child(star)
		cells.append(promos)
		var upgrades: Array = u.get("upgrades", [])
		if not upgrades.is_empty():
			var up: Dictionary = upgrades[0]
			var key := "upgrade:%s|%s" % [id, up["to"]]
			var text := ("Click again: %d gold" if armed == key else "%s %dg") % ([int(up.get("cost", 0))] if armed == key else [up["to"], int(up.get("cost", 0))])
			var button := _icon_button(Icons.get_icon("unit", str(up["to"])), text,
				func() -> void:
					if armed == key:
						chosen.emit("ov_upgrade", key.substr(8))
					else:
						arm(key),
				Color(0.55, 0.42, 0.1) if armed == key else Color(0.2, 0.36, 0.22))
			button.disabled = not up.get("enabled", false)
			cells.append(button)
		else:
			cells.append(Control.new())
		var health := int(u.get("health", 100))
		cells.append(_num(health, GOOD if health > 66 else (HEADER if health > 33 else BAD)) if health < 100 else Control.new())
		cells.append(_label("%d/%d" % [int(u["xp"]), int(u.get("xpForNextPromotion", 0))], 15, TEXT) if u.has("xp") else Control.new())
		_body.add_child(_row(cols, cells, i))
		i += 1


# region politics ----------------------------------------------------------------------------

func _build_politics() -> void:
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 8)
	toggles.add_child(_button("Show global politics" if show_diagram else "Show diagram", func() -> void:
		show_diagram = not show_diagram
		_rebuild(), BUTTON, 17))
	if show_diagram:
		toggles.add_child(_button("Hide city-states" if diagram_city_states else "Include city-states", func() -> void:
			diagram_city_states = not diagram_city_states
			_rebuild(), BUTTON, 17))
	var count := int(data.get("civsInGame", -1))
	toggles.add_child(_label(Lang.format("   %s civilizations in the game", ("?" if count < 0 else str(count))), 17, DIM))
	_body.add_child(toggles)
	if show_diagram:
		_build_diagram()
		return
	var i := 0
	for c: Dictionary in data.get("civs", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.add_child(_icon(Icons.civ_badge(c), 96))
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(240, 0)
		info.add_child(_label(str(c.get("leader", "")), 24, Color.html(str(c.get("outerColor", "ffffffff"))).lightened(0.2)))
		info.add_child(_label(str(c["name"]), 17, TEXT))
		info.add_child(_label(str(c.get("era", "")), 16, DIM))
		info.add_child(_label(Lang.format("Score %d", int(c.get("score", 0))), 16, DIM))
		row.add_child(info)
		var policies := VBoxContainer.new()
		policies.custom_minimum_size = Vector2(220, 0)
		for p: Dictionary in c.get("policies", []):
			var line := HBoxContainer.new()
			line.add_child(_icon(Icons.get_icon("branch", str(p["branch"])), 22))
			line.add_child(_label(Lang.format("%s: %d", [p["branch"], int(p["count"])]), 16, TEXT))
			policies.add_child(line)
		row.add_child(policies)
		var wonders := VBoxContainer.new()
		wonders.custom_minimum_size = Vector2(260, 0)
		for w: Dictionary in c.get("wonders", []):
			if w.has("x"):
				var at := "%d,%d" % [int(w["x"]), int(w["y"])]
				wonders.add_child(_button(str(w["name"]), func() -> void: chosen.emit("ov_goto", at), BUTTON, 15))
			else:
				wonders.add_child(_label(str(w["name"]), 15, TEXT))
		row.add_child(wonders)
		var relations := VBoxContainer.new()
		if c.get("defeated", false):
			relations.add_child(_label("Defeated", 18, BAD))
		for w: String in c.get("wars", []):
			relations.add_child(_label(Lang.format("At war with %s", w), 16, BAD))
		for p: Dictionary in c.get("defensivePacts", []):
			relations.add_child(_label(Lang.format("Defensive pact with %s (%d turns)", [p["civ"], int(p["turns"])]), 16, Color(0.5, 0.9, 1.0)))
		for p: Dictionary in c.get("friends", []):
			relations.add_child(_label(Lang.format("Friends with %s (%d turns)", [p["civ"], int(p["turns"])]), 16, GOOD))
		for p: Dictionary in c.get("denounced", []):
			relations.add_child(_label(Lang.format("Denounced %s (%d turns)", [p["civ"], int(p["turns"])]), 16, BAD))
		for a: String in c.get("alliedCityStates", []):
			relations.add_child(_label(Lang.format("Allied with %s", a), 16, Color(0.5, 0.9, 1.0)))
		row.add_child(relations)
		var holder := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = ROW_A if i % 2 == 0 else ROW_B
		style.set_corner_radius_all(8)
		style.set_content_margin_all(8)
		holder.add_theme_stylebox_override("panel", style)
		holder.add_child(row)
		_body.add_child(holder)
		i += 1


func _build_diagram() -> void:
	var diagram_data: Dictionary = data.get("diagram", {})
	var civs: Array = diagram_data.get("civs", []).filter(func(c: Dictionary) -> bool: return diagram_city_states or not c.get("isCityState", false))
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 20)
	var diagram := Diagram.new()
	diagram.layout_direction = Control.LAYOUT_DIRECTION_LTR
	diagram.custom_minimum_size = Vector2(760, 720)
	var centre := Vector2(380, 360)
	var radius := 300.0
	for i in civs.size():
		var angle := TAU * i / maxf(1, civs.size()) - PI / 2.0
		var at := centre + Vector2(cos(angle), sin(angle)) * radius
		diagram.positions[civs[i]["name"]] = at
		var badge := _icon(Icons.civ_badge(civs[i]), 54)
		badge.layout_direction = Control.LAYOUT_DIRECTION_LTR
		badge.position = at - Vector2(27, 27)
		badge.set_meta("diagram_position", at - Vector2(27, 27))
		badge.tooltip_text = str(civs[i]["name"])
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		diagram.add_child(badge)
		var name := _label(str(civs[i]["name"]), 14, TEXT)
		name.layout_direction = Control.LAYOUT_DIRECTION_LTR
		name.position = at + Vector2(-60, 30)
		name.set_meta("diagram_position", at + Vector2(-60, 30))
		name.size = Vector2(120, 20)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		diagram.add_child(name)
	diagram.lines = diagram_data.get("lines", [])
	diagram.colors = RELATION_COLORS
	holder.add_child(diagram)
	var legend := VBoxContainer.new()
	legend.add_child(_label("Relations", 20, HEADER))
	for relation: String in ["War", "Unforgivable", "Enemy", "Afraid", "Competitor", "Neutral", "Favorable", "Friend", "Ally", "DefensivePact"]:
		var line := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = RELATION_COLORS[relation]
		swatch.custom_minimum_size = Vector2(36, 6)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(swatch)
		line.add_child(_label({"DefensivePact": "Defensive pact"}.get(relation, relation), 16, TEXT))
		legend.add_child(line)
	holder.add_child(legend)
	_body.add_child(holder)


# region resources ---------------------------------------------------------------------------

func _build_resources() -> void:
	var resources: Array = data.get("resources", [])
	if resources.is_empty():
		_body.add_child(_label("You don't have any luxury or strategic resources yet.", 20, DIM))
		return
	var origins: Array = data.get("origins", [])
	var extras: Array = data.get("extraOrigins", [])
	var extra_names := {"Unimproved": "Unimproved", "CelebratingWLTK": "WLTK+", "DemandingWLTK": "WLTK-", "TradeOffer": "Trade offer", "Stockpile": "Stockpile"}
	var cols: Array = [["icon", "", 44.0, null], ["name", "Resource", 190.0, null]]
	for o: String in origins:
		cols.append(["o:" + o, _plain(o.trim_suffix("+")), 120.0, null])
	cols.append(["total", "Total", 90.0, null])
	for o: String in extras:
		cols.append(["x:" + o, extra_names.get(o, o), 110.0, null])
	_body.add_child(_header_row(cols, false))
	var i := 0
	for r: Dictionary in resources:
		var cells: Array = []
		cells.append(_icon(Icons.badge("resource", str(r["name"]), {"Luxury": Color(0.5, 0.3, 0.6), "Strategic": Color(0.55, 0.3, 0.2)}.get(str(r.get("type", "")), Color(0.3, 0.45, 0.3))), 34))
		cells.append(_label(str(r["name"]), 17, {"Luxury": Color(0.85, 0.65, 1.0), "Strategic": Color(1.0, 0.7, 0.5)}.get(str(r.get("type", "")), TEXT)))
		for o: String in origins:
			var amounts: Dictionary = r.get("amounts", {})
			if amounts.has(o):
				var v := int(amounts[o])
				cells.append(_label(("+%d" % v) if r.get("stockpiled", false) and v >= 0 else str(v), 17, BAD if v < 0 else TEXT))
			else:
				cells.append(Control.new())
		var total := int(r.get("total", 0))
		cells.append(_label(str(total), 18, BAD if total < 0 else HEADER))
		for o: String in extras:
			var extra: Dictionary = r.get("extra", {})
			cells.append(_label(str(int(extra[o])), 17, DIM) if extra.has(o) else Control.new())
		_body.add_child(_row(cols, cells, i))
		i += 1
	_body.add_child(_label(Lang.t("Unimproved: tiles in your (or allied city-states') land with this resource but no improvement to use it.  ") +
		Lang.t("WLTK+/-: cities celebrating / demanding it for We Love The King Day."), 15, DIM))


# region religion ----------------------------------------------------------------------------

func _build_religion() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 30)
	var facts := VBoxContainer.new()
	var to_found := int(data.get("toFound", -1))
	facts.add_child(_label(Lang.format("Religions to be founded: %s", ("?" if to_found < 0 else str(to_found))), 18, TEXT))
	for b: Dictionary in data.get("toFoundBreakdown", []):
		facts.add_child(_label(Lang.format("   %s: %d", [_plain(str(b["text"])), int(b["value"])]), 15, DIM))
	if data.has("faithForProphet"):
		facts.add_child(_label(Lang.format("Minimal faith for the next %s: %d", [data.get("prophet", "Great Prophet"), int(data["faithForProphet"])]), 17, STAT_COLORS["faith"]))
	facts.add_child(_label(Lang.format("Religious status: %s", data.get("status", "None")), 17, TEXT))
	top.add_child(facts)
	_body.add_child(top)
	var religions: Array = data.get("religions", [])
	if religions.is_empty():
		_body.add_child(_label("No religions or pantheons have been founded yet.", 18, DIM))
		return
	if selected_religion == "" or not religions.any(func(r: Dictionary) -> bool: return r["name"] == selected_religion):
		selected_religion = religions[0]["name"]
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	for r: Dictionary in religions:
		var name: String = r["name"]
		var icon: Texture2D = Icons.civ_badge(r["founder"]) if r.get("pantheon", false) and r.has("founder") else Icons.get_icon("religion", str(r.get("icon", "Religion")))
		var b := _icon_button(icon, _plain(str(r.get("displayName", name))), func() -> void:
			selected_religion = name
			_rebuild(), SELECTED if name == selected_religion else BUTTON)
		buttons.add_child(b)
	_body.add_child(buttons)
	for r: Dictionary in religions:
		if r["name"] != selected_religion:
			continue
		var panel := _panel_box(_plain(str(r.get("displayName", r["name"]))), Icons.get_icon("religion", str(r.get("icon", "Religion"))), STAT_COLORS["faith"])
		panel.custom_minimum_size = Vector2(900, 0)
		var box: VBoxContainer = panel.get_child(0)
		box.add_child(_value_text(Lang.format("%s name:", ("Pantheon" if r.get("pantheon", false) else "Religion")), _plain(str(r.get("displayName", "")))))
		box.add_child(_value_text("Founding civ:", str(r.get("foundingCiv", "?"))))
		if r.has("holyCity"):
			box.add_child(_value_text("Holy city:", str(r["holyCity"])))
		box.add_child(_value_text("Cities following this religion:", str(int(r.get("cities", 0)))))
		box.add_child(_value_text("Followers of this religion:", str(int(r.get("followers", 0)))))
		for belief: Dictionary in r.get("beliefs", []):
			box.add_child(HSeparator.new())
			box.add_child(_label(Lang.format("%s  (%s)", [belief["name"], belief.get("type", "")]), 19, HEADER))
			var text := _label(_plain(str(belief.get("text", ""))), 16, TEXT)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.custom_minimum_size = Vector2(860, 0)
			box.add_child(text)
		_body.add_child(panel)


func _value_text(caption: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(caption, 17, DIM)
	label.custom_minimum_size = Vector2(320, 0)
	row.add_child(label)
	row.add_child(_label(value, 17, TEXT))
	return row


# region wonders -----------------------------------------------------------------------------

func _build_wonders() -> void:
	var cols: Array = [["icon", "", 54.0, null], ["name", "Name", 330.0, null], ["status", "Status", 240.0, null], ["location", "Location", 360.0, null]]
	_body.add_child(_header_row(cols, false))
	var group := ""
	var i := 0
	for w: Dictionary in data.get("wonders", []):
		if str(w.get("group", "")) != group:
			group = str(w.get("group", ""))
			var heading := _label(group, 20, Color.html(str(w.get("groupColor", "ffffffff"))).lightened(0.2))
			_body.add_child(heading)
		var cells: Array = []
		var known: bool = w.get("status", "") != "Unknown"
		var texture: Texture2D = null
		if known:
			texture = Icons.construction(str(w.get("realName", ""))) if w.get("category", "") != "Terrain" else Icons.get_icon("other", "Wonders")
		cells.append(_icon(texture, 40))
		cells.append(_label(str(w.get("name", "")), 17, TEXT if known else DIM))
		var status := str(w.get("status", ""))
		cells.append(_label(_plain(str(w.get("statusText", ""))), 16, {"Owned": GOOD, "Known": TEXT}.get(status, DIM)))
		var location := _plain(str(w.get("location", "")).replace("[", "").replace("]", ""))
		if w.has("x"):
			var at := "%d,%d" % [int(w["x"]), int(w["y"])]
			cells.append(_button(location, func() -> void: chosen.emit("ov_goto", at), BUTTON, 15))
		else:
			cells.append(_label(location, 15, DIM))
		_body.add_child(_row(cols, cells, i))
		i += 1


# region notifications -----------------------------------------------------------------------

func _build_notifications() -> void:
	var turns: Array = data.get("turns", [])
	var any := false
	for t: Dictionary in turns:
		var notes: Array = t.get("notifications", [])
		if notes.is_empty():
			continue
		any = true
		var turn := int(t["turn"])
		var year := int(t.get("year", 0))
		var open := not closed_turns.has(turn)
		var title := Lang.format("%s%s   Turn %d   %s", ["v " if open else "> ", "Current turn  |" if t.get("current", false) else "",
			turn, (Lang.format("%d BC", -year)) if year < 0 else (Lang.format("%d AD", year))])
		var head := _button(title, func() -> void:
			if closed_turns.has(turn):
				closed_turns.erase(turn)
			else:
				closed_turns[turn] = true
			_rebuild(), Color(0.18, 0.2, 0.28), 18)
		_body.add_child(head)
		if not open:
			continue
		var category := ""
		for n: Dictionary in notes:
			if str(n.get("category", "General")) != category:
				category = str(n.get("category", "General"))
				if category != "General":
					_body.add_child(_label("   " + Lang.t(category), 17, HEADER))
			_body.add_child(_notification_row(n))
	if not any:
		_body.add_child(_label("No notifications yet.", 20, DIM))


func _notification_row(n: Dictionary) -> Button:
	var actions: Array = n.get("actions", [])
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 42)
	_restyle(button, Color(0.12, 0.14, 0.19) if actions.is_empty() else Color(0.16, 0.2, 0.28))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 8
	inner.offset_right = -8
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for path: String in n.get("icons", []).slice(0, 3):
		inner.add_child(_icon(Icons.from_path(path), 28))
	var label := _label(_plain(str(n.get("text", "")).replace("[", "").replace("]", "").replace("{", "").replace("}", "")), 16, TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	inner.add_child(label)
	button.add_child(inner)
	if not actions.is_empty():
		var action: Dictionary = actions[0]
		button.pressed.connect(func() -> void: _do_action(action))
	return button


## What clicking a notification does, like Unciv's NotificationActions.
func _do_action(action: Dictionary) -> void:
	var type := str(action.get("type", ""))
	var at := "%d,%d" % [int(action.get("x", 0)), int(action.get("y", 0))]
	match type:
		"City":
			chosen.emit("ov_city_card", at)
		"Location", "MapUnit", "PromoteUnit":
			chosen.emit("ov_goto", at)
		"Tech":
			chosen.emit("ov_big", "tech")
		"Policy":
			chosen.emit("ov_big", "policies")
		"Diplomacy":
			chosen.emit("ov_big", "diplomacy")
		"Religion":
			chosen.emit("ov_tab", "religion")
		"Overview":
			chosen.emit("ov_tab", "cities")


# region table helpers ------------------------------------------------------------------------

## Sorts [param rows] by this tab's chosen column. [param keys]: column -> key function; others use [param fallback].
func _sort(rows: Array, keys: Dictionary, fallback: Callable) -> void:
	var state: Array = sort_by.get(tab, [])
	if state.is_empty():
		return
	var column: String = state[0]
	var descending: bool = state[1]
	var key_of: Callable = keys.get(column, func(row: Dictionary) -> Variant: return fallback.call(row, column))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Variant = key_of.call(a)
		var kb: Variant = key_of.call(b)
		return ka > kb if descending else ka < kb)


## The header: one button per column (click to sort, again to reverse - like Unciv's sortable grids).
func _header_row(cols: Array, sortable := true) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var state: Array = sort_by.get(tab, [])
	for col: Array in cols:
		var id: String = col[0]
		var caption: String = col[1]
		if state.size() == 2 and state[0] == id:
			caption += " v" if state[1] else " ^"
		var button := _button(caption, func() -> void:
			var current: Array = sort_by.get(tab, [])
			sort_by[tab] = [id, not current[1]] if current.size() == 2 and current[0] == id else [id, id not in ["name", "action", "construction", "closestCity", "religion"]]
			_rebuild(), Color(0.16, 0.18, 0.26), 15)
		button.icon = col[3]
		button.add_theme_constant_override("icon_max_width", 24)
		button.custom_minimum_size = Vector2(col[2], 38)
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.disabled = not sortable
		row.add_child(button)
	return row


## One table row: each cell in a box as wide as its column.
func _row(cols: Array, cells: Array, index: int, background := Color(-1, 0, 0)) -> Control:
	var holder := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = background if background.r >= 0.0 else (ROW_A if index % 2 == 0 else ROW_B)
	style.set_corner_radius_all(6)
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	holder.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	holder.add_child(row)
	for i in cols.size():
		var cell := MarginContainer.new()
		cell.custom_minimum_size = Vector2(cols[i][2], 40)
		cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cell.clip_contents = true
		var content: Control = cells[i] if i < cells.size() else Control.new()
		content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if content is Button:
			(content as Button).clip_text = true   # fits its column
		elif content is Label:
			(content as Label).clip_text = true   # (a long text would otherwise widen its column, and the table past the board)
		cell.add_child(content)
		row.add_child(cell)
	return holder


func _num(value: int, colour: Color) -> Label:
	var label := _label(str(value), 17, colour)
	label.text_direction = Control.TEXT_DIRECTION_LTR
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


# region helpers ------------------------------------------------------------------------------

static func _plain(text: String) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 0xE000 or code > 0xF8FF:
			out += text[i]
	return out.replace("  ", " ").strip_edges()


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _icon(texture: Texture2D, side: float) -> Control:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _icon_button(texture: Texture2D, text: String, on_press: Callable, colour: Color) -> Button:
	var button := _button(text, on_press, colour, 15)
	button.icon = texture
	button.add_theme_constant_override("icon_max_width", 26)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button


func _button(text: String, on_press: Callable, color: Color, font_size := 17) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.52, 0.56))
	_restyle(button, color)
	button.pressed.connect(on_press)
	return button


func _restyle(button: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		match state:
			"hover": style.bg_color = color.lightened(0.18)
			"pressed": style.bg_color = color.darkened(0.2)
			"disabled": style.bg_color = color.darkened(0.45)
			_: style.bg_color = color
		style.set_corner_radius_all(7)
		style.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, style)
