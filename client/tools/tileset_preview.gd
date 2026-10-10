# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## Tileset preview: a tool for making tilesets. Shows a grid of example tiles - every terrain and feature
## combination, natural wonder, resource, improvement or unit in an Unciv ruleset - drawn with the game's own map
## code, with a report of which pieces each one used and what's missing. Reload re-reads the files (after you
## export from Blender, say) without restarting; Save picture writes the view to a PNG.
##
## Run it from the client folder:  godot --path . --xr-mode off tools/tileset_preview.tscn
## or open tools/tileset_preview.tscn in the Godot editor and press F6.
## Command line (after "--"): --tileset=<folder> --ruleset="Civ V - Vanilla" --category=terrain|features|wonders|
##   resources|improvements|units  --save=<file.png> (saves that view and quits)
## Mouse: left-drag turns, right- or middle-drag slides, wheel zooms; point at a tile to see its pieces.

const Tileset := preload("res://scripts/tileset.gd")
const HexMap := preload("res://scripts/hex_map.gd")
const Backgrounds := preload("res://scripts/backgrounds.gd")

const CATEGORIES := [["terrain", "Terrain"], ["features", "Features"], ["wonders", "Natural wonders"],
	["resources", "Resources"], ["improvements", "Improvements"], ["units", "Units"]]
const SPACING := 2.6          # map units between example tiles (a hex is 2 across)
var columns := 8             # grid width, picked to suit how many examples there are
const CIVS := [
	{"name": "Red", "nation": "", "outerColor": "#b52a2aff", "innerColor": "#f6d34dff"},
	{"name": "Blue", "nation": "", "outerColor": "#2a52b5ff", "innerColor": "#f2f2f2ff"},
	{"name": "Green", "nation": "", "outerColor": "#1f7d3fff", "innerColor": "#f2cc33ff"},
	{"name": "Purple", "nation": "", "outerColor": "#73358cff", "innerColor": "#dcdce6ff"},
]

var tileset_name := "LowPoly"
var ruleset_name := "Civ V - Gods & Kings"
var category := "terrain"
var rules := {}               # terrains / resources / improvements / units, read from Unciv's json files
var map: Node3D
var backgrounds: Node3D
var camera: Camera3D
var _labels: Node3D
var _cells: Array = []        # [{key, title, tile}]
var _orbit := Vector2(-0.6, 0.0)   # pitch, yaw
var _distance := 20.0
var _focus := Vector3.ZERO
var _dragging := 0            # mouse button held
var _ui: Dictionary = {}      # widgets
var _background := "studio"


func _ready() -> void:
	var options := {}
	var args := Array(OS.get_cmdline_user_args())
	# the same developer hook as the game: override.cfg's [unciv_vr] preview_args
	args.append_array(str(ProjectSettings.get_setting("unciv_vr/preview_args", "")).split(" ", false))
	for arg: String in args:
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			options[parts[0]] = parts[1] if parts.size() > 1 else ""
	tileset_name = str(options.get("tileset", tileset_name))
	ruleset_name = str(options.get("ruleset", ruleset_name))
	category = str(options.get("category", category))

	backgrounds = Backgrounds.new()
	add_child(backgrounds)
	_background = str(options.get("background", "studio"))
	backgrounds.apply(_background)   # plain by default; the game's are in the menu
	backgrounds.position.y = -0.3    # its meadow just under the tiles
	map = HexMap.new()
	map.tileset_name = tileset_name
	add_child(map)
	map.set_tileset(tileset_name)
	map.animate_moves = false
	_labels = Node3D.new()
	add_child(_labels)
	camera = Camera3D.new()
	camera.fov = 40
	add_child(camera)
	camera.current = true
	_build_ui()
	_load_rules()
	_show_category(category)
	if options.has("save"):
		await get_tree().create_timer(1.5).timeout
		_save_picture(str(options["save"]))
		get_tree().quit()


# region the examples --------------------------------------------------------------------------

## Reads Unciv's ruleset files straight from the Unciv checkout next to the client.
func _load_rules() -> void:
	var folder := ProjectSettings.globalize_path("res://").path_join("../unciv/android/assets/jsons").path_join(ruleset_name).simplify_path()
	rules = {}
	for file: String in ["Terrains", "TileResources", "TileImprovements", "Units"]:
		rules[file] = _read_lenient_json(folder.path_join(file + ".json"))
	var terrain_info := {}
	for t: Dictionary in rules["Terrains"]:
		terrain_info[t["name"]] = {"type": t.get("type", ""), "rgb": t.get("RGB", []), "impassable": false}
	var unit_info := {}
	for u: Dictionary in rules["Units"]:
		var domain := "Land"
		var unit_type := str(u.get("unitType", ""))
		if unit_type.contains("Water") or unit_type in ["Submarine", "Aircraft Carrier"]:
			domain = "Water"
		elif unit_type in ["Fighter", "Bomber", "Helicopter", "Missile", "Atomic Bomber"]:
			domain = "Air"
		unit_info[u["name"]] = {"unitType": unit_type, "replaces": u.get("replaces", ""), "rangedStrength": u.get("rangedStrength", 0),
			"attackSound": u.get("attackSound", ""), "domain": domain}
	var resources := {}
	for r: Dictionary in rules["TileResources"]:
		resources[r["name"]] = {"type": r.get("resourceType", "")}
	map.set_ruleset({"terrains": terrain_info, "units": unit_info, "resources": resources})


## Unciv's json allows comments and trailing commas.
static func _read_lenient_json(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_warning("Can't read " + path)
		return []
	var regex := RegEx.new()
	regex.compile("/\\*[\\s\\S]*?\\*/")
	text = regex.sub(text, "", true)
	var lines := PackedStringArray()
	for line in text.split("\n"):
		var cut := line.find("//")
		while cut >= 0 and line.substr(0, cut).count("\"") % 2 == 1:
			cut = line.find("//", cut + 2)
		lines.append(line if cut < 0 else line.substr(0, cut))
	text = "\n".join(lines)
	regex.compile(",(\\s*[\\]}])")
	text = regex.sub(text, "$1", true)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Array else []


func _terrains_of_type(type: String) -> Array:
	return rules["Terrains"].filter(func(t: Dictionary) -> bool: return t.get("type") == type)


func _occurs_on(feature: String) -> Array:
	for t: Dictionary in rules["Terrains"]:
		if t["name"] == feature:
			return t.get("occursOn", [])
	return []


## Turns a list of terrain names (base terrains and features mixed, like Unciv's "terrainsCanBeFoundOn")
## into a tile: the first base terrain, or the feature on the first base it occurs on.
func _tile_on(terrains: Array) -> Dictionary:
	var bases: Array = _terrains_of_type("Land").map(func(t: Dictionary) -> String: return t["name"]) \
		+ _terrains_of_type("Water").map(func(t: Dictionary) -> String: return t["name"])
	for name_: String in terrains:
		if name_ in bases:
			return {"base": name_, "features": []}
	for name_: String in terrains:
		var on := _occurs_on(name_)
		if not on.is_empty():
			return {"base": on[0], "features": [name_] if name_ != on[0] else []}
	return {"base": "Grassland", "features": []}


## The example tiles for [param which]: [[title, tile], ...].
func _examples(which: String) -> Array:
	var out: Array = []
	match which:
		"terrain":
			for t: Dictionary in _terrains_of_type("Land") + _terrains_of_type("Water"):
				out.append([t["name"], {"base": t["name"], "features": []}])
			out.append(["River (all three sides)", {"base": "Grassland", "features": [], "river": {"bottom": true, "bottomLeft": true, "bottomRight": true}}])
			out.append(["River (one side)", {"base": "Plains", "features": [], "river": {"bottom": true}}])
		"features":
			for f: Dictionary in _terrains_of_type("TerrainFeature"):
				var feature := str(f["name"])
				if feature == "River":
					continue
				for base: String in f.get("occursOn", []):
					if _terrains_of_type("TerrainFeature").any(func(t: Dictionary) -> bool: return t["name"] == base):
						continue   # features on features are made below
					out.append(["%s + %s" % [base, feature], {"base": base, "features": [feature]}])
			for vegetation: String in ["Forest", "Jungle"]:   # on a hill, the most common combination
				for base: String in _occurs_on(vegetation):
					if base in _occurs_on("Hill"):
						out.append(["%s + Hill + %s" % [base, vegetation], {"base": base, "features": ["Hill", vegetation]}])
		"wonders":
			for w: Dictionary in _terrains_of_type("NaturalWonder"):
				var on: Array = w.get("occursOn", ["Grassland"])
				out.append([w["name"], {"base": str(w.get("turnsInto", on[0] if not on.is_empty() else "Grassland")), "features": [], "wonder": w["name"]}])
		"resources":
			for r: Dictionary in rules["TileResources"]:
				var tile := _tile_on(r.get("terrainsCanBeFoundOn", []))
				tile["resource"] = r["name"]
				out.append([r["name"], tile.duplicate(true)])
				var improved_by: Array = r.get("improvedBy", [])
				if improved_by.is_empty() and r.has("improvement"):
					improved_by = [r["improvement"]]
				if not improved_by.is_empty():
					tile["improvement"] = improved_by[0]
					out.append(["%s + %s" % [r["name"], improved_by[0]], tile])
		"improvements":
			for imp: Dictionary in rules["TileImprovements"]:
				var name_ := str(imp["name"])
				if name_.begins_with("Remove") or name_.begins_with("Cancel") or name_ in ["Road", "Railroad", "Repair"]:
					continue
				var tile := _tile_on(imp.get("terrainsCanBeBuiltOn", ["Grassland"]))
				tile["improvement"] = name_
				out.append([name_, tile.duplicate(true)])
				tile["pillaged"] = true
				out.append([name_ + " (pillaged)", tile])
		"units":
			for u: Dictionary in rules["Units"]:
				var water := str(map.unit_info.get(u["name"], {}).get("domain", "")) == "Water"
				out.append([u["name"], {"base": "Coast" if water else "Grassland", "features": [], "unit": u["name"]}])
	return out


func _show_category(which: String) -> void:
	category = which
	_cells = []
	var tiles: Array = []
	var examples := _examples(which)
	columns = clampi(ceili(sqrt(examples.size() * 1.6)), 4, 16)
	for i in examples.size():
		var col := i % columns
		var row := i / columns
		var tile: Dictionary = examples[i][1].duplicate(true)
		tile["x"] = col
		tile["y"] = row
		tile["wx"] = col * SPACING
		tile["wy"] = -row * SPACING
		tile["explored"] = true
		tile["visible"] = true
		if tile.has("unit"):
			tile["units"] = [{"id": 1000 + i, "name": tile["unit"], "civ": CIVS[i % CIVS.size()]["name"], "health": 100,
				"civilian": str(map.unit_info.get(tile["unit"], {}).get("unitType", "")).begins_with("Civilian")}]
			tile.erase("unit")
		tiles.append(tile)
		_cells.append({"key": Vector2i(col, row), "title": examples[i][0], "tile": tile})
	map.build({"tiles": tiles, "civs": CIVS})
	map.set_view(Vector2.ZERO, 0.0)
	_place_labels()
	var rows := ceili(examples.size() / float(columns))
	_focus = Vector3.ZERO
	for cell: Dictionary in _cells:
		_focus += map.to_global(map.tile_local_center(cell["key"])) / float(_cells.size())
	_distance = maxf(8.0, maxf(mini(columns, examples.size()), rows * 1.4) * SPACING * 1.1)
	_orbit = Vector2(-0.95, 0.0)
	_update_camera()
	_update_report()
	for button: Button in _ui["tabs"].get_children():
		button.button_pressed = button.get_meta("id") == which


func _place_labels() -> void:
	for child in _labels.get_children():
		child.queue_free()
	for cell: Dictionary in _cells:
		var label := Label3D.new()
		label.text = cell["title"]
		label.font_size = 48
		label.pixel_size = 0.006
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = map.to_global(map.tile_local_center(cell["key"])) + Vector3(0, 0.15, 1.15)
		label.width = 380
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_labels.add_child(label)


# region what each example used ----------------------------------------------------------------

## A line per example: the pieces it was drawn with (and from which set), or what's missing.
func _describe(cell: Dictionary) -> Array:   # [ok: bool, text]
	var tile: Dictionary = cell["tile"]
	var ts: RefCounted = map.tileset
	if ts == null:
		return [false, "plain coloured hex (no tileset)"]
	if tile.has("units"):
		var unit: Dictionary = tile["units"][0]
		var source: Array = ts.unit_model_source(str(unit["name"]), map.unit_info.get(unit["name"], {}))
		if source[0] == "":
			return [false, "no model - drawn as a round token"]
		var own: bool = source[0] == unit["name"] and source[1] == ts.name
		return [own, "Units/%s%s" % [source[0], "" if source[1] == ts.name else " (from %s)" % source[1]]]
	if not ts.covers(tile):
		return [false, "no piece for %s - drawn as a plain coloured hex" % tile["base"]]
	var used: Array[String] = []
	for entry: Dictionary in ts.pieces_for(tile):
		var source: String = ts.piece_source(entry["piece"])
		used.append(str(entry["piece"]) + ("" if source == ts.name else " (from %s)" % source))
	var missing: Array[String] = []
	if tile.has("resource") and not ts.has_piece(str(tile["resource"])) and not ts.has_piece(str(tile["resource"]) + "+" + str(tile.get("improvement", ""))):
		missing.append("%s: icon only" % tile["resource"])
	if tile.has("improvement") and ts.improvement_piece_for(str(tile["improvement"]), tile.get("pillaged", false)) == "":
		missing.append("%s: the game's little model" % tile["improvement"])
	if tile.has("wonder") and not ts.has_piece(str(tile["wonder"])):
		missing.append("no %s piece - uses NaturalWonder" % tile["wonder"])
	if tile.get("pillaged", false) and tile.has("improvement") and not ts.has_piece(str(tile["improvement"]) + "-Pillaged"):
		missing.append("no -Pillaged piece")
	var text := " + ".join(used)
	if not missing.is_empty():
		text += "   [" + "; ".join(missing) + "]"
	return [missing.is_empty(), text]


func _update_report() -> void:
	var good := 0
	var lines := PackedStringArray()
	for cell: Dictionary in _cells:
		var d := _describe(cell)
		if d[0]:
			good += 1
		lines.append("%s [b]%s[/b]: %s" % ["[color=#7fd17f]✓[/color]" if d[0] else "[color=#e6b04d]•[/color]", cell["title"], d[1]])
	var report: RichTextLabel = _ui["report"]
	report.text = "[b]%s, %s[/b]: %d of %d have pieces of their own\n\n%s" % [
		_ui["tileset"].get_item_text(_ui["tileset"].selected) if _ui["tileset"].item_count > 0 else tileset_name,
		category, good, _cells.size(), "\n".join(lines)]


# region interface -----------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 10)
	bar.add_theme_constant_override("separation", 8)
	layer.add_child(bar)
	var sets := OptionButton.new()
	var available: Dictionary = Tileset.available()
	var i := 0
	for folder: String in available:
		sets.add_item("%s (%s)" % [available[folder], folder])
		sets.set_item_metadata(i, folder)
		if folder == tileset_name:
			sets.select(i)
		i += 1
	sets.item_selected.connect(func(index: int) -> void:
		tileset_name = str(sets.get_item_metadata(index))
		_reload())
	bar.add_child(sets)
	_ui["tileset"] = sets
	var rulesets := OptionButton.new()
	for r: String in ["Civ V - Gods & Kings", "Civ V - Vanilla"]:
		rulesets.add_item(r)
	rulesets.select(0 if ruleset_name.contains("Gods") else 1)
	rulesets.item_selected.connect(func(index: int) -> void:
		ruleset_name = rulesets.get_item_text(index)
		_load_rules()
		_show_category(category))
	bar.add_child(rulesets)
	var looks := OptionButton.new()
	for b: String in ["studio", "mountains", "space"]:
		looks.add_item(b.capitalize())
	looks.select(maxi(0, ["studio", "mountains", "space"].find(_background)))
	looks.item_selected.connect(func(index: int) -> void: backgrounds.apply(["studio", "mountains", "space"][index]))
	bar.add_child(looks)
	var tabs := HBoxContainer.new()
	for c: Array in CATEGORIES:
		var b := Button.new()
		b.text = c[1]
		b.toggle_mode = true
		b.set_meta("id", c[0])
		var id: String = c[0]
		b.pressed.connect(func() -> void: _show_category(id))
		tabs.add_child(b)
	bar.add_child(tabs)
	_ui["tabs"] = tabs
	var reload := Button.new()
	reload.text = "Reload files"
	reload.tooltip_text = "Read the tileset's files again (after you've changed or added pieces)"
	reload.pressed.connect(_reload)
	bar.add_child(reload)
	var save := Button.new()
	save.text = "Save picture"
	save.tooltip_text = "Save this view as preview-<category>.png in the tileset's folder"
	save.pressed.connect(func() -> void:
		var folder: String = map.tileset.folder if map.tileset != null else "user://"
		_save_picture(folder.path_join("preview-%s.png" % category)))
	bar.add_child(save)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -420
	panel.offset_top = 56
	panel.offset_right = -10
	panel.offset_bottom = -10
	layer.add_child(panel)
	var report := RichTextLabel.new()
	report.bbcode_enabled = true
	report.scroll_active = true
	report.add_theme_font_size_override("normal_font_size", 13)
	report.add_theme_font_size_override("bold_font_size", 13)
	panel.add_child(report)
	_ui["report"] = report
	var hint := Label.new()
	hint.text = "Left-drag: turn   right-drag: slide   wheel: zoom   point at a tile: its pieces"
	hint.position = Vector2(12, 48)
	layer.add_child(hint)
	var status := Label.new()
	status.position = Vector2(12, 70)
	layer.add_child(status)
	_ui["status"] = status


## Reads the tileset (and its fallback) from disk again and redraws.
func _reload() -> void:
	map.set_tileset(tileset_name)
	_show_category(category)
	(_ui["status"] as Label).text = "Reloaded %s" % tileset_name


func _save_picture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path)
	(_ui["status"] as Label).text = ("Saved " + path) if error == OK else ("Couldn't save %s (error %d)" % [path, error])
	print((_ui["status"] as Label).text)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_distance = maxf(2.0, _distance * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance = minf(200.0, _distance * 1.1)
		elif mb.pressed:
			_dragging = mb.button_index
		else:
			_dragging = 0
		_update_camera()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging == MOUSE_BUTTON_LEFT:
			_orbit += Vector2(-mm.relative.y, -mm.relative.x) * 0.006
			_orbit.x = clampf(_orbit.x, -1.5, -0.1)
			_update_camera()
		elif _dragging == MOUSE_BUTTON_RIGHT or _dragging == MOUSE_BUTTON_MIDDLE:
			var right := camera.global_transform.basis.x
			var forward := Vector3(camera.global_transform.basis.z.x, 0, camera.global_transform.basis.z.z).normalized()
			_focus += (-right * mm.relative.x + -forward * mm.relative.y) * _distance * 0.0015
			_update_camera()
		else:
			_point_at(mm.position)


func _update_camera() -> void:
	var offset := Vector3(0, 0, _distance).rotated(Vector3.RIGHT, _orbit.x).rotated(Vector3.UP, _orbit.y)
	camera.look_at_from_position(_focus + offset, _focus)
	camera.h_offset = _distance * 0.16   # the report panel covers the right of the window


func _point_at(screen: Vector2) -> void:
	var key: Variant = map.pick(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	var status: Label = _ui["status"]
	if key == null:
		status.text = ""
		return
	for cell: Dictionary in _cells:
		if cell["key"] == key:
			status.text = "%s: %s" % [cell["title"], _describe(cell)[1]]
			return
