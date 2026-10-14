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

## Panels are seen from further away than their pixels are drawn for: from a metre or two, several of a panel's
## pixels land on one pixel of the headset's screen. A viewport's picture has no mipmaps, so plain sampling then picks
## one pixel in several and the text breaks up (badly on the Quest's own, lower resolution). This samples the whole
## patch of the panel under each screen pixel instead (up to 4 x 4 samples, from how fast UV changes across it),
## weighting by alpha so the transparent surround doesn't darken the edges.
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D panel : source_color, filter_linear, repeat_disable;

void fragment() {
	vec2 size = vec2(textureSize(panel, 0));
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	int nx = clamp(int(ceil(length(dx * size))), 1, 4);
	int ny = clamp(int(ceil(length(dy * size))), 1, 4);
	vec4 sum = vec4(0.0);
	for (int i = 0; i < nx; i++) {
		for (int j = 0; j < ny; j++) {
			vec2 offset = ((float(i) + 0.5) / float(nx) - 0.5) * dx + ((float(j) + 0.5) / float(ny) - 0.5) * dy;
			vec4 c = texture(panel, UV + offset);
			sum += vec4(c.rgb * c.a, c.a);
		}
	}
	float count = float(nx * ny);
	ALBEDO = sum.a > 0.0 ? sum.rgb / sum.a : vec3(0.0);
	ALPHA = sum.a / count;
}
"""
static var _shader: Shader
## A board is redrawn at least this often anyway, for the few changes no signal tells about (a fading colour).
const REFRESH_SECONDS := 1.0

var _dirty := true
var _since_drawn := 0.0


## Puts [param card] on a panel [param size_metres] big, rendered at [param size_pixels].
func setup(card: Control, size_pixels: Vector2i, size_metres: Vector2) -> void:
	pixels = size_pixels
	metres = size_metres
	content = card

	viewport = SubViewport.new()
	viewport.size = pixels
	viewport.transparent_bg = true
	# Drawn again only when something on it changes (see _watch), not every frame: on the Quest, 16 boards redrawn
	# every frame cost about 7 ms of the 13.9 ms a frame has, which dropped the frame rate and blurred the text.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	viewport.add_child(card)
	card.position = Vector2.ZERO
	_watch(viewport)

	quad = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = metres
	quad.mesh = mesh
	# Unshaded, both sides, and a depth pre-pass: the card hides what is behind it (labels, other cards) instead of
	# letting it bleed through
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("panel", viewport.get_texture())
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)


## Asks for the board to be drawn again on the next frame.
func mark_dirty() -> void:
	_dirty = true


## Something that changes how a node looks makes it redraw itself (the draw signal), or moves, resizes or shows and
## hides it: each of those, anywhere on the card, marks the board for drawing. Nodes added later are watched too.
func _watch(node: Node) -> void:
	if not node.child_entered_tree.is_connected(_on_child_entered):
		node.child_entered_tree.connect(_on_child_entered)
		node.child_exiting_tree.connect(_on_child_exiting)
		if node is CanvasItem:
			(node as CanvasItem).draw.connect(mark_dirty)
			(node as CanvasItem).visibility_changed.connect(mark_dirty)
		if node is Control:
			(node as Control).item_rect_changed.connect(mark_dirty)
	for child in node.get_children():
		_watch(child)


func _on_child_entered(child: Node) -> void:
	_watch(child)
	_dirty = true


func _on_child_exiting(_child: Node) -> void:
	_dirty = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_dirty = true


func _process(delta: float) -> void:
	if viewport == null:
		return
	_since_drawn += delta
	if not is_visible_in_tree():
		return   # stays marked, and is drawn as soon as it's shown
	if _dirty or _since_drawn >= REFRESH_SECONDS:
		_dirty = false
		_since_drawn = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


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
