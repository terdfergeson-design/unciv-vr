# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Panels: boards anyone can add, each a folder with a panel.json that says where its rows come from (a list in
## the bridge's getState, or a read-only bridge request) and how a row looks, through small "{field}" templates.
## Built-in ones are in client/panels, players' and mods' own in ~/.unciv-vr/Panels; see panels/README.md.
##
## Everything here is data in, data out (no nodes), so the client and the tests use the same code.
## A panel can only read: requests are limited to READ_METHODS and clicks to CLICKS.

const ModFolders := preload("res://scripts/mod_folders.gd")
const KIND := "Panels"
const JSON_NAME := "panel.json"

## Bridge methods a panel may ask for its rows: the ones that only read (see the bridge's PROTOCOL.md).
const READ_METHODS := ["getState", "getOverview", "getDiplomacy", "getTechs", "getPolicies", "getVictory",
	"getEspionage", "getReligionChoices", "getGreatPersonChoices", "getVoteChoices", "getRuleset", "getCity",
	"getUnit", "getTile", "getTradeOptions", "listSaves"]
## What clicking a row may do, and the fields each one needs.
const CLICKS := {
	"select_unit": ["id"],        # select that unit of yours (the view slides to it)
	"look_at": ["x", "y"],        # slide the map to a tile
	"open_city": ["name"],        # one of your cities: its card
	"city_view": ["name"],        # one of your cities: the city view
}
## Where a panel stands when its panel.json doesn't say: on your left, beside the table, facing you.
const HOME := [-1.02, 0.42, 0.3, 62.0]
const SIZE := [0.3, 0.8]          # metres
const WIDTH := 360                # pixels across; the height follows the size's shape


## Every panel that can be shown: folder name -> its spec (panel.json, with "folder" and "builtin" added).
static func available() -> Dictionary:
	var out := {}
	var builtin_dir: String = ModFolders.search_dirs(KIND)[0]
	for dir_path: String in ModFolders.search_dirs(KIND):
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var subs := dir.get_directories()
		subs.sort()
		for sub in subs:
			if out.has(sub):
				continue   # a built-in one with the same name wins; a mod should pick its own
			var spec := load_spec(dir_path.path_join(sub))
			if spec.is_empty():
				continue
			spec["folder"] = sub
			spec["builtin"] = dir_path == builtin_dir
			out[sub] = spec
	return out


## A panel.json, with the defaults filled in; {} when it's missing or broken (with a warning saying why).
static func load_spec(folder: String) -> Dictionary:
	var json: Variant = ModFolders.read_json(folder.path_join(JSON_NAME))
	if not json is Dictionary:
		return {}
	var spec: Dictionary = json
	var problem := check(spec)
	if problem != "":
		push_warning("Panel %s: %s" % [folder, problem])
		return {}
	spec["name"] = str(spec.get("name", folder.get_file()))
	spec["shown"] = bool(spec.get("shown", true))
	spec["size"] = _numbers(spec.get("size"), SIZE)
	spec["home"] = _numbers(spec.get("home"), HOME)
	spec["width"] = int(spec.get("width", WIDTH))
	spec["tilt"] = float(spec.get("tilt", 0.0))
	return spec


## What's wrong with a spec, or "" if nothing. Checked when it's read, so a broken mod says so once.
static func check(spec: Dictionary) -> String:
	var source: Variant = spec.get("source")
	if source is Dictionary:
		var method := str((source as Dictionary).get("request", ""))
		if method not in READ_METHODS:
			return "\"source\" asks for %s, which a panel can't (it may use %s)" % [method, ", ".join(READ_METHODS)]
	elif not source is String or str(source) == "":
		return "needs a \"source\": a list in getState (\"units\", \"cities\"...) or {\"request\": ..., \"path\": ...}"
	var click: Variant = spec.get("click")
	if click != null:
		if not click is Dictionary or str((click as Dictionary).get("do", "")) not in CLICKS:
			return "\"click\" must be {\"do\": one of %s, ...}" % ", ".join(CLICKS.keys())
		for field: String in CLICKS[str((click as Dictionary)["do"])]:
			if not (click as Dictionary).has(field):
				return "\"click\" %s needs \"%s\"" % [(click as Dictionary)["do"], field]
	return ""


## The request a panel needs before it can show anything, or {} when its rows come from getState.
## "refresh" in the source says how often to ask again: "turn" (the default: each turn, and when the panel is
## shown) or "always" (after everything you do, like getState).
static func request_for(spec: Dictionary) -> Dictionary:
	var source: Variant = spec.get("source")
	if source is Dictionary:
		return {"method": str(source["request"]), "params": (source as Dictionary).get("params", {}),
			"refresh": str((source as Dictionary).get("refresh", "turn"))}
	return {}


## The rows to show: from [param state] (getState) or [param reply] (the request's result), filtered,
## sorted and grouped as the spec says. Each row is the source's own Dictionary; a group heading is
## {"_group": text}.
static func rows(spec: Dictionary, state: Dictionary, reply: Variant = null) -> Array:
	var source: Variant = spec.get("source")
	var found: Variant
	if source is Dictionary:
		found = value_at(reply, str((source as Dictionary).get("path", "")))
	else:
		found = value_at(state, str(source))
	if not found is Array:
		return []
	var list: Array = (found as Array).filter(func(row: Variant) -> bool: return row is Dictionary and _passes(spec, row))
	var sort_keys: Array = spec.get("sort", []) if spec.get("sort") is Array else ([spec["sort"]] if spec.has("sort") else [])
	var group := str(spec.get("group", ""))
	if group != "":
		sort_keys.push_front(group)   # rows of a group together, in the order the groups first come
	if not sort_keys.is_empty():
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _before(a, b, sort_keys))
	if group == "":
		return list
	var out: Array = []
	var last := ""
	for row: Dictionary in list:
		var here := show(value_at(row, group))
		if out.is_empty() or here != last:
			out.append({"_group": fill(str(spec.get("groupTitle", "{" + group + "}")), row)})
			last = here
		out.append(row)
	return out


## "filter": {"field": value, ...} - every field must match (true / false, a number or a text).
static func _passes(spec: Dictionary, row: Dictionary) -> bool:
	var filter: Variant = spec.get("filter")
	if not filter is Dictionary:
		return true
	for path: String in filter:
		var want: Variant = filter[path]
		var have: Variant = value_at(row, path)
		if want is bool:
			if bool(have) != want:
				return false
		elif str(have) != str(want):
			return false
	return true


## "sort": ["field", "-field"...]: ascending, or descending with a minus. Missing values go last.
static func _before(a: Dictionary, b: Dictionary, keys: Array) -> bool:
	for key: String in keys:
		var descending := key.begins_with("-")
		var path := key.trim_prefix("-")
		var x: Variant = value_at(a, path)
		var y: Variant = value_at(b, path)
		if x == null and y == null:
			continue
		if x == null or y == null:
			return y == null
		var order := _compare(x, y)
		if order != 0:
			return order > 0 if descending else order < 0
	return false


static func _compare(x: Variant, y: Variant) -> int:
	if (x is int or x is float or x is bool) and (y is int or y is float or y is bool):
		var a := float(x)
		var b := float(y)
		return 0 if is_equal_approx(a, b) else (-1 if a < b else 1)
	return str(x).naturalnocasecmp_to(str(y))


## The value at [param path] ("name", "location.x", "promotions.size", "list.0"), or null.
static func value_at(data: Variant, path: String) -> Variant:
	if path == "":
		return data
	var here: Variant = data
	for part in path.split("."):
		if here is Dictionary:
			here = (here as Dictionary).get(part)
		elif here is Array:
			if part == "size":
				here = (here as Array).size()
			elif part.is_valid_int() and int(part) < (here as Array).size():
				here = (here as Array)[int(part)]
			else:
				return null
		elif here is String and part == "size":
			here = (here as String).length()
		else:
			return null
	return here


## Fills a template: "{field}" is the row's value ("{a.b}" goes deeper); "{a|b|'text'}" is the first of
## them that isn't empty, quoted ones being plain text. [param extra] adds names of its own (like "count").
static func fill(template: String, row: Dictionary, extra := {}) -> String:
	var out := ""
	var i := 0
	while i < template.length():
		var open := template.find("{", i)
		if open < 0:
			out += template.substr(i)
			break
		var close := template.find("}", open)
		if close < 0:
			out += template.substr(i)
			break
		out += template.substr(i, open - i)
		out += _first_of(template.substr(open + 1, close - open - 1), row, extra)
		i = close + 1
	return out


static func _first_of(choices: String, row: Dictionary, extra: Dictionary) -> String:
	for choice in choices.split("|"):
		var name := choice.strip_edges()
		# "field?'text'": the text (or another field) only when the field is set - "{canPromote?'Promotion ready'}"
		var question := name.find("?")
		if question > 0:
			if not truthy(_named(name.substr(0, question).strip_edges(), row, extra)):
				continue
			name = name.substr(question + 1).strip_edges()
		if name.begins_with("'") and name.ends_with("'") and name.length() >= 2:
			return name.substr(1, name.length() - 2)
		# "field#'word'": a count with its word, "1 turn" / "38 turns"; nothing unless it's above 0
		var hash := name.find("#")
		if hash > 0:
			var count: Variant = _named(name.substr(0, hash).strip_edges(), row, extra)
			var word := name.substr(hash + 1).strip_edges().trim_prefix("'").trim_suffix("'")
			if (count is int or count is float) and float(count) > 0.0:
				return "%s %s%s" % [show(count), word, "" if is_equal_approx(float(count), 1.0) else "s"]
			continue
		var text := show(_named(name, row, extra))
		if text != "":
			return text
	return ""


static func _named(name: String, row: Dictionary, extra: Dictionary) -> Variant:
	return extra[name] if extra.has(name) else value_at(row, name)


## Whether a value counts as set: true, a number above 0 (Unciv's -1 means "doesn't apply"), text or a list
## that isn't empty.
static func truthy(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) > 0.0 and not is_zero_approx(float(value))
	if value is String:
		return value != ""
	if value is Array:
		return not (value as Array).is_empty()
	return true


## A value as text: whole numbers without ".0", others with one decimal; nothing for null or false.
static func show(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool:
		return "yes" if value else ""
	if value is float:
		var f: float = value
		return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f
	if value is Array:
		return ", ".join((value as Array).map(func(v: Variant) -> String: return show(v)))
	return str(value)


## What clicking [param row] does: {"do": ..., and its fields filled from the row}, or {} for nothing.
static func click_for(spec: Dictionary, row: Dictionary) -> Dictionary:
	var click: Variant = spec.get("click")
	if not click is Dictionary or row.has("_group"):
		return {}
	var out := {"do": str(click["do"])}
	for field: String in CLICKS.get(out["do"], []):
		out[field] = fill(str(click[field]), row)
	return out


static func _numbers(value: Variant, default: Array) -> Array:
	if value is Array and (value as Array).size() == default.size():
		return (value as Array).map(func(v: Variant) -> float: return float(v))
	return default.duplicate()
