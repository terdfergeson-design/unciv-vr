# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## The game's language on the client side.
##
## The bridge translates what it writes (messages, popups, descriptions, notifications...) with Unciv's own
## translations. Names - units, buildings, techs, nations, cities, resources - stay English in the protocol, since
## they're also what commands and icons go by. For those the bridge hands over Unciv's plain translations
## (getTranslations), and this puts them into Godot's TranslationServer: every Label, Button and Label3D whose
## whole text is one of Unciv's words or names then shows it in the chosen language, while the node's text (what
## the code reads) stays English. Our own wording that happens to be Unciv's ("Next turn", "Found city", "Close")
## follows along. Frontend catalogs supply the VR-specific wording.

static var _translation: Translation
static var language := "English"
const FRONTEND_LANGUAGES := {
	"German": {"tag": "de", "label": "Deutsch"},
	"Arabic": {"tag": "ar", "label": "العربية"},
	"Hebrew": {"tag": "he", "label": "עברית"},
	"Spanish": {"tag": "es", "label": "Español"},
	"French": {"tag": "fr", "label": "Français"},
	"Italian": {"tag": "it", "label": "Italiano"},
	"Brazilian_Portuguese": {"tag": "pt_BR", "label": "Português (Brasil)"},
	"Swedish": {"tag": "sv", "label": "Svenska"},
	"Portuguese": {"tag": "pt_PT", "label": "Português (Portugal)"},
	"Dutch": {"tag": "nl", "label": "Nederlands"},
	"Polish": {"tag": "pl", "label": "Polski"},
	"Turkish": {"tag": "tr", "label": "Türkçe"},
	"Indonesian": {"tag": "id", "label": "Bahasa Indonesia"},
	"Japanese": {"tag": "ja", "label": "日本語"},
	"Russian": {"tag": "ru", "label": "Русский"},
	"Ukrainian": {"tag": "uk", "label": "Українська"},
	"Czech": {"tag": "cs", "label": "Čeština"},
	"Hungarian": {"tag": "hu", "label": "Magyar"},
	"Romanian": {"tag": "ro", "label": "Română"},
	"Croatian": {"tag": "hr", "label": "Hrvatski"},
	"Catalan": {"tag": "ca", "label": "Català"},
	"Galician": {"tag": "gl", "label": "Galego"},
	"Norwegian": {"tag": "nb", "label": "Norsk"},
	"Esperanto": {"tag": "eo", "label": "Esperanto"},
}


static func frontend_tag(name: String, fallback := "en") -> String:
	return str(FRONTEND_LANGUAGES.get(name, {}).get("tag", fallback))


static func is_rtl() -> bool:
	return TranslationServer.get_locale().get_slice("_", 0) in ["ar", "he"]


## Display-only isolation prevents Latin names from reordering adjoining RTL punctuation.
static func display_value(value: String) -> String:
	var translated := t(value)
	return "\u2068" + translated + "\u2069" if is_rtl() and not translated.is_empty() else translated


## [param entries]: English -> translated; [param tag]: the language's IETF tag ("de-DE"; "en" for English).
static func apply(new_language: String, entries: Dictionary, tag: String) -> void:
	language = new_language
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	var locale := tag.replace("-", "_")
	if locale.get_slice("_", 0) == "en":
		TranslationServer.set_locale("en")
		return
	var translation := Translation.new()
	translation.locale = locale
	for key: String in entries:
		translation.add_message(key, str(entries[key]))
	# Merge the frontend last so shared words have one consistent translation.
	for path: String in ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray()):
		var frontend := load(path) as Translation
		if frontend == null:
			continue
		# Only the merged catalog should participate in lookup. Otherwise Godot can
		# fall back to another region's registered catalog for missing messages.
		TranslationServer.remove_translation(frontend)
		var frontend_locale := frontend.get_locale().replace("-", "_")
		# Regional catalogs apply only to that region; a generic catalog can serve any region.
		# In particular, Brazilian Portuguese must not replace European Portuguese wording.
		if frontend_locale == locale or (not frontend_locale.contains("_") and frontend_locale == locale.get_slice("_", 0)):
			for key: String in frontend.get_message_list():
				translation.add_message(key, frontend.get_message(key))
	TranslationServer.add_translation(translation)
	_translation = translation
	TranslationServer.set_locale(locale)   # every node re-translates its text


## [param text] as the chosen language has it, for text built in code ("%s (%d)" % [Lang.t(name), n]).
static func t(text: String) -> String:
	var translated := str(TranslationServer.translate(text))
	# Layout padding is not wording: reuse an unpadded key when no exact entry exists.
	var plain := text.strip_edges()
	if translated == text and plain != text and plain != "":
		var inner := str(TranslationServer.translate(plain))
		if inner != plain:
			return text.replace(plain, inner)
	return translated


## Translate display arguments without changing identifiers used in game commands.
static func format(source: String, arguments: Variant) -> String:
	var values: Variant = arguments
	if arguments is Array:
		values = arguments.map(func(value: Variant) -> Variant: return display_value(value) if value is String else value)
	elif arguments is String:
		values = display_value(arguments)
	return t(source) % values


## Translate each member before joining; the completed sentence is not a catalog key.
static func join(separator: String, values: Array) -> String:
	return separator.join(values.map(func(value: Variant) -> String: return display_value(str(value))))
