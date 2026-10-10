# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## A flat 2D UI (any Control) shown on a quad in the 3D world, usable with a VR laser pointer.
## Used for the wrist card and for the city card that pops up above a city.

var viewport: SubViewport
var quad: MeshInstance3D
var content: Control
var pixels := Vector2i(400, 700)
var metres := Vector2(0.17, 0.3)


## Puts [param card] on a panel [param size_metres] big, rendered at [param size_pixels].
func setup(card: Control, size_pixels: Vector2i, size_metres: Vector2) -> void:
	pixels = size_pixels
	metres = size_metres
	content = card

	viewport = SubViewport.new()
	viewport.size = pixels
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.add_child(card)
	card.position = Vector2.ZERO

	quad = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = metres
	quad.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Depth pre-pass: the card hides what is behind it (labels, other cards) instead of letting it bleed through
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = viewport.get_texture()
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)


## Where a ray hits the panel: [global point, panel pixel], or null when it misses or the panel is hidden.
func ray_hit(origin: Vector3, direction: Vector3) -> Variant:
	if quad == null or not quad.is_visible_in_tree():
		return null
	var t := quad.global_transform
	var plane := Plane(t.basis.z.normalized(), t.origin)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return null
	var local := quad.to_local(hit)
	var u := local.x / metres.x + 0.5
	var v := 0.5 - local.y / metres.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return null
	var pixel := Vector2(u * pixels.x, v * pixels.y)
	# Only the card itself counts - the transparent rest of the panel lets the laser through
	if content != null and not Rect2(content.position, content.size).has_point(pixel):
		return null
	return [hit, pixel]


func hover(pixel: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.global_position = pixel
	viewport.push_input(motion)


## The scrollbar under [param pixel] (this panel's pixels), or null. A laser can't drag a scrollbar's handle
## (clicks are a press and release at once), so main.gd moves it with [method scroll_to] while the trigger is held.
func scrollbar_at(pixel: Vector2) -> ScrollBar:
	return _scrollbar_in(content, pixel) if content != null else null


func _scrollbar_in(node: Node, pixel: Vector2) -> ScrollBar:
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is ScrollBar and (child as ScrollBar).get_global_rect().grow(4).has_point(pixel):
			return child
		var found := _scrollbar_in(child, pixel)
		if found != null:
			return found
	return null


## Moves [param bar] so the part of the page under [param pixel] comes into view (like dragging its handle there).
static func scroll_to(bar: ScrollBar, pixel: Vector2) -> void:
	var rect := bar.get_global_rect()
	var ratio := (pixel.x - rect.position.x) / maxf(1.0, rect.size.x) if bar is HScrollBar else (pixel.y - rect.position.y) / maxf(1.0, rect.size.y)
	var span := bar.max_value - bar.min_value
	bar.value = clampf(bar.min_value + clampf(ratio, 0.0, 1.0) * span - bar.page / 2.0, bar.min_value, bar.max_value - bar.page)


func click(pixel: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = pixel
		event.global_position = pixel
		viewport.push_input(event)
