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
## follows along; the rest of our own text stays English for now.

static var _translation: Translation
static var language := "English"


## [param entries]: English -> translated; [param tag]: the language's IETF tag ("de-DE"; "en" for English).
static func apply(new_language: String, entries: Dictionary, tag: String) -> void:
	language = new_language
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	var locale := tag.replace("-", "_")
	if entries.is_empty() or locale == "en":
		TranslationServer.set_locale("en")
		return
	var translation := Translation.new()
	translation.locale = locale
	for key: String in entries:
		translation.add_message(key, str(entries[key]))
	TranslationServer.add_translation(translation)
	_translation = translation
	TranslationServer.set_locale(locale)   # every node re-translates its text


## [param text] as the chosen language has it, for text built in code ("%s (%d)" % [Lang.t(name), n]).
static func t(text: String) -> String:
	if _translation == null:
		return text
	return str(TranslationServer.translate(text))
