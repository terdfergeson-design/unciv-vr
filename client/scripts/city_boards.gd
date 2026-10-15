# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## One of the two boards of the city view, which together do everything Unciv's city screen does.
##   mode "info":       the city's numbers, citizens (focus, avoid growth, reset), specialists, great people,
##                      religion, buildings, the selected tile (lock / unlock / buy), raze / annex
##   mode "production": what's being built, the queue (move up / down / remove, buy), everything the city could
##                      build, and the selected construction's details (build now, add to queue, buy, sell)
## Laser / mouse clickable; the strip along the top is the handle for moving it.
##
## Emits chosen(kind, value) - see main.gd _on_city_board_chosen for the list.
signal chosen(kind: String, value: String)

const Lang := preload("res://scripts/lang.gd")

const Icons := preload("res://scripts/icons.gd")

const SIZE := Vector2(720, 1030)
const GRAB_HEIGHT := 30.0

const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.66, 0.7, 0.78)
const GOOD := Color(0.45, 0.85, 0.4)
const BAD := Color(1.0, 0.42, 0.32)
const HEADER := Color(0.98, 0.85, 0.45)
const BUTTON := Color(0.2, 0.22, 0.3)
const SELECTED := Color(0.22, 0.42, 0.66)
## Unciv-like colours for each stat
const STAT_COLORS := {
	"food": Color(0.45, 0.85, 0.35), "production": Color(0.95, 0.55, 0.25), "gold": Color(0.98, 0.8, 0.25),
	"science": Color(0.4, 0.72, 1.0), "culture": Color(0.8, 0.5, 0.98), "happiness": Color(0.5, 0.9, 0.35),
	"faith": Color(0.75, 0.88, 1.0),
}
const STAT_ORDER := ["food", "production", "gold", "science", "culture", "happiness", "faith"]

var mode := "info"
var city: Dictionary = {}
var gold := 0
var faith := 0
var selected_construction := ""     # production board: shown in the details strip at the bottom
var selected_queue_index := -1      # ... when it was picked from the queue (buying it finishes that entry)
var construction_description := ""  # describeConstruction text for selected_construction
var selected_tile := Vector2i(999999, 999999)   # info board: the tile shown at the bottom
var tile_info: Dictionary = {}      # the getState tile under selected_tile (terrain, resource...)
var show_unavailable := false       # production board: also list what can't be built yet (and why)
var armed := ""                     # a buy / sell / raze button clicked once; the next click confirms

var _title: Label
var _rename_button: Button
var _subtitle: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _footer: VBoxContainer


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.96)
	style.border_color = Color(0.55, 0.48, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	var grab := Label.new()
	grab.text = "=====   hold the trigger here and drag to move   ====="
	grab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grab.custom_minimum_size = Vector2(0, GRAB_HEIGHT)
	grab.add_theme_font_size_override("font_size", 14)
	grab.add_theme_color_override("font_color", DIM)
	box.add_child(grab)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", HEADER)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	box.add_child(head)
	if mode == "info":
		_rename_button = _button("Rename", func() -> void: chosen.emit("city_rename", ""), BUTTON, 18)
		_rename_button.custom_minimum_size = Vector2(142, 44)
		head.add_child(_rename_button)
		for b: Array in [["<", "city_prev"], [">", "city_next"]]:
			var kind: String = b[1]
			var button := _button(b[0], func() -> void: chosen.emit(kind, ""), BUTTON, 22)
			button.custom_minimum_size = Vector2(48, 44)
			head.add_child(button)
	var exit := _button("Exit city", func() -> void: chosen.emit("city_exit", ""), Color(0.45, 0.25, 0.18), 20)
	exit.custom_minimum_size = Vector2(186, 44)
	head.add_child(exit)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 17)
	_subtitle.add_theme_color_override("font_color", DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_subtitle)

	_scroll = ScrollContainer.new()
	Icons.thick_scrollbars(_scroll)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	box.add_child(HSeparator.new())
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 4)
	box.add_child(_footer)


## True when [param pixel] (in this board's own pixels) is on the move handle along the top.
func grab_bar_contains(pixel: Vector2) -> bool:
	return pixel.y >= position.y and pixel.y < position.y + GRAB_HEIGHT


func scroll_by(amount: float) -> void:
	_scroll.scroll_vertical += int(amount)


## Shows a getCity result. [param keep_scroll]: stay where the list was scrolled to.
func show_city(data: Dictionary, gold_now: int, faith_now: int, keep_scroll := true) -> void:
	var scroll := _scroll.scroll_vertical
	if data.get("name") != city.get("name"):
		scroll = 0
		armed = ""
		selected_construction = ""
		selected_queue_index = -1
		construction_description = ""
		selected_tile = Vector2i(999999, 999999)
	city = data
	gold = gold_now
	faith = faith_now
	_rebuild()
	if keep_scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = scroll


func select_construction(construction: String, queue_index: int, description: String) -> void:
	selected_construction = construction
	selected_queue_index = queue_index
	construction_description = description
	armed = ""
	_rebuild_footer()


func select_tile(key: Vector2i, getstate_tile: Dictionary) -> void:
	selected_tile = key
	tile_info = getstate_tile
	armed = ""
	_rebuild_footer()


func arm(what: String) -> void:
	armed = what
	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	if city.is_empty():
		_title.text = "City"
		return
	if mode == "info":
		_build_info()
	else:
		_build_production()
	_rebuild_footer()


func _rebuild_footer() -> void:
	for child in _footer.get_children():
		child.queue_free()
	if city.is_empty():
		return
	if mode == "info":
		_build_tile_footer()
	else:
		_build_construction_footer()


# region info board --------------------------------------------------------------------------

func _build_info() -> void:
	var pop := int(city.get("population", 0))
	_title.text = Lang.format("%s%s  (%d)", ["* " if city.get("isCapital", false) else "", city.get("name", "?"), pop])
	var bits: Array[String] = []
	bits.append(Lang.format("Health %d/%d", [int(city.get("health", 0)), int(city.get("maxHealth", 0))]))
	bits.append(Lang.format("Defence %d", int(city.get("defense", 0))))
	if city.get("isPuppet", false):
		bits.append("Puppet")
	if city.get("isBeingRazed", false):
		bits.append("BEING RAZED")
	_subtitle.text = Lang.join("   ", bits)
	var can_change: bool = city.get("canChange", true)
	_rename_button.disabled = not can_change or city.get("isPuppet", false)

	# Stat row: like Unciv's, each stat symbol also sets (or clears) that focus
	var stats_row := HFlowContainer.new()
	stats_row.add_theme_constant_override("h_separation", 6)
	stats_row.add_theme_constant_override("v_separation", 4)
	var stats: Dictionary = city.get("stats", city.get("yields", {}))
	var focus: String = city.get("focus", "NoFocus")
	for stat: String in STAT_ORDER:
		if stat == "faith" and not city.get("religionEnabled", true):
			continue
		var focus_name := _focus_for_stat(stat)
		var is_focus := focus_name != "" and focus_name == focus
		var value := roundi(float(stats.get(stat, 0.0)))
		var button := _stat_button(stat, ("%+d" % value) if stat in ["food", "gold", "happiness"] else str(value), is_focus)
		if can_change and focus_name != "":
			var target := "NoFocus" if is_focus else focus_name
			button.pressed.connect(func() -> void: chosen.emit("city_focus", target))
		stats_row.add_child(button)
	_list.add_child(stats_row)

	# Growth, borders and the rest of Unciv's lines under the stats
	var free_pop := int(city.get("freePopulation", 0))
	var unassigned := _button(Lang.format("Unassigned citizens: %d/%d%s", [free_pop, pop, "   (click: let the city place them)" if free_pop > 0 else ""]),
		func() -> void: chosen.emit("city_reassign", ""), Color(0.25, 0.3, 0.22) if free_pop > 0 else BUTTON, 18)
	unassigned.disabled = not can_change
	_list.add_child(unassigned)
	var food_text := Lang.format("(%d/%d food)", [int(city.get("foodStored", 0)), int(city.get("foodToGrow", 0))])
	match str(city.get("growthStatus", "")):
		"starving":
			_line(Lang.format("Starving: loses a citizen in %d turns %s", [int(city.get("turnsToStarvation", 0)), food_text]), BAD)
		"foodToProduction":
			_line("Food goes into production while this unit is built", STAT_COLORS["production"])
		"growing":
			_line(Lang.format("New citizen in %d turns %s", [int(city.get("turnsToGrowth", 0)), food_text]), STAT_COLORS["food"])
		_:
			_line(Lang.format("Not growing %s", food_text), DIM)
	var expansion: Dictionary = city.get("expansion", {})
	if not expansion.is_empty():
		var culture := Lang.format("(%d/%d culture)", [int(expansion.get("cultureStored", 0)), int(expansion.get("cultureToNextTile", 0))])
		if int(expansion.get("turns", -1)) > 0:
			_line(Lang.format("Borders grow in %d turns %s", [int(expansion["turns"]), culture]), STAT_COLORS["culture"])
		else:
			_line(Lang.t("Borders have stopped growing") + (" " + culture if expansion.get("canExpand", false) else ""), DIM)
	if city.has("resistanceTurns"):
		_line(Lang.format("In resistance for another %d turns", int(city["resistanceTurns"])), BAD)
	if city.has("wltkTurns"):
		_line(Lang.format("We Love The King Day for another %d turns", int(city["wltkTurns"])), GOOD)
	elif city.has("demandedResource"):
		_line_icon(Lang.format("Demanding %s (We Love The King Day if you get it)", city["demandedResource"]), Color(1.0, 0.6, 0.45),
			Icons.badge("resource", str(city["demandedResource"]), Color(0.3, 0.3, 0.38)))
	var resources: Array = city.get("resources", [])
	if not resources.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		for r: Dictionary in resources:
			flow.add_child(_icon_text(Icons.badge("resource", str(r["name"]), Color(0.3, 0.3, 0.38)), Lang.format("%s %d", [r["name"], int(r["amount"])]), TEXT, false))
		_list.add_child(flow)
	if city.get("canAnnex", false):
		_list.add_child(_button("Annex city (stop it being a puppet)", func() -> void: chosen.emit("city_annex", ""), Color(0.25, 0.4, 0.25), 18))
	elif city.get("isBeingRazed", false):
		_list.add_child(_button("Stop razing city", func() -> void: chosen.emit("city_raze", "false"), Color(0.25, 0.4, 0.25), 18))
	elif city.get("canRaze", false):
		if armed == "raze":
			_list.add_child(_button(Lang.format("Click again to RAZE %s (it burns down a citizen a turn)", city.get("name", "")),
				func() -> void: chosen.emit("city_raze", "true"), Color(0.7, 0.15, 0.12), 17))
		else:
			_list.add_child(_button("Raze city", func() -> void: chosen.emit("city_arm", "raze"), Color(0.42, 0.16, 0.14), 18))

	_build_citizens(can_change, focus)
	_build_specialists(can_change)
	_build_great_people()
	_build_religion()
	_build_buildings()


func _focus_for_stat(stat: String) -> String:
	for option: Dictionary in city.get("focusOptions", []):
		var option_stats: Array = option.get("stats", [])
		if option_stats.size() == 1 and option_stats[0] == stat:
			return str(option["name"])
	return ""


func _build_citizens(can_change: bool, focus: String) -> void:
	_header("Citizen management")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var reset := _button("Reset citizens", func() -> void: chosen.emit("city_reset", ""), BUTTON, 17)
	reset.disabled = not can_change
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reset)
	var avoid: bool = city.get("avoidGrowth", false)
	var avoid_button := _button(("[x] " if avoid else "[  ] ") + Lang.t("Avoid growth"), func() -> void: chosen.emit("city_avoid_growth", "false" if avoid else "true"),
		SELECTED if avoid else BUTTON, 17)
	avoid_button.disabled = not can_change
	avoid_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(avoid_button)
	_list.add_child(row)
	_small("Citizen focus (which tiles the city prefers to work):")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	for option: Dictionary in city.get("focusOptions", []):
		var name: String = option["name"]
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 42)
		_restyle(button, SELECTED if name == focus else BUTTON)
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 8
		inner.offset_right = -8
		inner.offset_top = 5
		inner.offset_bottom = -5
		var label_text: String = option.get("label", "")
		if label_text != "":
			var label := _plain_label(label_text, 17, TEXT)
			inner.add_child(label)
		for stat: String in option.get("stats", []):
			inner.add_child(_icon_rect(Icons.get_icon("stat", stat.capitalize()), 30))
		button.add_child(inner)
		# Use the shaped, translated text instead of an English character-count estimate.
		inner.minimum_size_changed.connect(func() -> void:
			button.custom_minimum_size = inner.get_combined_minimum_size() + Vector2(16, 10))
		button.custom_minimum_size = inner.get_combined_minimum_size() + Vector2(16, 10)
		button.disabled = not can_change
		button.pressed.connect(func() -> void: chosen.emit("city_focus", name))
		flow.add_child(button)
	_list.add_child(flow)


func _build_specialists(can_change: bool) -> void:
	var specialists: Array = city.get("specialists", [])
	if specialists.is_empty():
		return
	_header("Specialists")
	var manual: bool = city.get("manualSpecialists", false)
	var toggle := _button("Manual specialists (click for automatic)" if manual else "Automatic specialists (click for manual)",
		func() -> void: chosen.emit("city_manual_specialists", "false" if manual else "true"), SELECTED if manual else BUTTON, 16)
	toggle.disabled = not can_change
	_list.add_child(toggle)
	var free_pop := int(city.get("freePopulation", 0))
	for s: Dictionary in specialists:
		var name: String = s["name"]
		var assigned := int(s.get("assigned", 0))
		var most := int(s.get("max", 0))
		var colour := _rgb(s.get("color", []), Color(0.8, 0.8, 0.8))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var minus := _button("-", func() -> void: chosen.emit("city_specialist", name + "|-1"), Color(0.5, 0.18, 0.15), 22)
		minus.custom_minimum_size = Vector2(42, 40)
		minus.disabled = not can_change or assigned <= 0
		row.add_child(minus)
		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 2)
		for i in most:
			slots.add_child(_icon_rect(Icons.get_icon("stat", "Specialist"), 26, colour if i < assigned else Color(0.4, 0.4, 0.42)))
		row.add_child(slots)
		var plus := _button("+", func() -> void: chosen.emit("city_specialist", name + "|1"), Color(0.2, 0.45, 0.2), 22)
		plus.custom_minimum_size = Vector2(42, 40)
		plus.disabled = not can_change or assigned >= most or free_pop <= 0
		row.add_child(plus)
		var label := _plain_label(Lang.format("%s %d/%d", [name, assigned, most]), 17, colour.lightened(0.2))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_stat_icons(s.get("stats", {}), 22))
		_list.add_child(row)


func _build_great_people() -> void:
	var people: Array = city.get("greatPeople", [])
	if people.is_empty():
		return
	_header("Great people")
	for p: Dictionary in people:
		var needed := maxi(1, int(p.get("needed", 1)))
		var current := int(p.get("current", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_icon_rect(Icons.badge("unit", str(p["name"]), Color(0.45, 0.35, 0.1)), 34))
		var label := _plain_label(Lang.format("%s (+%d)", [p["name"], int(p.get("perTurn", 0))]), 17, HEADER)
		label.custom_minimum_size = Vector2(250, 0)
		row.add_child(label)
		var bar := _progress_bar(float(current) / needed, Color(0.95, 0.6, 0.15), "%d/%d" % [current, needed])
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		_list.add_child(row)


func _build_religion() -> void:
	var religion: Dictionary = city.get("religion", {})
	if religion.is_empty() or (religion.get("followers", []).is_empty() and not religion.has("holyCityOf")):
		return
	_header("Religion")
	if religion.has("majority"):
		_line(Lang.format("Majority religion: %s", religion["majority"]), TEXT)
	if religion.has("holyCityOf"):
		_line(("Former holy city of %s" if religion.get("holyCityBlocked", false) else "Holy city of %s") % religion["holyCityOf"], HEADER)
	for f: Dictionary in religion.get("followers", []):
		_line(Lang.format("%s: %d followers, pressure %+d", [f["name"], int(f.get("followers", 0)), int(f.get("pressure", 0))]), DIM)


func _build_buildings() -> void:
	var details: Array = city.get("buildingDetails", [])
	if details.is_empty():
		return
	for group: Array in [["specialist", "Specialist buildings"], ["wonder", "Wonders"], ["other", "Buildings"]]:
		var of_kind := details.filter(func(b: Dictionary) -> bool: return b.get("kind", "other") == group[0])
		if of_kind.is_empty():
			continue
		_header(group[1])
		for b: Dictionary in of_kind:
			var name: String = b["name"]
			var row := _row_button(func() -> void: chosen.emit("city_select", name), SELECTED if selected_construction == name else Color(0.13, 0.15, 0.2))
			var inner: HBoxContainer = row.get_child(0)
			inner.add_child(_icon_rect(Icons.construction(name), 34))
			var label := _plain_label(name + ("  (free)" if b.get("free", false) else ""), 17, TEXT)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			inner.add_child(label)
			for slot: Dictionary in b.get("specialistSlots", []):
				inner.add_child(_icon_rect(Icons.get_icon("stat", "Specialist"), 20,
					_specialist_color(str(slot["name"])) if slot.get("filled", false) else Color(0.4, 0.4, 0.42)))
			inner.add_child(_stat_icons(b.get("stats", {}), 20))
			_list.add_child(row)


func _specialist_color(name: String) -> Color:
	for s: Dictionary in city.get("specialists", []):
		if s["name"] == name:
			return _rgb(s.get("color", []), Color.WHITE)
	return Color.WHITE


## The bottom of the info board: the tile you last clicked on the table.
func _build_tile_footer() -> void:
	var tile := _city_tile(selected_tile)
	if tile.is_empty():
		_footer_line(Lang.t("Click a tile on the table: worked tiles stop being worked, free citizens go to unworked ones, ") +
			Lang.t("and tiles with a price can be bought (click twice)."), DIM)
		return
	var names: Array[String] = []
	if tile_info.has("base"):
		names.append(str(tile_info["base"]))
		for f: String in tile_info.get("features", []):
			names.append(f)
	var title := Lang.join(", ", names) if not names.is_empty() else "Tile"
	var state := str(tile.get("state", ""))
	var state_text: String = {"center": "city centre", "worked": "worked", "locked": "worked (locked)", "notWorked": "not worked",
		"providesYield": "gives its yield without a citizen", "noYield": "gives nothing", "blockaded": "blockaded by an enemy",
		"otherCity": Lang.format("worked by %s", tile.get("workedBy", "another city")), "outOfRange": "too far to work",
		"buyable": "can be bought", "foreign": "not yours"}.get(state, state)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _plain_label(Lang.format("%s - %s", [title, state_text]), 19, TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	row.add_child(_stat_icons(tile.get("yields", {}), 24))
	_footer.add_child(row)
	var extras: Array[String] = []
	if tile_info.has("resource"):
		extras.append(Lang.format("Resource: %s", tile_info["resource"]))
	if tile_info.has("improvement"):
		extras.append(Lang.format("Improvement: %s", tile_info["improvement"]))
	if tile.has("owner"):
		extras.append(Lang.format("Owned by %s", tile["owner"]))
	if not extras.is_empty():
		_footer_line(Lang.join("   ", extras), DIM)
	var key := "%d,%d" % [selected_tile.x, selected_tile.y]
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	var can_change: bool = city.get("canChange", true)
	match state:
		"worked":
			buttons.add_child(_button("Lock (keep a citizen here)", func() -> void: chosen.emit("city_tile", key + "|lock"), BUTTON, 17))
			buttons.add_child(_button("Stop working", func() -> void: chosen.emit("city_tile", key + "|unwork"), BUTTON, 17))
		"locked":
			buttons.add_child(_button("Unlock", func() -> void: chosen.emit("city_tile", key + "|unlock"), BUTTON, 17))
			buttons.add_child(_button("Stop working", func() -> void: chosen.emit("city_tile", key + "|unwork"), BUTTON, 17))
		"notWorked":
			buttons.add_child(_button("Work this tile", func() -> void: chosen.emit("city_tile", key + "|work"), BUTTON, 17))
			buttons.add_child(_button("Work and lock", func() -> void: chosen.emit("city_tile", key + "|lock"), BUTTON, 17))
	if tile.has("buyCost"):
		var cost := int(tile["buyCost"])
		if armed == "tile:" + key:
			buttons.add_child(_button(Lang.format("Click again: buy for %d gold", cost), func() -> void: chosen.emit("city_tile", key + "|buy"), Color(0.6, 0.48, 0.1), 17))
		else:
			var buy := _button(Lang.format("Buy for %d gold (you have %d)", [cost, gold]), func() -> void: chosen.emit("city_arm", "tile:" + key), Color(0.45, 0.38, 0.12), 17)
			buy.disabled = not tile.get("canAfford", false)
			buttons.add_child(buy)
	for child in buttons.get_children():
		(child as Button).disabled = (child as Button).disabled or not can_change
		(child as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# In a wrapping row a button is only as wide as its minimum size, which clipped text would make zero
	for button: Button in buttons.get_children():
		button.clip_text = false
		button.custom_minimum_size = Vector2(minf(SIZE.x - 40, button.get_theme_font("font").get_string_size(Lang.t(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x + 24), 44)
	if buttons.get_child_count() > 0:
		_footer.add_child(buttons)


func _city_tile(key: Vector2i) -> Dictionary:
	for t: Dictionary in city.get("tiles", []):
		if int(t["x"]) == key.x and int(t["y"]) == key.y:
			return t
	return {}


# region production board --------------------------------------------------------------------

func _build_production() -> void:
	_title.text = "Production"
	_subtitle.text = Lang.format("Gold %d   Faith %d   Production %+d a turn", [gold, faith, roundi(float(city.get("stats", city.get("yields", {})).get("production", 0.0)))])
	var can_change: bool = city.get("canChange", true)
	var queue: Array = city.get("queue", [])

	_header("Being built" if not queue.is_empty() else "Nothing being built - pick something below")
	for entry: Dictionary in queue:
		var index := int(entry["index"])
		var name: String = entry["name"]
		var picked := selected_construction == name and selected_queue_index == index
		var row := _row_button(func() -> void: chosen.emit("city_select_queue", str(index)), SELECTED if picked else Color(0.2, 0.18, 0.1))
		var inner: HBoxContainer = row.get_child(0)
		inner.add_child(_icon_rect(Icons.construction(name), 40 if index == 0 else 32))
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var turns := int(entry.get("turns", -1))
		var queue_title := _plain_label(Lang.format("%d. %s%s", [index + 1, name, (Lang.format("   %d turns", turns)) if turns >= 0 else ""]), 18 if index == 0 else 17, TEXT)
		queue_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(queue_title)
		if index == 0 and entry.has("cost"):
			var cost := maxi(1, int(entry["cost"]))
			column.add_child(_progress_bar(float(entry.get("progress", 0)) / cost, STAT_COLORS["production"],
				"%d/%d" % [int(entry.get("progress", 0)), cost]))
		inner.add_child(column)
		if can_change:
			for b: Array in [["^", "up", index > 0], ["v", "down", index < queue.size() - 1], ["X", "remove", true]]:
				var move: String = b[1]
				var small := _button(b[0], func() -> void: chosen.emit("city_move", "%d|%s" % [index, move]),
					Color(0.4, 0.15, 0.15) if move == "remove" else BUTTON, 18)
				small.custom_minimum_size = Vector2(40, 38)
				small.disabled = not b[2]
				inner.add_child(small)
		_list.add_child(row)

	var options: Array = city.get("options", [])
	var buildable := options.filter(func(o: Dictionary) -> bool: return o.get("buildable", false))
	for group: Array in [["unit", "Units"], ["building", "Buildings"], ["wonder", "Wonders"], ["perpetual", "Other"]]:
		var of_kind := (options if show_unavailable else buildable).filter(func(o: Dictionary) -> bool: return o["kind"] == group[0])
		if of_kind.is_empty():
			continue
		_header(group[1])
		for option: Dictionary in of_kind:
			var name: String = option["name"]
			var available: bool = option.get("buildable", false)
			var picked := selected_construction == name and selected_queue_index < 0
			var row := _row_button(func() -> void: chosen.emit("city_select", name),
				SELECTED if picked else (Color(0.13, 0.15, 0.2) if available else Color(0.1, 0.1, 0.12)))
			var inner: HBoxContainer = row.get_child(0)
			inner.add_child(_icon_rect(Icons.construction(name), 32, Color.WHITE if available else Color(0.6, 0.6, 0.6)))
			var turns := int(option.get("turns", -1))
			var text := Lang.t(name) + ((Lang.format("   %d turns", turns)) if turns >= 0 and available else "")
			if not available and not option.get("why", []).is_empty():
				text += "   (" + _plain(str(option["why"][0])) + ")"
			var label := _plain_label(text, 17, TEXT if available else DIM)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			inner.add_child(label)
			for buy: Dictionary in option.get("buy", []):
				if buy.get("allowed", false):
					inner.add_child(_plain_label("%d%s" % [int(buy["cost"]), "g" if buy["stat"] == "gold" else " " + str(buy["stat"])], 15,
						STAT_COLORS.get(buy["stat"], TEXT)))
			_list.add_child(row)
	var toggle := _button("Hide what can't be built yet" if show_unavailable else "Show what can't be built yet (and why)",
		func() -> void: chosen.emit("city_show_unavailable", "false" if show_unavailable else "true"), BUTTON, 16)
	_list.add_child(toggle)


## The bottom of the production board: the picked construction - what it does, and build / queue / buy / sell.
func _build_construction_footer() -> void:
	if selected_construction == "":
		_footer_line("Click something to see what it does, then build it now, add it to the queue, or buy it.", DIM)
		return
	var name := selected_construction
	var option := _option(name)
	var built: Dictionary = {}
	for b: Dictionary in city.get("buildingDetails", []):
		if b["name"] == name:
			built = b
	var queue_entry: Dictionary = {}
	if selected_queue_index >= 0 and selected_queue_index < city.get("queue", []).size():
		queue_entry = city["queue"][selected_queue_index]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(_icon_rect(Icons.construction(name), 56))
	var title_text := Lang.t(name)
	var info: Dictionary = queue_entry if not queue_entry.is_empty() else option
	if info.has("cost"):
		title_text += Lang.format("   %d production", int(info["cost"]))
	if int(info.get("turns", -1)) >= 0:
		title_text += Lang.format(", %d turns", int(info["turns"]))
	if not built.is_empty():
		title_text += Lang.t("   (built)")
	var title := _plain_label(title_text, 21, HEADER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(title)
	_footer.add_child(top)

	var description := RichTextLabel.new()
	description.bbcode_enabled = false
	description.fit_content = false
	description.scroll_active = true
	description.custom_minimum_size = Vector2(0, 150)
	description.add_theme_font_size_override("normal_font_size", 16)
	description.add_theme_color_override("default_color", TEXT)
	description.text = _plain(construction_description) if construction_description != "" else "..."
	_footer.add_child(description)
	if option.get("needsTile", false):
		var place := Lang.format("Its %s goes on a tile you pick on the table after Build now / Add to queue / Buy.", option.get("improvement", "improvement"))
		if queue_entry.has("tile"):
			place = Lang.format("Its %s goes on the ringed tile picked when it was queued.", option.get("improvement", "improvement"))
		_footer.add_child(_plain_label(place, 16, DIM))

	var can_change: bool = city.get("canChange", true)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	if queue_entry.is_empty() and option.get("buildable", false):
		var now := _button("Build now", func() -> void: chosen.emit("city_build_now", name), Color(0.2, 0.42, 0.25), 18)
		# A full queue (Unciv's limit is 10) takes nothing more, not even at the front
		var queue_full := (city.get("queue", []) as Array).size() >= 10
		now.disabled = not can_change or queue_full
		buttons.add_child(now)
		var queue := _button("Add to queue", func() -> void: chosen.emit("city_queue", name), BUTTON, 18)
		queue.disabled = not can_change or not option.get("canQueue", true)
		buttons.add_child(queue)
	for buy: Dictionary in info.get("buy", []):
		var stat: String = buy["stat"]
		var cost := int(buy["cost"])
		var have := gold if stat == "gold" else (faith if stat == "faith" else -1)
		var key := "buy:%s|%s|%d" % [name, stat, selected_queue_index]
		var button: Button
		if armed == key:
			button = _button(Lang.format("Click again: buy for %d %s", [cost, stat]), func() -> void: chosen.emit("city_buy", key.substr(4)), Color(0.6, 0.48, 0.1), 18)
		else:
			var text := Lang.format("Buy for %d %s", [cost, stat]) + (Lang.format(" (you have %d)", have) if have >= 0 else "")
			button = _button(text, func() -> void: chosen.emit("city_arm", key), Color(0.45, 0.38, 0.12), 18)
			button.disabled = not buy.get("allowed", false)
			if buy.get("blockedByUnit", false):
				button.text = "Buy: move the unit out of the city first"
				button.disabled = true
		buttons.add_child(button)
	if built.has("sellGold"):
		var sell_key := "sell:" + name
		if armed == sell_key:
			buttons.add_child(_button(Lang.format("Click again: sell for %d gold", int(built["sellGold"])), func() -> void: chosen.emit("city_sell", name), Color(0.7, 0.2, 0.15), 18))
		else:
			var sell := _button(Lang.format("Sell for %d gold", int(built["sellGold"])), func() -> void: chosen.emit("city_arm", sell_key), Color(0.42, 0.18, 0.15), 18)
			sell.disabled = not built.get("canSell", false)
			buttons.add_child(sell)
	# In a wrapping row a button is only as wide as its minimum size, which clipped text would make zero
	for button: Button in buttons.get_children():
		button.clip_text = false
		button.custom_minimum_size = Vector2(minf(SIZE.x - 40, button.get_theme_font("font").get_string_size(Lang.t(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x + 24), 44)
	if buttons.get_child_count() > 0:
		_footer.add_child(buttons)


func _option(name: String) -> Dictionary:
	for o: Dictionary in city.get("options", []):
		if o["name"] == name:
			return o
	return {}


# region helpers --------------------------------------------------------------------------

static func _plain(text: String) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 0xE000 or code > 0xF8FF:
			out += text[i]
	return out.replace("  ", " ")


static func _rgb(values: Array, fallback: Color) -> Color:
	if values.size() < 3:
		return fallback
	return Color(float(values[0]) / 255.0, float(values[1]) / 255.0, float(values[2]) / 255.0)


func _header(text: String) -> void:
	var label := _plain_label(text, 20, HEADER)
	_list.add_child(HSeparator.new())
	_list.add_child(label)


func _line(text: String, colour: Color) -> void:
	var label := _plain_label(text, 17, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(label)


func _line_icon(text: String, colour: Color, icon: Texture2D) -> void:
	_list.add_child(_icon_text(icon, text, colour))


func _small(text: String) -> void:
	var label := _plain_label(text, 16, DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(label)


func _footer_line(text: String, colour: Color) -> void:
	var label := _plain_label(text, 16, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_child(label)


func _plain_label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = _plain(text)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _icon_rect(texture: Texture2D, side: float, tint := Color.WHITE) -> Control:
	if texture == null:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(side, side)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return gap
	var rect := TextureRect.new()
	rect.texture = texture
	rect.modulate = tint
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _icon_text(icon: Texture2D, text: String, colour: Color, wrap := true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_icon_rect(icon, 26))
	var label := _plain_label(text, 17, colour)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


## Small stat symbols with numbers (non-zero ones only), e.g. a tile's or a building's yields.
func _stat_icons(stats: Dictionary, side: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for stat: String in STAT_ORDER:
		var value := roundi(float(stats.get(stat, 0.0)))
		if value == 0:
			continue
		row.add_child(_icon_rect(Icons.get_icon("stat", stat.capitalize()), side))
		var amount := _plain_label(str(value), int(side * 0.75), STAT_COLORS[stat].lightened(0.2))
		amount.text_direction = Control.TEXT_DIRECTION_LTR
		row.add_child(amount)
	return row


func _stat_button(stat: String, value: String, highlighted: bool) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(86, 48)
	_restyle(button, SELECTED if highlighted else Color(0.1, 0.12, 0.17))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(6, 6)
	row.add_child(_icon_rect(Icons.get_icon("stat", stat.capitalize()), 34))
	var amount := _plain_label(value, 20, STAT_COLORS[stat].lightened(0.25))
	amount.text_direction = Control.TEXT_DIRECTION_LTR
	row.add_child(amount)
	button.add_child(row)
	return button


## A full-width clickable row; put things in its HBoxContainer child.
func _row_button(on_press: Callable, colour: Color) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_restyle(button, colour)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 6
	inner.offset_right = -6
	inner.offset_top = 3
	inner.offset_bottom = -3
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	button.add_child(inner)
	inner.minimum_size_changed.connect(func() -> void:
		button.custom_minimum_size.y = maxf(46, inner.get_combined_minimum_size().y + 6))
	button.pressed.connect(on_press)
	return button


func _progress_bar(fraction: float, colour: Color, text: String) -> Control:
	var back := Panel.new()
	back.custom_minimum_size = Vector2(120, 22)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18)
	style.set_corner_radius_all(5)
	back.add_theme_stylebox_override("panel", style)
	var fill := ColorRect.new()
	fill.color = colour.darkened(0.15)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(fraction, 0.0, 1.0)
	back.add_child(fill)
	var label := _plain_label(text, 14, Color.WHITE)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	back.add_child(label)
	return back


func _button(text: String, on_press: Callable, color: Color, font_size := 17) -> Button:
	var button := Button.new()
	button.text = _plain(text)
	button.tooltip_text = _plain(text)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.52, 0.56))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
