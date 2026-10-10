# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Developer scenarios (--scenario=<name>): set up a situation that takes a long game to reach, using the bridge's
## debug commands (only available when the bridge was started by hand with --debug), then drive the client through
## it the way a player would and print what happened ("SCENARIO: ..."). Used for testing; players never see this.

var main: Node


func _init(owner: Node) -> void:
	main = owner


func debug(params: Dictionary) -> Dictionary:
	var reply: Dictionary = await main.bridge.request("debug", params)
	if not reply.ok:
		print("SCENARIO: debug %s failed: %s" % [params.get("command"), reply.error])
		return {}
	return reply.result


func say(text: String) -> void:
	print("SCENARIO: " + text)


## Founds the capital with the first settler and picks research, like a player's first turn.
func start_civ() -> Vector2i:
	for alert: Dictionary in main.state.get("alerts", []):
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	for u: Dictionary in main.state.get("units", []):
		if u["name"] == "Settler":
			await main._select_unit(int(u["id"]))
			await main.found_city()
			break
	await main.bridge.request("setResearch", {"tech": "Pottery"})
	await main.refresh()
	var cities: Array = main.state.get("cities", [])
	if cities.is_empty():
		say("no city founded")
		return Vector2i.ZERO
	return Vector2i(int(cities[0]["x"]), int(cities[0]["y"]))


func run(name: String) -> void:
	say("start " + name)
	match name:
		"blockers": await blockers()
		"alerts": await alerts()
		"alerts_show": await alerts(false)
		"conquest": await conquest()
		"religion": await religion()
		"great_person": await great_person()
		"victory": await victory()
		"diplomacy": await diplomacy()
		"unit_actions": await unit_actions()
		"bombard": await bombard()
		"espionage": await espionage()
		"sequences": await sequences()
		"cityview_production": await cityview_production()
		"cityview_pick": await cityview_production(true)
		"screens": await screens()
		"tiles": await tiles()
		"battles": await battles()
		"make_test_save": await make_test_save()
		"playback": await playback()
		"surroundings": await surroundings()
		"settings_board": await settings_board()
		"stacking": await stacking()
		"unit_death": await unit_death()
		_: say("unknown scenario " + name)
	say("end " + name)


func blockers() -> void:
	var capital := await start_civ()
	await main.bridge.request("setResearch", {"tech": "Pottery"})
	await main.refresh()
	say("blockers at start: %s" % [main.state.get("blockers", []).map(func(b: Dictionary) -> String: return b["type"])])
	# A city with nothing to build (Unciv: a construction finished with "Auto-assign city production" off):
	# End turn takes you to the city instead
	await main._handle_blocker({"type": "PickConstruction", "text": "Pick construction", "x": capital.x, "y": capital.y})
	say("PickConstruction opens: city card '%s', status '%s'" % [main.selected_city.get("name", "-"), main._status_text])
	await main._handle_blocker({"type": "PickTech", "text": "Pick a tech"})
	say("PickTech opens: big screen '%s' shown %s" % [main.big_screen.tab, main._big_screen_shown()])
	await main.city_command("produce", "Warrior")
	await main.end_turn()
	say("after picking production and End turn: turn %d" % int(main.state.get("turn", 0)))
	# Confirmation setting
	main.settings["confirmNextTurn"] = true
	await main.end_turn()
	say("confirm on, first press: turn %d, status '%s'" % [int(main.state.get("turn", 0)), main._status_text])
	await main.end_turn()
	say("second press: turn %d" % int(main.state.get("turn", 0)))
	main.settings["confirmNextTurn"] = false


func alerts(answer := true) -> void:
	await start_civ()
	var others: Array = main.state.get("civs", []).filter(func(c: Dictionary) -> bool:
		return not c.get("isCityState", false) and not c.get("isBarbarian", false) and c["name"] != main.state.get("playerCiv"))
	var other: String = others[0]["name"]
	await debug({"command": "meet", "other": other})
	await debug({"command": "popupAlert", "type": "DeclarationOfFriendship", "value": other})
	await debug({"command": "popupAlert", "type": "DemandToStopSettlingCitiesNear", "value": other})
	await main.refresh()
	say("alerts: %s, shown '%s', blockers %s" % [main.state.get("alerts", []).map(func(a: Dictionary) -> String: return a["type"]), main._alert_shown_key,
		main.state.get("blockers", []).map(func(b: Dictionary) -> String: return b["type"])])
	await main.end_turn()
	say("End turn with messages waiting: turn %d, status '%s'" % [int(main.state.get("turn", 0)), main._status_text])
	if not answer:
		var first: Dictionary = main.state["alerts"][0]
		await main.answer_alert("%s|%s" % [first["key"], first["options"][0]["id"]])   # the first contact; leave the friendship offer up
		return
	var guard := 0
	while not main.state.get("alerts", []).is_empty() and guard < 10:
		guard += 1
		var alert: Dictionary = main.state["alerts"][0]
		var option: String = alert["options"][0]["id"]
		say("answering %s with %s" % [alert["type"], option])
		await main.answer_alert("%s|%s" % [alert["key"], option])
	say("alerts left %d, status '%s'" % [main.state.get("alerts", []).size(), main._status_text])


func conquest() -> void:
	await start_civ()
	await main.end_turn()
	await debug({"command": "reveal"})
	await main.refresh()
	var target := {}
	for tile: Dictionary in main.state.get("tiles", []):
		if tile.has("city") and tile["city"]["civ"] != main.state.get("playerCiv"):
			var civ: Dictionary = {}
			for c: Dictionary in main.state.get("civs", []):
				if c["name"] == tile["city"]["civ"]:
					civ = c
			if not civ.get("isCityState", false):
				target = tile
				break
	if target.is_empty():
		say("no enemy city found")
		return
	var key := Vector2i(int(target["x"]), int(target["y"]))
	await debug({"command": "war", "other": target["city"]["civ"]})
	for attempt in 3:
		var spawned := await debug({"command": "spawnUnit", "unit": "Swordsman", "x": key.x + 1, "y": key.y})
		await debug({"command": "cityHealth", "city": target["city"]["name"], "health": 1})
		await main.refresh()
		await main._select_unit(int(spawned.get("result", "0")))
		await main.click_tile(key)   # aim
		await main.click_tile(key)   # attack
		if not main.state.get("alerts", []).filter(func(a: Dictionary) -> bool: return a["type"] == "CityConquered").is_empty():
			break
	var conquered: Array = main.state.get("alerts", []).filter(func(a: Dictionary) -> bool: return a["type"] == "CityConquered")
	say("conquest alert: %s, card shown: %s, options %s" % [not conquered.is_empty(), main._alert_card_visible(),
		conquered[0]["options"].map(func(o: Dictionary) -> String: return "%s%s" % [o["id"], "" if o.get("enabled", true) else "(off)"]) if not conquered.is_empty() else []])
	await main.end_turn()
	say("End turn before deciding: status '%s'" % main._status_text)


## Saves and loads the game through the main menu, like a player quitting mid-decision and coming back.
func save_load() -> void:
	var before: Array = main.state.get("alerts", []).map(func(a: Dictionary) -> String: return a["type"])
	await main.bridge.request("saveGame", {"name": "scenario save"})
	await main.open_lobby()
	await main._on_lobby_choice("load_save", "scenario save")
	await main.get_tree().create_timer(0.5).timeout
	say("save and load: alerts %s -> %s, card shown %s" % [before, main.state.get("alerts", []).map(func(a: Dictionary) -> String: return a["type"]),
		main._alert_card_visible()])


func conquest_answer(option: String) -> void:
	for alert: Dictionary in main.state.get("alerts", []):
		if alert["type"] == "CityConquered":
			await main.answer_alert("%s|%s" % [alert["key"], option])
			say("answered %s: status '%s'" % [option, main._status_text])


func religion() -> void:
	var capital := await start_civ()
	await debug({"command": "addStat", "stat": "Faith", "amount": 300})
	await main.refresh()
	say("blockers: %s" % [main.state.get("blockers", []).map(func(b: Dictionary) -> String: return b["type"])])
	await main.end_turn()
	say("End turn opened the big screen on '%s' (shown %s), mode %s" % [main.big_screen.tab, main._big_screen_shown(), main.big_screen._religion.get("mode")])
	var beliefs: Array = main.big_screen._religion.get("beliefs", []).filter(func(b: Dictionary) -> bool: return b.get("available", false))
	await main._on_big_screen_chosen("religion_belief", beliefs[0]["name"])
	await main._on_big_screen_chosen("religion_confirm", "")
	say("pantheon founded: state %s, blockers %s" % [main.big_screen._religion.get("state"), main.state.get("blockers", []).map(func(b: Dictionary) -> String: return b["type"])])
	# A Great Prophet in the capital founds a religion
	var prophet := await debug({"command": "spawnUnit", "unit": "Great Prophet", "x": capital.x, "y": capital.y})
	await main.refresh()
	await main._select_unit(int(prophet.get("result", "0")))
	var found: Array = main.selected_unit.get("actions", []).filter(func(a: Dictionary) -> bool: return a["type"] == "FoundReligion")
	say("prophet can found: %s (at capital: %s)" % [not found.is_empty() and found[0].get("enabled", false), main._selected_key() == capital])
	if found.is_empty() or not found[0].get("enabled", false):
		await main.move_selected_to(capital)
		await main._select_unit(int(prophet.get("result", "0")))
		found = main.selected_unit.get("actions", []).filter(func(a: Dictionary) -> bool: return a["type"] == "FoundReligion")
	if not found.is_empty():
		await main.unit_action("FoundReligion|" + str(found[0].get("title", "")))
	await main.refresh()
	say("after using the prophet: blockers %s" % [main.state.get("blockers", []).map(func(b: Dictionary) -> String: return b["type"])])
	await main.end_turn()
	var data: Dictionary = main.big_screen._religion
	say("religion picker: mode %s, slots %s, %d icons" % [data.get("mode"), data.get("slots", []), data.get("icons", []).size()])
	var free_icon: Array = data.get("icons", []).filter(func(i: Dictionary) -> bool: return i.get("available", false))
	await main._on_big_screen_chosen("religion_icon", free_icon[0]["name"])
	for slot in data.get("slots", []).size():
		await main._on_big_screen_chosen("religion_slot", str(slot))
		var slot_type: String = data["slots"][slot]
		for b: Dictionary in data.get("beliefs", []):
			if b.get("available", false) and (b["type"] == slot_type or slot_type == "Any") and not main.big_screen.religion_picks.has(b["name"]):
				await main._on_big_screen_chosen("religion_belief", b["name"])
				break
	main.big_screen.religion_name = "Smokeism"
	say("picks %s, icon %s" % [main.big_screen.religion_picks, main.big_screen.religion_icon])


func religion_confirm() -> void:
	await main._on_big_screen_chosen("religion_confirm", "")
	say("religion founded: %s (%s), status '%s'" % [main.big_screen._religion.get("displayName"), main.big_screen._religion.get("state"), main._status_text])


func great_person() -> void:
	await start_civ()
	await debug({"command": "freeGreatPerson"})
	await main.refresh()
	await main.end_turn()
	say("great person card shown: %s, status '%s'" % [main._popup_kind if main._xr_mode else str(main._alert_layer != null and main._alert_layer.visible), main._status_text])


func great_person_pick() -> void:
	await main.choose_great_person("Great Scientist")
	say("picked: selected %s, blockers %s" % [main.selected_unit.get("name", "-"), main.state.get("blockers", []).map(func(b: Dictionary) -> String: return b["type"])])


func victory() -> void:
	await start_civ()
	for i in 3:
		await main.end_turn()
	await main.show_big_screen("victory")
	say("victory: %d victories, rankings %s, charts %s" % [main.big_screen._victory.get("ourStatus", []).size(),
		main.big_screen._victory.get("showRankings"), main.big_screen._victory.get("showCharts")])


func diplomacy() -> void:
	await start_civ()
	for c: Dictionary in main.state.get("civs", []):
		if c["name"] != main.state.get("playerCiv") and not c.get("isBarbarian", false):
			await debug({"command": "meet", "other": c["name"]})
	await debug({"command": "addStat", "stat": "Gold", "amount": 600})
	await main.refresh()
	await main.show_big_screen("diplomacy")
	var cs: Array = main.big_screen._diplomacy.get("civs", []).filter(func(c: Dictionary) -> bool: return c.get("isCityState", false))
	if cs.is_empty():
		say("no city-state met")
		return
	var name: String = cs[0]["name"]
	await main._on_big_screen_chosen("civ_open", name)
	await main._on_big_screen_chosen("diplo_action", name + "|giftGold|250")
	say("gift: status '%s'" % main._status_text)
	await main._on_big_screen_chosen("diplo_arm", name + "|pledgeProtection")
	await main._on_big_screen_chosen("diplo_action", name + "|pledgeProtection")
	say("pledge: status '%s'" % main._status_text)


func diplomacy_major() -> void:
	var majors: Array = main.big_screen._diplomacy.get("civs", []).filter(func(c: Dictionary) -> bool: return not c.get("isCityState", false))
	if majors.is_empty():
		return
	await main._on_big_screen_chosen("civ_open", majors[0]["name"])
	say("major civ page for %s: demands %d" % [majors[0]["name"], majors[0].get("demands", []).size()])


func unit_actions() -> void:
	var capital := await start_civ()
	await debug({"command": "addTech", "tech": "The Wheel"})
	var worker := await debug({"command": "spawnUnit", "unit": "Worker", "x": capital.x, "y": capital.y})
	var warrior := await debug({"command": "spawnUnit", "unit": "Warrior", "x": capital.x + 1, "y": capital.y})
	await main.refresh()
	await main._select_unit(int(worker.get("result", "0")))
	say("worker actions: %s" % [main.selected_unit.get("actions", []).map(func(a: Dictionary) -> String: return "%s%s" % [a["type"], "*" if a.get("target", "") == "tile" else ""])])
	var road: Array = main.selected_unit.get("actions", []).filter(func(a: Dictionary) -> bool: return a["type"] == "ConnectRoad")
	if not road.is_empty():
		await main.unit_action("ConnectRoad|" + str(road[0]["title"]))
		say("picking for road: %s" % main._pick.get("kind", "-"))
		var spot := capital
		for tile: Dictionary in main.state.get("tiles", []):
			var k := Vector2i(int(tile["x"]), int(tile["y"]))
			if tile.get("explored", false) and not tile.has("city") and str(tile.get("base", "")) in ["Grassland", "Plains", "Desert", "Tundra"] \
					and (k - capital).length() > 2.5 and (k - capital).length() < 4.0:
				spot = k
				break
		await main.click_tile(spot)
		say("road: status '%s', picking %s" % [main._status_text, not main._pick.is_empty()])
	# Disband needs a second click
	await main._select_unit(int(warrior.get("result", "0")))
	var disband: Array = main.selected_unit.get("actions", []).filter(func(a: Dictionary) -> bool: return a["type"] == "DisbandUnit")
	if not disband.is_empty():
		var key := "DisbandUnit|" + str(disband[0]["title"])
		main._on_menu_chosen("action_arm", key)
		say("disband armed: '%s'" % main.action_menu.armed_action)
		await main._on_menu_chosen("action", key + "|confirm")
		say("disbanded: unit still selected %s, status '%s'" % [not main.selected_unit.is_empty() and int(main.selected_unit["id"]) == int(warrior.get("result", "0")), main._status_text])


func bombard() -> void:
	var capital := await start_civ()
	var others: Array = main.state.get("civs", []).filter(func(c: Dictionary) -> bool:
		return not c.get("isCityState", false) and not c.get("isBarbarian", false) and c["name"] != main.state.get("playerCiv"))
	var enemy: String = others[0]["name"]
	await debug({"command": "war", "other": enemy})
	for offset: Vector2i in [Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2), Vector2i(-2, 0), Vector2i(0, -2), Vector2i(1, 2)]:
		var placed := await debug({"command": "spawnUnit", "unit": "Warrior", "x": capital.x + offset.x, "y": capital.y + offset.y, "civ": enemy})
		if not placed.is_empty():
			break
	await main.refresh()
	await main.open_city(capital)
	say("city can bombard: %s, %d targets" % [main.selected_city.get("canBombard"), main.selected_city.get("bombardTargets", []).size()])
	await main._on_menu_chosen("bombard", main.selected_city.get("name", ""))
	var targets: Array = main._pick.get("targets", [])
	if not targets.is_empty():
		await main.click_tile(targets[0])
	say("bombard: status '%s'" % main._status_text)


func espionage() -> void:
	main._set_overview_visible(true)
	main.overview_board.show_tab("espionage")
	await main._refresh_overview()
	say("espionage tab: %s" % main.overview_board.data.get("enabled"))


# region realistic input sequences ---------------------------------------------------------------
# Things a player does in an order nobody planned for: switching units halfway through an action, pressing
# buttons twice, popups arriving while something else is open. Each check prints OK or PROBLEM.

var _problems := 0


func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_problems += 1
	say("%s %s%s" % ["OK     " if ok else "PROBLEM", what, "" if detail == "" else "  (" + detail + ")"])


## Waits until the client has finished what a click started (requests answered, busy cleared).
func settle(seconds := 0.6) -> void:
	await main.get_tree().create_timer(seconds).timeout
	var guard := 0
	while main.busy and guard < 200:
		guard += 1
		await main.get_tree().create_timer(0.1).timeout


## Clicks the first visible button on [param menu] whose text starts with [param prefix], like a player would.
func press(menu: Control, prefix: String) -> bool:
	var button := _find_button(menu, prefix)
	if button == null:
		say("(no '%s' button on the card)" % prefix)
		return false
	button.pressed.emit()
	await settle()
	return true


func _find_button(node: Node, prefix: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).disabled \
			and ((node as Button).text.begins_with(prefix) or _has_label(node, prefix)):
		return node
	for child in node.get_children():
		var found := _find_button(child, prefix)
		if found != null:
			return found
	return null


## The great person / vote / alert card is up (VR: the floating popup; desktop: the centred card).
func _card_up(kind: String) -> bool:
	if main._xr_mode:
		return main._popup_kind == kind or (kind == "alert" and main._popup_kind == "alert_tile")
	return main._alert_layer != null and main._alert_layer.visible


## A row button's text lives in labels inside it.
func _has_label(node: Node, prefix: String) -> bool:
	for child in node.get_children():
		if child is Label and (child as Label).text.begins_with(prefix):
			return true
		if not child is Button and _has_label(child, prefix):
			return true
	return false


func _unit_exists(id: int) -> bool:
	return main.state.get("units", []).any(func(u: Dictionary) -> bool: return int(u["id"]) == id)


func _spawn(unit: String, at: Vector2i, civ := "") -> int:
	var params := {"command": "spawnUnit", "unit": unit, "x": at.x, "y": at.y}
	if civ != "":
		params["civ"] = civ
	var r := await debug(params)
	return int(r.get("result", "-1"))


## A free land tile near [param centre] (no unit, no city), at about [param distance].
func _free_tile(centre: Vector2i, distance: float) -> Vector2i:
	for tile: Dictionary in main.state.get("tiles", []):
		var k := Vector2i(int(tile["x"]), int(tile["y"]))
		var d := Vector2(k - centre).length()
		if tile.get("explored", false) and not tile.has("city") and not tile.has("units") and not tile.has("unit") \
				and str(tile.get("base", "")) in ["Grassland", "Plains", "Desert", "Tundra"] and str(tile.get("terrainFeature", "")) == "" \
				and d >= distance - 0.5 and d <= distance + 1.0:
			return k
	return centre


func sequences() -> void:
	var capital := await start_civ()
	await debug({"command": "addTech", "tech": "The Wheel"})
	await debug({"command": "addStat", "stat": "Gold", "amount": 2000})
	await debug({"command": "reveal"})
	await main.refresh()
	var menu: Control = main.action_menu
	var a := await _spawn("Warrior", capital + Vector2i(1, 0))
	var b := await _spawn("Warrior", capital + Vector2i(0, 1))
	var worker := await _spawn("Worker", capital)
	await main.refresh()

	# 1. Disband armed on one unit, then switching to another and clicking Disband once must not disband it
	await main._select_unit(a)
	await press(menu, "Disband")
	check("first Disband click only arms", _unit_exists(a), main.action_menu.armed_action)
	await main._select_unit(b)
	await press(menu, "Disband")
	await main.refresh()
	check("armed Disband doesn't carry over to another unit", _unit_exists(b))
	main._deselect()

	# 2. A tile pick (road to...) abandoned by switching units with Next unit: the pick must end
	await main._select_unit(worker)
	var started := await press(menu, "Connect road")
	check("road pick started", started and not main._pick.is_empty())
	await main.cycle_unit(1)
	await settle()
	check("switching units ends the pick", main._pick.is_empty(), str(main._pick.get("kind", "")))
	var far := _free_tile(capital, 3.0)
	await main.click_tile(far)
	await settle()
	check("a map click after switching aims the new unit instead of building a road", main._pick.is_empty() and main.hex_map.aim_key() == far,
		"status '%s'" % main._status_text)
	main._deselect()

	# 3. Pick started, then the player clicks one of their own units on the map
	await main._select_unit(worker)
	await press(menu, "Connect road")
	await main.click_tile(capital + Vector2i(1, 0))   # warrior A's tile
	await settle()
	say("clicking a unit while picking a road: picking %s, selected %s, status '%s'" % [not main._pick.is_empty(),
		main.selected_unit.get("name", "-"), main._status_text])
	await main.cancel_pick()
	main._deselect()

	# 4. End turn pressed twice in a row (double click / impatient second press)
	var turn := int(main.state.get("turn", 0))
	main.end_turn()
	await main.end_turn()
	await settle(1.0)
	check("double End turn advances one turn", int(main.state.get("turn", 0)) == turn + 1, "turn %d -> %d" % [turn, int(main.state.get("turn", 0))])

	# 5. Double click on a move target: one move, no error
	await main._select_unit(a)
	var dest := _free_tile(main._selected_key(), 1.0)
	await main.click_tile(dest)
	main.click_tile(dest)
	await main.click_tile(dest)
	await settle()
	check("double click to move doesn't error", not main._status_text.to_lower().contains("error"), main._status_text)
	main._deselect()

	# 6. A popup arrives while the city view is open: it waits, then shows when you leave
	var cities: Array = main.state.get("cities", [])
	var others: Array = main.state.get("civs", []).filter(func(c: Dictionary) -> bool:
		return not c.get("isCityState", false) and not c.get("isBarbarian", false) and c["name"] != main.state.get("playerCiv"))
	var other: String = others[0]["name"]
	await debug({"command": "meet", "other": other})
	await main.refresh()
	for alert: Dictionary in main.state.get("alerts", []):   # the first-contact message
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	await main.enter_city_view(str(cities[0]["name"]))
	await debug({"command": "popupAlert", "type": "DeclarationOfFriendship", "value": other})
	await main.refresh()
	check("no popup over the city view", not main._alert_card_visible())
	await main.exit_city_view()
	await settle()
	check("popup shows after leaving the city view", main._alert_card_visible(), "shown key '%s'" % main._alert_shown_key)

	# 7. The keyboard opened (rename) while the popup is up, then cancelled: the popup is still there to answer
	await main._select_unit(b)
	await main.rename_unit(b)
	await settle()
	main._close_keyboard()
	await settle()
	check("popup still answerable after the keyboard", main._alert_card_visible() or not main.state.get("alerts", []).is_empty(),
		"card %s, alerts %d" % [main._alert_card_visible(), main.state.get("alerts", []).size()])
	var friendship: Array = main.state.get("alerts", [])
	if not friendship.is_empty():
		await main.answer_alert("%s|%s" % [friendship[0]["key"], friendship[0]["options"][-1]["id"]])
	check("alert answered, card closed", not main._alert_card_visible() and main.state.get("alerts", []).is_empty())
	main._deselect()

	# 8. City card: buy while a unit is selected, then refresh, then buy again
	await main._select_unit(a)
	await main.open_city(capital, true)
	await main.city_command("buy", "Worker")
	await main.refresh()
	await main.city_command("buy", "Warrior")
	await settle()
	check("buying twice with a unit selected keeps working", not main._status_text.to_lower().contains("error"), main._status_text)
	main._deselect()

	# 9. Bombard pick, then the player switches to a unit with Next unit: the pick ends
	await debug({"command": "war", "other": other})
	await _spawn("Warrior", capital + Vector2i(2, 0), other)
	await _spawn("Warrior", capital + Vector2i(0, 2), other)
	await main.refresh()
	await main.open_city(capital)
	main._on_menu_chosen("bombard", str(main.selected_city.get("name", "")))
	await settle()
	var bombard_started: bool = main._pick.get("kind", "") == "bombard"
	await main.cycle_unit(1)
	await settle()
	check("Next unit ends a bombard pick", main._pick.is_empty(), "started %s" % bombard_started)
	main._deselect()

	# 10. Stale unit: its card is up, the unit dies some other way, then an action is clicked
	var doomed := await _spawn("Scout", _free_tile(capital, 2.0))
	await main.refresh()
	await main._select_unit(doomed)
	await main.bridge.request("unitAction", {"unitId": doomed, "action": "DisbandUnit", "confirm": true})
	await press(menu, "Explore")
	await settle()
	check("clicking an action of a unit that's gone is harmless", main.selected_unit.is_empty() or int(main.selected_unit.get("id", -1)) != doomed,
		"status '%s'" % main._status_text)

	# 11. Great person card up, the player clicks around the map, then End turn brings it back
	await debug({"command": "freeGreatPerson"})
	await main.refresh()
	await main.end_turn()
	await settle()
	var gp_shown: bool = _card_up("great_person")
	await main.click_tile(_free_tile(capital, 2.0))
	await main.click_tile(capital)
	await settle()
	main._deselect()
	await main.end_turn()
	await settle()
	check("End turn reopens the great person choice", gp_shown and _card_up("great_person"),
		"first %s, status '%s'" % [gp_shown, main._status_text])
	await main.choose_great_person("Great Scientist")
	check("great person chosen", main.state.get("blockers", []).filter(func(x: Dictionary) -> bool: return x["type"] == "PickGreatPerson").is_empty())

	# 12. Main menu with a popup waiting, then Resume: the popup comes back
	await debug({"command": "popupAlert", "type": "DemandToStopSettlingCitiesNear", "value": other})
	await main.refresh()
	await main.open_lobby()
	await settle()
	check("popup card hidden in the main menu", not main._alert_card_visible())
	await main._on_lobby_choice("lobby_resume", "")
	await settle()
	check("popup back after Resume", main._alert_card_visible(), "alerts %d" % main.state.get("alerts", []).size())

	# 12b. Main menu from inside the city view (Settings -> Main menu), then Resume: back on the map, nothing left over
	await main.enter_city_view(str(cities[0]["name"]))
	await main.open_lobby()
	await settle()
	check("city view closed by the main menu", not main._city_view and not main.city_boards_visible() if main.has_method("city_boards_visible") else not main._city_view)
	await main._on_lobby_choice("lobby_resume", "")
	await settle()
	check("resumed on the map after leaving from the city view", not main._in_lobby and not main._city_view and main.hex_map.visible)

	# 13. Save with a popup waiting, load it again: the popup is still there and answerable
	await main.bridge.request("saveGame", {"name": "sequence test"})
	await main._on_lobby_choice("load_save", "sequence test")
	await settle()
	var after_load: Array = main.state.get("alerts", [])
	check("popup survives save and load", not after_load.is_empty() and main._alert_card_visible(), "alerts %d" % after_load.size())
	if not after_load.is_empty():
		await main.answer_alert("%s|%s" % [after_load[0]["key"], after_load[0]["options"][0]["id"]])
		check("answered after load", main.state.get("alerts", []).size() == after_load.size() - 1, main._status_text)

	# 14. Overview open, then End turn with research to pick: the tech screen opens and nothing is stuck
	main._set_overview_visible(true)
	await main._refresh_overview()
	await main.end_turn()
	await settle()
	say("End turn with the overview open: blockers %s, big screen %s on '%s'" % [main.state.get("blockers", []).map(func(x: Dictionary) -> String: return x["type"]),
		main._big_screen_shown(), main.big_screen.tab])
	main._set_overview_visible(false)

	# 15. Double click on Buy in the city view: one unit, paid once
	var scouts := func() -> int: return main.state.get("units", []).filter(func(u: Dictionary) -> bool: return u["name"] == "Scout").size()
	for u: Dictionary in main.state.get("units", []):   # Unciv won't buy a unit with one standing in the city
		if Vector2i(int(u["x"]), int(u["y"])) == capital:
			await main.bridge.request("unitAction", {"unitId": int(u["id"]), "action": "DisbandUnit", "confirm": true})
	await main.refresh()
	var before: int = scouts.call()
	await main.enter_city_view(str(cities[0]["name"]))
	main._on_city_board_chosen("city_buy", "Scout|Gold|-1")
	await main._on_city_board_chosen("city_buy", "Scout|Gold|-1")
	await settle()
	await main.exit_city_view()
	await settle()
	check("double click on Buy buys one", scouts.call() == before + 1, "scouts %d -> %d, status '%s'" % [before, scouts.call(), main._status_text])

	# 16. Double click on Propose: a gift of gold goes through once
	await debug({"command": "meet", "other": others[-1]["name"]})
	await main.refresh()
	for alert: Dictionary in main.state.get("alerts", []):
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	var partner: String = others[-1]["name"]
	await main.show_big_screen("diplomacy")
	await main._on_big_screen_chosen("trade_open", partner)
	main.big_screen.stage_trade([{"name": "Gold", "type": "Gold", "amount": 50}], [])
	var gold_before := int(main.state.get("player", {}).get("gold", 0))
	main._on_big_screen_chosen("trade_propose", "")
	await main._on_big_screen_chosen("trade_propose", "")
	await settle()
	await main.refresh()
	var gold_after := int(main.state.get("player", {}).get("gold", 0))
	check("double click on Propose trades once", gold_before - gold_after <= 50 + 10, "gold %d -> %d, status '%s'" % [gold_before, gold_after, main._status_text])
	main._set_big_visible(false)

	# 17. Clicking a city with two units on it: unit, other unit, then the city, then back to the first unit
	await main.exit_city_view()
	var stack_a := await _spawn("Warrior", capital)
	var stack_b := await _spawn("Archer", capital)
	await main.refresh()
	main._deselect()
	var seen: Array[String] = []
	for i in 4:
		await main.click_tile(capital)
		await settle(0.3)
		seen.append(str(main.selected_unit.get("name", "")) if not main.selected_unit.is_empty() else "city:" + str(main.selected_city.get("name", "-")))
	var stack: int = main._own_units_at(capital).size()
	var expected: Array[bool] = []   # true = the city
	for i in 4:
		expected.append(i % (stack + 1) == stack)
	var got: Array[bool] = []
	for name: String in seen:
		got.append(name.begins_with("city:"))
	check("clicking a city with %d unit(s) cycles them, then opens the city" % stack, got == expected and stack >= 1, str(seen))
	main._deselect()

	# 18. City view production board: Build now / Add to queue are real, clickable-sized buttons
	await main.enter_city_view(str(cities[0]["name"]))
	var queued_names: Array = main.city_view_data.get("queue", []).map(func(q: Dictionary) -> String: return q["name"])
	for option: Dictionary in main.city_view_data.get("options", []):
		if option.get("buildable", false) and not option["name"] in queued_names:
			await press(main.city_prod_board, option["name"])
			break
	await settle(1.0)
	var add := _find_button(main.city_prod_board, "Add to queue")
	check("Add to queue is visible and wide enough to point at", add != null and add.size.x > 100, "width %s" % (add.size.x if add != null else -1.0))
	await main.exit_city_view()

	say("sequences finished with %d problem(s)" % _problems)


## The city view's production board, clicked like a player: pick an item in the list, then Build now / Add to queue.
func cityview_production(pick_only := false) -> void:
	await start_civ()
	await main.refresh()
	var city: Dictionary = main.state.get("cities", [])[0]
	await main.enter_city_view(str(city["name"]))
	await settle()
	var board: Control = main.city_prod_board
	say("queue at start: %s" % [main.city_view_data.get("queue", []).map(func(q: Dictionary) -> String: return q["name"])])
	if pick_only:   # stop with an item picked, for a screenshot of the board
		await press(board, "Warrior")
		await settle(1.0)
		var footer: Control = board._footer
		say("footer: rect %s of board %s, buttons visible %s" % [footer.get_global_rect(), board.size, _find_button(board, "Add to queue") != null])
		return
	for item in ["Monument", "Warrior"]:
		var found := await press(board, item)
		await settle(1.0)
		say("picked %s: %s, selected '%s'" % [item, found, board.selected_construction])
		var queued := await press(board, "Add to queue")
		await settle(1.0)
		say("Add to queue pressed %s: queue %s, status '%s'" % [queued, main.city_view_data.get("queue", []).map(func(q: Dictionary) -> String: return q["name"]), main._status_text])
	await press(board, "Scout")
	await settle(1.0)
	var now := await press(board, "Build now")
	await settle(1.0)
	say("Build now pressed %s: queue %s, status '%s', busy %s" % [now, main.city_view_data.get("queue", []).map(func(q: Dictionary) -> String: return q["name"]), main._status_text, main.busy])


## Saves exactly what a board shows (its own viewport in VR, the window on the desktop) as <shots>/<name>.png.
func shot(board: Control, name: String) -> void:
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder := str(main.options.get("shots", "user://shots"))
	DirAccess.make_dir_recursive_absolute(folder)
	board.get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))
	say("shot " + name)


## Every big screen tab and page, the overview tabs and the city boards, for a look at the layout.
## The test save tests/saves/everything.json has what this needs (see tests/saves/README.md); this still starts
## from a new game itself, which can be dropped once it's switched over to --load.
## That makes the runs much faster.
func screens() -> void:
	var capital := await start_civ()
	for c: Dictionary in main.state.get("civs", []):
		if c["name"] != main.state.get("playerCiv") and not c.get("isBarbarian", false):
			await debug({"command": "meet", "other": c["name"]})
	for i in 6:
		await main.refresh()
		for alert: Dictionary in main.state.get("alerts", []):
			await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
		await main.bridge.request("setResearch", {"tech": "Pottery"})
		await main.end_turn()
		await settle()
	await main.refresh()
	for alert: Dictionary in main.state.get("alerts", []):
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	say("turn %d, blockers %s" % [int(main.state.get("turn", 0)), main.state.get("blockers", []).map(func(b: Dictionary) -> String: return b["type"])])
	await debug({"command": "addStat", "stat": "Faith", "amount": 300})
	await main.refresh()
	var big: Control = main.big_screen
	for tab in ["tech", "policies", "diplomacy", "religion"]:
		await main.show_big_screen(tab)
		await settle(1.0)
		await shot(big, "big_" + tab)
		if tab == "tech":
			await main._on_big_screen_chosen("tech_select", "Writing")
			await settle(1.0)
			await shot(big, "big_tech_selected")
		if tab == "religion":
			var beliefs: Array = big._religion.get("beliefs", []).filter(func(b: Dictionary) -> bool: return b.get("available", false))
			if not beliefs.is_empty():
				await main._on_big_screen_chosen("religion_belief", beliefs[-1]["name"])
				await settle(0.5)
				big.scroll_by(Vector2(0, 5000))
				await settle(0.5)
				await shot(big, "big_religion_picked")
	await main.show_big_screen("victory")
	await settle(1.0)
	for page in ["ours", "global", "rankings", "charts", "demographics"]:
		await main._on_big_screen_chosen("victory_page", page)
		await settle(0.5)
		await shot(big, "victory_" + page)
	await main.show_big_screen("diplomacy")
	await settle(0.5)
	for c: Dictionary in big._diplomacy.get("civs", []):
		var kind := "cs" if c.get("isCityState", false) else "major"
		if not FileAccess.file_exists(str(main.options.get("shots", "user://shots")).path_join("civ_%s.png" % kind)):
			await main._on_big_screen_chosen("civ_open", c["name"])
			await settle(0.5)
			await shot(big, "civ_" + kind)
			await main._on_big_screen_chosen("civ_close", "")
			if kind == "major":
				await main._on_big_screen_chosen("trade_open", c["name"])
				await settle(0.5)
				await shot(big, "trade")
				big.close_trade()
	main._set_big_visible(false)
	main._set_overview_visible(true)
	for t: Array in main.overview_board.TABS:
		main.overview_board.show_tab(t[0])
		await main._refresh_overview()
		await settle(0.5)
		await shot(main.overview_board, "overview_" + t[0])
		var body: Control = main.overview_board._body
		var view: ScrollContainer = main.overview_board._scroll
		if body.get_combined_minimum_size().x > view.size.x:
			say("overview %s is %d px wider than the board" % [t[0], int(body.get_combined_minimum_size().x - view.size.x)])
	main._set_overview_visible(false)
	# The cards: in VR the floating popup, on the desktop the side card
	var card: Control = main.popup_menu if main._xr_mode else main.action_menu
	var units: Array = main.state.get("units", [])
	if not units.is_empty():
		await main._select_unit(int(units[0]["id"]))
		await settle(0.5)
		await shot(card, "card_unit")
		main._deselect()
	await main.open_city(capital)
	await settle(0.5)
	await shot(card, "card_city")
	main._deselect()
	main.open_settings()
	await settle(0.5)
	await shot(card, "card_settings")
	main._close_popup()
	var others: Array = main.state.get("civs", []).filter(func(c: Dictionary) -> bool:
		return not c.get("isCityState", false) and not c.get("isBarbarian", false) and c["name"] != main.state.get("playerCiv"))
	await debug({"command": "popupAlert", "type": "DemandToStopSettlingCitiesNear", "value": others[0]["name"]})
	await main.refresh()
	await settle(0.5)
	await shot(main.popup_menu if main._xr_mode else main.alert_menu, "card_alert")
	var alert: Array = main.state.get("alerts", [])
	if not alert.is_empty():
		await main.answer_alert("%s|%s" % [alert[0]["key"], alert[0]["options"][0]["id"]])
	await debug({"command": "freeGreatPerson"})
	await main.refresh()
	await main.open_great_people()
	await settle(0.5)
	await shot(main.popup_menu if main._xr_mode else main.alert_menu, "card_great_person")
	await main.choose_great_person("Great Scientist")

	await main.enter_city_view(str(main.state.get("cities", [])[0]["name"]))
	await press(main.city_prod_board, "Warrior")
	await settle(1.0)
	await shot(main.city_info_board, "city_info")
	await shot(main.city_prod_board, "city_prod")
	await main.exit_city_view()


## The tileset on a real map: reveals the whole map, then pictures of the table zoomed out, at the usual
## window size and on the natural wonders, with how long each redraw took and how much it draws.
func tiles() -> void:
	var capital := await start_civ()
	await debug({"command": "reveal"})
	await main.refresh()
	for alert: Dictionary in main.state.get("alerts", []):
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	main._set_big_visible(false)
	var map: Node3D = main.hex_map
	var wonders: Array[Vector2i] = []
	for key: Vector2i in map.tiles:
		if map.tiles[key].has("wonder"):
			wonders.append(key)
	say("tileset %s, %d tiles, wonders: %s" % [map.tileset_name, map.tiles.size(),
		", ".join(wonders.map(func(k: Vector2i) -> String: return str(map.tiles[k]["wonder"])))])
	var views := [["whole", map.full_center, 0.0], ["window", map._world_of(capital), 14.0], ["close", map._world_of(capital), 6.0]]
	for w in wonders.slice(0, 5):
		views.append(["wonder_" + str(map.tiles[w]["wonder"]).replace(" ", "_").replace("'", ""), map._world_of(w), 5.0])
	for view: Array in views:
		var started := Time.get_ticks_usec()
		map.set_view(view[1], view[2])
		map._rebuild_view()
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		main._fit_table()
		await settle(1.2)
		var instances := 0
		var triangles := 0
		for node: MultiMeshInstance3D in map._piece_nodes.values():
			var mm := node.multimesh
			instances += mm.instance_count
			var per := 0
			for surface in mm.mesh.get_surface_count():
				per += (mm.mesh as ArrayMesh).surface_get_array_len(surface) / 3
			triangles += per * mm.instance_count
		say("%s: %d tiles drawn in %.0f ms, %d piece meshes, %d instances, %d triangles" % [view[0], map._shown.size(), ms,
			map._piece_nodes.size(), instances, triangles])
		await main.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var folder := str(main.options.get("shots", "user://shots"))
		DirAccess.make_dir_recursive_absolute(folder)
		main.get_viewport().get_texture().get_image().save_png(folder.path_join("tiles_%s.png" % view[0]))
	# The city view's marks (yields, worked tiles, prices) on top of the pieces
	var cities: Array = main.state.get("cities", [])
	if not cities.is_empty():
		await main.enter_city_view(str(cities[0]["name"]))
		await settle(1.5)
		await main.get_tree().process_frame
		await RenderingServer.frame_post_draw
		main.get_viewport().get_texture().get_image().save_png(str(main.options.get("shots", "user://shots")).path_join("tiles_cityview.png"))
		say("city view of %s on %s" % [cities[0]["name"], map.describe_tile(Vector2i(int(cities[0]["x"]), int(cities[0]["y"])))])


## Every background and table in Settings, like a player picking them, with a picture of each; then the table
## raised, lowered and scaled, to check its column and feet follow. Run it from the test save (--load).
func surroundings() -> void:
	var folder := str(main.options.get("shots", "user://shots"))
	DirAccess.make_dir_recursive_absolute(folder)
	var Backgrounds := load("res://scripts/backgrounds.gd")
	var TableModel := load("res://scripts/table_model.gd")
	for background: String in Backgrounds.available():
		await main.change_setting("background", background)
		await settle(0.4)
		say("background %s: floor %s, %d scenery nodes" % [main.backgrounds.current, main.backgrounds.has_floor,
			main.backgrounds.get_node("Scenery").get_child_count()])
		main.get_viewport().get_texture().get_image().save_png(folder.path_join("background_%s.png" % background))
	await main.change_setting("background", "Mountains")
	for table_folder: String in TableModel.available():
		await main.change_setting("table", table_folder)
		await settle(0.4)
		var model: Node3D = main.table_model
		var parts := []
		for part: Node in model.get_children() + [main.table.get_node_or_null("TableTop")]:
			if part is Node3D:
				parts.append("%s%s" % [part.name, "" if (part as Node3D).visible else " (hidden)"])
		say("table %s (saved %s): %s" % [model.current, main.settings["table"], ", ".join(parts)])
		main.get_viewport().get_texture().get_image().save_png(folder.path_join("table_%s.png" % table_folder))
		var start: Transform3D = main.table.transform
		for pose: Array in [[0.3, 1.0], [1.5, 1.0], [0.9, 2.0], [0.9, 0.5]]:
			main.table.position.y = pose[0]
			main.table.scale = Vector3.ONE * float(pose[1])
			main._update_pedestal()
			var column := model.get_node_or_null("TableColumn") as Node3D
			var base := model.get_node_or_null("TableBase") as Node3D
			say("  table at %.1f m, scale %.1f: column %s, base %s" % [pose[0], pose[1],
				"%.2f m" % (column.global_transform.basis.y.length()) if column != null and column.visible else "-",
				"%.2f tall" % (base.global_transform.basis.y.length()) if base != null and base.visible else "-"])
		main.table.transform = start
		main._update_pedestal()


## Killing a unit with your own attack. Its token is freed by the death animation, so nothing may look it
## up afterwards: the map rebuild that follows the attack did, and the error stopped the client dead in the
## middle of a game (user, 2026-10-10: "froze right after I had an atlatlist kill a brute").
func unit_death() -> void:
	var capital := await start_civ()
	var others: Array = main.state.get("civs", []).filter(func(c: Dictionary) -> bool:
		return not c.get("isCityState", false) and not c.get("isBarbarian", false) and c["name"] != main.state.get("playerCiv"))
	if others.is_empty():
		say("nobody to fight")
		return
	var enemy: String = others[0]["name"]
	await debug({"command": "war", "other": enemy})
	await debug({"command": "spawnUnit", "civ": enemy, "unit": "Scout", "x": capital.x + 2, "y": capital.y})
	var ours: Dictionary = await debug({"command": "spawnUnit", "unit": "Archer", "x": capital.x + 1, "y": capital.y})
	var archer := str(ours.get("result", ""))
	await main.refresh()
	for alert: Dictionary in main.state.get("alerts", []):
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	main._set_big_visible(false)
	main.hex_map.set_view(main.hex_map._world_of(capital), 6.0)
	main._fit_table()
	await settle(0.5)
	if not archer.is_valid_int():
		say("couldn't spawn an archer")
		return
	await main._select_unit(int(archer))
	var targets: Array = main.selected_unit.get("targets", [])
	if targets.is_empty():
		say("the archer has nothing to shoot at")
		return
	var target: Dictionary = targets[0]
	var key := Vector2i(int(target["x"]), int(target["y"]))
	var dead_id := -1
	for unit: Dictionary in main.hex_map.tiles.get(key, {}).get("units", []):
		dead_id = int(unit.get("id", -1))
	say("shooting the %s on %s (unit %d), one hit point left" % [target.get("name", "?"), key, dead_id])
	await debug({"command": "unitHealth", "x": key.x, "y": key.y, "health": 1})
	await main.refresh()
	await main._select_unit(int(archer))
	await main.attack(key)
	say("the attack: %s" % main._status_text.replace("\n", " | "))
	await settle(1.5)
	# What froze the game: the map rebuild looked the dead unit's freed token up
	say("the dead unit's token: %s" % main.hex_map.token_for(dead_id))
	var freed: int = main.hex_map._tokens.values().filter(func(t: Variant) -> bool: return not is_instance_valid(t)).size()
	say("tokens after the kill: %d, %d of them freed (want 0)" % [main.hex_map._tokens.size(), freed])
	main.hex_map.build(main.state)   # the rebuild that used to stop the client dead
	await settle(0.3)
	say("map rebuilt: %d tokens" % main.hex_map._tokens.size())
	await main.refresh()
	say("and another refresh: turn %d, %d units, status '%s'" % [int(main.state.get("turn", 0)),
		(main.state.get("units", []) as Array).size(), main._status_text.replace("\n", " | ")])


## From the test save: moving onto a tile one of your own units is already on. A click there selects that unit
## (that's how you pick it), so holding the trigger - or the mouse button - aims at the tile instead, and the
## click after that goes. Saves a picture of each aim to --shots, including a tile with no room left on it.
func stacking() -> void:
	var folder := str(main.options.get("shots", "user://shots"))
	DirAccess.make_dir_recursive_absolute(folder)
	var shot := func(name: String) -> void:
		main.get_viewport().get_texture().get_image().save_png(folder.path_join("stack_%s.png" % name))
	# Two tiles to try: one with room for the unit (Unciv lets a civilian and a military unit share a tile),
	# and one with none left, which the aim should say so that the click doesn't walk the unit up to it
	var share: Array = []
	var crowded: Array = []
	for u: Dictionary in main.state.get("units", []):
		if not share.is_empty() and not crowded.is_empty():
			break
		await main._select_unit(int(u["id"]))
		var from: Vector2i = main._selected_key()
		for t: Dictionary in main.selected_unit.get("reachable", []):
			var key := Vector2i(int(t["x"]), int(t["y"]))
			var occupants: Array = main._own_units_at(key)
			if key == from or occupants.is_empty():
				continue
			var room: bool = occupants.size() == 1 \
				and bool(occupants[0].get("civilian", false)) != bool(u.get("civilian", false))
			if room and share.is_empty():
				share = [int(u["id"]), key]
			elif not room and crowded.is_empty():
				crowded = [int(u["id"]), key]
	if share.is_empty():
		say("no unit could reach a tile with room for it next to one of yours")
	else:
		await _stacking_case(share[0], share[1], shot, true)
	if crowded.is_empty():
		say("no full tile to try (one with as many units as Unciv allows)")
	else:
		await _stacking_case(crowded[0], crowded[1], shot, false)


## One tile: click it (which selects whoever is there), hold on it (which aims), then click to go.
## [param expected] is whether the unit should fit on the tile; [param shot] saves a picture by name.
func _stacking_case(unit_id: int, key: Vector2i, shot: Callable, expected: bool) -> void:
	await main._select_unit(unit_id)
	var mover := str(main.selected_unit.get("name", "?"))
	var from: Vector2i = main._selected_key()
	var occupants := ", ".join(main._own_units_at(key).map(func(o: Dictionary) -> String: return str(o["name"])))
	await main.click_tile(key)
	say("%s on %s: clicking there selected %s, it didn't move %s" % [occupants, key,
		main.selected_unit.get("name", "nothing"), mover])
	await main._select_unit(unit_id)
	await main._long_press_tile(key)
	await settle(0.3)
	var armed: bool = main._forced_aim == key
	say("holding %s on it: %s%s" % [mover, "aimed, so the next click goes" if armed else "no room for it there",
		"" if armed == expected else " - NOT what the tile looks like!"])
	shot.call("aimed" if armed else "no_room")
	if not armed:
		await main.click_tile(key)
		await settle(0.3)
		say("clicking it anyway: %s is still at %s, and %s is selected" % [mover, from,
			main.selected_unit.get("name", "nothing")])
		return
	await main.click_tile(key)
	await settle(0.4)
	say("the click moved %s %s -> %s, %d units on the tile now" % [mover, from, main._selected_key(),
		main._own_units_at(key).size()])
	shot.call("moved")
	# The card's "Move here" does the same without the hold
	await main._select_unit(unit_id)
	await main.unit_action("MoveHere")
	await settle(0.3)
	say("Move here: picking %s, %d tiles ringed, card says '%s'" % [main._pick.get("kind", "-"),
		(main._pick.get("targets", []) as Array).size(), main.action_menu.picking_text])
	shot.call("move_here")
	await main.cancel_pick()
	await settle(0.2)
	say("cancelled: picking %s, status '%s'" % [main._pick.is_empty(), main._status_text])


## The settings board, through its own buttons: every page (a picture of each), a drop-down opened and used,
## toggles, the number settings (checked against what the bridge echoes back), then Close.
func settings_board() -> void:
	var folder := str(main.options.get("shots", "user://shots"))
	DirAccess.make_dir_recursive_absolute(folder)
	main.open_settings()
	await settle(0.4)
	var board: Control = main.settings_board
	for page: String in ["look", "gameplay", "automation", "sound", "controls", "game", "about"]:
		board.show_page(page)
		await settle(0.3)
		main.get_viewport().get_texture().get_image().save_png(folder.path_join("settings_%s.png" % page))
		say("page %s: %d rows" % [page, board._body.get_child_count()])
	board.show_page("sound")
	await settle(0.3)
	say("sound page: effects %s%%, ambience %s%%, %d sounds found" % [main.settings.get("soundVolume"),
		main.settings.get("ambienceVolume"), (load("res://scripts/sounds.gd").available() as Array).size()])
	say("turn the effects down: %s" % board.press("70%"))
	await settle(0.3)
	say("pick 30%%: %s -> saved %s" % [board.press("30%"), main.settings.get("soundVolume")])
	board.show_page("look")
	await settle(0.2)
	say("open the background list: %s" % board.press("Mountains and clouds"))
	await settle(0.3)
	main.get_viewport().get_texture().get_image().save_png(folder.path_join("settings_look_open.png"))
	say("pick space: %s" % board.press("Floating in space"))
	await settle(0.6)
	say("background now %s (saved %s), list closed: %s" % [main.backgrounds.current, main.settings["background"], board._open_choice == ""])
	board.press("Floating in space")
	await settle(0.2)
	board.press("Mountains and clouds")
	await settle(0.5)
	board.press("Plain wood")
	await settle(0.2)
	board.press("Ornate oak")
	await settle(0.5)
	say("table now %s" % main.table_model.current)
	var models := func() -> int:
		return main.hex_map._tokens.values().filter(func(t: Node) -> bool: return is_instance_valid(t) and t.get_node_or_null("Model") != null).size()
	var with_models: int = models.call()
	board.press("Same as the tiles")
	await settle(0.2)
	board.press("No models")
	await settle(0.6)
	say("units: %d models with the tiles' set, %d with No models (saved %s)" % [with_models, models.call(), main.settings["unitset"]])
	board.press("No models")
	await settle(0.2)
	board.press("Same as the tiles")
	await settle(0.6)
	say("units back: %d models" % models.call())
	var yields_before: bool = main.settings["overlays"]["yields"]
	board._rebuild()
	await settle(0.2)
	board.show_page("gameplay")
	await settle(0.2)
	var before_cycle: bool = main.settings["autoUnitCycle"]
	board.press("On") if before_cycle else board.press("Off")
	await settle(0.5)
	say("a gameplay toggle: autoUnitCycle %s -> %s" % [before_cycle, main.settings["autoUnitCycle"]])
	board.press("5 turns")
	await settle(0.2)
	board.press("8 turns")
	await settle(0.5)
	var echo: Variant = await main.bridge.request("setSettings", {})
	say("notification log: setting %s, bridge %s" % [main.settings["notificationsLogMaxTurns"], echo.result.get("notificationsLogMaxTurns")])
	board.show_page("game")
	await settle(0.2)
	board.press("Every turn")
	await settle(0.2)
	board.press("Every 5 turns")
	await settle(0.5)
	echo = await main.bridge.request("setSettings", {})
	say("autosave: setting %s, bridge %s" % [main.settings["turnsBetweenAutosaves"], echo.result.get("turnsBetweenAutosaves")])
	board.show_page("look")
	await settle(0.2)
	board._open_choice = ""
	var overlay_rows := board.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text in ["On", "Off"])
	(overlay_rows[1] as Button).pressed.emit()   # Show tile yields
	await settle(0.3)
	say("tile yields overlay %s -> %s" % [yields_before, main.settings["overlays"]["yields"]])
	(board.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text in ["On", "Off"])[1] as Button).pressed.emit()
	await settle(0.3)
	board.press("Close")
	await settle(0.2)
	say("closed: %s" % (not main.settings_shown()))
	# put things back
	await main.change_setting("table", "Plain")
	await main.change_setting("notificationsLogMaxTurns", "5")
	await main.change_setting("turnsBetweenAutosaves", "1")
	if main.settings["autoUnitCycle"] != before_cycle:
		await main.change_setting("setting_toggle", "autoUnitCycle")


## --then=switch_tileset:<folder>: picks another tileset in Settings, like a player would, and reports what's drawn.
func switch_tileset(folder: String) -> void:
	await main.change_setting("tileset", folder)
	await settle(0.5)
	var map: Node3D = main.hex_map
	var instances := 0
	for node: MultiMeshInstance3D in map._piece_nodes.values():
		instances += node.multimesh.instance_count
	say("tileset now %s (saved %s): %d piece instances, %d plain hexes" % [map.tileset_name, main.settings["tileset"],
		instances, map._terrain.multimesh.instance_count])


## Battles: war with a neighbour, enemy troops placed next to the capital, one of ours shoots first, then End turn
## lets the AI attack and its moves and fights play back. Saves pictures during both to --shots.
func battles() -> void:
	var capital := await start_civ()
	var others: Array = main.state.get("civs", []).filter(func(c: Dictionary) -> bool:
		return not c.get("isCityState", false) and not c.get("isBarbarian", false) and c["name"] != main.state.get("playerCiv"))
	var enemy: String = others[0]["name"]
	await debug({"command": "war", "other": enemy})
	var kinds := ["Swordsman", "Horseman", "Archer", "Catapult"]
	var spots := [Vector2i(2, 0), Vector2i(2, 1), Vector2i(3, 1), Vector2i(3, 2)]
	for i in spots.size():
		var spot: Vector2i = spots[i]
		await debug({"command": "spawnUnit", "civ": enemy, "unit": kinds[i], "x": capital.x + spot.x, "y": capital.y + spot.y})
	var spawned: Dictionary = await debug({"command": "spawnUnit", "unit": "Archer", "x": capital.x, "y": capital.y + 1})
	var ours := str(spawned.get("result", ""))
	await main.refresh()
	for alert: Dictionary in main.state.get("alerts", []):
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	main._set_big_visible(false)
	main.hex_map.set_view(main.hex_map._world_of(capital), 6.0)
	main._fit_table()
	await settle(0.8)
	say("our archer %s; enemy units near %s" % [ours, capital])
	var recorder := func(prefix: String, seconds: float) -> void:
		var folder := str(main.options.get("shots", "user://shots"))
		DirAccess.make_dir_recursive_absolute(folder)
		var started := Time.get_ticks_msec()
		var n := 0
		while Time.get_ticks_msec() - started < seconds * 1000.0:
			await main.get_tree().create_timer(0.12).timeout
			await RenderingServer.frame_post_draw
			main.get_viewport().get_texture().get_image().save_png(folder.path_join("%s_%03d.png" % [prefix, n]))
			n += 1
	# our archer shoots the nearest enemy
	if ours.is_valid_int():
		await main._select_unit(int(ours))
		var targets: Array = main.selected_unit.get("targets", [])
		say("archer targets: %s" % [targets])
		if not targets.is_empty():
			var t: Dictionary = targets[0]
			recorder.call("own", 3.0)
			await main.attack(Vector2i(int(t["x"]), int(t["y"])))
			say("own attack: %s" % main._status_text)
			await settle(2.0)
	# the AI's turn
	recorder.call("ai", 16.0)
	await main.end_turn()
	say("after end turn: status '%s', turn %d" % [main._status_text.replace("\n", " | "), int(main.state.get("turn", 0))])
	await settle(1.0)


## --then=staged_fight: plays made-up events with the units on the table (an enemy charging our nearest unit, a
## ranged unit shooting it, one shooting our capital), through the same playback as the AI's turn.
func staged_fight() -> void:
	var map: Node3D = main.hex_map
	var mine: Array = []
	var theirs: Array = []
	for key: Vector2i in map.tiles:
		for u: Dictionary in map.tiles[key].get("units", []):
			(mine if u["civ"] == main.state.get("playerCiv") else theirs).append([key, u])
	var cities: Array = main.state.get("cities", [])
	if mine.is_empty() or theirs.is_empty() or cities.is_empty():
		say("staged fight: nothing to stage")
		return
	var capital := Vector2i(int(cities[0]["x"]), int(cities[0]["y"]))
	map.set_view(map._world_of(capital), 5.0)
	main._fit_table()
	await settle(0.6)
	var target: Array = mine[0]
	var events := []
	for t: Array in theirs:
		var u: Dictionary = t[1]
		var info: Dictionary = map.unit_info.get(str(u["name"]), {})
		var ranged := float(info.get("rangedStrength", 0)) > 0.0
		events.append({"type": "attack", "attacker": int(u["id"]), "name": u["name"], "civ": u["civ"], "sound": str(info.get("attackSound", "")),
			"ranged": ranged, "from": [t[0].x, t[0].y], "to": [capital.x, capital.y] if ranged else [target[0].x, target[0].y],
			"defender": -1 if ranged else int(target[1]["id"]), "damage": 15, "damageTaken": 6, "defenderDied": false})
	var folder := str(main.options.get("shots", "user://shots"))
	# a close-up camera over the capital, so the units fill the picture
	var close := Camera3D.new()
	main.add_child(close)
	var centre: Vector3 = map.global_transform * map.tile_local_center(capital)
	var hex: float = map.global_transform.basis.get_scale().x
	close.fov = 40
	close.look_at_from_position(centre + Vector3(0.5, 4.2, 5.2) * hex, centre + Vector3(0, 0.3, 0) * hex)
	main._close_popup()
	main._set_info_visible(false)
	if main._xr_camera != null:
		main._xr_camera.current = false
	close.current = true
	var recorder := func() -> void:
		var n := 0
		while main._playback_active or n == 0:
			await main.get_tree().create_timer(0.1).timeout
			await RenderingServer.frame_post_draw
			main.get_viewport().get_texture().get_image().save_png(folder.path_join("staged_%03d.png" % n))
			n += 1
	main._playback_active = true
	recorder.call()
	main._playback_active = false
	await main._play_turn_events(events, 1.0)
	close.current = false
	close.queue_free()
	if main._xr_camera != null:
		main._xr_camera.current = true
	say("staged fight: %d events played" % events.size())


## --then=unit_icons: turns the unit icons overlay off and on again, like clicking its button, and counts the icons.
func unit_icons() -> void:
	for i in 2:
		main.toggle_overlay("unit_icons")
		await settle(0.3)
		var icons := 0
		for token: Node3D in main.hex_map._tokens.values():
			for child in token.get_children():
				if child is Sprite3D and child.name != "HealthBar":
					icons += 1
		say("unit icons %s: %d icons over %d units" % ["on" if main.settings["overlays"]["unit_icons"] else "off", icons, main.hex_map._tokens.size()])


## Builds the test save (--scenario=make_test_save --then=save_test_game): a game with everything the other
## scenarios and screenshots need, so test runs start from --load=res://tests/saves/everything.json instead of
## a new game plus debug commands and End turns. See tests/saves/README.md.
func make_test_save() -> void:
	var capital := await start_civ()
	var player := str(main.state.get("playerCiv"))
	for c: Dictionary in main.state.get("civs", []):
		if c["name"] != player and not c.get("isBarbarian", false):
			await debug({"command": "meet", "other": c["name"]})
	await debug({"command": "reveal"})
	for stat: Array in [["Gold", 1500], ["Faith", 400], ["Culture", 300]]:
		await debug({"command": "addStat", "stat": stat[0], "amount": stat[1]})
	for tech: String in ["Pottery", "Animal Husbandry", "Archery", "Mining", "Sailing", "Bronze Working", "Writing",
			"The Wheel", "Masonry", "Horseback Riding", "Mathematics", "Calendar", "Trapping"]:
		await debug({"command": "addTech", "tech": tech})
	# two more cities, a few tiles from the capital
	var founded := 1
	for offset: Vector2i in [Vector2i(4, 0), Vector2i(0, 4), Vector2i(-4, 0), Vector2i(0, -4), Vector2i(4, 4), Vector2i(-4, -4), Vector2i(5, 1), Vector2i(1, 5)]:
		if founded >= 3:
			break
		if not main.hex_map.tiles.has(capital + offset):
			continue
		var spawned: Dictionary = await debug({"command": "spawnUnit", "unit": "Settler", "x": capital.x + offset.x, "y": capital.y + offset.y})
		if spawned.is_empty():
			continue
		var reply: Dictionary = await main.bridge.request("unitAction", {"unitId": int(str(spawned["result"])), "action": "FoundCity"})
		if reply.ok:
			founded += 1
		else:
			await main.bridge.request("unitAction", {"unitId": int(str(spawned["result"])), "action": "DisbandUnit", "confirm": true})
	await main.refresh()
	say("cities: %s" % [main.state.get("cities", []).map(func(c: Dictionary) -> String: return str(c["name"]))])
	# a few turns, so there's history for the victory charts and the cities have grown a little
	for turn in 4:
		await _end_turn_quietly()
	await main.refresh()
	var cities: Array = main.state.get("cities", [])
	var second := Vector2i(int(cities[-1]["x"]), int(cities[-1]["y"])) if cities.size() > 1 else capital
	# our army, and two units stacked in the capital
	for unit: String in ["Warrior", "Worker", "Archer", "Swordsman", "Spearman", "Horseman", "Catapult", "Chariot Archer",
			"Scout", "Work Boats", "Trireme", "Great General", "Settler", "Great Prophet"]:
		var at := capital if unit in ["Warrior", "Worker", "Great General"] else second
		if unit in ["Trireme", "Work Boats"]:   # ships need a city by the water
			for c: Dictionary in cities:
				var key := Vector2i(int(c["x"]), int(c["y"]))
				if (await main.bridge.request("debug", {"command": "spawnUnit", "unit": unit, "x": key.x, "y": key.y})).ok:
					break
			continue
		await debug({"command": "spawnUnit", "unit": unit, "x": at.x, "y": at.y})
	await debug({"command": "freeGreatPerson"})
	# war with the nearest major civ, its troops next to our second city
	var majors: Array = main.state.get("civs", []).filter(func(c: Dictionary) -> bool:
		return not c.get("isCityState", false) and not c.get("isBarbarian", false) and c["name"] != player)
	if not majors.is_empty():
		var enemy: String = majors[0]["name"]
		await debug({"command": "war", "other": enemy})
		var spot := second
		for offset: Vector2i in [Vector2i(2, 1), Vector2i(-2, -1), Vector2i(1, 2), Vector2i(-1, -2), Vector2i(2, 0)]:
			if main.hex_map.tiles.has(second + offset):
				spot = second + offset
				break
		for unit: String in ["Swordsman", "Horseman", "Archer", "Catapult", "Spearman"]:
			await debug({"command": "spawnUnit", "civ": enemy, "unit": unit, "x": spot.x, "y": spot.y})
	await main.refresh()
	for alert: Dictionary in main.state.get("alerts", []):
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	await main.refresh()
	var units: Array = main.state.get("units", [])
	var foreign := 0
	for key: Vector2i in main.hex_map.tiles:
		for u: Dictionary in main.hex_map.tiles[key].get("units", []):
			if u["civ"] != player:
				foreign += 1
	say("turn %d: %d cities, %d units (%s), %d foreign units in sight" % [int(main.state.get("turn", 0)), main.state.get("cities", []).size(),
		units.size(), ", ".join(units.map(func(u: Dictionary) -> String: return str(u["name"]))), foreign])


## Ends the turn through the bridge, settling whatever blocks it the simplest way (first tech, first policy...).
func _end_turn_quietly() -> void:
	for attempt in 8:
		var reply: Dictionary = await main.bridge.request("endTurn")
		if reply.ok:
			return
		await main.refresh()
		for alert: Dictionary in main.state.get("alerts", []):
			await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
		for blocker: Dictionary in main.state.get("blockers", []):
			match str(blocker.get("type", "")):
				"PickTech":
					for tech: String in ["Iron Working", "Construction", "Philosophy", "Optics", "Currency", "Engineering", "Drama and Poetry"]:
						if (await main.bridge.request("setResearch", {"tech": tech})).ok:
							break
				"PickPolicy", "AdoptPolicy":
					for policy: String in ["Tradition", "Liberty", "Honor", "Aristocracy", "Collective Rule", "Discipline"]:
						if (await main.bridge.request("adoptPolicy", {"policy": policy})).ok:
							break
				"FoundPantheon":
					var choices: Dictionary = await main.bridge.request("getReligionChoices")
					if choices.ok:
						var beliefs: Array = choices.result.get("beliefs", []).filter(func(b: Dictionary) -> bool: return b.get("available", false))
						if not beliefs.is_empty():
							await main.bridge.request("chooseReligion", {"beliefs": [beliefs[0]["name"]]})
				_:
					await main.bridge.request("dismissBlocker", {"type": blocker.get("type", "")})
	say("couldn't end the turn: %s" % [main.state.get("blockers", [])])


## --then=save_test_game: saves the game the bridge is running as tests/saves/everything.json.
func save_test_game() -> void:
	var path := ProjectSettings.globalize_path("res://tests/saves/everything.json")
	var reply: Dictionary = await main.bridge.request("saveGame", {"path": path})
	say("test save: %s" % (reply.result.get("path", "") if reply.ok else reply.error))


## From the test save: settles what blocks the turn, then End turn the way a player would, so the AI's moves and
## attacks (its war party is next to one of our cities) play back on the table. Prints PLAYBACK lines.
func playback() -> void:
	for alert: Dictionary in main.state.get("alerts", []):
		await main.answer_alert("%s|%s" % [alert["key"], alert["options"][0]["id"]])
	await _clear_blockers()
	main._set_big_visible(false)
	await main.end_turn()
	say("after End turn: turn %d, status '%s'" % [int(main.state.get("turn", 0)), main._status_text.replace("\n", " | ")])


func _clear_blockers() -> void:
	for attempt in 6:
		await main.refresh()
		var blockers: Array = main.state.get("blockers", [])
		if blockers.is_empty():
			return
		for blocker: Dictionary in blockers:
			match str(blocker.get("type", "")):
				"FreeGreatPerson", "PickGreatPerson", "GreatPerson":
					var choices: Dictionary = await main.bridge.request("getGreatPersonChoices")
					if choices.ok and not choices.result.get("choices", []).is_empty():
						await main.bridge.request("chooseGreatPerson", {"unit": choices.result["choices"][0]["name"]})
				"PickTech":
					for tech: String in ["Iron Working", "Construction", "Philosophy", "Optics", "Currency"]:
						if (await main.bridge.request("setResearch", {"tech": tech})).ok:
							break
				"FoundPantheon":
					var religion: Dictionary = await main.bridge.request("getReligionChoices")
					if religion.ok:
						var beliefs: Array = religion.result.get("beliefs", []).filter(func(b: Dictionary) -> bool: return b.get("available", false))
						if not beliefs.is_empty():
							await main.bridge.request("chooseReligion", {"beliefs": [beliefs[0]["name"]]})
				_:
					await main.bridge.request("dismissBlocker", {"type": blocker.get("type", "")})
	say("blockers left: %s" % [main.state.get("blockers", [])])
