# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## The card: shows the selected unit, a city's production, or the research list.
## Used as-is on the desktop HUD, and rendered into a SubViewport on the left wrist in VR.

## Kinds and values:
##   unit card:     "action" (UnitActionType), "improvement" (name)
##   city card:     "produce" (name, build next), "queue" (name, add to end), "buy" (name), "unqueue" (index)
##   research card: "research" (tech name)
##   promotion card: "promote" (promotion name); unit card: "promotion_card" opens it, "rename_unit" names it
##   footer "settings_card" opens the settings board (settings_board.gd)
##   footer:        "prev_unit", "next_unit", "next_idle", "research_card", "end_turn", "recenter", "close"
##   lobby card:    "lobby_resume", "lobby_continue" (save name), "lobby_quick", "lobby_new", "lobby_load", "settings_card", "civilopedia_card", "quit"
##   setup card:    "setup_tab" (you/world/rules), "setup_set" ("key|value"), "setup_toggle" (key),
##                  "setup_step" ("key|+1"), "setup_start", "lobby" (back to the lobby card)
##   saves card:    "load_save" (name), "lobby"
##   settings card also: "save_game", "main_menu", "reset_boards", "setting_toggle" (an Unciv option's key)
##   unit card also: "action" ("type|title", "|confirm" appended once a risky action is confirmed), "action_arm"
##                   (first click on a risky action: "type|title"), "pick_cancel" (stop picking a tile)
##   city card also: "bombard" (city name: pick a target for the city's guns)
##   alert card:    "alert_answer" ("key|option")
##   great people:  "great_person" (unit name); vote card: "vote" (civ name, "" abstains)
signal chosen(kind: String, value: String)
## Emitted after the card's contents change, so whoever places it can re-fit it.
signal layout_changed

const WIDTH := 380
const Icons := preload("res://scripts/icons.gd")
const LIST_HEIGHT := 360

var show_recenter := false   # VR only
var in_vr := false
var compact := false         # no unit/turn footer (the floating city card); set before adding to the tree
var civ_colors: Dictionary = {}   # civ name -> {inner, outer} (from the map), for unit portraits
var civ_info: Dictionary = {}     # civ name -> getState civs entry (nation, colours), for emblems
var lobby_mode := false      # no game on the table yet: hide the unit/turn footer
var keep_scroll_once := false   # the next card rebuild keeps the scroll position (e.g. after pressing + or -)
var _restore_scroll := 0
## A risky unit action clicked once ("type|title"): its button now asks to be clicked again
var armed_action := ""
## While main.gd waits for a tile to be picked for a unit action (swap with, road to...): what to say on the card
var picking_text := ""
var _armed_unit := -1
## What the footer's End turn button says (what still has to be decided first, like Unciv's next-turn button)
var end_turn_text := "End turn":
	set(value):
		end_turn_text = value
		if _end_turn_button != null:
			_end_turn_button.text = value
var _end_turn_button: Button

var _title: Label
var _info: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _recenter_row: HBoxContainer
var _footer: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.clip_text = true
	box.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	box.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	Icons.thick_scrollbars(_scroll)
	_scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)

	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 6)
	box.add_child(_footer)
	_footer.add_child(HSeparator.new())
	var units_row := HBoxContainer.new()
	units_row.add_theme_constant_override("separation", 6)
	_footer.add_child(units_row)
	units_row.add_child(_make_button("< Prev", func() -> void: chosen.emit("prev_unit", ""), Color(0.25, 0.3, 0.4)))
	units_row.add_child(_make_button("Idle unit", func() -> void: chosen.emit("next_idle", ""), Color(0.25, 0.3, 0.4)))
	units_row.add_child(_make_button("Next >", func() -> void: chosen.emit("next_unit", ""), Color(0.25, 0.3, 0.4)))
	var turn_row := HBoxContainer.new()
	turn_row.add_theme_constant_override("separation", 6)
	_footer.add_child(turn_row)
	turn_row.add_child(_make_button("Research", func() -> void: chosen.emit("research_card", ""), Color(0.2, 0.3, 0.5)))
	turn_row.add_child(_make_button("Settings", func() -> void: chosen.emit("settings_card", ""), Color(0.25, 0.25, 0.3)))
	_end_turn_button = _make_button(end_turn_text, func() -> void: chosen.emit("end_turn", ""), Color(0.55, 0.35, 0.1))
	turn_row.add_child(_end_turn_button)
	_recenter_row = HBoxContainer.new()
	_footer.add_child(_recenter_row)
	_recenter_row.add_child(_make_button("Recenter table", func() -> void: chosen.emit("recenter", ""), Color(0.25, 0.25, 0.25)))
	_recenter_row.visible = show_recenter
	_footer.visible = not compact
	show_unit({})


func scroll_by(pixels: float) -> void:
	_scroll.scroll_vertical += int(pixels)


# region cards ---------------------------------------------------------------------------

## Rebuilds the card for a getUnit result (or an empty Dictionary for "nothing selected").
func show_unit(unit: Dictionary) -> void:
	if not _begin():
		return
	_title.remove_theme_color_override("font_color")
	if unit.is_empty():
		_title.text = "No unit selected"
		_info.text = "Point at a unit or city to select it."
		_end()
		return

	if int(unit.get("id", -1)) != _armed_unit:
		armed_action = ""   # a different unit: forget the half-confirmed action
		_armed_unit = int(unit.get("id", -1))
	var name: String = str(unit.get("name", "?"))
	var given_name := str(unit.get("instanceName", ""))
	_title.text = given_name if given_name != "" else name
	_title.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45))
	var facts: Array[String] = []
	if given_name != "":
		facts.append(name)
	if unit.has("unitType"):
		facts.append(str(unit["unitType"]))
	for flag: Array in [["fortified", "Fortified"], ["sleeping", "Sleeping"], ["automated", "Automated"],
			["moving", "On its way"], ["embarked", "Embarked"]]:
		if unit.get(flag[0], false):
			facts.append(flag[1])
	_info.text = "   ".join(facts)
	if compact:
		_add_close()

	# Portrait in its civ's colours, with its strength and moves beside it
	var colours: Dictionary = civ_colors.get(str(unit.get("civ", "")), {})
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_icon(Icons.badge("unit", name, colours.get("inner", Color(0.2, 0.25, 0.35)), colours.get("outer", Color.WHITE)), 64))
	var chips := GridContainer.new()
	chips.columns = 2
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if int(unit.get("strength", 0)) > 0:
		chips.add_child(_value_chip("Strength", str(int(unit["strength"])), Color(1.0, 0.75, 0.55)))
	if int(unit.get("rangedStrength", 0)) > 0:
		chips.add_child(_value_chip("RangedStrength", "%d" % int(unit["rangedStrength"]), Color(1.0, 0.6, 0.5)))
		chips.add_child(_value_chip("Range", str(int(unit.get("range", 1))), Color(0.85, 0.85, 0.9)))
	chips.add_child(_value_chip("Movement", "%s/%d" % [str(snappedf(float(unit.get("movement", 0)), 0.1)), int(unit.get("maxMovement", 0))],
		Color(0.7, 0.9, 1.0)))
	top.add_child(chips)
	var rename := _make_button("Rename", func() -> void: chosen.emit("rename_unit", ""), Color(0.25, 0.28, 0.38))
	rename.size_flags_horizontal = Control.SIZE_SHRINK_END
	rename.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rename.custom_minimum_size = Vector2(92, 36)
	rename.alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(rename)
	_list.add_child(top)

	if picking_text != "":
		var pick := _make_row(picking_text, Color(0.22, 0.34, 0.5), [["Cancel", func() -> void: chosen.emit("pick_cancel", ""), Color(0.4, 0.22, 0.2)]])
		_list.add_child(pick)
	if not unit.get("due", true):
		_add_note("Skipping this turn (Skip again to give it orders).")

	# Health, then experience towards the next promotion
	var health := int(unit.get("health", 100))
	var health_colour := Color(0.35, 0.85, 0.35) if health > 66 else (Color(0.95, 0.8, 0.2) if health > 33 else Color(0.95, 0.3, 0.25))
	_list.add_child(_labelled_bar("Health", float(health) / 100.0, health_colour, "%d/100" % health))
	var military := int(unit.get("strength", 0)) > 0 or int(unit.get("rangedStrength", 0)) > 0
	if military and int(unit.get("xpForNextPromotion", 0)) > 0:
		var needed := int(unit["xpForNextPromotion"])
		_list.add_child(_labelled_bar("XP", float(unit.get("xp", 0)) / needed, Color(0.95, 0.75, 0.25), "%d/%d" % [int(unit.get("xp", 0)), needed]))
	if unit.get("canPromote", false):
		var promote := _make_button("Promote!  Choose a promotion", func() -> void: chosen.emit("promotion_card", ""), Color(0.6, 0.45, 0.08))
		promote.icon = Icons.action("Promote")
		promote.add_theme_constant_override("icon_max_width", 26)
		_list.add_child(promote)
	var promotions: Array = unit.get("promotions", [])
	if not promotions.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 2)
		for p: String in promotions:
			var found := Icons.promotion(p)
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 3)
			chip.add_child(_icon(found[0], 22))
			var label := Label.new()
			label.text = p
			label.add_theme_font_size_override("font_size", 13)
			label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
			chip.add_child(label)
			flow.add_child(chip)
		_list.add_child(flow)

	# Work in progress, and enemies in reach
	var work: Dictionary = unit.get("tileWork", {})
	if work.get("inProgress") != null:
		_list.add_child(_icon_row(Icons.badge("improvement", str(work["inProgress"]), Color(0.25, 0.4, 0.25)),
			"Building %s" % work["inProgress"], "%d turns left" % int(work.get("turnsLeft", 0)), Color(0.18, 0.28, 0.18), Callable(), 30))
	var targets: Array = unit.get("targets", [])
	if not targets.is_empty():
		var warn := Label.new()
		warn.text = "%d enemy target%s in reach (red rings): click one to aim" % [targets.size(), "s" if targets.size() > 1 else ""]
		warn.add_theme_font_size_override("font_size", 15)
		warn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(warn)

	# Actions as icon buttons, two to a row (like Unciv's action bar)
	var actions := (unit.get("actions", []) as Array).filter(func(a: Dictionary) -> bool:
		return a.get("enabled", false) and a["type"] != "Promote")   # promotions use the card above instead
	if not actions.is_empty():
		_add_header("Actions")
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		var armed_text := ""
		for action: Dictionary in actions:
			var type: String = action["type"]
			var raw_title := str(action.get("title", type))
			var title: String = _plain(raw_title.replace("{", "").replace("}", ""))   # Unciv templates like "{Found city}"
			var active: bool = action.get("current", false)
			var colour := Color(0.24, 0.36, 0.55) if active else Color(0.2, 0.22, 0.3)
			if type == "FoundCity":
				colour = Color(0.45, 0.35, 0.1)
			elif type in ["DisbandUnit", "Pillage"]:
				colour = Color(0.42, 0.18, 0.15)
			var key := "%s|%s" % [type, raw_title]
			var confirm_text := str(action.get("confirm", ""))
			if action.get("target", "") == "tile":
				title += "..."   # then pick a tile on the map
			if confirm_text != "" and armed_action == key:
				title = "Sure? Click again"
				colour = Color(0.6, 0.2, 0.15)
			var button := _make_button(title, func() -> void:
				if confirm_text != "" and armed_action != key:
					armed_action = key
					chosen.emit("action_arm", key)
				else:
					armed_action = ""
					chosen.emit("action", key + ("|confirm" if confirm_text != "" else "")), colour)
			if confirm_text != "" and armed_action == key:
				button.tooltip_text = confirm_text
				armed_text = confirm_text
			button.icon = Icons.action(type)
			button.add_theme_constant_override("icon_max_width", 24)
			button.add_theme_font_size_override("font_size", 15)
			button.custom_minimum_size = Vector2(0, 40)
			if button.tooltip_text == "":
				button.tooltip_text = title
			grid.add_child(button)
		_list.add_child(grid)
		if armed_text != "":
			var warn := Label.new()
			warn.text = armed_text + "  (click the red button again)"
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.add_theme_font_size_override("font_size", 15)
			warn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
			_list.add_child(warn)

	var improvements: Array = unit.get("improvements", [])
	if not improvements.is_empty():
		_add_header("Build here")
		for imp: Dictionary in improvements:
			var imp_name: String = imp["name"]
			var turns := int(imp.get("turns", 0))
			var cancel := imp_name.begins_with("Cancel")
			var texture: Texture2D = Icons.action("Stop") if cancel else Icons.badge("improvement", imp_name, Color(0.25, 0.4, 0.25))
			_list.add_child(_icon_row(texture, imp_name, ("%d turns" % turns) if turns > 0 else "",
				Color(0.4, 0.2, 0.15) if cancel else Color(0.17, 0.28, 0.17), func() -> void: chosen.emit("improvement", imp_name), 30))
	_end()


## A stat symbol (from StatIcons) and a number on a dark tile.
func _value_chip(icon_name: String, value: String, colour: Color) -> Control:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 4
	style.content_margin_right = 6
	chip.add_theme_stylebox_override("panel", style)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)
	row.add_child(_icon(Icons.get_icon("stat", icon_name), 24))
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", colour)
	row.add_child(label)
	return chip


## "Health [bar]" - a caption in front of a progress bar.
func _labelled_bar(caption: String, fraction: float, colour: Color, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(62, 0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", colour.lightened(0.2))
	row.add_child(label)
	var bar := _progress_bar(fraction, colour, text, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	return row


## Drops Unciv's icon characters (private-use code points our font doesn't have).
static func _plain(text: String) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 0xE000 or code > 0xF8FF:
			out += text[i]
	return out.strip_edges()


## A getCity result: the city's numbers, growth and borders, what it's building, and everything it can build
## (click to build it next; the gold chip buys it). "City view" opens the full city screen.
func show_city(city: Dictionary, gold: int) -> void:
	if not _begin():
		return
	var pop := int(city.get("population", 0))
	_title.text = "%s%s" % ["* " if city.get("isCapital", false) else "", city.get("name", "?")]
	_title.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45))
	var facts: Array[String] = ["Population %d" % pop]
	if city.has("defense"):
		facts.append("Defence %d" % int(city["defense"]))
	facts.append("Health %d/%d" % [int(city.get("health", 0)), int(city.get("maxHealth", 0))])
	if int(city.get("freePopulation", 0)) > 0:
		facts.append("%d idle citizen%s" % [int(city["freePopulation"]), "s" if int(city["freePopulation"]) > 1 else ""])
	if city.get("isPuppet", false):
		facts.append("Puppet")
	_info.text = "   ".join(facts)

	# The city's yields, in Unciv's colours and symbols
	var stats: Dictionary = city.get("stats", city.get("yields", {}))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for stat: String in ["food", "production", "gold", "science", "culture", "faith", "happiness"]:
		if not stats.has(stat) or (stat == "faith" and not city.get("religionEnabled", true)):
			continue
		var value := roundi(float(stats[stat]))
		grid.add_child(_stat_chip(stat, ("%+d" % value) if stat in ["food", "gold", "happiness"] else str(value)))
	_list.add_child(grid)

	# Growth and borders as bars
	var food_to_grow := maxi(1, int(city.get("foodToGrow", 1)))
	var growth_text := ""
	var growth_colour: Color = STAT_COLORS["food"]
	match str(city.get("growthStatus", "growing" if city.get("turnsToGrowth") != null else "stopped")):
		"starving":
			growth_text = "Starving! %d turns" % int(city.get("turnsToStarvation", 0))
			growth_colour = Color(1.0, 0.35, 0.3)
		"growing":
			growth_text = "Grows in %d turns" % int(city.get("turnsToGrowth", 0))
		"foodToProduction":
			growth_text = "Food -> production"
		_:
			growth_text = "Not growing"
	_list.add_child(_bar_row("food", float(city.get("foodStored", 0)) / food_to_grow, growth_colour,
		"%d/%d" % [int(city.get("foodStored", 0)), food_to_grow], growth_text))
	var expansion: Dictionary = city.get("expansion", {})
	if not expansion.is_empty():
		var needed := maxi(1, int(expansion.get("cultureToNextTile", 1)))
		var turns := int(expansion.get("turns", -1))
		_list.add_child(_bar_row("culture", float(expansion.get("cultureStored", 0)) / needed, STAT_COLORS["culture"],
			"%d/%d" % [int(expansion.get("cultureStored", 0)), needed], ("Border in %d turns" % turns) if turns > 0 else "Borders stopped"))

	if compact:
		_add_close()
	var city_name: String = city.get("name", "")
	var view := _make_button("City view  -  tiles, citizens, queue, buying", func() -> void: chosen.emit("city_view", city_name),
		Color(0.5, 0.38, 0.12))
	view.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(view)
	if city.get("canBombard", false) and not city.get("bombardTargets", []).is_empty():
		var shots: Array = city["bombardTargets"]
		var bombard := _make_button("Bombard  -  %d enem%s in range (strength %d)" % [shots.size(), "y" if shots.size() == 1 else "ies",
			int(city.get("rangedStrength", 0))], func() -> void: chosen.emit("bombard", city_name), Color(0.55, 0.2, 0.15))
		bombard.icon = Icons.get_icon("stat", "RangedStrength")
		bombard.add_theme_constant_override("icon_max_width", 24)
		_list.add_child(bombard)
	if city.get("isBeingRazed", false):
		_add_note("This city is being razed - it shrinks each turn until it's gone. Stop razing it in the city view.")

	# What it's building: the current item with its progress, then the rest of the queue
	var queue: Array = city.get("queue", [])
	_add_header("Producing" if not queue.is_empty() else "Producing nothing - pick something below")
	for entry: Dictionary in queue:
		var index := int(entry["index"])
		var name: String = entry["name"]
		var turns := int(entry.get("turns", -1))
		var row := _icon_row(Icons.construction(name), name, ("%d turns" % turns) if turns >= 0 else "",
			Color(0.32, 0.26, 0.1) if index == 0 else Color(0.22, 0.2, 0.12), Callable(), 42 if index == 0 else 30)
		if index == 0 and entry.has("cost"):
			var column: VBoxContainer = row.get_child(0).get_child(1)
			var cost := maxi(1, int(entry["cost"]))
			column.add_child(_progress_bar(float(entry.get("progress", 0)) / cost, STAT_COLORS["production"],
				"%d/%d" % [int(entry.get("progress", 0)), cost], 16))
			row.custom_minimum_size.y = 58
		var remove := _make_button("X", func() -> void: chosen.emit("unqueue", str(index)), Color(0.45, 0.15, 0.13))
		remove.custom_minimum_size = Vector2(36, 34)
		remove.alignment = HORIZONTAL_ALIGNMENT_CENTER
		remove.size_flags_horizontal = Control.SIZE_SHRINK_END
		remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.get_child(0).add_child(remove)
		_list.add_child(row)

	var options: Array = city.get("options", []).filter(func(o: Dictionary) -> bool: return o.get("buildable", false))
	for group: Array in [["unit", "Units"], ["building", "Buildings"], ["wonder", "Wonders"], ["perpetual", "Other"]]:
		var of_kind := options.filter(func(o: Dictionary) -> bool: return o["kind"] == group[0])
		if of_kind.is_empty():
			continue
		_add_header(group[1])
		for option: Dictionary in of_kind:
			var option_name: String = option["name"]
			var turns := int(option.get("turns", -1))
			var row := _icon_row(Icons.construction(option_name), option_name, ("%d turns" % turns) if turns >= 0 else "",
				Color(0.15, 0.17, 0.23), func() -> void: chosen.emit("produce", option_name), 30)
			if option.get("canBuy", false):
				var buy := _make_button("%d" % int(option["goldCost"]), func() -> void: chosen.emit("buy", option_name), Color(0.5, 0.4, 0.08))
				buy.icon = Icons.get_icon("stat", "Gold")
				buy.add_theme_constant_override("icon_max_width", 20)
				buy.custom_minimum_size = Vector2(74, 34)
				buy.size_flags_horizontal = Control.SIZE_SHRINK_END
				buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				buy.tooltip_text = "Buy now for %d gold (you have %d)" % [int(option["goldCost"]), gold]
				row.get_child(0).add_child(buy)
			_list.add_child(row)
	if not compact:
		_add_close()
	_end()


const STAT_COLORS := {
	"food": Color(0.45, 0.85, 0.35), "production": Color(0.95, 0.55, 0.25), "gold": Color(0.98, 0.8, 0.25),
	"science": Color(0.4, 0.72, 1.0), "culture": Color(0.8, 0.5, 0.98), "happiness": Color(0.5, 0.9, 0.35),
	"faith": Color(0.75, 0.88, 1.0),
}


## A stat symbol and its number on a dark tile.
func _stat_chip(stat: String, value: String) -> Control:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 4
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)
	chip.custom_minimum_size = Vector2(84, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)
	row.add_child(_icon(Icons.get_icon("stat", stat.capitalize()), 26))
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", STAT_COLORS[stat].lightened(0.25))
	row.add_child(label)
	return chip


## A stat symbol, a progress bar and a caption, e.g. food towards the next citizen.
func _bar_row(stat: String, fraction: float, colour: Color, bar_text: String, caption: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_icon(Icons.get_icon("stat", stat.capitalize()), 24))
	var bar := _progress_bar(fraction, colour, bar_text, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(150, 0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", colour.lightened(0.2))
	row.add_child(label)
	return row


func _progress_bar(fraction: float, colour: Color, text: String, height: float) -> Control:
	var back := Panel.new()
	back.custom_minimum_size = Vector2(60, height)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.16, 0.2)
	style.set_corner_radius_all(5)
	back.add_theme_stylebox_override("panel", style)
	var fill := Panel.new()
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = colour.darkened(0.2)
	fill_style.set_corner_radius_all(5)
	fill.add_theme_stylebox_override("panel", fill_style)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(fraction, 0.0, 1.0)
	back.add_child(fill)
	var label := Label.new()
	label.text = text
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(height * 0.72))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(label)
	return back


func _icon(texture: Texture2D, side: float) -> Control:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


## A full-width row: icon, name (with room under it for a bar), text on the right; clickable when
## [param on_press] is valid. Extra buttons go into row.get_child(0) (the HBoxContainer).
func _icon_row(texture: Texture2D, text: String, right: String, colour: Color, on_press: Callable, icon_side: float) -> Button:
	var button := _make_button("", on_press if on_press.is_valid() else func() -> void: pass, colour)
	button.custom_minimum_size = Vector2(0, maxf(40, icon_side + 8))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 6
	inner.offset_right = -6
	inner.offset_top = 3
	inner.offset_bottom = -3
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	button.add_child(inner)
	inner.add_child(_icon(texture, icon_side))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	inner.add_child(column)
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 17)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	if right != "":
		var turns := Label.new()
		turns.text = right
		turns.add_theme_font_size_override("font_size", 14)
		turns.add_theme_color_override("font_color", Color(0.72, 0.76, 0.84))
		turns.mouse_filter = Control.MOUSE_FILTER_IGNORE
		turns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(turns)
	return button


## A getUnit result's promotionChoices, one button each with its description underneath.
func show_promotions(unit: Dictionary) -> void:
	if not _begin():
		return
	_title.text = "Promote %s" % unit.get("name", "?")
	var owned: Array = unit.get("promotions", [])
	_info.text = "XP %d/%d. Pick one promotion.%s" % [int(unit.get("xp", 0)), int(unit.get("xpForNextPromotion", 0)),
		("\nHas: " + ", ".join(owned)) if not owned.is_empty() else ""]
	if compact:
		_add_close()
	var choices: Array = unit.get("promotionChoices", [])
	if choices.is_empty():
		_add_header("No promotion available right now.")
	for choice: Dictionary in choices:
		var promotion_name: String = choice["name"]
		_list.add_child(_make_button(promotion_name, func() -> void: chosen.emit("promote", promotion_name), Color(0.45, 0.35, 0.1)))
		var description := Label.new()
		description.text = str(choice.get("description", ""))
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 14)
		description.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
		_list.add_child(description)
	if not compact:
		_add_close()
	_end()


# region popups from Unciv ---------------------------------------------------------------------

## One of Unciv's popups (getState alerts): who says it, what, and the answers to pick from.
func show_alert(alert: Dictionary, waiting := 0) -> void:
	if not _begin():
		return
	_title.text = _plain(str(alert.get("title", "")))
	_title.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45))
	var lines: Array[String] = []
	if alert.get("type", "") == "Tutorial":   # one of Unciv's tutorials, a step at a time
		lines.append("Tutorial" + ("  -  %d of %d" % [int(alert["step"]), int(alert["steps"])] if int(alert.get("steps", 1)) > 1 else ""))
	if alert.has("leader"):
		lines.append(str(alert["leader"]) if not alert.get("isCityState", false) else str(alert.get("civ", "")))   # e.g. "Boudicca of Celts"
	if waiting > 0:
		lines.append("%d more message%s after this one" % [waiting, "s" if waiting > 1 else ""])
	_info.text = "\n".join(lines)
	if alert.has("nation"):
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		var badge := Icons.civ_badge(civ_info.get(str(alert.get("civ", "")), {"nation": alert["nation"]}))
		if badge != null:
			head.add_child(_icon(badge, 64))
		var text := Label.new()
		text.text = _plain(str(alert.get("text", "")))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", 17)
		head.add_child(text)
		_list.add_child(head)
	elif str(alert.get("text", "")) != "":
		var text := Label.new()
		text.text = _plain(str(alert["text"]))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 17)
		_list.add_child(text)
	if alert.get("type", "") in ["TechResearched", "WonderBuilt"]:
		var icon: Texture2D = Icons.get_icon("tech", str(alert.get("tech", ""))) if alert.has("tech") else Icons.construction(str(alert.get("wonder", "")))
		if icon != null:
			_list.add_child(_icon(icon, 72))
	# A trade offer: what each side gives
	if alert.has("theyGive"):
		_add_header("%s gives:" % alert.get("civ", "They"))
		for offer: Dictionary in alert["theyGive"]:
			_add_note(_offer_text(offer))
		_add_header("You give:")
		for offer: Dictionary in alert.get("youGive", []):
			_add_note(_offer_text(offer))
	# The World Congress results
	if alert.has("votes"):
		for civ: Dictionary in alert["votes"].get("civs", []):
			var text := str(civ["name"])
			if civ.get("isMajor", false):
				text = "%d votes  %s" % [int(civ.get("votesReceived", 0)), text]
			text += "  -  " + ("abstained" if civ.get("abstained", false) else "voted for %s" % civ.get("votedFor", "?"))
			_add_note(text)
	_list.add_child(HSeparator.new())
	var key := str(alert.get("key", ""))
	for option: Dictionary in alert.get("options", []):
		var option_id: String = option["id"]
		var colour := Color(0.2, 0.3, 0.45)
		if option_id in ["accept", "annex", "yes", "victory"]:
			colour = Color(0.2, 0.42, 0.25)
		elif option_id in ["raze", "war", "refuse", "destroy"]:
			colour = Color(0.48, 0.2, 0.15)
		elif option_id in ["liberate"]:
			colour = Color(0.45, 0.38, 0.12)
		var button := _make_button(_plain(str(option["label"])), func() -> void: chosen.emit("alert_answer", key + "|" + option_id), colour)
		button.disabled = not option.get("enabled", true)
		button.clip_text = false
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(button)
		if str(option.get("description", "")) != "":
			_add_note(_plain(str(option["description"])))
	if alert.get("type", "") == "Tutorial":
		_add_note("Tutorials can be turned off in Settings > Gameplay. They're all in the Civilopedia too.")
	_end()


static func _offer_text(offer: Dictionary) -> String:
	var text := _plain(str(offer.get("label", offer.get("name", "?"))))
	if offer.get("countable", false) and int(offer.get("amount", 0)) > 1:
		text = "%d %s" % [int(offer["amount"]), text]
	if int(offer.get("duration", -1)) > 0:
		text += " (%d turns)" % int(offer["duration"])
	return text


## Unciv's free great person picker (getGreatPersonChoices).
func show_great_people(data: Dictionary) -> void:
	if not _begin():
		return
	_title.text = "Choose a free great person"
	_info.text = "You have %d free great person%s to pick." % [int(data.get("free", 0)), "" if int(data.get("free", 0)) == 1 else "s"]
	for choice: Dictionary in data.get("choices", []):
		var unit_name: String = choice["name"]
		var button := _make_button(unit_name, func() -> void: chosen.emit("great_person", unit_name),
			Color(0.45, 0.35, 0.1) if choice.get("available", false) else Color(0.18, 0.18, 0.2))
		button.icon = Icons.get_icon("unit", unit_name)
		button.add_theme_constant_override("icon_max_width", 28)
		button.disabled = not choice.get("available", false)
		_list.add_child(button)
		if choice.get("available", false):
			_add_note(_plain(str(choice.get("description", ""))))
	if compact:
		_add_close()
	_end()


## The World Congress vote: who should become world leader (getVoteChoices).
func show_vote(data: Dictionary) -> void:
	if not _begin():
		return
	_title.text = "Vote for world leader"
	_info.text = "Choose who should become the world leader and win a Diplomatic Victory!"
	for civ: Dictionary in data.get("civs", []):
		var civ_name: String = civ["name"]
		var button := _make_button("Vote for %s" % civ_name, func() -> void: chosen.emit("vote", civ_name), Color(0.2, 0.3, 0.45))
		var badge := Icons.civ_badge(civ_info.get(civ_name, {"nation": civ.get("nation", civ_name)}))
		if badge != null:
			button.icon = badge
			button.add_theme_constant_override("icon_max_width", 28)
		_list.add_child(button)
	_list.add_child(_make_button("Abstain", func() -> void: chosen.emit("vote", ""), Color(0.3, 0.25, 0.25)))
	if compact:
		_add_close()
	_end()


## A getTechs result: what's being researched, and every tech you could aim for.
func show_research(techs: Dictionary) -> void:
	if not _begin():
		return
	var current: Variant = techs.get("current")
	_title.text = "Research"
	var lines: Array[String] = []
	if current == null:
		lines.append("Nothing being researched - pick a tech!")
	else:
		lines.append("Researching %s" % current)
	if int(techs.get("freeTechs", 0)) > 0:
		lines.append("You have %d free tech(s) to pick - choose a highlighted one." % int(techs["freeTechs"]))
	lines.append("Science %+d per turn. Picking a later tech queues its prerequisites." % int(techs.get("sciencePerTurn", 0)))
	_info.text = "\n".join(lines)
	if compact:
		_add_close()

	var open: Array = techs.get("techs", []).filter(func(t: Dictionary) -> bool: return not t.get("researched", false))
	open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["column"]) != int(b["column"]):
			return int(a["column"]) < int(b["column"])
		return int(a["row"]) < int(b["row"]))
	var era := ""
	for tech: Dictionary in open:
		if tech["era"] != era:
			era = tech["era"]
			_add_header(era)
		var tech_name: String = tech["name"]
		var text := tech_name
		if tech.has("turns"):
			text += "  (%s turns)" % tech["turns"]
		var queue_index := int(tech.get("queueIndex", -1))
		var color := Color(0.2, 0.22, 0.28)
		if queue_index == 0:
			color = Color(0.2, 0.4, 0.6)
			text = "> " + text
		elif queue_index > 0:
			color = Color(0.18, 0.3, 0.42)
			text = "%d. %s" % [queue_index + 1, text]
		elif tech.get("researchable", false):
			color = Color(0.22, 0.32, 0.25)
		_list.add_child(_make_button(text, func() -> void: chosen.emit("research", tech_name), color))
	if not compact:
		_add_close()
	_end()


# region lobby -----------------------------------------------------------------------------

## The main menu shown when no game is on the table. info: {running (bool), running_text, autosave (name or ""),
## autosave_text, quick_text, has_saves}
func show_lobby(info: Dictionary) -> void:
	if not _begin():
		return
	_title.text = "Unciv VR"
	if info.get("busy", false):
		_info.text = str(info.get("quick_text", ""))
		_end()
		return
	_info.text = "Pick up where you left off, or start a new game."
	if info.get("running", false):
		_list.add_child(_make_button("Resume  -  " + str(info.get("running_text", "")), func() -> void: chosen.emit("lobby_resume", ""),
			Color(0.2, 0.42, 0.25)))
	elif str(info.get("autosave", "")) != "":
		var save_name: String = info["autosave"]
		_list.add_child(_make_button("Continue  -  " + str(info.get("autosave_text", "")), func() -> void: chosen.emit("lobby_continue", save_name),
			Color(0.2, 0.42, 0.25)))
	_list.add_child(_make_button("Quick start", func() -> void: chosen.emit("lobby_quick", ""), Color(0.55, 0.35, 0.1)))
	_add_note(str(info.get("quick_text", "")))
	_list.add_child(_make_button("New game...", func() -> void: chosen.emit("lobby_new", ""), Color(0.2, 0.3, 0.5)))
	if info.get("has_saves", false):
		_list.add_child(_make_button("Load game...", func() -> void: chosen.emit("lobby_load", ""), Color(0.22, 0.25, 0.32)))
	_list.add_child(_make_button("Settings", func() -> void: chosen.emit("settings_card", ""), Color(0.25, 0.25, 0.3)))
	_list.add_child(_make_button("Civilopedia", func() -> void: chosen.emit("civilopedia_card", ""), Color(0.22, 0.32, 0.28)))
	_list.add_child(_make_button("Quit", func() -> void: chosen.emit("quit", ""), Color(0.35, 0.18, 0.18)))
	_end()


## The new-game setup, in three tabs. setup: the getSetup fields being edited; options: the listOptions result.
func show_setup(setup: Dictionary, options: Dictionary, tab: String) -> void:
	if not _begin():
		return
	_title.text = "New game"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for t: Array in [["you", "You"], ["world", "World"], ["rules", "Rules"]]:
		var id: String = t[0]
		var button := _make_button(t[1], func() -> void: chosen.emit("setup_tab", id),
			Color(0.2, 0.4, 0.6) if id == tab else Color(0.2, 0.22, 0.28))
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tabs.add_child(button)
	_list.add_child(tabs)

	var civ: String = str(setup.get("civ", "Random"))
	_info.text = "%s  -  %s %s map, %s, %d AI, %d city-states" % [civ, setup.get("mapSize", "?"), setup.get("mapType", ""),
		setup.get("difficulty", "?"), int(setup.get("aiPlayers", 0)), int(setup.get("cityStates", 0))]

	match tab:
		"you":
			var nations: Array = options.get("nations", [])
			var picked: Dictionary = {}
			for n: Dictionary in nations:
				if n["name"] == civ:
					picked = n
			if not picked.is_empty():
				_add_header("%s, led by %s" % [picked["name"], picked.get("leader", "?")])
				_add_note("%s: %s" % [picked.get("uniqueName", ""), picked.get("uniqueText", "")])
			else:
				_add_note("Random: you'll find out who you are when the game starts.")
			_add_header("Your civilization")
			_list.add_child(_make_button(("> " if civ == "Random" else "") + "Random", func() -> void: chosen.emit("setup_set", "civ|Random"),
				Color(0.2, 0.4, 0.6) if civ == "Random" else Color(0.2, 0.22, 0.28)))
			for n: Dictionary in nations:
				var nation_name: String = n["name"]
				var color := Color.html(str(n.get("innerColor", "333333ff"))).darkened(0.35)
				if nation_name == civ:
					color = Color(0.2, 0.4, 0.6)
				var nation_button := _make_button(("> " if nation_name == civ else "") + "%s  (%s)" % [nation_name, n.get("leader", "")],
					func() -> void: chosen.emit("setup_set", "civ|" + nation_name), color)
				nation_button.icon = Icons.civ_badge(n)   # Unciv's nation symbol, in its colours
				nation_button.add_theme_constant_override("icon_max_width", 30)
				_list.add_child(nation_button)
		"world":
			_add_choices("Map size", "mapSize", options.get("mapSizes", []), setup)
			_add_choices("Map type", "mapType", options.get("mapTypes", []), setup)
			_add_choices("Shape", "mapShape", options.get("mapShapes", []), setup)
			_add_choices("Resources", "mapResources", options.get("mapResources", []), setup)
			_add_header("Options")
			_add_toggle("No ancient ruins", "noRuins", setup)
			_add_toggle("No natural wonders", "noNaturalWonders", setup)
			_add_note("Bigger maps slide under the table: hold a grip and drag, or use the overview at the far edge.")
		"rules":
			_add_choices("Rules", "ruleset", options.get("rulesets", []), setup)
			_add_note("Gods & Kings adds religion, espionage, more civilizations and more units and buildings.")
			_add_choices("Difficulty", "difficulty", options.get("difficulties", []), setup)
			_add_choices("Game speed", "speed", options.get("speeds", []), setup)
			_add_choices("Starting era", "startingEra", options.get("eras", []), setup)
			_add_stepper("AI players", "aiPlayers", setup)
			_add_stepper("City-states", "cityStates", setup)
			_add_header("Victory types (none picked = all)")
			var victories: Array = setup.get("victoryTypes", [])
			for v: String in options.get("victoryTypes", []):
				var on := victories.is_empty() or v in victories
				_list.add_child(_make_button(("[x] " if on else "[  ] ") + v, func() -> void: chosen.emit("setup_toggle", "victory|" + v),
					Color(0.2, 0.36, 0.3) if on else Color(0.2, 0.22, 0.28)))
			_add_header("Options")
			_add_toggle("No barbarians", "noBarbarians", setup)
			_add_toggle("Raging barbarians", "ragingBarbarians", setup)
			_add_toggle("One-city challenge", "oneCityChallenge", setup)
			_add_toggle("No city razing", "noCityRazing", setup)
			_add_toggle("Nuclear weapons", "nuclearWeapons", setup)
			_add_toggle("Espionage", "espionage", setup)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.add_child(_make_button("< Back", func() -> void: chosen.emit("lobby", ""), Color(0.25, 0.25, 0.3)))
	var start := _make_button("Start game", func() -> void: chosen.emit("setup_start", ""), Color(0.55, 0.35, 0.1))
	start.alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions.add_child(start)
	_list.add_child(HSeparator.new())
	_list.add_child(actions)
	_end()


## listSaves: one button per save, newest first.
func show_saves(saves: Array) -> void:
	if not _begin():
		return
	_title.text = "Load game"
	_info.text = "Saves in your Unciv VR folder, newest first."
	_list.add_child(_make_button("< Back", func() -> void: chosen.emit("lobby", ""), Color(0.25, 0.25, 0.3)))
	for save: Dictionary in saves:
		var save_name: String = save["name"]
		var when := local_time_text(float(save.get("modified", 0)))
		_list.add_child(_make_button("%s   (%s)" % [save_name, when], func() -> void: chosen.emit("load_save", save_name),
			Color(0.2, 0.36, 0.3) if save.get("autosave", false) else Color(0.2, 0.22, 0.28)))
	_end()


## "2026-10-08 15:13" in this PC's time zone, from milliseconds since 1970 (UTC).
static func local_time_text(ms: float) -> String:
	var seconds := int(ms / 1000.0) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_string_from_unix_time(seconds, true).left(16)


## A row of small buttons, one per value, with the current one highlighted.
func _add_choices(title: String, key: String, values: Array, setup: Dictionary) -> void:
	_add_header(title)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for value: String in values:
		var selected: bool = str(setup.get(key, "")) == value
		var button := _make_button(value, func() -> void: chosen.emit("setup_set", "%s|%s" % [key, value]),
			Color(0.2, 0.4, 0.6) if selected else Color(0.2, 0.22, 0.28))
		button.size_flags_horizontal = Control.SIZE_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.clip_text = false
		flow.add_child(button)
	_list.add_child(flow)


func _add_toggle(title: String, key: String, setup: Dictionary) -> void:
	var on: bool = setup.get(key, false)
	_list.add_child(_make_button(("[x] " if on else "[  ] ") + title, func() -> void: chosen.emit("setup_toggle", key),
		Color(0.2, 0.36, 0.3) if on else Color(0.2, 0.22, 0.28)))


func _add_stepper(title: String, key: String, setup: Dictionary) -> void:
	_list.add_child(_make_row("%s: %d" % [title, int(setup.get(key, 0))], Color(0.2, 0.22, 0.28), [
		["-", func() -> void: chosen.emit("setup_step", key + "|-1"), Color(0.3, 0.25, 0.25)],
		["+", func() -> void: chosen.emit("setup_step", key + "|1"), Color(0.25, 0.3, 0.25)]]))


func _add_note(text: String) -> void:
	if text == "":
		return
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_list.add_child(note)


# region helpers --------------------------------------------------------------------------

func _begin() -> bool:
	if _list == null:
		return false
	for child in _list.get_children():
		child.queue_free()
	_title.remove_theme_color_override("font_color")
	_restore_scroll = _scroll.scroll_vertical if keep_scroll_once else 0
	keep_scroll_once = false
	_scroll.scroll_vertical = 0
	_recenter_row.visible = show_recenter
	_footer.visible = not compact and not lobby_mode
	return true


func _end() -> void:
	# Cards are only as tall as their contents (up to a cap, then they scroll), so they hide less of the map
	await get_tree().process_frame   # let removed buttons leave and new ones size themselves
	var wanted := _list.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0, minf(wanted, LIST_HEIGHT + (60 if compact else 0)))
	reset_size()
	if _restore_scroll > 0:
		await get_tree().process_frame   # the scroll range only updates once the new contents are laid out
		_scroll.scroll_vertical = _restore_scroll
	layout_changed.emit()


func _add_header(text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	_list.add_child(header)


func _add_close() -> void:
	_list.add_child(_make_button("Close", func() -> void: chosen.emit("close", ""), Color(0.25, 0.25, 0.25)))


## A wide main button plus small extra buttons: extras = [[text, callable, color], ...]
func _make_row(text: String, color: Color, extras: Array, on_press := Callable()) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var main := _make_button(text, on_press if on_press.is_valid() else func() -> void: pass, color)
	row.add_child(main)
	for extra: Array in extras:
		var small := _make_button(extra[0], extra[1], extra[2])
		small.size_flags_horizontal = Control.SIZE_SHRINK_END
		small.custom_minimum_size = Vector2(52, 36)
		small.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(small)
	return row


func _make_button(text: String, on_press: Callable, color := Color(0.2, 0.22, 0.28)) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	button.custom_minimum_size = Vector2(0, 36)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.15) if state == "hover" else (color.darkened(0.2) if state == "pressed" else color)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(on_press)
	return button
