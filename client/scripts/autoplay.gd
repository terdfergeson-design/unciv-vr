# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node
## Autoplay playtest of the client: a whole game where Unciv's AI plays every civilization, yours included, while
## the client does what a player would make it do every turn - and every script error, warning, hang and slow frame
## is written down with the turn and what it was doing at the time.
##
##   godot --path client -- --autoplay [--seed=7] [--map-size=Small] [--ai=3] [--max-turns=300] [--shots=10]
##   (add --fake-xr for the VR layout without a headset; --playback=off|fast|normal for the other players' turns;
##   --speed=4: animations and waits run that many times faster)
##
## Every turn: select your units (their cards), answer Unciv's messages through their buttons, then let the AI play
## your turn (the bridge's debug autoPlay - the client starts its bridge with --debug for this), clear whatever still
## stops the turn the way a player would (the client's own pickers first), and press End turn - with the other
## players' moves played back. Every few turns it also opens a city view, the overview's tabs, the big screen's tabs,
## the Civilopedia and the settings. A screenshot every --shots turns (0: none).
##
## The report: logs/autoplay/<date-time>/report.md (and report.json, and the screenshots). The run quits when the game
## ends; the exit code is 1 when anything went wrong.

const NOISE := ["ALSA", "status < 0", "PagedAllocator", "leaked", "RID alloc", "never freed", "init_output",
	"pulseaudio", "AudioDriver"]
const SLOW_FRAME := 0.25      # seconds: a frame this long is a hitch worth reporting
const STUCK_TURN := 300.0     # seconds: a turn this long means something hangs

var main: Node
var turn := 0
var phase := "starting"
var errors: Dictionary = {}    # message -> {count, first_turn, phase, kind}
var hitches: Array = []        # [turn, phase, seconds]
var turn_seconds: Array = []   # [turn, seconds the whole turn took]
var shots: Array[String] = []
var result := ""
var dir := ""
var _logger: AutoplayLogger
var _turn_started := 0.0
var _frames := 0
var _phase_started := 0.0
var time_in: Dictionary = {}   # what it was doing (first word or two) -> seconds, to see where a turn's time goes


func _enter(new_phase: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var key := " ".join(phase.split(" ").slice(0, 3))
	time_in[key] = float(time_in.get(key, 0.0)) + now - _phase_started
	_phase_started = now
	phase = new_phase


class AutoplayLogger extends Logger:
	var owner_ref: WeakRef
	var _mutex := Mutex.new()
	var pending: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["error", "warning", "script error", "shader error"][clampi(error_type, 0, 3)]
		var text := "%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function]
		_mutex.lock()
		pending.append([kind, text])
		_mutex.unlock()

	func take() -> Array:
		_mutex.lock()
		var out := pending.duplicate()
		pending.clear()
		_mutex.unlock()
		return out


func _init(main_node: Node) -> void:
	main = main_node
	name = "Autoplay"


func _process(delta: float) -> void:
	_collect_errors()
	var real := delta / maxf(Engine.time_scale, 0.001)   # delta runs faster with --speed; this is the frame's real time
	_frames += 1
	_wave_pointer()
	if real > SLOW_FRAME and turn > 0:
		hitches.append([turn, phase, snappedf(real, 0.01)])


## The laser (or mouse) never rests: every frame it points somewhere new on the map - mostly at units - so whatever
## the pointer touches is exercised while units move, fight and die (a freed unit's label under the pointer once
## stopped the game: see the freeze-after-a-kill notes).
func _wave_pointer() -> void:
	var map: Node = main.hex_map
	if map == null or main.state.is_empty() or main._in_lobby or turn == 0:
		return
	var keys: Array = map._unit_labels.keys()
	if keys.is_empty() or _frames % 4 == 3:
		keys = map._shown.keys()
	if keys.is_empty():
		return
	map.set_hover(keys[_frames * 7 % keys.size()])


func _collect_errors() -> void:
	if _logger == null:
		return
	for entry: Array in _logger.take():
		var text := str(entry[1])
		if NOISE.any(func(n: String) -> bool: return text.contains(n)):
			continue
		if not errors.has(text):
			errors[text] = {"count": 0, "first_turn": turn, "phase": phase, "kind": entry[0]}
			print("AUTOPLAY: %s on turn %d while %s: %s" % [entry[0], turn, phase, text])
		errors[text]["count"] += 1


func run() -> int:
	_logger = AutoplayLogger.new()
	OS.add_logger(_logger)
	dir = ProjectSettings.globalize_path("res://logs/autoplay").path_join(Time.get_datetime_string_from_system().replace(":", "-"))
	DirAccess.make_dir_recursive_absolute(dir)
	var options: Dictionary = main.options
	var max_turns := int(options.get("max-turns", 500))
	var shot_every := int(options.get("shots", 10))
	main.settings["playback"] = str(options.get("playback", "fast"))   # not saved: the player's own setting stays
	# Animations, glides and waits run this many times faster (they're all timers and tweens); the frames still draw
	Engine.time_scale = float(options.get("speed", 4.0))
	var probe: Dictionary = await main.bridge.request("debug", {"command": "nothing"})
	if not probe.ok and str(probe.error).contains("off"):
		result = "the bridge has no debug commands - start it with --debug (the client does when it starts one for --autoplay)"
		return _finish()
	await main.bridge.request("setSettings", {"checkForDueUnits": false})
	var player := str(main.state.get("playerCiv", "?"))
	print("AUTOPLAY: playing %s, up to turn %d; report in %s" % [player, max_turns, dir])
	while true:
		turn = int(main.state.get("turn", 0))
		_turn_started = Time.get_ticks_msec() / 1000.0
		await _look_around()
		await _answer_messages()
		_enter("the AI playing your turn")
		var auto: Dictionary = await main.bridge.request("debug", {"command": "autoPlay"})
		if not auto.ok:
			result = "autoPlay failed on turn %d: %s" % [turn, auto.error]
			break
		await main.refresh()
		if not await _clear_blockers():
			result = "stuck on turn %d: %s" % [turn, (main.state.get("blockers", [{}]) as Array)[0].get("text", "?")]
			break
		_enter("ending the turn (other players' moves played back)")
		var before := int(main.state.get("turn", 0))
		await main.end_turn()
		await _settle()
		turn_seconds.append([turn, snappedf(Time.get_ticks_msec() / 1000.0 - _turn_started, 0.1)])
		if shot_every > 0 and turn % shot_every == 0:
			_screenshot("turn%03d" % turn)
		var victory: Dictionary = main.state.get("game", {}) if main.state.get("game") is Dictionary else {}
		var over := bool(main.state.get("gameOver", false)) or bool(victory.get("gameOver", false))
		var reply: Dictionary = await main.bridge.request("getVictory")
		if reply.ok and reply.result.has("winner"):
			var w: Dictionary = reply.result["winner"]
			result = "%s won (%s victory) on turn %d" % [w.get("civ", "?"), w.get("victoryType", "?"), int(main.state.get("turn", 0))]
			over = true
		elif reply.ok and bool(reply.result.get("defeated", false)):
			result = "%s was defeated on turn %d" % [player, int(main.state.get("turn", 0))]
			over = true
		if over:
			_screenshot("end")
			break
		if int(main.state.get("turn", 0)) == before:
			result = "End turn didn't end the turn (turn %d): %s" % [turn, main._status_text if "_status_text" in main else "?"]
			break
		if int(main.state.get("turn", 0)) >= max_turns:
			result = "no winner by turn %d (--max-turns)" % int(main.state.get("turn", 0))
			break
		if Time.get_ticks_msec() / 1000.0 - _turn_started > STUCK_TURN:
			result = "turn %d took over %d seconds" % [turn, int(STUCK_TURN)]
			break
		if turn % 10 == 0:
			print("AUTOPLAY: turn %d, %d problems so far, %d fps" % [turn, errors.size(), Engine.get_frames_per_second()])
	return _finish()


## What a player looks at during a turn: their units' cards always, the rest every few turns.
func _look_around() -> void:
	var player := str(main.state.get("playerCiv", ""))
	var units: Array = main.state.get("units", []).filter(func(u: Dictionary) -> bool: return u.get("civ") == player)
	_enter("selecting units")
	var attacked := false
	for unit: Dictionary in units.slice(0, 6):
		await main._select_unit(int(unit["id"]), false)
		await _settle()
		# A player attacks whatever their units can reach: through the client's own attack, with its animation
		var targets: Array = main.selected_unit.get("targets", []) if not main.selected_unit.is_empty() else []
		if not attacked and not targets.is_empty():
			var t: Dictionary = targets[turn % targets.size()]
			_enter("attacking with %s" % unit.get("name", "a unit"))
			await main.attack(Vector2i(int(t["x"]), int(t["y"])))
			for i in 30:   # the pointer keeps moving over the map while the fight and any death play out
				await get_tree().process_frame
			attacked = true
			_enter("selecting units")
	main._deselect()
	var cities: Array = main.state.get("cities", []).filter(func(c: Dictionary) -> bool: return c.get("civ", player) == player and not c.get("isPuppet", false))
	if turn % 5 == 0 and not cities.is_empty():
		var city: Dictionary = cities[turn / 5 % cities.size()]
		_enter("in the city view of %s" % city["name"])
		await main.enter_city_view(str(city["name"]))
		await _settle()
		var options: Array = main.city_view_data.get("options", [])
		if not options.is_empty():
			await main._select_city_construction(str(options[turn % options.size()]["name"]), -1)
			await _settle()
		await main.exit_city_view()
		await _settle()
	if turn % 7 == 0:
		for tab: Array in main.overview_board.TABS:
			_enter("on the overview's %s tab" % tab[0])
			main.overview_board.show_tab(str(tab[0]))
			await main._refresh_overview()
			await _settle()
		main.overview_board.show_tab("cities")
	if turn % 11 == 0:
		for tab: Array in main.big_screen.TABS:
			_enter("on the big screen's %s tab" % tab[0])
			await main.show_big_screen(str(tab[0]))
			await _settle()
		if not main._xr_mode:
			main._set_big_visible(false)
	if turn % 23 == 0:
		_enter("in the Civilopedia")
		await main.open_civilopedia()
		await _settle()
		main.close_civilopedia()
	if turn % 29 == 0:
		_enter("in the settings")
		main.open_settings()
		for page: Array in main.settings_board.PAGES:
			main.settings_board.show_page(str(page[0]))
			await _settle()
		main.close_settings()
		await _settle()


## Unciv's messages, answered through the client the way its buttons do (a different option each time).
func _answer_messages() -> void:
	_enter("answering messages")
	for i in 12:
		var waiting: Array = main.state.get("alerts", []).filter(func(a: Dictionary) -> bool: return a.get("needsAnswer", false))
		if waiting.is_empty():
			return
		var alert: Dictionary = waiting[0]
		var options: Array = alert.get("options", []).filter(func(o: Dictionary) -> bool: return o.get("enabled", true) and o["id"] != "counter")
		if options.is_empty():
			return
		var option: Dictionary = options[(turn + i) % options.size()]
		_enter("answering '%s' with %s" % [alert.get("type", "?"), option["id"]])
		await main.answer_alert("%s|%s" % [alert["key"], option["id"]])
		await _settle()


## Whatever still stops the turn ending: the client's own picker for it first (as End turn would open it), then the
## choice a player would make there.
func _clear_blockers() -> bool:
	for i in 10:
		var blockers: Array = main.state.get("blockers", [])
		if blockers.is_empty():
			return true
		var blocker: Dictionary = blockers[0]
		var kind := str(blocker.get("type", ""))
		_enter("handling '%s'" % kind)
		await main._handle_blocker(blocker)
		await _settle()
		match kind:
			"AnswerAlerts":
				await _answer_messages()
			"PickPolicy", "MoveSpies":
				await main.bridge.request("dismissBlocker", {"type": kind})
			"PickTech":
				var techs: Dictionary = await main.bridge.request("getTechs")
				if techs.ok:
					for tech: Dictionary in techs.result.get("techs", []):
						if tech.get("researchable", false):
							await main.bridge.request("setResearch", {"tech": tech["name"]})
							break
			"PickConstruction":
				var city: Dictionary = await main.bridge.request("getCity", {"name": blocker.get("city", "")})
				if city.ok:
					for option: Dictionary in city.result.get("options", []):
						if option.get("buildable", false):
							await main.bridge.request("setProduction", {"name": blocker.get("city", ""), "construction": option["name"]})
							break
			"PickGreatPerson":
				var people: Dictionary = await main.bridge.request("getGreatPersonChoices")
				if people.ok:
					for person: Dictionary in people.result.get("choices", []):
						if person.get("available", false):
							await main.bridge.request("chooseGreatPerson", {"unit": person["name"]})
							break
			"WorldCongressVote":
				var votes: Dictionary = await main.bridge.request("getVoteChoices")
				var civs: Array = votes.result.get("civs", []) if votes.ok else []
				await main.bridge.request("vote", {"civ": civs[0]["name"]} if not civs.is_empty() else {})
			"FoundPantheon", "ExpandPantheon", "FoundReligion", "EnhanceReligion", "ReformReligion":
				await _choose_religion()
			"NextUnit":
				await main.bridge.request("setSettings", {"checkForDueUnits": false})
			_:
				await main.bridge.request("debug", {"command": "autoPlay"})
		await main.refresh()
		await _settle()
	return (main.state.get("blockers", []) as Array).is_empty()


func _choose_religion() -> void:
	var reply: Dictionary = await main.bridge.request("getReligionChoices")
	if not reply.ok or reply.result.get("mode") == null:
		return
	var choices: Dictionary = reply.result
	var beliefs: Array = []
	for slot: String in choices.get("slots", []):
		for belief: Dictionary in choices.get("beliefs", []):
			if belief.get("type") == slot and belief.get("available", false) and not belief["name"] in beliefs:
				beliefs.append(belief["name"])
				break
	var params := {"beliefs": beliefs}
	if choices.get("pickIconAndName", false):
		for icon: Dictionary in choices.get("icons", []):
			if icon.get("available", false):
				params["icon"] = icon["name"]
				break
	await main.bridge.request("chooseReligion", params)


## A few frames for what was just opened to lay itself out and draw (and for its errors to show up).
func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	_collect_errors()


func _screenshot(label: String) -> void:
	var path := dir.path_join("%s.png" % label)
	var image := get_viewport().get_texture().get_image()
	if image != null and image.save_png(path) == OK:
		shots.append(path.get_file())


func _finish() -> int:
	Engine.time_scale = 1.0
	_collect_errors()
	if _logger != null:
		OS.remove_logger(_logger)
	var slow: Array = turn_seconds.duplicate()
	slow.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var lines: Array[String] = ["# Client autoplay - %s" % Time.get_datetime_string_from_system(), "",
		"**%s.** %d turns played%s." % [result, turn_seconds.size(), " in the VR layout" if main._xr_mode else " on the desktop"],
		"%d problems, %d slow frames (over %.2f s)." % [errors.size(), hitches.size(), SLOW_FRAME], ""]
	lines.append("Slowest turns, start to finish (seconds, turn): %s" % [slow.slice(0, 5).map(func(t: Array) -> String: return "%s (%d)" % [t[1], t[0]])])
	var spent: Array = time_in.keys()
	spent.sort_custom(func(a: String, b: String) -> bool: return time_in[a] > time_in[b])
	lines.append("Where the time went (seconds): %s" % ", ".join(spent.slice(0, 8).map(func(k: String) -> String: return "%s %d" % [k, int(time_in[k])])))
	lines.append("")
	lines.append("## Problems")
	if errors.is_empty():
		lines.append("None.")
	for text: String in errors:
		var e: Dictionary = errors[text]
		lines.append("- **%s**, first on turn %d while %s%s: %s" % [e["kind"], e["first_turn"], e["phase"],
			"" if int(e["count"]) == 1 else " (x%d)" % int(e["count"]), text])
	lines.append("")
	lines.append("## Slow frames")
	var by_phase := {}
	for h: Array in hitches:
		var key := str(h[1])
		if not by_phase.has(key):
			by_phase[key] = [0, 0.0, int(h[0])]
		by_phase[key][0] += 1
		by_phase[key][1] = maxf(by_phase[key][1], float(h[2]))
	if by_phase.is_empty():
		lines.append("None.")
	for key: String in by_phase:
		lines.append("- %s: %d, the longest %.2f s (first on turn %d)" % [key, by_phase[key][0], by_phase[key][1], by_phase[key][2]])
	if not shots.is_empty():
		lines.append("")
		lines.append("## Screenshots")
		lines.append(", ".join(shots))
	var report := FileAccess.open(dir.path_join("report.md"), FileAccess.WRITE)
	if report != null:
		report.store_string("\n".join(lines) + "\n")
		report.close()
	var data := FileAccess.open(dir.path_join("report.json"), FileAccess.WRITE)
	if data != null:
		data.store_string(JSON.stringify({"result": result, "turns": turn_seconds.size(), "problems": errors,
			"slowFrames": hitches, "turnSeconds": turn_seconds, "screenshots": shots}, " "))
		data.close()
	print("AUTOPLAY: %s - %d problems, %d slow frames. Report: %s" % [result, errors.size(), hitches.size(), dir.path_join("report.md")])
	return 1 if not errors.is_empty() or result.begins_with("stuck") or result.contains("failed") else 0
