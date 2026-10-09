# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Unciv's own icons, loaded straight from the Unciv repo next to this project (../unciv/android/Images.*),
## so the game uses the symbols Unciv players already know. Missing icons give null; callers fall back to text.
##
## get_icon(kind, name): the plain icon (most are white silhouettes; stat and tech icons are coloured).
## badge(kind, name, back, front): the icon tinted [front] on a round [back] disc, like Unciv's portraits
## and unit flags - composed once and cached.
## civ_badge(civ): a civilization's emblem (nation icon, or the city-state type icon) in its colours.

const FOLDERS := {
	"policy": "Images.PolicyIcons/PolicyIcons",
	"branch": "Images.PolicyIcons/PolicyBranchIcons",
	"tech": "Images.Tech/TechIcons",
	"stat": "Images.Icons/StatIcons",
	"resource": "Images.Icons/ResourceIcons",
	"improvement": "Images.Icons/ImprovementIcons",
	"tile": "Images.Icons/TileIcons",
	"unittype": "Images.Icons/UnitTypeIcons",
	"other": "Images.Icons/OtherIcons",
	"citystate": "Images.Icons/CityStateIcons",
	"nation": "Images.NationIcons/NationIcons",
	"unit": "Images.ConstructionIcons/UnitIcons",
	"building": "Images.ConstructionIcons/BuildingIcons",
	"action": "Images.ConstructionIcons/UnitActionIcons",
	"promotion": "Images.UnitPromotionIcons/UnitPromotionIcons",
	"religion": "Images.ReligionIcons/ReligionIcons",
}
## Unciv image paths ("StatIcons/Gold", "UnitIcons/Warrior"...) -> our kinds
const PATH_KINDS := {
	"StatIcons": "stat", "UnitIcons": "unit", "BuildingIcons": "building", "TechIcons": "tech", "ResourceIcons": "resource",
	"ImprovementIcons": "improvement", "OtherIcons": "other", "ReligionIcons": "religion", "NationIcons": "nation",
	"PolicyIcons": "policy", "PolicyBranchIcons": "branch", "UnitPromotionIcons": "promotion", "UnitActionIcons": "action",
	"CityStateIcons": "citystate", "TileIcons": "tile", "UnitTypeIcons": "unittype",
}
## Unciv's unit action types -> their icon in UnitActionIcons (from Unciv's UnitActionType)
const ACTION_ICONS := {
	"StopEscortFormation": "StopEscort", "EscortFormation": "Escort", "SwapUnits": "Swap", "Automate": "Automate",
	"ConnectRoad": "RoadConnection", "StopAutomation": "Stop", "StopMovement": "StopMove", "Sleep": "Sleep",
	"SleepUntilHealed": "Sleep", "Fortify": "Fortify", "FortifyUntilHealed": "FortifyUntilHealed", "Guard": "Guard",
	"Explore": "Explore", "StopExploration": "Stop", "Promote": "Promote", "Upgrade": "Upgrade", "Transform": "Transform",
	"Pillage": "Pillage", "Paradrop": "Paradrop", "AirSweep": "AirSweep", "SetUp": "SetUp", "FoundCity": "FoundCity",
	"ConstructImprovement": "ConstructImprovement", "CreateImprovement": "ConstructImprovement", "Repair": "Repair",
	"HurryResearch": "HurryResearch", "HurryPolicy": "HurryPolicy", "HurryWonder": "HurryConstruction",
	"HurryBuilding": "HurryConstruction", "ConductTradeMission": "ConductTradeMission", "FoundReligion": "FoundReligion",
	"RemoveHeresy": "RemoveHeresy", "EnhanceReligion": "EnhanceReligion", "DisbandUnit": "DisbandUnit",
	"GiftUnit": "Present", "Skip": "Skip", "AddInCapital": "AddInCapital", "TriggerUnique": "Star",
}
const BADGE_SIZE := 96

static var _images: Dictionary = {}    # "kind/name" -> Image or null
static var _textures: Dictionary = {}  # cache key -> Texture2D or null


static func _image(kind: String, name: String) -> Image:
	var key := kind + "/" + name
	if _images.has(key):
		return _images[key]
	var image: Image = null
	var folder: String = FOLDERS.get(kind, "")
	if folder != "":
		var path := ProjectSettings.globalize_path("res://").path_join("../unciv/android").path_join(folder).path_join(name + ".png").simplify_path()
		if FileAccess.file_exists(path):
			image = Image.load_from_file(path)
			if image != null and image.is_empty():
				image = null
			if image != null:
				image.convert(Image.FORMAT_RGBA8)
	_images[key] = image
	return image


static func get_icon(kind: String, name: String) -> Texture2D:
	var key := "icon:" + kind + "/" + name
	if not _textures.has(key):
		var image := _image(kind, name)
		var texture: Texture2D = null
		if image != null:
			var copy := image.duplicate() as Image
			copy.generate_mipmaps()
			texture = ImageTexture.create_from_image(copy)
		_textures[key] = texture
	return _textures[key]


## A units/buildings icon: whichever folder has it. Unit icons are white silhouettes; building pictures
## (which can be dark) sit on a light disc, the way Unciv's city screen shows them.
static func construction(name: String) -> Texture2D:
	var texture := get_icon("unit", name)
	if texture != null:
		return texture
	return badge("building", name, Color(0.86, 0.84, 0.78), Color.WHITE, 0.78)


## An icon by Unciv's image path ("StatIcons/Gold"); a bare name is tried as a nation, unit, building and resource.
static func from_path(path: String) -> Texture2D:
	var slash := path.find("/")
	if slash > 0:
		var kind: String = PATH_KINDS.get(path.substr(0, slash), "")
		return get_icon(kind, path.substr(slash + 1)) if kind != "" else null
	for kind: String in ["nation", "unit", "building", "resource", "tech"]:
		var texture := get_icon(kind, path)
		if texture != null:
			return texture
	return null


## A unit action's icon (Unciv's UnitActionIcons), by UnitActionType name.
static func action(type: String) -> Texture2D:
	return get_icon("action", str(ACTION_ICONS.get(type, type)))


## A promotion's icon: "Drill II" uses Drill's (Unciv shows the level as stars). Returns [texture, level].
static func promotion(name: String) -> Array:
	var level := 0
	var base := name
	for suffix: Array in [[" III", 3], [" II", 2], [" I", 1]]:
		if name.ends_with(suffix[0]):
			base = name.substr(0, name.length() - str(suffix[0]).length())
			level = suffix[1]
			break
	var texture := get_icon("promotion", name)
	if texture != null:
		return [texture, 0]
	texture = get_icon("promotion", base)
	if texture == null:
		texture = get_icon("unit", base.trim_suffix(" ability"))
	return [texture, level]


## The icon tinted [param front] on a round [param back] disc (with a thin darker rim). Null if there's no icon.
static func badge(kind: String, name: String, back: Color, front := Color.WHITE, scale := 0.68) -> Texture2D:
	var key := "badge:%s/%s/%s/%s/%s" % [kind, name, back.to_html(), front.to_html(), scale]
	if _textures.has(key):
		return _textures[key]
	var icon := _image(kind, name)
	var texture: Texture2D = null
	if icon != null:
		var size := BADGE_SIZE
		var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var centre := Vector2(size, size) / 2.0
		var radius := size / 2.0 - 1.0
		for y in size:
			for x in size:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
				if d <= radius:
					var c := back.darkened(0.35) if d > radius - 4.0 else back
					c.a = clampf(radius - d + 0.5, 0.0, 1.0)   # soft edge
					out.set_pixel(x, y, c)
		var inner := int(size * scale)
		var resized := icon.duplicate() as Image
		resized.resize(inner, inner, Image.INTERPOLATE_BILINEAR)
		var offset := (size - inner) / 2
		for y in inner:
			for x in inner:
				var p := resized.get_pixel(x, y)
				if p.a <= 0.01:
					continue
				# White silhouettes take the tint; coloured icons (stats, techs) keep their colours
				var c := Color(p.r * front.r, p.g * front.g, p.b * front.b, 1.0)
				var under := out.get_pixel(x + offset, y + offset)
				out.set_pixel(x + offset, y + offset, under.lerp(c, p.a))
		out.generate_mipmaps()
		texture = ImageTexture.create_from_image(out)
	_textures[key] = texture
	return texture


## A civilization's emblem in its colours: [param civ] has name, nation?, isCityState, cityStateType?,
## outerColor, innerColor (a getState civ or a getDiplomacy entry).
static func civ_badge(civ: Dictionary) -> Texture2D:
	var outer := Color.html(str(civ.get("outerColor", "ffffffff")))
	var inner := Color.html(str(civ.get("innerColor", "333333ff")))
	if civ.get("isCityState", false) and civ.has("cityStateType"):
		return badge("citystate", str(civ["cityStateType"]), inner, outer)
	return badge("nation", str(civ.get("nation", civ.get("name", ""))), inner, outer)


## A plain round disc texture (for overlay buttons and backgrounds).
static func disc(color: Color) -> Texture2D:
	var key := "disc:" + color.to_html()
	if _textures.has(key):
		return _textures[key]
	var size := 64
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			var c := color
			c.a *= clampf(size / 2.0 - 1.0 - d + 0.5, 0.0, 1.0)
			out.set_pixel(x, y, c)
	var texture := ImageTexture.create_from_image(out)
	_textures[key] = texture
	return texture
