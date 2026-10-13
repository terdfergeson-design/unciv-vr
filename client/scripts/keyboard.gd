# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends PanelContainer
## An on-screen keyboard for typing names in VR (cities, units, saves): point at the keys with the laser and pull
## the trigger. Shift is one-shot (it turns off after a letter, like a phone keyboard); the first letter starts
## shifted. On the desktop the real keyboard types into it too (see handle_key).
##
## Emits submitted(text) on OK / Enter and cancelled() on Cancel / Escape.
signal submitted(text: String)
signal cancelled

const SIZE := Vector2(880, 450)
const MAX_LENGTH := 40
const ROWS := ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm-.,", "äöüß"]
const ACCENT_KEYS := {
	"Spanish": "áéíóúüñ¿¡",
	"French": "àâæçéèêëîïôœùûüÿ",
	"Italian": "àèéìíîòóùú",
	"Brazilian_Portuguese": "áàâãéêíóôõúüç",
	"Swedish": "åäöé",
	"Portuguese": "áàâãéêíóôõúüç",
	"Dutch": "áàéèëïíóöüç",
	"Polish": "ąćęłńóśźż",
	"Turkish": "çğıöşü",
	"Indonesian": "",
	"Japanese": "",
}
const ARABIC_ROWS := ["1234567890", "ضصثقفغعهخحجد", "شسيبلاتنمكط", "ئءؤرىةوزظ", "أإآذَُِّْ؟،.-"]
const HEBREW_ROWS := ["1234567890", "קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ", "'\"-.,?!"]
const JAPANESE_ROWS := ["あいうえおかきくけこ", "さしすせそたちつてと", "なにぬねのはひふへほ", "まみむめもやゆよらりるれろ", "わをんー、。ゃゅょっぁぃぅぇぉゎ゛゜"]
const Lang := preload("res://scripts/lang.gd")
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.66, 0.7, 0.78)
const KEY := Color(0.2, 0.22, 0.3)

var text := ""
var shift := true
var _title: Label
var _field: LineEdit
var _rows_box: VBoxContainer
var _layout_key: Button
var _latin := false
var _keyboard_language := ""
var _letter_keys: Array[Button] = []
var _shift_key: Button


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 1.0)
	style.border_color = Color(0.55, 0.48, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45))
	var heading := HBoxContainer.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	_layout_key = _key("Latin keyboard", func() -> void:
		_latin = not _latin
		_build_keys()
		_refresh(), KEY, Vector2(200, 28))
	heading.add_child(_layout_key)
	box.add_child(heading)

	var field_back := PanelContainer.new()
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = Color(0.12, 0.14, 0.2)
	field_style.border_color = Color(0.35, 0.42, 0.6)
	field_style.set_border_width_all(2)
	field_style.set_corner_radius_all(8)
	field_style.content_margin_left = 12
	field_style.content_margin_right = 12
	field_back.add_theme_stylebox_override("panel", field_style)
	field_back.custom_minimum_size = Vector2(0, 48)
	_field = LineEdit.new()
	_field.focus_mode = Control.FOCUS_NONE   # desktop input still goes through handle_key()
	_field.caret_force_displayed = true
	_field.caret_blink = true
	_field.max_length = MAX_LENGTH
	_field.flat = true
	_field.text_direction = Control.TEXT_DIRECTION_AUTO
	_field.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # names typed by the player are literal
	_field.add_theme_font_size_override("font_size", 26)
	_field.add_theme_color_override("font_color", TEXT)
	field_back.add_child(_field)
	box.add_child(field_back)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	box.add_child(_rows_box)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 5)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	_shift_key = _key("Shift", func() -> void:
		shift = not shift
		_refresh(), KEY, Vector2(110, 50))
	bottom.add_child(_shift_key)
	bottom.add_child(_key("Space", func() -> void: _type(" "), KEY, Vector2(250, 50)))
	bottom.add_child(_key("< Del", _backspace, Color(0.4, 0.22, 0.18), Vector2(110, 50)))
	bottom.add_child(_key("Clear", func() -> void:
		text = ""
		shift = not (Lang.language == "Japanese" and not _latin)
		_refresh(), Color(0.32, 0.24, 0.2), Vector2(90, 50)))
	bottom.add_child(_key("Cancel", func() -> void: cancelled.emit(), Color(0.3, 0.3, 0.32), Vector2(100, 50)))
	bottom.add_child(_key("OK", func() -> void: submitted.emit(text.strip_edges()), Color(0.2, 0.45, 0.25), Vector2(110, 50)))
	box.add_child(bottom)
	_build_keys()
	_refresh()


func _build_keys() -> void:
	_letter_keys.clear()
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	var native := Lang.language in ["Arabic", "Hebrew", "Japanese"]
	_layout_key.visible = native
	var native_label: String = {"Arabic": "Arabic keyboard", "Hebrew": "Hebrew keyboard", "Japanese": "かな"}.get(Lang.language, "Latin keyboard")
	_layout_key.text = native_label if _latin else "Latin keyboard"
	var rows: Array = ROWS.duplicate()
	if ACCENT_KEYS.has(Lang.language):
		rows[rows.size() - 1] = ACCENT_KEYS[Lang.language]
	if native and not _latin:
		rows = {"Arabic": ARABIC_ROWS, "Hebrew": HEBREW_ROWS, "Japanese": JAPANESE_ROWS}[Lang.language]
	_shift_key.disabled = Lang.language in ["Arabic", "Hebrew"] and not _latin
	for row: String in rows:
		if row.is_empty():
			continue
		var line := HBoxContainer.new()
		# Physical key order stays stable; the entry field shapes RTL text itself.
		line.layout_direction = Control.LAYOUT_DIRECTION_LTR
		line.add_theme_constant_override("separation", 5)
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		for i in row.length():
			var character := row[i]
			var width := minf(78, (SIZE.x - 30 - 5 * (row.length() - 1)) / row.length())
			var key := _key(character, func() -> void: _type(character), KEY, Vector2(width, 50))
			key.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			if character != character.to_upper() or (Lang.language == "Japanese" and not _latin):
				key.set_meta("character", character)
				_letter_keys.append(key)
			line.add_child(key)
		_rows_box.add_child(line)


## Starts typing: [param title] above the field, [param initial] already in it.
func open(title: String, initial: String) -> void:
	if _keyboard_language != Lang.language:
		_keyboard_language = Lang.language
		_latin = false
		_build_keys()
	_title.text = title
	text = initial.left(MAX_LENGTH)
	shift = text.is_empty() and not (Lang.language == "Japanese" and not _latin)
	_refresh()


## Desktop: the real keyboard types too. Returns true if the key was used.
func handle_key(event: InputEventKey) -> bool:
	if not event.pressed:
		return false
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			submitted.emit(text.strip_edges())
		KEY_ESCAPE:
			cancelled.emit()
		KEY_BACKSPACE:
			_backspace()
		_:
			if event.unicode >= 32 and text.length() < MAX_LENGTH:
				text += char(event.unicode)
				shift = false
				_refresh()
			else:
				return false
	return true


func _type(character: String) -> void:
	if Lang.language == "Japanese" and not _latin and character in ["゛", "゜"]:
		_apply_kana_mark(character)
		_refresh()
		return
	if text.length() >= MAX_LENGTH:
		return
	text += _uppercase(character) if shift else character
	if shift and character != character.to_upper():
		shift = false   # one-shot, like a phone keyboard
	elif character == " " and text.strip_edges().is_empty():
		shift = true
	_refresh()


func _backspace() -> void:
	text = text.left(maxi(0, text.length() - 1))
	if text.is_empty():
		shift = not (Lang.language == "Japanese" and not _latin)
	_refresh()


func _refresh() -> void:
	_shift_key.text = ("ひらがな" if shift else "カタカナ") if Lang.language == "Japanese" and not _latin else "Shift"
	for key: Button in _letter_keys:
		var character: String = key.get_meta("character")
		key.text = _uppercase(character) if shift else character
	_restyle(_shift_key, Color(0.25, 0.45, 0.7) if shift else KEY)
	_field.text = text
	_field.caret_column = text.length()


func _uppercase(character: String) -> String:
	if Lang.language == "Japanese" and not _latin and character.length() == 1:
		var code := character.unicode_at(0)
		if code >= 0x3041 and code <= 0x3096:
			return String.chr(code + 0x60) # Hiragana -> katakana; punctuation stays unchanged.
	if Lang.language == "Turkish":
		if character == "i":
			return "İ"
		if character == "ı":
			return "I"
	return "ẞ" if character == "ß" else character.to_upper()


## Modify the previous kana in place; store a composed character so one backspace removes it.
func _apply_kana_mark(mark: String) -> void:
	if text.is_empty():
		return
	var code := text.unicode_at(text.length() - 1)
	var katakana := code >= 0x30A1 and code <= 0x30F6
	var last := String.chr(code - 0x60 if katakana else code)
	var bases := "うかきくけこさしすせそたちつてとはひふへほ"
	var voiced := "ゔがぎぐげござじずぜぞだぢづでどばびぶべぼ"
	var semi := "ぱぴぷぺぽ"
	var replacement := ""
	if mark == "゛":
		var at := bases.find(last)
		if at >= 0:
			replacement = voiced[at]
		elif voiced.contains(last):
			replacement = bases[voiced.find(last)]
		elif semi.contains(last):
			replacement = "ばびぶべぼ"[semi.find(last)]
	else:
		var at := "はひふへほ".find(last)
		if at >= 0:
			replacement = semi[at]
		elif "ばびぶべぼ".contains(last):
			replacement = semi["ばびぶべぼ".find(last)]
		elif semi.contains(last):
			replacement = "はひふへほ"[semi.find(last)]
	if not replacement.is_empty():
		if katakana:
			replacement = String.chr(replacement.unicode_at(0) + 0x60)
		text = text.left(text.length() - 1) + replacement


func _key(label: String, on_press: Callable, colour: Color, key_size: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = key_size
	button.add_theme_font_size_override("font_size", 24 if label.length() == 1 else 18)
	button.add_theme_color_override("font_color", TEXT)
	_restyle(button, colour)
	button.pressed.connect(on_press)
	return button


func _restyle(button: Button, colour: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		match state:
			"hover": style.bg_color = colour.lightened(0.22)
			"pressed": style.bg_color = colour.darkened(0.2)
			_: style.bg_color = colour
		style.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, style)
