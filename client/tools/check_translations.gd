extends SceneTree
## Run with Godot --headless --path client --script res://tools/check_translations.gd.
const Lang := preload("res://scripts/lang.gd")
const Panels := preload("res://scripts/panels.gd")

func _initialize() -> void:
	Lang.apply("German", {"Warrior": "Krieger", "Gameplay": "different engine wording"}, "de-DE")
	assert(Lang.t("Settings") == "Einstellungen")
	assert(Lang.t("Gameplay") == "Spielablauf")
	assert(Lang.t("     You can adopt a policy!") == "     Du kannst eine Sozialpolitik einführen!")
	assert(Lang.format("Promote %s", "Warrior") == "Krieger befördern")
	assert(Lang.join(", ", ["Warrior", "Settings"]) == "Krieger, Einstellungen")
	assert(Panels.display("Units ({count})", {}, {"count": 2}) == "Einheiten (2)")
	assert(Panels.display("{turns#'turn'}", {"turns": 1}) == "1 Runde")
	assert(Panels.display("{turns#'turn'}", {"turns": 2}) == "2 Runden")
	assert(Panels.display("{action|'Waiting for orders'}", {}) == "Wartet auf Befehle")
	assert(Panels.fill("{name}", {"name": "Warrior"}) == "Warrior")
	assert(Panels.click_for({"click": {"do": "open_city", "name": "{name}"}}, {"name": "Warrior"})["name"] == "Warrior")
	var catalog := load("res://translations/de.po") as Translation
	var spec := RegEx.new()
	spec.compile("%(?:[-+0-9.]*[sdfi]|%)")
	for source: String in catalog.get_message_list():
		var target := str(catalog.get_message(source))
		assert(not target.is_empty(), source)
		var original := spec.search_all(source)
		var translated := spec.search_all(target)
		assert(original.size() == translated.size(), source)
		var args: Array = []
		for i in original.size():
			assert(original[i].get_string() == translated[i].get_string(), source)
			var token: String = original[i].get_string()
			if token != "%%":
				args.append("Warrior" if token.ends_with("s") else 2)
		if not args.is_empty():
			assert(not Lang.format(source, args).is_empty(), source)
	Lang.apply("English", {}, "en")
	assert(Lang.t("Settings") == "Settings")
	assert(Lang.format("Promote %s", "Warrior") == "Promote Warrior")
	assert(Panels.display("Units ({count})", {}, {"count": 2}) == "Units (2)")
	Lang.apply("German", {}, "de-DE")
	assert(Lang.t("Settings") == "Einstellungen")
	print("German catalog, formatted messages, panel display, raw commands and language switching passed: %d entries" % catalog.get_message_list().size())
	for name: String in ["Arabic", "Hebrew"]:
		Lang.apply(name, {}, Lang.frontend_tag(name))
		var rtl_catalog := load("res://translations/%s.po" % Lang.frontend_tag(name)) as Translation
		assert(Lang.is_rtl())
		assert(rtl_catalog.get_message_list().size() == catalog.get_message_list().size())
		assert(Lang.t("Settings") == ("الإعدادات" if name == "Arabic" else "הגדרות"))
		for source: String in catalog.get_message_list():
			var target := str(rtl_catalog.get_message(source))
			assert(not target.is_empty(), source)
			var original := spec.search_all(source)
			var translated := spec.search_all(target)
			assert(original.size() == translated.size(), source)
			var args: Array = []
			for i in original.size():
				assert(original[i].get_string() == translated[i].get_string(), source)
				var token: String = original[i].get_string()
				if token != "%%":
					args.append("Rome" if token.ends_with("s") else -2)
			if not args.is_empty():
				assert(not Lang.format(source, args).is_empty(), source)
		assert(Panels.fill("{name}", {"name": "Rome"}) == "Rome")
		assert(Panels.display("{turns#'turn'}", {"turns": 2}) == Lang.format("Turns: %s", "2"))
		assert(Lang.format("Researching %s", "Pottery").contains("\u2068Pottery\u2069"))
		var font := load("res://fonts/ui_font.tres") as Font
		for code: int in ("العربية שלום").to_utf32_buffer().to_int32_array():
			assert(font.has_char(code), "Missing glyph: " + char(code))
		print("%s: %d entries, placeholders, mixed text, raw commands and font coverage passed" % [name, rtl_catalog.get_message_list().size()])
	Lang.apply("English", {}, "en")
	assert(not Lang.is_rtl())
	quit()
