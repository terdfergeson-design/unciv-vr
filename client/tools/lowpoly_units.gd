# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends "res://tools/lowpoly_wonders.gd"   # for its helpers (steam, rocks...); build_all is our own
## The LowPoly tileset's units: a model for every regular unit in Unciv's Civ V rulesets, one per unit type
## (for units from mods), and the boat embarked land units ride in.
##
## Conventions (see tilesets/README.md):
##   - origin on the ground at the middle of the unit's spot, which is about 0.25 map units across
##   - the unit faces +Z; the game turns it towards where it's going or what it's fighting
##   - surfaces in the materials "CivOuter" / "CivInner" are tinted with the owner's colours
##   - land troops are small squads (three figures, two riders), like Civ V; civilians and machines stand alone
##   - aircraft are modelled in the air, about 0.3 above the ground

const SKIN := [Color(0.94, 0.78, 0.64), Color(0.8, 0.6, 0.45), Color(0.6, 0.42, 0.3), Color(0.42, 0.29, 0.2)]
const METAL := Color(0.72, 0.73, 0.76)
const DARK_METAL := Color(0.44, 0.45, 0.48)
const WOOD := Color(0.64, 0.47, 0.3)
const LEATHER := Color(0.62, 0.47, 0.32)
const OLIVE := Color(0.52, 0.56, 0.38)
const NAVY := Color(0.58, 0.61, 0.66)
const SAIL := Color(0.93, 0.9, 0.82)
const CIV_O := Color(1, 1, 1)          # drawn into CivOuter / CivInner: the colour comes from the civ
const SQUAD := [Vector3(-0.075, 0, -0.04), Vector3(0.075, 0, -0.04), Vector3(0.0, 0, 0.065)]
const PAIR := [Vector3(-0.07, 0, -0.02), Vector3(0.07, 0, 0.03)]

var _skin := 0


func build_all() -> Dictionary:
	var out := {}
	var makers := units()
	for unit: String in makers:
		_rng.seed = hash(unit)
		_skin = absi(hash(unit)) % SKIN.size()
		_begin()
		(makers[unit] as Callable).call()
		out["Units/" + unit] = _finish()
	# One per unit type, for units from mods: the most typical unit of that type
	for unit_type: String in TYPE_FALLBACKS:
		_rng.seed = hash(unit_type)
		_begin()
		(makers[TYPE_FALLBACKS[unit_type]] as Callable).call()
		out["Units/" + unit_type] = _finish()
	_begin()
	embarked()
	out["Units/Embarked"] = _finish()
	return out


## What a unit of each type looks like when the set has no model for the unit itself (Unciv's unit types).
const TYPE_FALLBACKS := {
	"Civilian": "Worker", "Scout": "Scout", "Sword": "Swordsman", "Archery": "Archer", "Mounted": "Horseman",
	"Siege": "Catapult", "Gunpowder": "Rifleman", "Ranged Gunpowder": "Machine Gun", "Armored": "Tank",
	"Melee Water": "Trireme", "Ranged Water": "Frigate", "Civilian Water": "Work Boats", "Submarine": "Submarine",
	"Aircraft Carrier": "Carrier", "Fighter": "Fighter", "Bomber": "Bomber", "Helicopter": "Helicopter Gunship",
	"Missile": "Guided Missile", "Atomic Bomber": "Atomic Bomb",
}


func units() -> Dictionary:
	return {
		# civilians
		"Worker": func() -> void: _single({"weapon": "pick", "hat": "cap", "torso": LEATHER}),
		"Settler": settler,
		"Work Boats": work_boats,
		"Missionary": func() -> void: _single({"robe": true, "weapon": "staff", "hat": "hood", "item": "book"}),
		"Inquisitor": func() -> void: _single({"robe": true, "weapon": "staff", "hat": "mitre", "dark": true}),
		"Great Artist": func() -> void: _single({"robe": true, "hat": "beret", "item": "palette"}, true),
		"Great Scientist": func() -> void: _single({"robe": true, "item": "book", "weapon": "telescope"}, true),
		"Great Merchant": great_merchant,
		"Great Engineer": func() -> void: _single({"weapon": "hammer", "hat": "cap", "item": "gear", "torso": LEATHER}, true),
		"Great Prophet": func() -> void: _single({"robe": true, "weapon": "staff", "hat": "hood", "halo": true}, true),
		"Great General": great_general,
		"Great Admiral": great_admiral,
		"SS Booster": func() -> void: _space_part("booster"),
		"SS Cockpit": func() -> void: _space_part("cockpit"),
		"SS Engine": func() -> void: _space_part("engine"),
		"SS Stasis Chamber": func() -> void: _space_part("stasis"),
		# ancient and classical
		"Scout": func() -> void: _squad({"hat": "brim", "weapon": "spear_short", "torso": LEATHER}, 2),
		"Warrior": func() -> void: _squad({"weapon": "club", "torso": LEATHER, "bare": true}),
		"Archer": func() -> void: _squad({"weapon": "bow", "torso": LEATHER, "hat": "band"}),
		"Spearman": func() -> void: _squad({"weapon": "spear", "shield": "round", "hat": "cone"}),
		"Swordsman": func() -> void: _squad({"weapon": "sword", "shield": "square", "hat": "helmet"}),
		"Composite Bowman": func() -> void: _squad({"weapon": "bow", "hat": "cone"}),
		"Horseman": func() -> void: _cavalry({"weapon": "spear_short", "hat": "helmet"}),
		"Chariot Archer": chariot_archer,
		"Catapult": catapult,
		"Trireme": func() -> void: _galley(false),
		# medieval and renaissance
		"Pikeman": func() -> void: _squad({"weapon": "pike", "shield": "kite", "hat": "kettle"}),
		"Longswordsman": func() -> void: _squad({"weapon": "longsword", "shield": "kite", "hat": "great_helm"}),
		"Crossbowman": func() -> void: _squad({"weapon": "crossbow", "hat": "kettle"}),
		"Knight": func() -> void: _cavalry({"weapon": "lance", "hat": "great_helm", "shield": "kite"}, true),
		"Trebuchet": trebuchet,
		"Galleass": func() -> void: _galley(true),
		"Caravel": func() -> void: _sailing_ship(2, false),
		"Musketman": func() -> void: _squad({"weapon": "musket", "hat": "morion"}),
		"Lancer": func() -> void: _cavalry({"weapon": "lance", "hat": "shako"}),
		"Cannon": func() -> void: _gun_carriage(0.15, 0.03, true),
		"Privateer": func() -> void: _sailing_ship(2, true),
		"Frigate": func() -> void: _sailing_ship(3, true),
		# industrial
		"Rifleman": func() -> void: _squad({"weapon": "rifle", "hat": "shako"}),
		"Cavalry": func() -> void: _cavalry({"weapon": "sabre", "hat": "shako"}),
		"Gatling Gun": gatling_gun,
		"Artillery": func() -> void: _gun_carriage(0.22, 0.025, false, true),
		"Ironclad": ironclad,
		"Great War Infantry": func() -> void: _squad({"weapon": "rifle", "hat": "brodie", "torso": OLIVE, "legs": OLIVE}),
		"Triplane": func() -> void: _biplane(3),
		"Great War Bomber": func() -> void: _biplane(2, true),
		"Landship": landship,
		"Submarine": func() -> void: _submarine(false),
		# modern and later
		"Infantry": func() -> void: _squad({"weapon": "rifle", "hat": "modern", "torso": OLIVE, "legs": OLIVE}),
		"Marine": func() -> void: _squad({"weapon": "rifle", "hat": "modern", "torso": Color(0.3, 0.38, 0.3), "legs": Color(0.3, 0.38, 0.3), "pack": true}),
		"Paratrooper": func() -> void: _squad({"weapon": "rifle", "hat": "modern", "torso": OLIVE, "legs": OLIVE, "parachute": true}),
		"Machine Gun": machine_gun,
		"Anti-Aircraft Gun": func() -> void: _flak(false),
		"Anti-Tank Gun": func() -> void: _gun_carriage(0.2, 0.02, false, true, true),
		"Mechanized Infantry": func() -> void: _apc(),
		"Tank": func() -> void: _tank(false),
		"Modern Armor": func() -> void: _tank(true),
		"Giant Death Robot": giant_death_robot,
		"Rocket Artillery": func() -> void: _truck("rockets"),
		"Mobile SAM": func() -> void: _truck("sam"),
		"Destroyer": func() -> void: _warship(0.36, 1, false),
		"Battleship": func() -> void: _warship(0.44, 3, false),
		"Missile Cruiser": func() -> void: _warship(0.4, 1, true),
		"Nuclear Submarine": func() -> void: _submarine(true),
		"Carrier": carrier,
		"Fighter": func() -> void: _prop_fighter(),
		"Jet Fighter": func() -> void: _jet(false),
		"Bomber": func() -> void: _heavy_bomber(),
		"Stealth Bomber": func() -> void: _jet(true),
		"Helicopter Gunship": helicopter,
		"Atomic Bomb": func() -> void: _bomb(true),
		"Guided Missile": func() -> void: _missile(false),
		"Nuclear Missile": func() -> void: _missile(true),
	}


# region shape helpers ------------------------------------------------------------------------

## A flat shape [param points] (x right, y up) at [param center], [param depth] thick front to back, turned by [param yaw].
func _plate(center: Vector3, points: Array, depth: float, color: Color, yaw := 0.0, surface := "") -> void:
	var before := _special
	if surface != "":
		_special = surface
	var basis := Basis(Vector3.UP, yaw)
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	for p: Vector2 in points:
		front.append(center + basis * Vector3(p.x, p.y, depth / 2.0))
		back.append(center + basis * Vector3(p.x, p.y, -depth / 2.0))
	_hint_up = false
	var mid := Vector3.ZERO
	for v in front:
		mid += v
	mid /= front.size()
	_hint = mid - basis * Vector3(0, 0, 1)
	for i in range(1, points.size() - 1):
		_tri(front[0], front[i], front[i + 1], color)
	_hint = mid + basis * Vector3(0, 0, 1)
	for i in range(1, points.size() - 1):
		_tri(back[0], back[i], back[i + 1], color)
	_hint = center
	for i in points.size():
		var j := (i + 1) % points.size()
		_quad(front[i], front[j], back[j], back[i], color.darkened(0.08))
	_hint_up = true
	_special = before


## A flat shape [param points] (x right, z forward) lying flat at [param center], [param thickness] thick.
func _deck(center: Vector3, points: Array, thickness: float, color: Color, yaw := 0.0, surface := "") -> void:
	var before := _special
	if surface != "":
		_special = surface
	var basis := Basis(Vector3.UP, yaw)
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for p: Vector2 in points:
		top.append(center + basis * Vector3(p.x, thickness / 2.0, p.y))
		bottom.append(center + basis * Vector3(p.x, -thickness / 2.0, p.y))
	_hint_up = false
	_hint = center - Vector3(0, 1, 0)
	for i in range(1, points.size() - 1):
		_tri(top[0], top[i], top[i + 1], color)
	_hint = center + Vector3(0, 1, 0)
	for i in range(1, points.size() - 1):
		_tri(bottom[0], bottom[i], bottom[i + 1], color.darkened(0.15))
	_hint = center
	for i in points.size():
		var j := (i + 1) % points.size()
		_quad(top[i], top[j], bottom[j], bottom[i], color.darkened(0.06))
	_hint_up = true
	_special = before


func _rod(from: Vector3, to: Vector3, radius: float, color: Color, surface := "") -> void:
	var before := _special
	if surface != "":
		_special = surface
	_trunk(from, to, radius, color)
	_special = before


func _civ_box(center: Vector3, size: Vector3, yaw := 0.0, inner := false) -> void:
	var before := _special
	_special = "CivInner" if inner else "CivOuter"
	_box(center, size, CIV_O, yaw)
	_special = before


static func _circle(radius: float, sides := 8) -> Array:
	var out := []
	for i in sides:
		var a := TAU * i / sides
		out.append(Vector2(cos(a), sin(a)) * radius)
	return out


func _wheel(center: Vector3, radius: float, yaw: float, color := WOOD) -> void:
	_plate(center, _circle(radius, 8), 0.012, color, yaw + PI / 2.0)


## Turns a point given in the unit's own frame (x right, z forward) to model space at [param at], facing [param yaw].
static func _at(at: Vector3, yaw: float, local: Vector3) -> Vector3:
	return at + local.rotated(Vector3.UP, yaw)


# region people ---------------------------------------------------------------------------------

## A standing figure about 0.2 tall at [param at], facing +Z turned by [param yaw]. [param kit] picks the
## clothes and gear: torso / legs colours, robe, bare (no shirt), hat, weapon, shield, item, pack, halo...
func _figure(at: Vector3, yaw: float, kit: Dictionary, seated := false) -> void:
	var skin: Color = SKIN[(_skin + int(at.x * 37.0 + at.z * 53.0 + 10.0)) % SKIN.size()]
	var lift := 0.06 if seated else 0.0
	var robe: bool = kit.get("robe", false)
	var legs_color: Color = kit.get("legs", Color(0.5, 0.42, 0.32))
	var dark: bool = kit.get("dark", false)
	var p := func(x: float, y: float, z: float) -> Vector3: return _at(at, yaw, Vector3(x, y + lift, z))
	if robe:
		var before := _special
		_special = "CivOuter"
		_frustum(p.call(0, 0, 0), 0.042, 0.026, 0.14, 6, Color(0.35, 0.33, 0.33) if dark else CIV_O)
		_special = before
	elif seated:
		_box(p.call(-0.014, 0.0, 0.02), Vector3(0.022, 0.024, 0.06), legs_color, yaw)
		_box(p.call(0.014, 0.0, 0.02), Vector3(0.022, 0.024, 0.06), legs_color, yaw)
	else:
		_box(p.call(-0.014, 0.0375, 0), Vector3(0.022, 0.075, 0.025), legs_color, yaw)
		_box(p.call(0.014, 0.0375, 0), Vector3(0.022, 0.075, 0.025), legs_color, yaw)
	if kit.get("bare", false):
		_box(p.call(0, 0.11, 0), Vector3(0.055, 0.07, 0.032), skin, yaw)
		_civ_box(p.call(0, 0.08, 0), Vector3(0.058, 0.02, 0.035), yaw)   # a sash in the civ's colour
	elif not robe:
		if kit.has("torso"):
			_box(p.call(0, 0.11, 0), Vector3(0.055, 0.07, 0.032), kit["torso"], yaw)
			_civ_box(p.call(0, 0.128, 0.0165), Vector3(0.03, 0.02, 0.004), yaw, true)   # a patch
		else:
			_civ_box(p.call(0, 0.11, 0), Vector3(0.055, 0.07, 0.032), yaw)
		_box(p.call(0, 0.08, 0), Vector3(0.057, 0.012, 0.034), LEATHER, yaw)
	# arms
	var sleeve: Color = skin if kit.get("bare", false) else kit.get("torso", Color(0.9, 0.9, 0.9))
	for side: float in [-1.0, 1.0]:
		if robe or not kit.has("torso"):
			_civ_box(p.call(side * 0.036, 0.115, 0.004), Vector3(0.015, 0.06, 0.016), yaw)
		else:
			_box(p.call(side * 0.036, 0.115, 0.004), Vector3(0.015, 0.06, 0.016), sleeve, yaw)
		_blob(p.call(side * 0.036, 0.082, 0.006), Vector3(0.009, 0.009, 0.009), skin, 0.1, 0.0)
	# head
	_blob(p.call(0, 0.168, 0), Vector3(0.021, 0.023, 0.021), skin, 0.1, 0.0)
	_hat(p, yaw, str(kit.get("hat", "none")))
	if kit.get("halo", false):
		_special = "Sparkle"
		_deck(p.call(0, 0.205, 0), _circle(0.024, 8), 0.004, Color(1.0, 0.9, 0.5), yaw)
		_special = ""
	if kit.get("pack", false):
		_box(p.call(0, 0.11, -0.026), Vector3(0.04, 0.05, 0.02), OLIVE.darkened(0.2), yaw)
	if kit.get("parachute", false):
		_box(p.call(0, 0.115, -0.026), Vector3(0.042, 0.055, 0.024), Color(0.85, 0.85, 0.8), yaw)
	_weapon(p, yaw, str(kit.get("weapon", "")))
	_shield(p, yaw, str(kit.get("shield", "")))
	_item(p, yaw, str(kit.get("item", "")))


func _hat(p: Callable, yaw: float, hat: String) -> void:
	match hat:
		"cone":
			_cone(p.call(0, 0.175, 0), 0.025, 0.04, 6, METAL)
		"helmet":
			_blob(p.call(0, 0.177, 0), Vector3(0.025, 0.016, 0.025), METAL, 0.05, 0.0)
			_civ_box(p.call(0, 0.198, 0), Vector3(0.006, 0.014, 0.034), yaw, true)   # crest
		"kettle":
			_deck(p.call(0, 0.176, 0), _circle(0.035, 8), 0.005, METAL, yaw)
			_blob(p.call(0, 0.182, 0), Vector3(0.022, 0.014, 0.022), METAL, 0.05, 0.0)
		"great_helm":
			_frustum(p.call(0, 0.15, 0), 0.025, 0.024, 0.042, 6, METAL, METAL.darkened(0.1))
			_civ_box(p.call(0, 0.198, 0), Vector3(0.006, 0.012, 0.03), yaw, true)
		"morion":
			_blob(p.call(0, 0.18, 0), Vector3(0.024, 0.016, 0.03), METAL, 0.05, 0.0)
			_deck(p.call(0, 0.178, 0), _circle(0.033, 6), 0.004, METAL, yaw)
		"shako":
			_frustum(p.call(0, 0.178, 0), 0.02, 0.023, 0.035, 6, Color(0.25, 0.25, 0.28), Color(0.25, 0.25, 0.28))
			_civ_box(p.call(0, 0.185, 0.02), Vector3(0.016, 0.01, 0.004), yaw, true)
		"brodie":
			_deck(p.call(0, 0.181, 0), _circle(0.034, 8), 0.004, OLIVE.darkened(0.15), yaw)
			_blob(p.call(0, 0.184, 0), Vector3(0.02, 0.01, 0.02), OLIVE.darkened(0.15), 0.05, 0.0)
		"modern":
			_blob(p.call(0, 0.178, 0), Vector3(0.026, 0.017, 0.027), OLIVE.darkened(0.2), 0.05, 0.0)
		"cap":
			_frustum(p.call(0, 0.178, 0), 0.023, 0.02, 0.016, 6, Color(0.55, 0.45, 0.3), Color(0.55, 0.45, 0.3))
		"brim":
			_deck(p.call(0, 0.181, 0), _circle(0.04, 8), 0.004, Color(0.5, 0.38, 0.25), yaw)
			_frustum(p.call(0, 0.181, 0), 0.021, 0.018, 0.02, 6, Color(0.5, 0.38, 0.25), Color(0.45, 0.33, 0.22))
		"band":
			_civ_box(p.call(0, 0.175, 0), Vector3(0.045, 0.008, 0.045), yaw, true)
			_box(p.call(0.012, 0.195, -0.015), Vector3(0.006, 0.035, 0.004), Color(0.95, 0.95, 0.9), yaw)   # a feather
		"hood":
			var before := _special
			_special = "CivOuter"
			_blob(p.call(0, 0.172, -0.004), Vector3(0.026, 0.028, 0.026), CIV_O, 0.05, 0.0)
			_special = before
		"mitre":
			_civ_box(p.call(0, 0.195, 0), Vector3(0.026, 0.04, 0.02), yaw, true)
		"beret":
			_blob(p.call(0.004, 0.186, 0), Vector3(0.026, 0.008, 0.026), Color(0.6, 0.15, 0.2), 0.05, 0.0)
		"bicorne":
			_plate(p.call(0, 0.188, 0), [Vector2(-0.04, 0), Vector2(0.04, 0), Vector2(0.0, 0.025)], 0.016, Color(0.22, 0.22, 0.25), yaw + PI / 2.0)


func _weapon(p: Callable, yaw: float, weapon: String) -> void:
	match weapon:
		"club":
			_rod(p.call(0.04, 0.08, 0.015), p.call(0.05, 0.16, 0.03), 0.009, WOOD)
		"spear_short":
			_rod(p.call(0.042, 0.0, 0.012), p.call(0.042, 0.24, 0.012), 0.004, WOOD)
			_cone(p.call(0.042, 0.24, 0.012), 0.008, 0.025, 4, METAL)
		"spear":
			_rod(p.call(0.042, 0.0, 0.012), p.call(0.042, 0.3, 0.012), 0.004, WOOD)
			_cone(p.call(0.042, 0.3, 0.012), 0.009, 0.03, 4, METAL)
		"pike":
			_rod(p.call(0.042, 0.0, 0.0), p.call(0.042, 0.36, 0.06), 0.004, WOOD)
			_cone(p.call(0.042, 0.36, 0.06), 0.008, 0.03, 4, METAL)
		"lance":
			_rod(p.call(0.045, 0.1, -0.05), p.call(0.045, 0.2, 0.2), 0.005, WOOD)
			_cone(p.call(0.045, 0.2, 0.2), 0.009, 0.03, 4, METAL)
		"sword":
			_box(p.call(0.04, 0.11, 0.02), Vector3(0.006, 0.065, 0.004), METAL, yaw)
			_box(p.call(0.04, 0.078, 0.02), Vector3(0.018, 0.005, 0.006), LEATHER, yaw)
		"longsword":
			_box(p.call(0.04, 0.13, 0.02), Vector3(0.006, 0.1, 0.004), METAL, yaw)
			_box(p.call(0.04, 0.08, 0.02), Vector3(0.024, 0.005, 0.006), LEATHER, yaw)
		"sabre":
			_rod(p.call(0.04, 0.08, 0.02), p.call(0.05, 0.16, 0.06), 0.003, METAL)
		"bow":
			var c := p.call(-0.045, 0.11, 0.015) as Vector3
			_rod(c + Vector3(0, -0.06, 0), c + Vector3(0, -0.02, 0).rotated(Vector3.UP, yaw) + Vector3(0, 0, 0.015).rotated(Vector3.UP, yaw), 0.003, WOOD)
			_rod(c + Vector3(0, -0.02, 0) + Vector3(0, 0, 0.015).rotated(Vector3.UP, yaw), c + Vector3(0, 0.02, 0) + Vector3(0, 0, 0.015).rotated(Vector3.UP, yaw), 0.003, WOOD)
			_rod(c + Vector3(0, 0.02, 0) + Vector3(0, 0, 0.015).rotated(Vector3.UP, yaw), c + Vector3(0, 0.06, 0), 0.003, WOOD)
			_rod(c + Vector3(0, -0.06, 0), c + Vector3(0, 0.06, 0), 0.001, Color(0.9, 0.9, 0.85))
			_box(p.call(0.0, 0.12, -0.022), Vector3(0.016, 0.05, 0.014), LEATHER, yaw)   # quiver
		"crossbow":
			_box(p.call(0.0, 0.1, 0.04), Vector3(0.012, 0.012, 0.07), WOOD, yaw)
			_box(p.call(0.0, 0.1, 0.07), Vector3(0.07, 0.006, 0.008), WOOD, yaw)
		"musket":
			_rod(p.call(0.042, 0.03, 0.0), p.call(0.042, 0.2, 0.01), 0.005, WOOD)
			_rod(p.call(0.042, 0.2, 0.01), p.call(0.042, 0.22, 0.012), 0.002, METAL)
		"rifle":
			_rod(p.call(0.03, 0.09, 0.0), p.call(0.012, 0.13, 0.11), 0.005, Color(0.25, 0.2, 0.16))
		"pick":
			_rod(p.call(0.042, 0.06, 0.01), p.call(0.042, 0.17, 0.02), 0.004, WOOD)
			_box(p.call(0.042, 0.17, 0.02), Vector3(0.006, 0.008, 0.05), DARK_METAL, yaw)
		"hammer":
			_rod(p.call(0.042, 0.06, 0.01), p.call(0.042, 0.15, 0.02), 0.004, WOOD)
			_box(p.call(0.042, 0.155, 0.02), Vector3(0.014, 0.014, 0.03), DARK_METAL, yaw)
		"staff":
			_rod(p.call(0.042, 0.0, 0.012), p.call(0.042, 0.23, 0.014), 0.005, WOOD)
		"telescope":
			_rod(p.call(0.036, 0.13, 0.0), p.call(0.03, 0.17, 0.06), 0.007, Color(0.75, 0.6, 0.3))


func _shield(p: Callable, yaw: float, shield: String) -> void:
	match shield:
		"round":
			_plate(p.call(-0.046, 0.105, 0.012), _circle(0.034, 8), 0.007, CIV_O, yaw + PI / 2.0 - 0.3, "CivInner")
		"square":
			_plate(p.call(-0.046, 0.1, 0.012), [Vector2(-0.025, -0.045), Vector2(0.025, -0.045), Vector2(0.025, 0.045), Vector2(-0.025, 0.045)], 0.007, CIV_O, yaw + PI / 2.0 - 0.2, "CivInner")
		"kite":
			_plate(p.call(-0.046, 0.1, 0.012), [Vector2(0, -0.05), Vector2(0.026, 0.0), Vector2(0.024, 0.03), Vector2(-0.024, 0.03), Vector2(-0.026, 0.0)], 0.007, CIV_O, yaw + PI / 2.0 - 0.2, "CivInner")


func _item(p: Callable, yaw: float, item: String) -> void:
	match item:
		"book":
			_box(p.call(-0.03, 0.1, 0.03), Vector3(0.03, 0.036, 0.01), Color(0.55, 0.2, 0.15), yaw)
		"palette":
			_deck(p.call(-0.04, 0.095, 0.03), _circle(0.026, 7), 0.005, Color(0.8, 0.65, 0.45), yaw)
			for i in 4:
				_blob(p.call(-0.04 + cos(i * 1.4) * 0.014, 0.1, 0.03 + sin(i * 1.4) * 0.014), Vector3(0.005, 0.004, 0.005), [Color(0.9, 0.2, 0.2), Color(0.2, 0.4, 0.9), Color(0.95, 0.85, 0.2), Color(0.2, 0.7, 0.3)][i], 0.1, 0.0)
		"gear":
			_plate(p.call(-0.042, 0.1, 0.03), _circle(0.022, 8), 0.008, DARK_METAL, yaw + PI / 2.0)
		"coins":
			_box(p.call(-0.035, 0.07, 0.025), Vector3(0.028, 0.028, 0.022), Color(0.6, 0.45, 0.25), yaw)
			_special = "Sparkle"
			_blob(p.call(-0.035, 0.088, 0.025), Vector3(0.012, 0.006, 0.01), Color(1.0, 0.85, 0.3), 0.1)
			_special = ""


## Three soldiers in a little triangle (or [param count] of them).
func _squad(kit: Dictionary, count := 3) -> void:
	var spots := SQUAD if count == 3 else PAIR
	for spot: Vector3 in spots:
		_figure(spot, _rng.randf_range(-0.12, 0.12), kit)


func _single(kit: Dictionary, great := false) -> void:
	_figure(Vector3(0, 0, 0), 0.0, kit)
	if great:   # great people stand on a little plinth, so they read as special
		_frustum(Vector3(0, -0.012, 0), 0.075, 0.07, 0.012, 8, Color(0.85, 0.75, 0.45), Color(0.9, 0.8, 0.5))


# region animals and carts -----------------------------------------------------------------------

func _horse(at: Vector3, yaw: float, coat: Color, barded := false, kind := "horse") -> void:
	var p := func(x: float, y: float, z: float) -> Vector3: return _at(at, yaw, Vector3(x, y, z))
	var body := Vector3(0.05, 0.045, 0.12)
	var leg := 0.065
	if kind == "camel":
		leg = 0.085
	for s: float in [-1.0, 1.0]:
		for f: float in [-1.0, 1.0]:
			_box(p.call(s * 0.017, leg / 2.0, f * 0.043), Vector3(0.013, leg, 0.013), coat.darkened(0.25), yaw)
	_box(p.call(0, leg + 0.02, 0), body, coat, yaw)
	if kind == "camel":
		_blob(p.call(0, leg + 0.055, 0), Vector3(0.025, 0.025, 0.035), coat, 0.1, 0.0)
	_box(p.call(0, leg + 0.055, 0.065), Vector3(0.026, 0.06, 0.026), coat, yaw - 0.0)   # neck
	_box(p.call(0, leg + 0.085, 0.085), Vector3(0.022, 0.022, 0.05), coat.darkened(0.05), yaw)   # head
	_box(p.call(0, leg + 0.03, -0.066), Vector3(0.01, 0.04, 0.012), coat.darkened(0.4), yaw)   # tail
	if barded:
		_civ_box(p.call(0, leg + 0.012, 0), Vector3(body.x + 0.008, 0.05, body.z + 0.01), yaw)
	else:
		_civ_box(p.call(0, leg + 0.044, -0.005), Vector3(body.x + 0.006, 0.006, 0.05), yaw, true)   # saddle cloth


func _cavalry(kit: Dictionary, barded := false, coats: Array = [Color(0.66, 0.47, 0.3), Color(0.5, 0.38, 0.27)]) -> void:
	for i in PAIR.size():
		var spot: Vector3 = PAIR[i]
		var yaw := _rng.randf_range(-0.1, 0.1)
		_horse(spot, yaw, coats[i % coats.size()], barded)
		_figure(spot + Vector3(0, 0.05, -0.01), yaw, kit, true)


func chariot_archer() -> void:
	_horse(Vector3(0.0, 0, 0.08), 0.0, Color(0.66, 0.5, 0.32))
	_box(Vector3(0, 0.07, -0.06), Vector3(0.09, 0.04, 0.07), WOOD)
	_civ_box(Vector3(0, 0.095, -0.03), Vector3(0.09, 0.02, 0.008))
	for s: float in [-1.0, 1.0]:
		_wheel(Vector3(s * 0.05, 0.04, -0.06), 0.04, 0.0)
	_rod(Vector3(0, 0.07, -0.02), Vector3(0, 0.08, 0.04), 0.004, WOOD)
	_figure(Vector3(0, 0.09, -0.065), 0.0, {"weapon": "bow", "torso": LEATHER})


func settler() -> void:
	# a covered wagon with an ox, and the settler walking beside it
	_box(Vector3(0, 0.07, -0.03), Vector3(0.1, 0.04, 0.15), WOOD)
	var before := _special
	_special = "CivOuter"
	for i in 5:
		var a := PI * i / 4.0
		_box(Vector3(cos(a) * 0.05, 0.09 + sin(a) * 0.05, -0.03), Vector3(0.025, 0.025, 0.14), Color(0.95, 0.93, 0.88), 0.0)
	_special = before
	for s: float in [-1.0, 1.0]:
		for z: float in [-0.08, 0.03]:
			_wheel(Vector3(s * 0.055, 0.035, z), 0.035, 0.0)
	_horse(Vector3(0, 0, 0.12), 0.0, Color(0.55, 0.45, 0.35), false)
	_figure(Vector3(0.1, 0, 0.06), 0.1, {"torso": LEATHER, "hat": "brim", "weapon": "staff"})


func great_merchant() -> void:
	_horse(Vector3(0.03, 0, 0.0), 0.3, Color(0.78, 0.65, 0.45), false, "camel")
	_figure(Vector3(-0.08, 0, 0.04), 0.2, {"robe": true, "hat": "hood", "item": "coins"})
	_frustum(Vector3(0, -0.012, 0), 0.11, 0.1, 0.012, 8, Color(0.85, 0.75, 0.45), Color(0.9, 0.8, 0.5))


func great_general() -> void:
	_horse(Vector3(0, 0, 0), 0.0, Color(0.92, 0.9, 0.86), true)
	_figure(Vector3(0, 0.05, -0.01), 0.0, {"hat": "bicorne", "weapon": "sabre"}, true)
	_rod(Vector3(-0.05, 0.05, -0.04), Vector3(-0.05, 0.3, -0.04), 0.004, WOOD)
	_plate(Vector3(-0.05, 0.27, -0.005), [Vector2(-0.035, -0.022), Vector2(0.035, -0.022), Vector2(0.035, 0.022), Vector2(-0.035, 0.022)], 0.004, CIV_O, PI / 2.0, "CivOuter")
	_frustum(Vector3(0, -0.012, 0), 0.11, 0.1, 0.012, 8, Color(0.85, 0.75, 0.45), Color(0.9, 0.8, 0.5))


func great_admiral() -> void:
	_hull(Vector3(0, 0, 0), 0.3, 0.09, 0.05, WOOD)
	_rod(Vector3(0, 0.04, 0.02), Vector3(0, 0.3, 0.02), 0.005, WOOD)
	_plate(Vector3(0, 0.19, 0.02), [Vector2(-0.06, -0.08), Vector2(0.06, -0.08), Vector2(0.05, 0.08), Vector2(-0.05, 0.08)], 0.006, SAIL, 0.0)
	_plate(Vector3(0, 0.29, 0.05), [Vector2(0, -0.02), Vector2(0.06, -0.005), Vector2(0, 0.012)], 0.003, CIV_O, PI / 2.0, "CivOuter")
	_figure(Vector3(0, 0.04, -0.09), 0.0, {"hat": "bicorne", "weapon": "telescope", "torso": Color(0.15, 0.18, 0.32)})


func _space_part(kind: String) -> void:
	_box(Vector3(0, 0.02, 0), Vector3(0.2, 0.04, 0.12), Color(0.55, 0.55, 0.58))   # a flatbed
	for s: float in [-1.0, 1.0]:
		for z: float in [-0.04, 0.04]:
			_wheel(Vector3(s * 0.065, 0.02, z), 0.02, 0.0, Color(0.15, 0.15, 0.15))
	match kind:
		"booster":
			_rod(Vector3(-0.09, 0.08, 0), Vector3(0.09, 0.08, 0), 0.04, Color(0.92, 0.92, 0.94))
			_civ_box(Vector3(0, 0.08, 0), Vector3(0.03, 0.082, 0.082))
		"cockpit":
			_cone(Vector3(0, 0.04, 0), 0.06, 0.16, 8, Color(0.92, 0.92, 0.94), 0.0, true)
			_civ_box(Vector3(0, 0.09, 0.042), Vector3(0.04, 0.02, 0.01))
		"engine":
			_frustum(Vector3(0, 0.04, 0), 0.06, 0.035, 0.08, 8, DARK_METAL, DARK_METAL)
			_frustum(Vector3(0, 0.12, 0), 0.04, 0.04, 0.03, 8, Color(0.92, 0.92, 0.94), Color(0.92, 0.92, 0.94))
		"stasis":
			_rod(Vector3(-0.08, 0.08, 0), Vector3(0.08, 0.08, 0), 0.04, Color(0.85, 0.88, 0.92))
			_special = "Shimmer"
			_box(Vector3(0, 0.08, 0.035), Vector3(0.09, 0.03, 0.02), Color(0.4, 0.85, 1.0))
			_special = ""


# region siege and guns ---------------------------------------------------------------------------

func catapult() -> void:
	_box(Vector3(0, 0.04, 0), Vector3(0.1, 0.025, 0.16), WOOD)
	for s: float in [-1.0, 1.0]:
		for z: float in [-0.05, 0.05]:
			_wheel(Vector3(s * 0.058, 0.03, z), 0.03, 0.0)
		_box(Vector3(s * 0.04, 0.09, -0.01), Vector3(0.012, 0.09, 0.012), WOOD)
	_box(Vector3(0, 0.13, -0.01), Vector3(0.1, 0.012, 0.012), WOOD)
	_rod(Vector3(0, 0.06, 0.05), Vector3(0, 0.17, -0.06), 0.006, WOOD)   # the arm, cocked back
	_box(Vector3(0, 0.175, -0.065), Vector3(0.035, 0.015, 0.035), LEATHER)
	rock(Vector3(0, 0.18, -0.065), 0.016, Color(0.55, 0.53, 0.5))
	_civ_box(Vector3(0, 0.06, 0.08), Vector3(0.1, 0.02, 0.006))
	_figure(Vector3(0.1, 0, 0.06), -0.4, {"torso": LEATHER})


func trebuchet() -> void:
	_box(Vector3(0, 0.02, 0), Vector3(0.14, 0.02, 0.2), WOOD)
	for s: float in [-1.0, 1.0]:
		_rod(Vector3(s * 0.05, 0.02, -0.06), Vector3(s * 0.04, 0.2, 0), 0.006, WOOD)
		_rod(Vector3(s * 0.05, 0.02, 0.06), Vector3(s * 0.04, 0.2, 0), 0.006, WOOD)
	_rod(Vector3(-0.05, 0.2, 0), Vector3(0.05, 0.2, 0), 0.006, WOOD)
	_rod(Vector3(0, 0.15, 0.07), Vector3(0, 0.3, -0.12), 0.006, WOOD)   # long arm
	_box(Vector3(0, 0.13, 0.08), Vector3(0.05, 0.05, 0.05), Color(0.4, 0.38, 0.36))   # counterweight
	_civ_box(Vector3(0, 0.03, 0.1), Vector3(0.14, 0.02, 0.006))
	_figure(Vector3(0.11, 0, 0.08), -0.5, {"torso": LEATHER, "hat": "kettle"})


## A gun on a two-wheeled carriage: [param length] barrel, [param radius] bore. [param shielded]: a gun shield.
func _gun_carriage(length: float, radius: float, bronze: bool, shielded := false, low := false) -> void:
	var y := 0.05 if low else 0.065
	_box(Vector3(0, y - 0.02, -0.05), Vector3(0.03, 0.02, 0.14), WOOD if bronze else DARK_METAL, 0.0)   # trail
	for s: float in [-1.0, 1.0]:
		_wheel(Vector3(s * 0.05, y - 0.015, 0.01), 0.05 if not low else 0.035, 0.0, WOOD if bronze else Color(0.2, 0.2, 0.2))
	_rod(Vector3(0, y, -0.03), Vector3(0, y + length * 0.25, length * 0.85), radius, Color(0.75, 0.55, 0.25) if bronze else DARK_METAL)
	if shielded:
		_civ_box(Vector3(0, y + 0.03, 0.04), Vector3(0.1, 0.06, 0.006))
	else:
		_civ_box(Vector3(0, y - 0.005, -0.02), Vector3(0.032, 0.012, 0.05))
	_figure(Vector3(-0.1, 0, -0.06), 0.3, {"torso": Color(0.2, 0.25, 0.4) if bronze else OLIVE, "hat": "bicorne" if bronze else "brodie", "legs": Color(0.3, 0.3, 0.3)})


func gatling_gun() -> void:
	_box(Vector3(0, 0.04, -0.04), Vector3(0.03, 0.02, 0.11), DARK_METAL)
	for s: float in [-1.0, 1.0]:
		_wheel(Vector3(s * 0.05, 0.045, 0.0), 0.045, 0.0, WOOD)
	for i in 6:
		var a := TAU * i / 6.0
		var o := Vector3(cos(a) * 0.012, 0.075 + sin(a) * 0.012, 0)
		_rod(o + Vector3(0, 0, -0.02), o + Vector3(0, 0, 0.13), 0.004, DARK_METAL)
	_civ_box(Vector3(0, 0.075, -0.035), Vector3(0.04, 0.04, 0.03))
	_figure(Vector3(0.0, 0, -0.12), 0.0, {"weapon": "", "hat": "shako", "torso": Color(0.25, 0.3, 0.45)})


func machine_gun() -> void:
	for spot: Vector3 in [Vector3(-0.07, 0, -0.02), Vector3(0.07, 0, 0.0)]:
		for i in 3:   # tripod
			var a := TAU * i / 3.0
			_rod(spot + Vector3(cos(a) * 0.04, 0, sin(a) * 0.04), spot + Vector3(0, 0.06, 0), 0.003, DARK_METAL)
		_box(spot + Vector3(0, 0.07, 0.02), Vector3(0.025, 0.025, 0.06), DARK_METAL)
		_rod(spot + Vector3(0, 0.07, 0.05), spot + Vector3(0, 0.072, 0.14), 0.006, DARK_METAL)
		_figure(spot + Vector3(0, 0, -0.07), 0.0, {"hat": "brodie", "torso": OLIVE, "legs": OLIVE})
	# sandbags in front
	for i in 5:
		_blob(Vector3(-0.12 + i * 0.06, 0.02, 0.12), Vector3(0.03, 0.018, 0.018), Color(0.7, 0.62, 0.45), 0.1)


func _flak(_mobile: bool) -> void:
	_deck(Vector3(0, 0.02, 0), _circle(0.09, 8), 0.03, DARK_METAL)
	_civ_box(Vector3(0, 0.06, 0), Vector3(0.07, 0.05, 0.06))
	for s: float in [-1.0, 1.0]:
		_rod(Vector3(s * 0.015, 0.07, 0.0), Vector3(s * 0.015, 0.22, 0.1), 0.007, DARK_METAL)
	_figure(Vector3(0.11, 0, -0.06), -0.6, {"hat": "modern", "torso": OLIVE, "legs": OLIVE})


# region vehicles ---------------------------------------------------------------------------------

func _tracks(length: float, width: float, height: float, y := 0.0) -> void:
	for s: float in [-1.0, 1.0]:
		_plate(Vector3(s * width / 2.0, y, 0), [Vector2(-length / 2.0, 0.0), Vector2(length / 2.0, 0.0),
			Vector2(length / 2.0 + 0.01, height * 0.8), Vector2(length / 2.0 - 0.01, height), Vector2(-length / 2.0 + 0.01, height),
			Vector2(-length / 2.0 - 0.01, height * 0.8)], 0.03, Color(0.3, 0.3, 0.3), -PI / 2.0)


func _tank(modern: bool) -> void:
	var body := OLIVE.darkened(0.1) if not modern else Color(0.55, 0.5, 0.4)
	_tracks(0.24, 0.13, 0.05)
	_box(Vector3(0, 0.065, 0), Vector3(0.12, 0.04, 0.22), body)
	_civ_box(Vector3(0, 0.087, -0.06), Vector3(0.122, 0.006, 0.06))
	if modern:
		_deck(Vector3(0, 0.1, -0.01), [Vector2(-0.05, -0.06), Vector2(0.05, -0.06), Vector2(0.06, 0.03), Vector2(0.0, 0.06), Vector2(-0.06, 0.03)], 0.04, body.darkened(0.05))
		_rod(Vector3(0, 0.1, 0.05), Vector3(0, 0.104, 0.26), 0.008, body.darkened(0.2))
	else:
		_frustum(Vector3(0, 0.085, -0.01), 0.05, 0.04, 0.045, 7, body.darkened(0.05), body.darkened(0.05))
		_rod(Vector3(0, 0.11, 0.03), Vector3(0, 0.115, 0.2), 0.009, body.darkened(0.2))


func landship() -> void:
	# the rhomboid tank of the Great War, tracks running all the way round
	_plate(Vector3(0, 0, 0), [Vector2(-0.13, 0.03), Vector2(-0.08, 0.0), Vector2(0.09, 0.0), Vector2(0.14, 0.05),
		Vector2(0.11, 0.1), Vector2(-0.1, 0.1)], 0.13, OLIVE.lightened(0.05), -PI / 2.0)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(s * 0.075, 0.06, 0.0), Vector3(0.025, 0.035, 0.05), OLIVE.darkened(0.15))   # side guns
		_rod(Vector3(s * 0.08, 0.06, 0.02), Vector3(s * 0.08, 0.06, 0.08), 0.005, DARK_METAL)
	_civ_box(Vector3(0, 0.102, -0.02), Vector3(0.08, 0.006, 0.08))


func _apc() -> void:
	_tracks(0.22, 0.13, 0.04)
	_deck(Vector3(0, 0.08, 0), [Vector2(-0.065, -0.11), Vector2(0.065, -0.11), Vector2(0.065, 0.06), Vector2(0.0, 0.12), Vector2(-0.065, 0.06)], 0.06, Color(0.45, 0.47, 0.38))
	_civ_box(Vector3(0, 0.112, -0.05), Vector3(0.1, 0.006, 0.06))
	_box(Vector3(0.0, 0.125, 0.02), Vector3(0.04, 0.025, 0.04), Color(0.4, 0.42, 0.34))
	_rod(Vector3(0, 0.125, 0.04), Vector3(0, 0.128, 0.13), 0.005, DARK_METAL)


func _truck(load: String) -> void:
	for s: float in [-1.0, 1.0]:
		for z: float in [-0.07, 0.0, 0.08]:
			_wheel(Vector3(s * 0.06, 0.028, z), 0.028, 0.0, Color(0.12, 0.12, 0.12))
	_box(Vector3(0, 0.05, 0), Vector3(0.11, 0.02, 0.24), OLIVE.darkened(0.15))
	_box(Vector3(0, 0.085, 0.09), Vector3(0.1, 0.05, 0.05), OLIVE)   # cab
	_special = "Glow"
	_box(Vector3(0, 0.095, 0.116), Vector3(0.08, 0.02, 0.003), Color(0.5, 0.65, 0.75))
	_special = ""
	match load:
		"rockets":
			_box(Vector3(0, 0.1, -0.04), Vector3(0.1, 0.05, 0.14), DARK_METAL, 0.0)
			for i in 3:
				for j in 2:
					_special = "CivOuter"
					_cone(Vector3(-0.03 + i * 0.03, 0.125, -0.02 - j * 0.06), 0.006, 0.02, 4, CIV_O)
					_special = ""
		"sam":
			for s: float in [-1.0, 1.0]:
				_rod(Vector3(s * 0.025, 0.08, -0.08), Vector3(s * 0.025, 0.16, 0.04), 0.013, Color(0.92, 0.92, 0.94))
				_special = "CivOuter"
				_cone(Vector3(s * 0.025, 0.16, 0.04), 0.012, 0.02, 6, CIV_O)
				_special = ""
	_civ_box(Vector3(0, 0.112, 0.09), Vector3(0.1, 0.006, 0.04))


func giant_death_robot() -> void:
	var steel := Color(0.6, 0.62, 0.66)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(s * 0.05, 0.06, 0), Vector3(0.04, 0.12, 0.05), steel.darkened(0.2))
		_box(Vector3(s * 0.05, 0.01, 0.015), Vector3(0.05, 0.02, 0.08), DARK_METAL)
		_box(Vector3(s * 0.1, 0.2, 0.02), Vector3(0.04, 0.04, 0.12), DARK_METAL)   # arm cannons
		_rod(Vector3(s * 0.1, 0.2, 0.08), Vector3(s * 0.1, 0.2, 0.14), 0.01, Color(0.2, 0.2, 0.22))
	_box(Vector3(0, 0.2, 0), Vector3(0.14, 0.12, 0.09), steel)
	_civ_box(Vector3(0, 0.21, 0.047), Vector3(0.1, 0.05, 0.005))
	_box(Vector3(0, 0.285, 0.0), Vector3(0.06, 0.05, 0.06), steel.darkened(0.1))
	_special = "Glow"
	_box(Vector3(0, 0.29, 0.031), Vector3(0.045, 0.012, 0.003), Color(1.0, 0.25, 0.15))
	_special = ""


# region ships ----------------------------------------------------------------------------------

## A hull pointing +Z: [param length] long, [param width] wide, its deck [param height] above the water.
func _hull(at: Vector3, length: float, width: float, height: float, color: Color, stern_square := true) -> void:
	var l := length / 2.0
	var w := width / 2.0
	var outline := [Vector2(-w, -l), Vector2(w, -l), Vector2(w, l * 0.45), Vector2(0, l), Vector2(-w, l * 0.45)]
	if not stern_square:
		outline = [Vector2(0, -l), Vector2(w, -l * 0.5), Vector2(w, l * 0.45), Vector2(0, l), Vector2(-w, l * 0.45), Vector2(-w, -l * 0.5)]
	_deck(at + Vector3(0, height / 2.0 - 0.01, 0), outline, height, color)
	_civ_box(at + Vector3(0, height - 0.012, 0), Vector3(width + 0.004, 0.008, length * 0.6), 0.0, true)   # a painted stripe


func _galley(ranged: bool) -> void:
	_hull(Vector3(0, 0, 0), 0.34, 0.08, 0.04, WOOD)
	for s: float in [-1.0, 1.0]:
		for i in 5:
			_rod(Vector3(s * 0.035, 0.025, -0.1 + i * 0.045), Vector3(s * 0.09, -0.005, -0.11 + i * 0.045), 0.003, WOOD.lightened(0.1))
	_rod(Vector3(0, 0.03, 0.0), Vector3(0, 0.24, 0.0), 0.005, WOOD)
	_plate(Vector3(0, 0.15, 0.003), [Vector2(-0.07, -0.07), Vector2(0.07, -0.07), Vector2(0.065, 0.07), Vector2(-0.065, 0.07)], 0.005, CIV_O, 0.0, "CivOuter")
	if ranged:   # a raised castle and a second, smaller sail
		_box(Vector3(0, 0.055, -0.13), Vector3(0.07, 0.035, 0.06), WOOD.darkened(0.1))
		_rod(Vector3(0, 0.03, 0.11), Vector3(0, 0.17, 0.11), 0.004, WOOD)
		_plate(Vector3(0, 0.12, 0.112), [Vector2(-0.045, -0.04), Vector2(0.045, -0.04), Vector2(0.04, 0.04), Vector2(-0.04, 0.04)], 0.004, SAIL)


func _sailing_ship(masts: int, guns: bool) -> void:
	_hull(Vector3(0, 0, 0), 0.36, 0.1, 0.06, WOOD.darkened(0.15))
	_box(Vector3(0, 0.075, -0.13), Vector3(0.09, 0.035, 0.08), WOOD.darkened(0.2))
	if guns:
		for s: float in [-1.0, 1.0]:
			for i in 4:
				_box(Vector3(s * 0.051, 0.035, -0.08 + i * 0.05), Vector3(0.004, 0.012, 0.014), Color(0.1, 0.1, 0.1))
	var zs := [0.0] if masts == 1 else ([0.08, -0.06] if masts == 2 else [0.1, 0.0, -0.1])
	for i in zs.size():
		var z: float = zs[i]
		var h := 0.3 if i == zs.size() / 2 else 0.25
		_rod(Vector3(0, 0.05, z), Vector3(0, h, z), 0.005, WOOD)
		_plate(Vector3(0, h * 0.62, z + 0.004), [Vector2(-0.06, -0.06), Vector2(0.06, -0.06), Vector2(0.05, 0.06), Vector2(-0.05, 0.06)], 0.005, SAIL)
		_plate(Vector3(0, h * 0.62 + 0.09, z + 0.004), [Vector2(-0.045, -0.025), Vector2(0.045, -0.025), Vector2(0.035, 0.025), Vector2(-0.035, 0.025)], 0.004, SAIL)
	_plate(Vector3(0, 0.31, zs[zs.size() / 2] + 0.02), [Vector2(0, -0.012), Vector2(0.05, 0.0), Vector2(0, 0.012)], 0.003, CIV_O, PI / 2.0, "CivOuter")


func ironclad() -> void:
	_hull(Vector3(0, 0, 0), 0.32, 0.1, 0.035, Color(0.3, 0.3, 0.32))
	_frustum(Vector3(0, 0.035, 0.02), 0.04, 0.035, 0.04, 8, DARK_METAL, DARK_METAL)   # turret
	_rod(Vector3(0, 0.055, 0.04), Vector3(0, 0.058, 0.1), 0.007, Color(0.15, 0.15, 0.15))
	_rod(Vector3(0, 0.03, -0.06), Vector3(0, 0.15, -0.06), 0.014, Color(0.2, 0.18, 0.18))   # funnel
	_steam(Vector3(0, 0.17, -0.07), 0.12, 0.02, Color(0.4, 0.4, 0.42), "Smoke", 4)


func _warship(length: float, turrets: int, missiles: bool) -> void:
	_hull(Vector3(0, 0, 0), length, 0.1, 0.045, NAVY)
	_box(Vector3(0, 0.07, -0.03), Vector3(0.06, 0.05, 0.1), NAVY.lightened(0.08))   # bridge
	_box(Vector3(0, 0.11, -0.03), Vector3(0.04, 0.03, 0.05), NAVY.lightened(0.12))
	_rod(Vector3(0, 0.12, -0.05), Vector3(0, 0.2, -0.05), 0.004, DARK_METAL)
	_civ_box(Vector3(0, 0.198, -0.05), Vector3(0.004, 0.015, 0.03))   # ensign
	var spots := [length * 0.28] if turrets == 1 else [length * 0.3, length * 0.15, -length * 0.3]
	for z: float in spots:
		_box(Vector3(0, 0.055, z), Vector3(0.05, 0.025, 0.05), NAVY.darkened(0.1))
		for s: float in ([-0.01, 0.01] if turrets > 1 else [0.0]):
			var dir := 1.0 if z > 0 else -1.0
			_rod(Vector3(s, 0.062, z + dir * 0.02), Vector3(s, 0.065, z + dir * 0.09), 0.004, DARK_METAL)
	if missiles:
		for i in 2:
			_box(Vector3(0, 0.055, -length * 0.3 + i * 0.03), Vector3(0.06, 0.02, 0.025), DARK_METAL)
	if turrets > 1:
		_rod(Vector3(0, 0.04, -0.09), Vector3(0, 0.12, -0.09), 0.014, NAVY.darkened(0.2))


func _submarine(nuclear: bool) -> void:
	var color := Color(0.36, 0.38, 0.42)
	_rod(Vector3(0, 0.02, -0.15), Vector3(0, 0.02, 0.15), 0.035 if nuclear else 0.028, color)
	_cone(Vector3(0, 0.02, 0.15), 0.03, 0.04, 6, color)
	_box(Vector3(0, 0.06, 0.03), Vector3(0.03, 0.05, 0.07 if nuclear else 0.05), color.lightened(0.05))   # sail
	_civ_box(Vector3(0, 0.07, 0.03), Vector3(0.032, 0.012, 0.03))
	_rod(Vector3(0, 0.08, 0.04), Vector3(0, 0.12, 0.04), 0.003, DARK_METAL)
	if nuclear:
		for i in 4:
			_box(Vector3(0, 0.054, -0.04 - i * 0.025), Vector3(0.03, 0.006, 0.015), color.lightened(0.1))


func carrier() -> void:
	_hull(Vector3(0, 0, 0), 0.44, 0.12, 0.05, NAVY)
	_deck(Vector3(0, 0.055, 0), [Vector2(-0.075, -0.22), Vector2(0.075, -0.22), Vector2(0.075, 0.2), Vector2(-0.075, 0.2)], 0.008, Color(0.3, 0.32, 0.34))
	_box(Vector3(0.06, 0.09, -0.02), Vector3(0.025, 0.06, 0.08), NAVY.lightened(0.1))   # island
	_civ_box(Vector3(0.06, 0.12, -0.02), Vector3(0.027, 0.01, 0.06))
	for i in 3:   # stripes and a few planes on deck
		_box(Vector3(-0.02, 0.06, -0.15 + i * 0.12), Vector3(0.004, 0.002, 0.08), Color(0.9, 0.9, 0.85))
	for z: float in [-0.12, 0.05]:
		_deck(Vector3(-0.03, 0.065, z), [Vector2(-0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.0, 0.03)], 0.004, Color(0.5, 0.52, 0.55))


func work_boats() -> void:
	_hull(Vector3(0, 0, 0), 0.2, 0.07, 0.035, WOOD)
	_rod(Vector3(0, 0.03, 0.02), Vector3(0, 0.17, 0.02), 0.004, WOOD)
	_plate(Vector3(0, 0.11, 0.022), [Vector2(0, -0.05), Vector2(0.05, -0.05), Vector2(0, 0.06)], 0.004, CIV_O, 0.0, "CivOuter")
	_figure(Vector3(0, 0.025, -0.05), 0.0, {"torso": LEATHER, "hat": "cap"})


## The boat a land unit rides in while embarked.
func embarked() -> void:
	_hull(Vector3(0, 0, 0), 0.26, 0.09, 0.035, WOOD.darkened(0.1))
	_rod(Vector3(0, 0.03, 0.03), Vector3(0, 0.2, 0.03), 0.004, WOOD)
	_plate(Vector3(0, 0.13, 0.033), [Vector2(-0.05, -0.06), Vector2(0.05, -0.06), Vector2(0.04, 0.06), Vector2(-0.04, 0.06)], 0.004, CIV_O, 0.0, "CivOuter")
	_box(Vector3(0, 0.05, -0.07), Vector3(0.05, 0.03, 0.05), Color(0.6, 0.5, 0.35))   # cargo


# region aircraft -------------------------------------------------------------------------------

const AIR := 0.3   # how high aircraft fly over their tile


func _wing(at: Vector3, span: float, chord: float, color: Color, sweep := 0.0, surface := "") -> void:
	var h := span / 2.0
	_deck(at, [Vector2(-h, -chord / 2.0 - sweep), Vector2(0, -chord / 2.0), Vector2(h, -chord / 2.0 - sweep),
		Vector2(h, chord / 2.0 - sweep), Vector2(0, chord / 2.0), Vector2(-h, chord / 2.0 - sweep)], 0.006, color, 0.0, surface)


func _biplane(wings: int, bomber := false) -> void:
	var body := Color(0.7, 0.6, 0.4)
	var y := AIR
	var size := 1.3 if bomber else 1.0
	_rod(Vector3(0, y, -0.1 * size), Vector3(0, y, 0.08 * size), 0.016 * size, body)
	for i in wings:
		_wing(Vector3(0, y - 0.01 + i * 0.03 * size, 0.03 * size), 0.24 * size, 0.04 * size, CIV_O, 0.0, "CivOuter")
	_wing(Vector3(0, y, -0.095 * size), 0.08 * size, 0.025 * size, body)
	_plate(Vector3(0, y + 0.02 * size, -0.095 * size), [Vector2(0, 0), Vector2(0.03 * size, 0), Vector2(0, 0.03 * size)], 0.004, body, -PI / 2.0)
	_box(Vector3(0, y, 0.088 * size), Vector3(0.07 * size, 0.008, 0.003), Color(0.3, 0.2, 0.15))   # propeller
	if bomber:
		for s: float in [-1.0, 1.0]:
			_rod(Vector3(s * 0.05, y - 0.002, -0.0), Vector3(s * 0.05, y - 0.002, 0.08), 0.012, body.darkened(0.1))


func _prop_fighter() -> void:
	var body := Color(0.55, 0.58, 0.55)
	_rod(Vector3(0, AIR, -0.11), Vector3(0, AIR, 0.08), 0.017, body)
	_wing(Vector3(0, AIR - 0.006, 0.02), 0.25, 0.05, CIV_O, 0.0, "CivOuter")
	_wing(Vector3(0, AIR, -0.1), 0.09, 0.03, body)
	_plate(Vector3(0, AIR + 0.02, -0.1), [Vector2(0, 0), Vector2(0.035, 0), Vector2(0, 0.035)], 0.004, body, -PI / 2.0)
	_box(Vector3(0, AIR + 0.016, 0.0), Vector3(0.018, 0.012, 0.04), Color(0.55, 0.7, 0.8))   # canopy
	_box(Vector3(0, AIR, 0.09), Vector3(0.08, 0.008, 0.003), Color(0.2, 0.2, 0.2))


func _heavy_bomber() -> void:
	var body := Color(0.65, 0.66, 0.68)
	_rod(Vector3(0, AIR, -0.15), Vector3(0, AIR, 0.13), 0.022, body)
	_wing(Vector3(0, AIR, 0.02), 0.38, 0.06, CIV_O, 0.0, "CivOuter")
	for x: float in [-0.13, -0.06, 0.06, 0.13]:
		_rod(Vector3(x, AIR - 0.004, 0.0), Vector3(x, AIR - 0.004, 0.06), 0.01, body.darkened(0.1))
	_wing(Vector3(0, AIR, -0.14), 0.12, 0.035, body)
	_plate(Vector3(0, AIR + 0.03, -0.14), [Vector2(0, 0), Vector2(0.04, 0), Vector2(0, 0.05)], 0.004, body, -PI / 2.0)


func _jet(stealth: bool) -> void:
	var body := Color(0.5, 0.52, 0.56) if not stealth else Color(0.2, 0.21, 0.24)
	if stealth:   # a flying wing
		_deck(Vector3(0, AIR, 0), [Vector2(0, 0.1), Vector2(0.2, -0.04), Vector2(0.17, -0.07), Vector2(0.09, -0.03), Vector2(0.0, -0.07),
			Vector2(-0.09, -0.03), Vector2(-0.17, -0.07), Vector2(-0.2, -0.04)], 0.014, body)
		_civ_box(Vector3(0, AIR + 0.008, 0.02), Vector3(0.05, 0.003, 0.03))
		return
	_rod(Vector3(0, AIR, -0.12), Vector3(0, AIR, 0.09), 0.016, body)
	_cone(Vector3(0, AIR, 0.09), 0.016, 0.05, 6, body)
	_deck(Vector3(0, AIR - 0.004, -0.02), [Vector2(0, 0.06), Vector2(0.12, -0.05), Vector2(0.12, -0.07), Vector2(0, -0.04),
		Vector2(-0.12, -0.07), Vector2(-0.12, -0.05)], 0.006, CIV_O, 0.0, "CivOuter")
	_plate(Vector3(0, AIR + 0.02, -0.1), [Vector2(-0.01, 0), Vector2(0.03, 0), Vector2(0.0, 0.04)], 0.004, body, -PI / 2.0)
	_box(Vector3(0, AIR + 0.014, 0.04), Vector3(0.016, 0.01, 0.04), Color(0.55, 0.7, 0.8))
	_special = "Glow"
	_deck(Vector3(0, AIR, -0.125), _circle(0.012, 6), 0.004, Color(1.0, 0.6, 0.25), 0.0)
	_special = ""


func helicopter() -> void:
	var body := OLIVE.darkened(0.1)
	var y := AIR - 0.05
	_blob(Vector3(0, y, 0.02), Vector3(0.04, 0.035, 0.07), body, 0.08, 0.02)
	_rod(Vector3(0, y + 0.01, -0.04), Vector3(0, y + 0.02, -0.16), 0.008, body)
	_plate(Vector3(0, y + 0.03, -0.16), [Vector2(0, -0.01), Vector2(0.025, 0.0), Vector2(0, 0.03)], 0.004, body, -PI / 2.0)
	_box(Vector3(0, y + 0.012, 0.075), Vector3(0.03, 0.02, 0.03), Color(0.5, 0.65, 0.75))
	_rod(Vector3(0, y + 0.035, 0.02), Vector3(0, y + 0.055, 0.02), 0.004, DARK_METAL)
	for a: float in [0.3, 0.3 + PI / 2.0]:
		_box(Vector3(0, y + 0.057, 0.02), Vector3(0.3, 0.003, 0.012), Color(0.15, 0.15, 0.15), a)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(s * 0.05, y - 0.005, 0.02), Vector3(0.03, 0.008, 0.012), body)   # stub wings with rockets
		_rod(Vector3(s * 0.06, y - 0.015, -0.0), Vector3(s * 0.06, y - 0.015, 0.05), 0.006, DARK_METAL)
		_rod(Vector3(s * 0.03, y - 0.04, -0.03), Vector3(s * 0.03, y - 0.04, 0.07), 0.003, DARK_METAL)   # skids
	_civ_box(Vector3(0, y + 0.02, -0.02), Vector3(0.082, 0.015, 0.03))


func _bomb(nuclear: bool) -> void:
	_rod(Vector3(0, AIR, -0.08), Vector3(0, AIR, 0.06), 0.04, Color(0.55, 0.55, 0.5))
	_cone(Vector3(0, AIR, 0.06), 0.04, 0.03, 8, Color(0.55, 0.55, 0.5))
	for a in 4:
		_plate(Vector3(0, AIR, -0.09), [Vector2(0, 0), Vector2(0.06, -0.03), Vector2(0.06, 0.02), Vector2(0, 0.03)], 0.004, Color(0.45, 0.45, 0.42), a * PI / 2.0)
	if nuclear:
		_special = "Glow"
		_box(Vector3(0, AIR + 0.04, 0.0), Vector3(0.025, 0.004, 0.025), Color(1.0, 0.85, 0.1))
		_special = ""
	_civ_box(Vector3(0, AIR, -0.02), Vector3(0.084, 0.084, 0.012))


func _missile(nuclear: bool) -> void:
	# standing on a launch rail
	_box(Vector3(0, 0.01, 0), Vector3(0.12, 0.02, 0.12), DARK_METAL)
	_rod(Vector3(0, 0.02, 0), Vector3(0, 0.26, 0), 0.02 if not nuclear else 0.026, Color(0.92, 0.92, 0.94))
	_cone(Vector3(0, 0.26, 0), 0.02 if not nuclear else 0.026, 0.05, 8, CIV_O if not nuclear else Color(0.95, 0.8, 0.15))
	for a in 4:
		_plate(Vector3(0, 0.04, 0), [Vector2(0, 0), Vector2(0.04, 0), Vector2(0.0, 0.05)], 0.004, DARK_METAL, a * PI / 2.0)
	_civ_box(Vector3(0, 0.15, 0), Vector3(0.042 if not nuclear else 0.054, 0.02, 0.042 if not nuclear else 0.054))
