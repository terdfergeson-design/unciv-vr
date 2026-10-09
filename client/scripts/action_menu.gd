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
##   promotion card: "promote" (promotion name); unit card: "promotion_card" opens it
##   settings card: "background" (studio/mountains/space), "auto_move" (end/start); footer "settings_card" opens it
##   footer:        "prev_unit", "next_unit", "next_idle", "research_card", "end_turn", "recenter", "close"
##   lobby card:    "lobby_resume", "lobby_continue" (save name), "lobby_quick", "lobby_new", "lobby_load", "settings_card", "quit"
##   setup card:    "setup_tab" (you/world/rules), "setup_set" ("key|value"), "setup_toggle" (key),
##                  "setup_step" ("key|+1"), "setup_start", "lobby" (back to the lobby card)
##   saves card:    "load_save" (name), "lobby"
##   settings card also: "save_game", "main_menu", "reset_boards"
signal chosen(kind: String, value: String)
## Emitted after the card's contents change, so whoever places it can re-fit it.
signal layout_changed

const WIDTH := 380
const Icons := preload("res://scripts/icons.gd")
const LIST_HEIGHT := 360

var show_recenter := false   # VR only
var in_vr := false
var compact := false         # no unit/turn footer (the floating city card); set before adding to the tree
var lobby_mode := false      # no game on the table yet: hide the unit/turn footer
var keep_scroll_once := false   # the next card rebuild keeps the scroll position (e.g. after pressing + or -)
var _restore_scroll := 0

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
	turn_row.add_child(_make_button("End turn", func() -> void: chosen.emit("end_turn", ""), Color(0.55, 0.35, 0.1)))
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
	if unit.is_empty():
		_title.text = "No unit selected"
		_info.text = "Point at a unit or city to select it."
		_end()
		return

	_title.text = str(unit.get("name", "?"))
	if compact:
		_add_close()
	var lines: Array[String] = []
	lines.append("Moves %s/%d   Health %d" % [str(snappedf(float(unit.get("movement", 0)), 0.1)),
		int(unit.get("maxMovement", 0)), int(unit.get("health", 100))])
	if int(unit.get("strength", 0)) > 0:
		var strength := "Strength %d" % int(unit["strength"])
		if int(unit.get("rangedStrength", 0)) > 0:
			strength += "   Ranged %d (range %d)" % [int(unit["rangedStrength"]), int(unit.get("range", 1))]
		lines.append(strength)
	if int(unit.get("xpForNextPromotion", 0)) > 0 and int(unit.get("strength", 0)) > 0:
		lines.append("XP %d/%d%s" % [int(unit.get("xp", 0)), int(unit["xpForNextPromotion"]),
			("   Promotions: " + ", ".join(unit.get("promotions", []))) if not unit.get("promotions", []).is_empty() else ""])
	var work: Dictionary = unit.get("tileWork", {})
	if work.get("inProgress") != null:
		lines.append("Building %s: %d turns left" % [work["inProgress"], int(work.get("turnsLeft", 0))])
	var targets: Array = unit.get("targets", [])
	if not targets.is_empty():
		lines.append("%d target(s) in reach - shown in red" % targets.size())
	_info.text = "\n".join(lines)

	if unit.get("canPromote", false):
		_list.add_child(_make_button("Promote!  (choose a promotion)", func() -> void: chosen.emit("promotion_card", ""),
			Color(0.55, 0.42, 0.08)))
	for action: Dictionary in unit.get("actions", []):
		if not action.get("enabled", false) or action["type"] == "Promote":
			continue   # Unciv's own Promote action opens its promotion screen; we use the card above instead
		var type: String = action["type"]
		var title: String = str(action.get("title", type)).replace("{", "").replace("}", "")   # Unciv templates like "{Found city}"
		if action.get("current", false):
			title += "  (active)"
		_list.add_child(_make_button(title, func() -> void: chosen.emit("action", type)))

	var improvements: Array = unit.get("improvements", [])
	if not improvements.is_empty():
		_add_header("Build here:")
		for imp: Dictionary in improvements:
			var imp_name: String = imp["name"]
			var turns := int(imp.get("turns", 0))
			var label := imp_name if turns <= 0 else "%s  (%d turns)" % [imp_name, turns]
			_list.add_child(_make_button(label, func() -> void: chosen.emit("improvement", imp_name), Color(0.2, 0.35, 0.2)))
	_end()


## A getCity result: growth, yields, the queue, and everything it can build.
func show_city(city: Dictionary, gold: int) -> void:
	if not _begin():
		return
	_title.text = "%s  (%d)" % [city.get("name", "?"), int(city.get("population", 0))]
	var y: Dictionary = city.get("yields", {})
	var lines: Array[String] = []
	lines.append("Food %+d  Prod %d  Gold %+d  Sci %d  Cult %d" % [int(y.get("food", 0)), int(y.get("production", 0)),
		int(y.get("gold", 0)), int(y.get("science", 0)), int(y.get("culture", 0))])
	var growth := int(city.get("turnsToGrowth", -1)) if city.get("turnsToGrowth") != null else -1
	if growth >= 0:
		lines.append("Grows in %d turns (%d/%d food)" % [growth, int(city.get("foodStored", 0)), int(city.get("foodToGrow", 0))])
	elif city.get("turnsToStarvation") != null:
		lines.append("STARVING - shrinks in %d turns" % int(city["turnsToStarvation"]))
	else:
		lines.append("Not growing")
	lines.append("Health %d/%d   Your gold: %d" % [int(city.get("health", 0)), int(city.get("maxHealth", 0)), gold])
	_info.text = "\n".join(lines)

	if compact:
		_add_close()
	var queue: Array = city.get("queue", [])
	_add_header("Producing:" if not queue.is_empty() else "Producing nothing - pick something below")
	for entry: Dictionary in queue:
		var index := int(entry["index"])
		var turns := int(entry.get("turns", -1))
		var text := "%d. %s" % [index + 1, entry["name"]] + ("  (%d turns)" % turns if turns >= 0 else "")
		_list.add_child(_make_row(text, Color(0.3, 0.27, 0.15), [
			["X", func() -> void: chosen.emit("unqueue", str(index)), Color(0.4, 0.15, 0.15)]]))

	var options: Array = city.get("options", []).filter(func(o: Dictionary) -> bool: return o.get("buildable", false))
	for kind_and_header: Array in [["unit", "Units"], ["building", "Buildings"], ["wonder", "Wonders"], ["perpetual", "Other"]]:
		var of_kind := options.filter(func(o: Dictionary) -> bool: return o["kind"] == kind_and_header[0])
		if of_kind.is_empty():
			continue
		_add_header(kind_and_header[1])
		for option: Dictionary in of_kind:
			var option_name: String = option["name"]
			var turns := int(option.get("turns", -1))
			var text := option_name + ("  %dt" % turns if turns >= 0 else "")
			var extras: Array = [["+Q", func() -> void: chosen.emit("queue", option_name), Color(0.22, 0.25, 0.32)]]
			if option.get("canBuy", false):
				extras.append(["%dg" % int(option["goldCost"]), func() -> void: chosen.emit("buy", option_name), Color(0.5, 0.42, 0.1)])
			_list.add_child(_make_row(text, Color(0.2, 0.22, 0.28), extras, func() -> void: chosen.emit("produce", option_name)))
	if not compact:
		_add_close()
	_end()


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


## The settings card. [param settings] is main.gd's settings dictionary; the current choices are highlighted.
func show_settings(settings: Dictionary) -> void:
	if not _begin():
		return
	_title.text = "Settings"
	_info.text = "Saved on this PC between sessions."
	if compact:
		_add_close()
	_add_header("Background")
	for option: Array in [["studio", "Studio"], ["mountains", "Mountains and clouds"], ["space", "Floating in space"]]:
		var value: String = option[0]
		var selected: bool = settings.get("background", "") == value
		_list.add_child(_make_button(("> " if selected else "") + option[1],
			func() -> void: chosen.emit("background", value), Color(0.2, 0.4, 0.6) if selected else Color(0.2, 0.22, 0.28)))
	if not lobby_mode:
		_add_header("Game")
		_list.add_child(_make_button("Save game", func() -> void: chosen.emit("save_game", ""), Color(0.2, 0.32, 0.25)))
		_list.add_child(_make_button("Main menu (the game keeps running)", func() -> void: chosen.emit("main_menu", ""), Color(0.25, 0.25, 0.3)))
	if in_vr:   # VR only: the boards at the far edge of the table can be dragged around
		_add_header("Overview and info board")
		_list.add_child(_make_button("Put them back where they started", func() -> void: chosen.emit("reset_boards", ""), Color(0.25, 0.25, 0.3)))
	_add_header("Automated and exploring units move")
	for option: Array in [["end", "When I end my turn"], ["start", "At the start of my turn"]]:
		var value: String = option[0]
		var selected: bool = settings.get("auto_move", "") == value
		_list.add_child(_make_button(("> " if selected else "") + option[1],
			func() -> void: chosen.emit("auto_move", value), Color(0.2, 0.4, 0.6) if selected else Color(0.2, 0.22, 0.28)))
	if not compact:
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
