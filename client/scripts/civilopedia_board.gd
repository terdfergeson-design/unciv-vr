# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## Unciv's Civilopedia, as a large board: the categories along the top, that category's entries down the left
## (under their sub-category headings), and the chosen entry's page on the right, written with Unciv's own
## formatted lines (headings, icons, links to other entries, separators, pictures). Links open their entry and
## Back goes back the way you came. Everything comes from the bridge (getCivilopedia, getCivilopediaEntry), so
## mods' entries show up too.
## In VR it floats over the table (the strip along the top moves it); on the desktop it's a window in the middle.
##
## Set [member fetch] to a function (link -> getCivilopediaEntry result, or {} when it failed) before opening.
## Emits chosen(kind, value): "close", "external" (a web link, opened in the browser).

signal chosen(kind: String, value: String)

const DataPaths := preload("res://scripts/data_paths.gd")
const Icons := preload("res://scripts/icons.gd")

const SIZE := Vector2(1600, 960)
const GRAB_HEIGHT := 30.0
const LIST_WIDTH := 380.0
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.64, 0.68, 0.76)
const HEADER := Color(0.98, 0.85, 0.45)
const BUTTON := Color(0.2, 0.22, 0.3)
const SELECTED := Color(0.22, 0.42, 0.66)
const LINK := Color(0.62, 0.8, 1.0)
const ENTRY_BUTTON := Color(0.2, 0.29, 0.49)    # Unciv's entry buttons are tinted rgb(50, 75, 125)
## Unciv's heading sizes (FormattedLine.headerSizes) for 1..8; ours are a little larger, as the text is read at a distance
const HEADER_SIZES := [0, 36, 32, 27, 24, 21, 15, 12, 9]
const BASE_FONT := 22

## Extra facts for icons from the last getCivilopedia: terrain name -> Color, nation -> [outer, inner], name group -> unit
static var terrain_colours: Dictionary = {}
static var nation_colours: Dictionary = {}
static var group_units: Dictionary = {}

var fetch: Callable            # async (link: String) -> Dictionary
var categories: Array = []      # getCivilopedia categories
var category := ""              # key of the category on show
var link := ""                  # "Category/Name" on show
var history: Array[String] = []
var _last_entry: Dictionary = {}    # category key -> the link last shown there
var _category_buttons: Dictionary = {}
var _entry_buttons: Dictionary = {}  # link -> Button
var _title: Label
var _back: Button
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _page_scroll: ScrollContainer
var _page: VBoxContainer
var _categories_box: HFlowContainer
var _loading := 0


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
	var grab := _label("=====   Civilopedia  -  hold the trigger here and drag to move   =====", 15, DIM)
	grab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grab.custom_minimum_size = Vector2(0, GRAB_HEIGHT)
	box.add_child(grab)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	_back = _button("<  Back", back, BUTTON, 20)
	_back.custom_minimum_size = Vector2(130, 46)
	top.add_child(_back)
	var icon := TextureRect.new()
	icon.texture = Icons.get_icon("other", "Question")
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(icon)
	_title = _label("Civilopedia", 28, HEADER)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	top.add_child(_title)
	var close := _button("Close", func() -> void: chosen.emit("close", ""), Color(0.42, 0.2, 0.2), 20)
	close.custom_minimum_size = Vector2(140, 46)
	top.add_child(close)

	_categories_box = HFlowContainer.new()
	_categories_box.add_theme_constant_override("h_separation", 6)
	_categories_box.add_theme_constant_override("v_separation", 6)
	box.add_child(_categories_box)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	box.add_child(columns)
	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Icons.thick_scrollbars(_list_scroll)
	columns.add_child(_list_scroll)
	var list_margin := MarginContainer.new()   # room for the thick scrollbar, which is drawn over the list
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_right", 22)
	_list_scroll.add_child(list_margin)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	list_margin.add_child(_list)

	var page_back := PanelContainer.new()
	page_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var page_style := StyleBoxFlat.new()
	page_style.bg_color = Color(0.08, 0.1, 0.16)
	page_style.set_corner_radius_all(8)
	page_style.content_margin_left = 18
	page_style.content_margin_top = 10
	page_style.content_margin_bottom = 10
	page_back.add_theme_stylebox_override("panel", page_style)
	columns.add_child(page_back)
	_page_scroll = ScrollContainer.new()
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Icons.thick_scrollbars(_page_scroll)
	page_back.add_child(_page_scroll)
	var page_margin := MarginContainer.new()
	page_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_margin.add_theme_constant_override("margin_right", 30)
	_page_scroll.add_child(page_margin)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 2)
	page_margin.add_child(_page)
	_update_back()


## The getCivilopedia result: builds the category buttons. The last entry looked at stays, if it's still there.
func set_categories(data: Dictionary) -> void:
	categories = data.get("categories", [])
	terrain_colours.clear()
	nation_colours.clear()
	group_units.clear()
	for entry_list: Dictionary in categories:
		for entry: Dictionary in entry_list.get("entries", []):
			if entry.has("rgb"):
				var rgb: Array = entry["rgb"]
				terrain_colours[entry["name"]] = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
			if entry.has("outer"):
				nation_colours[entry["name"]] = [Color.html(str(entry["outer"])), Color.html(str(entry["inner"])), str(entry.get("cityStateType", ""))]
			if entry.has("unit"):
				group_units[entry["name"]] = str(entry["unit"])
	for child in _categories_box.get_children():
		child.queue_free()
	_category_buttons.clear()
	for entry_list: Dictionary in categories:
		var key := str(entry_list["key"])
		var button := _button(str(entry_list["label"]), func() -> void: await open_category(key), BUTTON, 16)
		button.icon = Icons.from_path(str(entry_list.get("icon", "")))
		button.add_theme_constant_override("icon_max_width", 26)
		button.custom_minimum_size = Vector2(0, 40)
		_categories_box.add_child(button)
		_category_buttons[key] = button
	_last_entry.clear()


func has_categories() -> bool:
	return not categories.is_empty()


func _category_data(key: String) -> Dictionary:
	for entry_list: Dictionary in categories:
		if str(entry_list["key"]) == key or str(entry_list["label"]) == key:
			return entry_list
	return {}


## Shows a category's entries and opens the one last looked at there (or its first).
func open_category(key: String) -> void:
	var data := _category_data(key)
	if data.is_empty() or data["entries"].is_empty():
		return
	var first := "%s/%s" % [data["key"], data["entries"][0]["name"]]
	await open_link(str(_last_entry.get(data["key"], first)))


## Opens "Category/Name" (a category key or label, as Unciv's links have it). [param remember]: Back returns here.
func open_link(target: String, remember := true) -> void:
	var slash := target.find("/")
	var data := _category_data(target.left(slash) if slash > 0 else target)
	if data.is_empty():
		return
	if slash < 0:
		await open_category(str(data["key"]))
		return
	var full: String = "%s/%s" % [data["key"], target.substr(slash + 1)]
	if remember and link != "" and link != full:
		history.append(link)
		if history.size() > 60:
			history.remove_at(0)
	_show_list(data)
	link = full
	_last_entry[data["key"]] = full
	_highlight_entry()
	_update_back()
	_title.text = tr("Civilopedia") + "  -  " + _entry_label(data, target.substr(slash + 1))
	if not fetch.is_valid():
		return
	_loading += 1
	var ticket := _loading
	var reply: Dictionary = await fetch.call(full)
	if ticket != _loading:
		return   # another entry was picked meanwhile
	show_page(reply)


func back() -> void:
	if history.is_empty():
		return
	var previous: String = history.pop_back()
	await open_link(previous, false)


func _update_back() -> void:
	if _back != null:
		_back.disabled = history.is_empty()


func _entry_label(data: Dictionary, name: String) -> String:
	for entry: Dictionary in data["entries"]:
		if str(entry["name"]) == name:
			return str(entry.get("label", name))
	return name


func _show_list(data: Dictionary) -> void:
	if category == str(data["key"]) and _list.get_child_count() > 0:
		return
	category = str(data["key"])
	for key: String in _category_buttons:
		_paint(_category_buttons[key], SELECTED if key == category else BUTTON)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()
	var sub := ""
	for entry: Dictionary in data["entries"]:
		var entry_sub := str(entry.get("sub", ""))
		if entry_sub != "" and entry_sub != sub:
			var heading := _label(entry_sub, 18, HEADER)
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_list.add_child(heading)
		sub = entry_sub
		var entry_link := "%s/%s" % [category, entry["name"]]
		var button := _button(str(entry.get("label", entry["name"])), func() -> void: await open_link(entry_link), ENTRY_BUTTON, 19)
		button.icon = link_icon(entry_link)
		button.add_theme_constant_override("icon_max_width", 36)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size = Vector2(0, 50)
		_list.add_child(button)
		_entry_buttons[entry_link] = button
	_list_scroll.scroll_vertical = 0


func _highlight_entry() -> void:
	for entry_link: String in _entry_buttons:
		_paint(_entry_buttons[entry_link], SELECTED if entry_link == link else ENTRY_BUTTON)
	var button: Button = _entry_buttons.get(link)
	if button != null:
		await get_tree().process_frame
		if not is_instance_valid(button):
			return
		var top := button.position.y
		if top < _list_scroll.scroll_vertical or top + button.size.y > _list_scroll.scroll_vertical + _list_scroll.size.y:
			_list_scroll.scroll_vertical = int(top - (_list_scroll.size.y - button.size.y) / 2.0)


## Draws a getCivilopediaEntry result on the right.
func show_page(entry: Dictionary) -> void:
	for child in _page.get_children():
		_page.remove_child(child)
		child.queue_free()
	if entry.is_empty():
		_page.add_child(_label("This entry couldn't be loaded.", BASE_FONT, DIM))
		return
	var width := SIZE.x - LIST_WIDTH - 110.0
	render_lines(_page, entry.get("lines", []), width, func(target: String) -> void: follow(target))
	_page_scroll.scroll_vertical = 0


## A link on a page: another entry, or a web address.
func follow(target: String) -> void:
	if target.begins_with("http://") or target.begins_with("https://") or target.begins_with("mailto:"):
		chosen.emit("external", target)
	else:
		await open_link(target)


## Scrolls whichever column [param pixel] (board pixels) is over.
func scroll_at(pixel: Vector2, pixels: float) -> void:
	var on_list := pixel.x < _page_scroll.get_global_rect().position.x - get_global_rect().position.x
	var scroll := _list_scroll if on_list else _page_scroll
	scroll.scroll_vertical += int(pixels)


func scroll_by(pixels: float) -> void:
	_page_scroll.scroll_vertical += int(pixels)


func grab_bar_contains(pixel: Vector2) -> bool:
	return pixel.y >= 0.0 and pixel.y <= GRAB_HEIGHT + 4.0


## Presses the button whose text starts with [param caption] (for tests). Returns whether there was one.
func press(caption: String) -> bool:
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.text.strip_edges().begins_with(caption):
			button.pressed.emit()
			return true
	return false


## The links on the page on show (for tests).
func page_links() -> Array[String]:
	var out: Array[String] = []
	for node in _page.find_children("*", "Control", true, false):
		if node.has_meta("link"):
			out.append(str(node.get_meta("link")))
	return out


## The text of the page on show (for tests).
func page_text() -> String:
	var parts: Array[String] = []
	for node in _page.find_children("*", "RichTextLabel", true, false):
		parts.append((node as RichTextLabel).get_parsed_text())
	return "\n".join(parts)


func entry_count() -> int:
	return _entry_buttons.size()


# region formatted lines ---------------------------------------------------------------------

## Adds Unciv's formatted lines (getCivilopediaEntry lines, a tutorial task's lines) to [param box], wrapped to
## [param width] pixels. Links call [param on_link] with their target. [param pictures]: false leaves out the
## extraImage pictures (the tutorial tasks' are screenshots of Unciv's own screens).
static func render_lines(box: Container, lines: Array, width: float, on_link: Callable, base_font := BASE_FONT, pictures := true) -> void:
	for line: Dictionary in lines:
		var control := line_control(line, width, on_link, base_font, pictures)
		if control != null:
			box.add_child(control)


static func line_control(line: Dictionary, width: float, on_link: Callable, base_font := BASE_FONT, pictures := true) -> Control:
	if line.get("separator", false):
		var separator := HSeparator.new()
		var style := StyleBoxLine.new()
		style.color = Color.html(str(line["color"])) if line.has("color") else Color(0.4, 0.45, 0.55)
		style.thickness = 2
		separator.add_theme_stylebox_override("separator", style)
		separator.custom_minimum_size = Vector2(0, 12)
		return separator
	if line.has("extraImage"):
		if not pictures:
			return null
		var texture := extra_image(str(line["extraImage"]))
		if texture == null:
			return null
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var natural := Vector2(texture.get_size())
		var side := minf(float(line.get("imageSize", width)) * 1.2, width)
		var scale := side / maxf(natural.x, natural.y)
		picture.custom_minimum_size = natural * scale
		picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		return picture
	var text := str(line.get("text", ""))
	var target := str(line.get("link", ""))
	var external := target.begins_with("http") or target.begins_with("mailto:")
	if text == "" and external:
		text = target
	var icon_link := str(line.get("icon", ""))
	if text == "" and icon_link == "" and not line.get("starred", false):
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, base_font * 0.6)
		return gap
	var font_size := base_font
	if line.has("header"):
		var header := int(line["header"])
		font_size = int(HEADER_SIZES[clampi(header, 0, HEADER_SIZES.size() - 1)] * base_font / 18.0) if header > 0 else base_font
	elif line.has("size"):
		font_size = int(int(line["size"]) * base_font / 18.0)
	var colour := Color.html(str(line["color"])) if line.has("color") else (LINK if target != "" else TEXT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var indent := int(line.get("indent", 0))
	if indent > 0:
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(30 * indent, 0)
		row.add_child(pad)
	var icon_side := maxf(30.0, font_size * 1.5)
	if external:
		row.add_child(_icon_rect(Icons.get_icon("other", "Link"), icon_side, false))
	elif icon_link != "":
		var texture := link_icon(icon_link)
		if texture != null:
			row.add_child(_icon_rect(texture, icon_side, line.get("iconCrossed", false)))
	if line.get("starred", false):
		var star := _icon_rect(Icons.get_icon("other", "Star"), icon_side * 0.7, false)
		star.modulate = colour
		row.add_child(star)
	if text != "":
		var label := rich_label(text, font_size, Color.WHITE if line.get("starred", false) else colour, line.get("centered", false))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
	if line.get("centered", false):
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	if target == "":
		return row
	# A link: the whole line is clickable
	var holder := PanelContainer.new()
	holder.set_meta("link", target)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 4
	var hot := normal.duplicate() as StyleBoxFlat
	hot.bg_color = Color(0.25, 0.35, 0.55, 0.55)
	holder.add_theme_stylebox_override("panel", normal)
	holder.mouse_entered.connect(func() -> void: holder.add_theme_stylebox_override("panel", hot))
	holder.mouse_exited.connect(func() -> void: holder.add_theme_stylebox_override("panel", normal))
	holder.gui_input.connect(func(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			on_link.call(target))
	for child in row.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(row)
	return holder


static func _icon_rect(texture: Texture2D, side: float, crossed: bool) -> Control:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if crossed:   # Unciv draws a red cross over it ("avoid tundra")
		var cross := Label.new()
		cross.text = "✕"
		cross.add_theme_font_size_override("font_size", int(side * 0.9))
		cross.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rect.add_child(cross)
	return rect


## A wrapping label for Unciv's text: its icon characters (⚙ ¤ ⁂ ⍾ ♪...) drawn as the icons they stand for, and
## its «colour» markup dropped.
static func rich_label(text: String, font_size: int, colour: Color, centered := false) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", colour)
	if centered:
		label.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	add_unciv_text(label, text, font_size)
	if centered:
		label.pop()
	return label


static func add_unciv_text(label: RichTextLabel, text: String, font_size: int) -> void:
	var clean := RegEx.create_from_string("«[^»]*»").sub(text, "", true)
	var run := ""
	var side := int(font_size * 1.05)
	for i in clean.length():
		var ch := clean[i]
		var code := clean.unicode_at(i)
		if code >= 0xE000 and code <= 0xF8FF:
			continue   # private-use characters our font doesn't have
		var path: String = Icons.SYMBOLS.get(ch, "")
		var texture: Texture2D = Icons.from_path(path) if path != "" else null
		if texture == null:
			run += ch
			continue
		if run != "":
			label.add_text(run)
			run = ""
		label.add_image(texture, side, side, Color.WHITE, INLINE_ALIGNMENT_CENTER)
	if run != "":
		label.add_text(run)


## The icon for a Civilopedia link ("Unit/Warrior", "Terrain/Hill"...), the way Unciv's entry list draws it.
static func link_icon(target: String) -> Texture2D:
	var slash := target.find("/")
	if slash < 0:
		return null
	var kind := target.left(slash)
	var name := target.substr(slash + 1)
	match kind:
		"Building", "Buildings", "Wonder", "Wonders":
			return Icons.construction(name)
		"Unit", "Units":
			return Icons.badge("unit", name, Color(0.25, 0.3, 0.42))
		"Resource", "Resources":
			return Icons.badge("resource", name, Color(0.86, 0.84, 0.78), Color.WHITE, 0.8)
		"Improvement", "Tile Improvements":
			return Icons.badge("improvement", name, Color(0.25, 0.3, 0.42), Color.WHITE, 0.8)
		"Technology", "Technologies":
			return Icons.badge("tech", name, Color(0.25, 0.3, 0.42), Color.WHITE, 0.8)
		"Promotion", "Promotions":
			var found: Array = Icons.promotion(name)
			return found[0]
		"Policy", "Policies":
			var policy := Icons.get_icon("policy", name)
			return policy if policy != null else Icons.get_icon("branch", name.trim_suffix(" Complete"))
		"Belief", "Religions and Beliefs":
			var belief := Icons.get_icon("religion", name)
			return belief if belief != null else Icons.get_icon("religion", "Religion")
		"Nation", "Nations":
			var colours: Array = nation_colours.get(name, [])
			if colours.is_empty():
				return Icons.get_icon("nation", name)
			var civ := {"nation": name, "outerColor": (colours[0] as Color).to_html(), "innerColor": (colours[1] as Color).to_html()}
			if str(colours[2]) != "":
				civ["isCityState"] = true
				civ["cityStateType"] = colours[2]
			return Icons.civ_badge(civ)
		"Terrain", "Terrains":
			return hexagon(terrain_colours.get(name, Color(0.5, 0.5, 0.5)))
		"UnitType", "Unit types":
			if name.begins_with("Domain: ["):
				return Icons.get_icon("unittype", "Domain" + name.trim_prefix("Domain: [").trim_suffix("]"))
			return Icons.get_icon("unittype", name)
		"UnitNameGroup", "Unit Names":
			var unit: String = group_units.get(name, "")
			return Icons.badge("unit", unit, Color(0.25, 0.3, 0.42)) if unit != "" else Icons.get_icon("other", "UnitNameGroups")
		"Victory", "Victory Types":
			return Icons.get_icon("victory", name)
	return null


## A flat hexagon in a terrain's colour (Unciv draws the terrain tile itself).
static func hexagon(colour: Color) -> Texture2D:
	var key := "hex:" + colour.to_html()
	if _hexes.has(key):
		return _hexes[key]
	var size := 64
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) / 2.0
	var radius := size / 2.0 - 2.0
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - centre
			# pointy-top hexagon: inside when within the three pairs of edges
			var q := Vector2(absf(p.x), absf(p.y))
			var inside := q.x <= radius * 0.866 and q.y + q.x * 0.577 <= radius
			if inside:
				var edge := q.x > radius * 0.866 - 3.0 or q.y + q.x * 0.577 > radius - 3.0
				out.set_pixel(x, y, colour.darkened(0.3) if edge else colour)
	out.generate_mipmaps()
	var texture := ImageTexture.create_from_image(out)
	_hexes[key] = texture
	return texture

static var _hexes: Dictionary = {}
static var _extra_images: Dictionary = {}


## A picture from Unciv's ExtraImages folder ("World_Screen", "Tutorials/Move unit"), or one of its icons by path.
static func extra_image(name: String) -> Texture2D:
	if _extra_images.has(name):
		return _extra_images[name]
	var texture: Texture2D = null
	var folder := DataPaths.unciv_android_dir().path_join("assets/ExtraImages")
	for extension: String in [".png", ".jpg", ".jpeg", ".webp"]:
		var path := folder.path_join(name + extension)
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty():
				image.generate_mipmaps()
				texture = ImageTexture.create_from_image(image)
			break
	if texture == null:
		texture = Icons.from_path(name) if name.contains("/") else null
	_extra_images[name] = texture
	return texture


# region widgets ------------------------------------------------------------------------------

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, pressed: Callable, color: Color, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", DIM.darkened(0.3))
	_paint(button, color)
	button.pressed.connect(pressed)
	return button


func _paint(button: Button, color: Color) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color if state == "normal" else (color.lightened(0.15) if state == "hover" else color.darkened(0.15))
		if state == "disabled":
			style.bg_color = color.darkened(0.4)
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		button.add_theme_stylebox_override(state, style)
