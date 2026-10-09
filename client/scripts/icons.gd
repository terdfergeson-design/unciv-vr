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


## A units/buildings icon: whichever folder has it.
static func construction(name: String) -> Texture2D:
	var texture := get_icon("unit", name)
	return texture if texture != null else get_icon("building", name)


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
