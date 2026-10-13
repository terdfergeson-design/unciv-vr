# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## The info board: your civilization's numbers (gold, science, culture, faith, happiness, population)
## and whatever tile you're pointing at (terrain, yields, resource, owner, units, defence), colour-coded
## like Unciv's top bar and tile info. Stands next to the overview in VR; bottom-left on the desktop.

const Lang := preload("res://scripts/lang.gd")

const WIDTH := 420
const Icons := preload("res://scripts/icons.gd")

# Unciv-like colours for each kind of number
const GOLD := Color(0.98, 0.8, 0.25)
const SCIENCE := Color(0.4, 0.72, 1.0)
const CULTURE := Color(0.8, 0.5, 0.98)
const FAITH := Color(0.75, 0.88, 1.0)
const HAPPY := Color(0.5, 0.9, 0.35)
const UNHAPPY := Color(1.0, 0.4, 0.3)
const POPULATION := Color(0.95, 0.65, 0.35)
const FOOD := Color(0.45, 0.85, 0.35)
const PRODUCTION := Color(0.95, 0.55, 0.25)
const TEXT := Color(0.9, 0.92, 0.96)
const DIM := Color(0.68, 0.72, 0.8)

var _civ_header: Label
var _civ_badge: TextureRect
var _civ_stats: HFlowContainer
var _research: Label
var _tile_title: Label
var _tile_yields: HFlowContainer
var _tile_lines: VBoxContainer
var _civ_colors: Dictionary = {}    # civ name -> {outer, inner}


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.94)
	style.border_color = Color(0.3, 0.36, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	box.add_child(header_row)
	_civ_badge = TextureRect.new()
	_civ_badge.custom_minimum_size = Vector2(44, 44)
	_civ_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_civ_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header_row.add_child(_civ_badge)
	_civ_header = _label(header_row, 24, TEXT)
	_civ_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_civ_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_civ_stats = _flow(box)
	_research = _label(box, 18, SCIENCE)
	box.add_child(HSeparator.new())
	_tile_title = _label(box, 22, TEXT)
	_tile_yields = _flow(box)
	_tile_lines = VBoxContainer.new()
	_tile_lines.add_theme_constant_override("separation", 2)
	box.add_child(_tile_lines)
	show_tile({})


## The top half: your civ's numbers, from a getState result.
func show_civ(state: Dictionary, civ_colors: Dictionary) -> void:
	if _civ_header == null:
		return
	_civ_colors = civ_colors
	var p: Dictionary = state.get("player", {})
	var civ: String = state.get("playerCiv", "?")
	var year := int(state.get("year", 0))
	_civ_header.text = Lang.format("%s   Turn %d  (%s)", [civ, int(state.get("turn", 0)), Lang.format("%d BC", -year) if year < 0 else Lang.format("%d AD", year)])
	_civ_header.add_theme_color_override("font_color", _civ_color(civ, "outer").lightened(0.2))
	_civ_badge.texture = null
	for entry: Dictionary in state.get("civs", []):
		if entry.get("name") == civ:
			_civ_badge.texture = Icons.civ_badge(entry)
	_civ_badge.visible = _civ_badge.texture != null

	_clear(_civ_stats)
	_chip(_civ_stats, "G", GOLD, "%d (%+d)" % [int(p.get("gold", 0)), int(p.get("goldPerTurn", 0))])
	_chip(_civ_stats, "S", SCIENCE, "%+d" % int(p.get("science", 0)))
	var happiness := int(p.get("happiness", 0))
	_chip(_civ_stats, ":)" if happiness >= 0 else ":(", HAPPY if happiness >= 0 else UNHAPPY, str(happiness))
	var culture := "%+d" % int(p.get("culture", 0))
	if p.has("cultureForNextPolicy"):
		culture = "%d/%d (%+d)" % [int(p.get("culturePoints", 0)), int(p["cultureForNextPolicy"]), int(p.get("culture", 0))]
	_chip(_civ_stats, "C", CULTURE, culture)
	_chip(_civ_stats, "Fa", FAITH, "%d (%+d)" % [int(p.get("faithPoints", 0)), int(p.get("faith", 0))])
	var population := int(p.get("population", -1))
	if population < 0:   # older bridges: add it up from the cities
		population = 0
		for city: Dictionary in state.get("cities", []):
			population += int(city.get("population", 0))
	_chip(_civ_stats, "Pop", POPULATION, str(population))

	var tech: Variant = p.get("currentTech")
	_research.text = Lang.format("Researching %s", tech) if tech != null else "Not researching anything - pick a tech!"
	_research.add_theme_color_override("font_color", SCIENCE if tech != null else UNHAPPY)
	_refit()


## The bottom half: one tile (a getState tile, or a getTile result with yields), or {} for "nothing pointed at".
## [param attack] is the target preview when the selected unit could attack it.
func show_tile(tile: Dictionary, attack: Dictionary = {}) -> void:
	if _tile_title == null:
		return
	_clear(_tile_yields)
	_clear(_tile_lines)
	if tile.is_empty():
		_tile_title.text = "Point at a tile"
		_tile_title.add_theme_color_override("font_color", DIM)
		_refit()
		return
	if not tile.get("explored", false):
		_tile_title.text = "Unexplored"
		_tile_title.add_theme_color_override("font_color", DIM)
		_line("Send a unit to find out what's here.", DIM)
		_refit()
		return

	var names: Array[String] = [str(tile.get("base", "?"))]
	for feature: String in tile.get("features", []):
		names.append(feature)
	_tile_title.text = Lang.join(", ", names)
	_tile_title.add_theme_color_override("font_color", TEXT)

	var yields: Dictionary = tile.get("yields", {})
	for spec: Array in [["food", "F", FOOD], ["production", "Pr", PRODUCTION], ["gold", "G", GOLD],
			["science", "S", SCIENCE], ["culture", "C", CULTURE], ["faith", "Fa", FAITH]]:
		var amount := float(yields.get(spec[0], 0.0))
		if amount != 0.0:
			_chip(_tile_yields, spec[1], spec[2], str(snappedf(amount, 0.1)).trim_suffix(".0"))

	if tile.has("wonder"):
		_line(Lang.format("Natural wonder: %s", tile["wonder"]), GOLD)
	if tile.has("resource"):
		_line(Lang.format("Resource: %s", tile["resource"]), Color(0.95, 0.85, 0.5),
			Icons.badge("resource", str(tile["resource"]), Color(0.3, 0.45, 0.3)))
	if tile.has("improvement"):
		_line(Lang.format("Improvement: %s%s", [tile["improvement"], " (pillaged)" if tile.get("pillaged", false) else ""]), TEXT,
			Icons.badge("improvement", str(tile["improvement"]), Color(0.22, 0.25, 0.32)))
	if str(tile.get("road", "None")) != "None":
		_line(str(tile["road"]), DIM)
	if tile.has("river"):
		_line("River", Color(0.5, 0.75, 1.0))
	if tile.has("city"):
		var city: Dictionary = tile["city"]
		_line(Lang.format("City of %s  (population %d)", [city.get("name", "?"), int(city.get("population", 0))]),
			_civ_color(str(city.get("civ", "")), "outer").lightened(0.3))
	if tile.has("owner"):
		var owner: String = tile["owner"]
		var text := Lang.format("%s territory", owner)
		if tile.has("workedBy"):
			text += Lang.format(", worked by %s", tile["workedBy"])
		_line(text, _civ_color(owner, "outer").lightened(0.3))
	for unit: Dictionary in tile.get("units", []):
		var health := int(unit.get("health", 100))
		var colours: Dictionary = _civ_colors.get(str(unit.get("civ", "")), {})
		_line(Lang.format("%s  -  %s%s", [unit.get("name", "?"), unit.get("civ", "?"), Lang.format("  (%d HP)", health) if health < 100 else ""]),
			_civ_color(str(unit.get("civ", "")), "outer").lightened(0.3),
			Icons.badge("unit", str(unit.get("name", "")), colours.get("inner", Color(0.2, 0.2, 0.2)), colours.get("outer", Color.WHITE)))
	var defense := int(tile.get("defenseBonus", 0))
	if defense != 0:
		_line(Lang.format("%+d%% to unit defence", defense), HAPPY if defense > 0 else UNHAPPY)
	if tile.get("impassable", false):
		_line("Impassable", UNHAPPY)
	if not tile.get("visible", false):
		_line("Not currently in sight - last seen like this", DIM)
	if not attack.is_empty():
		_line(Lang.format("Attack %s: deal ~%d, take ~%d", [attack.get("name", "?"), int(attack.get("expectedDamageToDefender", 0)),
			int(attack.get("expectedDamageToAttacker", 0))]), UNHAPPY)
	_refit()


## Shrinks the board to its new contents once the old rows have gone.
func _refit() -> void:
	await get_tree().process_frame
	reset_size()


func _civ_color(civ: String, which: String) -> Color:
	var colors: Dictionary = _civ_colors.get(civ, {})
	var color: Color = colors.get(which, TEXT)
	# Some nations' colours are too dark to read on the dark board
	return color.lightened(0.55) if color.get_luminance() < 0.35 else color


## A coloured round badge with a short symbol, followed by the number.
const STAT_ICONS := {"G": "Gold", "S": "Science", ":)": "Happiness", ":(": "Malcontent", "C": "Culture",
	"Fa": "Faith", "Pop": "Population", "F": "Food", "Pr": "Production"}


func _chip(parent: Container, symbol: String, color: Color, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var icon := Icons.get_icon("stat", STAT_ICONS.get(symbol, ""))
	if icon == null and symbol == ":(":
		icon = Icons.get_icon("stat", "Happiness")
	if icon != null:   # Unciv's own stat symbol
		var picture := TextureRect.new()
		picture.texture = icon
		picture.custom_minimum_size = Vector2(26, 26)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
		var amount := Label.new()
		amount.text_direction = Control.TEXT_DIRECTION_LTR
		amount.text = value
		amount.add_theme_font_size_override("font_size", 20)
		amount.add_theme_color_override("font_color", color.lightened(0.25))
		row.add_child(amount)
		parent.add_child(row)
		return
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	style.content_margin_left = 6
	style.content_margin_right = 6
	badge.add_theme_stylebox_override("panel", style)
	var mark := Label.new()
	mark.text = symbol
	mark.add_theme_font_size_override("font_size", 16)
	mark.add_theme_color_override("font_color", Color(0.05, 0.05, 0.1))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(mark)
	row.add_child(badge)
	var number := Label.new()
	number.text_direction = Control.TEXT_DIRECTION_LTR
	number.text = value
	number.add_theme_font_size_override("font_size", 20)
	number.add_theme_color_override("font_color", color.lightened(0.25))
	row.add_child(number)
	parent.add_child(row)


func _line(text: String, color: Color, icon: Texture2D = null) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	if icon == null:
		_tile_lines.add_child(label)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var picture := TextureRect.new()
	picture.texture = icon
	picture.custom_minimum_size = Vector2(28, 28)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(picture)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_tile_lines.add_child(row)


func _label(parent: Container, size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _flow(parent: Container) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 4)
	parent.add_child(flow)
	return flow


func _clear(container: Container) -> void:
	for child in container.get_children():
		child.queue_free()
