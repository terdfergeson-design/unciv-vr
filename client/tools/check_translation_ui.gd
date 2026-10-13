extends RefCounted
## Read-only UI review against a loaded game. Use --language=German --load=... --translation-check.
const Lang := preload("res://scripts/lang.gd")
var screens := {}
var review_language := "German"
var prefix := "german"

func capture(id: String, board: Node) -> void:
	var texts: Array[String] = []
	for node: Node in board.find_children("*", "", true, false):
		if (node is Label or node is Button or node is RichTextLabel) and node.is_visible_in_tree():
			texts.append(node.tr(str(node.text)))
	screens[id] = texts

func snapshot(game: Node, id: String) -> void:
	await game.get_tree().create_timer(0.5).timeout
	game.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/" + prefix + "-" + id + ".png"))

func run(game: Node) -> void:
	if game.options.has("translation-gameplay-check"):
		await run_gameplay_check(game)
		return
	if game.options.has("translation-spot-check"):
		await run_spot_check(game)
		return
	review_language = Lang.language
	prefix = review_language.to_lower()
	game._close_alert_card()
	game._set_task_visible(false)
	if not game.state.get("cities", []).is_empty():
		await game.enter_city_view(str(game.state["cities"][0]["name"]))
		var queue: Array = game.city_view_data.get("queue", [])
		if not queue.is_empty():
			await game._select_city_construction(str(queue[0]["name"]), 0)
		await snapshot(game, "city")
		capture("city-info", game.city_info_board)
		capture("production", game.city_prod_board)
		await game.exit_city_view()
	for tab: String in ["tech", "policies", "diplomacy", "religion", "victory"]:
		await game.show_big_screen(tab)
		game.big_screen.position = Vector2(0, 130)   # ignore saved off-screen desktop poses for screenshots
		game.big_screen.scale = Vector2.ONE
		game.big_screen.get_parent().layer = 100   # review this board above saved desktop panels
		await game.get_tree().create_timer(0.2).timeout
		capture(tab, game.big_screen)
		if tab in ["tech", "policies"]:
			for node: Node in game.big_screen._body.find_children("*", "Control", true, false):
				if node.has_meta("diagram_position"):
					assert(node.position.is_equal_approx(node.get_meta("diagram_position")))
			await snapshot(game, tab)
	await game.show_big_screen("diplomacy")
	var civs: Array = game.big_screen._diplomacy.get("civs", [])
	if not civs.is_empty():
		await game._on_big_screen_chosen("civ_open", str(civs[0]["name"]))
		await game.get_tree().create_timer(0.2).timeout
		capture("diplomacy-detail", game.big_screen)
		await game._on_big_screen_chosen("trade_open", str(civs[0]["name"]))
		await game.get_tree().create_timer(0.2).timeout
		capture("trade", game.big_screen)
	game._set_big_visible(false)
	game._set_overview_visible(true)
	for tab: String in ["cities", "stats", "trades", "units", "politics", "resources", "religion", "wonders", "notifications", "espionage"]:
		game.overview_board.show_tab(tab)
		await game._refresh_overview()
		await game.get_tree().create_timer(0.1).timeout
		capture("overview-" + tab, game.overview_board)
	game.overview_board.show_diagram = true
	game.overview_board.show_tab("politics")
	await game._refresh_overview()
	await game.get_tree().process_frame
	capture("politics-diagram", game.overview_board)
	await snapshot(game, "politics")
	game._set_overview_visible(false)
	var sample: String = {"Arabic": "القاهرة Rome 12", "Hebrew": "ירושלים Rome 12"}.get(review_language, "München")
	game.open_keyboard("Save game as", sample, func(_name: String) -> void: pass)
	await game.get_tree().process_frame
	capture("keyboard", game.keyboard)
	await snapshot(game, "keyboard")
	if review_language in ["Arabic", "Hebrew"]:
		assert(game.keyboard._rows_box.get_child(0).layout_direction == Control.LAYOUT_DIRECTION_LTR)
		assert(game.keyboard._field.text == sample)
		game.keyboard._type("ع" if review_language == "Arabic" else "ש")
		game.keyboard._backspace()
		assert(game.keyboard.text == sample)
		game.keyboard._latin = true
		game.keyboard._build_keys()
		await snapshot(game, "keyboard-latin")
	game._close_keyboard()
	game.open_settings()
	for page: String in ["look", "gameplay", "automation", "sound", "panels", "controls", "game", "about"]:
		game.settings_board.show_page(page)
		await game.get_tree().process_frame
		capture("settings-" + page, game.settings_board)
		if page == "look":
			await snapshot(game, "settings")
	# Exercise a language change in the live game without writing the user's settings.
	for language: String in ["English", review_language]:
		game.settings["language"] = language
		await game._send_bridge_settings()
		game._state_revision = -1
		await game.refresh()
		game._refresh_settings()
		game.settings_board.show_page("gameplay")
		await game.get_tree().process_frame
		capture("switch-" + language, game.settings_board)
		assert(game.settings_board.tr("Settings") == {"English": "Settings", "German": "Einstellungen", "Arabic": "الإعدادات", "Hebrew": "הגדרות"}[language])
		assert(game.settings_board.is_layout_rtl() == (language in ["Arabic", "Hebrew"]))
	var file := FileAccess.open("res://../build/" + prefix + "-ui-review.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(screens, "\t"))
	file.close()
	print("Translation UI review completed: %d screens; %s/English/%s switch; no game orders issued." % [screens.size(), review_language, review_language])
	game.get_tree().quit()


## Read-only check of core gameplay boards, without advancing turns or issuing orders.
func run_gameplay_check(game: Node) -> void:
	prefix = Lang.language.to_lower() + "-gameplay-spot"
	game._close_alert_card()
	game._set_task_visible(false)
	game._set_overview_visible(false)
	assert(Lang.language == "Arabic")
	assert(Lang.is_rtl())
	assert(Lang.t("Granary") == "مخزن الحبوب")
	if not game.state.get("units", []).is_empty():
		await game._select_unit(int(game.state["units"][0]["id"]), false)
		game.action_menu.get_parent().layer = 100
		game.action_menu.position = Vector2(20, 20)
		await snapshot(game, "unit")
		capture("unit", game.action_menu)
		capture("empire-status", game.info_panel)
	if not game.state.get("cities", []).is_empty():
		await game.enter_city_view(str(game.state["cities"][0]["name"]))
		game.city_info_board.get_parent().layer = 101
		game.city_prod_board.get_parent().layer = 102
		game.city_info_board.position = Vector2(10, 10)
		game.city_prod_board.position = Vector2(820, 10)
		await game._select_city_construction("Granary", -1)
		await snapshot(game, "city")
		capture("city", game.city_info_board)
		capture("production", game.city_prod_board)
		await game.exit_city_view()
	for tab: String in ["tech", "policies"]:
		await game.show_big_screen(tab)
		game.big_screen.position = Vector2(0, 0)
		game.big_screen.scale = Vector2.ONE
		game.big_screen.get_parent().layer = 103
		if tab == "tech":
			await game._on_big_screen_chosen("tech_select", "Astronomy")
		else:
			await game._on_big_screen_chosen("policy_select", "Tradition")
		await game.get_tree().process_frame
		game.big_screen.size = Vector2(1600, 850)
		await snapshot(game, tab)
		capture(tab, game.big_screen)
		for node: Node in game.big_screen._body.find_children("*", "Control", true, false):
			if node.has_meta("diagram_position"):
				assert(node.position.is_equal_approx(node.get_meta("diagram_position")))
	var file := FileAccess.open("res://../build/" + prefix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(screens, "\t"))
	file.close()
	print("Arabic gameplay spot check complete: unit, city, production, research, policies; no orders or turns issued.")
	game.get_tree().quit()


## Small desktop review; --spot-languages accepts comma-separated Unciv language names.
func run_spot_check(game: Node) -> void:
	game._close_alert_card()
	game._set_task_visible(false)
	game._set_big_visible(false)
	game._set_overview_visible(false)
	for language: String in str(game.options.get("spot-languages", "French,Brazilian_Portuguese")).split(","):
		game.settings["language"] = language
		await game._send_bridge_settings()
		game._state_revision = -1
		await game.refresh()
		prefix = language.to_lower() + "-spot"
		screens = {}
		game.open_settings()
		game.settings_board.position = Vector2(20, 20)
		game.settings_board.scale = Vector2.ONE
		game.settings_board.get_parent().layer = 100
		for page: String in ["look", "gameplay"]:
			game.settings_board.show_page(page)
			await snapshot(game, page)
			capture(page, game.settings_board)
		var expected: String = {"French": "Paramètres", "Brazilian_Portuguese": "Configurações",
			"Spanish": "Ajustes", "Italian": "Impostazioni", "Swedish": "Inställningar"}[language]
		assert(Lang.t("Settings") == expected)
		assert(not game.settings_board.is_layout_rtl())
		var sample: String = {"French": "Orléans", "Brazilian_Portuguese": "São Paulo",
			"Spanish": "Córdoba", "Italian": "Forlì", "Swedish": "Västerås"}[language]
		game.open_keyboard("Save game as", sample, func(_name: String) -> void: pass)
		game.keyboard.get_parent().layer = 101
		await snapshot(game, "keyboard")
		capture("keyboard", game.keyboard)
		assert(game.keyboard._field.text == sample)
		var accent: String = {"French": "ç", "Brazilian_Portuguese": "ã",
			"Spanish": "ñ", "Italian": "è", "Swedish": "å"}[language]
		assert(accent in game.keyboard.ACCENT_KEYS[language])
		game.keyboard._type(accent)
		assert(game.keyboard.text == sample + accent)
		game.keyboard._backspace()
		assert(game.keyboard.text == sample)
		game._close_keyboard()
		var file := FileAccess.open("res://../build/" + prefix + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(screens, "\t"))
		file.close()
		print("Spot check complete: %s; Look, Gameplay, keyboard; no game orders issued." % language)
	game.get_tree().quit()
