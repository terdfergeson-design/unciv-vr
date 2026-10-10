# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## Battle and movement motion for units on the table, generic enough to work with any unit model
## (including still models from modders): the attacker lunges or fires, a projectile flies, the defender
## shakes and flashes, damage numbers float up, the loser topples (or sinks). Models with their own
## animation clips ("attack", "hit", "die", "move") play those as well.
## Everything is in this node's local space (the map's units: a hex has circumradius 1), and every
## call returns when its motion is done, so a whole turn's events can be played back in order.

## How fast everything plays (1 = normal; the playback setting changes it).
var speed := 1.0
## Unciv's sounds (scripts/sounds.gd), set by the client: battles are heard from where they happen.
var sounds: Node = null

## What flies, by Unciv's attack sound for the unit (Units.json "attackSound").
const PROJECTILES := {
	"arrow": "arrow", "crossbow": "bolt", "throw": "stone", "cannon": "ball", "shipCannonVolley": "volley",
	"artillery": "shell", "shot": "bullets", "machinegun": "tracers", "jetgun": "tracers", "tankshot": "shell_flat",
	"shipguns": "shell", "missile": "missile", "torpedo": "torpedo", "bombing": "bombs", "nuke": "nuke",
}


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds / maxf(speed, 0.01)).timeout


func _tween() -> Tween:
	var t := create_tween()
	t.set_speed_scale(speed)
	return t


## [param attacker] walks / charges most of the way to [param target] and back; the defender is hit halfway.
## [param sound] is the unit's Unciv attackSound ("nonmetalhit", "metalhit"...), heard as it lands.
func melee(attacker: Node3D, defender: Node3D, damage_dealt: int, damage_taken: int, defender_dies := false,
		attacker_dies := false, sound := "") -> void:
	if attacker == null:
		return
	var start := attacker.position
	var goal := defender.position if defender != null else start
	face(attacker, goal)
	if defender != null:
		face(defender, start)
	_play_clip(attacker, "attack")
	var t := _tween()
	t.tween_property(attacker, "position", start.lerp(goal, 0.62) + Vector3(0, 0.05, 0), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	hear(sound, defender.global_position if defender != null else attacker.global_position)
	if defender != null:
		hit(defender, damage_dealt)
	if damage_taken > 0:
		_number(attacker.position + Vector3(0, 0.45, 0), damage_taken, Color(1.0, 0.75, 0.3))
	await _wait(0.18)
	t = _tween()
	t.tween_property(attacker, "position", start, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	if defender_dies and defender != null:
		await die(defender)
	if attacker_dies:
		await die(attacker)


## [param attacker] fires at [param target] (a point in this node's space; [param defender] is what's there, may
## be null). [param sound] is the unit's Unciv attackSound, which picks the projectile and is what you hear.
## With no attacker (a city bombarding), the shot starts from [param origin] and [param heard] is played
## instead (Unciv's "bombard", while the shot still looks like a cannon's).
func ranged(attacker: Node3D, target: Vector3, defender: Node3D, sound: String, damage_dealt: int, defender_dies := false,
		origin := Vector3.INF, heard := "") -> void:
	if attacker == null and origin == Vector3.INF:
		return
	var kind: String = PROJECTILES.get(sound, "arrow")
	var from := origin + Vector3(0, 0.45, 0)
	if attacker != null:
		face(attacker, target)
		_play_clip(attacker, "attack")
		# a little recoil
		var start := attacker.position
		var back := (start - target).normalized() * 0.04
		var t := _tween()
		t.tween_property(attacker, "position", start + Vector3(back.x, 0, back.z), 0.06)
		t.tween_property(attacker, "position", start, 0.18)
		from = attacker.position + Vector3(0, 0.18, 0)
	var to := target + Vector3(0, 0.12, 0)
	hear(heard if heard != "" else sound, to_global(from))
	match kind:
		"volley", "bullets", "tracers", "bombs":
			var shots := 5 if kind == "tracers" else 3
			for i in shots:
				_projectile(kind, from + _jitter(0.05), to + _jitter(0.12), i == shots - 1)
				await _wait(0.07 if kind == "tracers" else 0.12)
			await _wait(_flight_time(kind))
		_:
			await _projectile(kind, from, to, true)
	_burst(to, kind)
	if defender != null:
		hit(defender, damage_dealt)
	await _wait(0.35)
	if defender_dies and defender != null:
		await die(defender)


## Plays one of Unciv's sounds from a spot on the table, when the client has given us its sound player.
## Public so the map can use it for what it plays itself (a city's guns, a unit setting off).
func hear(sound: String, where: Vector3, volume := 1.0) -> void:
	if sounds != null and sound != "":
		sounds.play_at(sound, where, volume)


## The defender's side of a hit: a shake, a red flash and the damage floating up.
func hit(unit: Node3D, damage: int) -> void:
	if unit == null:
		return
	_play_clip(unit, "hit")
	_flash(unit, Color(1.0, 0.2, 0.15))
	var home := unit.position
	var t := _tween()
	for i in 4:
		t.tween_property(unit, "position", home + _jitter(0.035) * Vector3(1, 0, 1), 0.04)
	t.tween_property(unit, "position", home, 0.05)
	if damage > 0:
		_number(home + Vector3(0, 0.45, 0), damage, Color(1.0, 0.35, 0.3))


## Topples over and sinks into the table (ships just sink), then the node is freed.
func die(unit: Node3D) -> void:
	if unit == null:
		return
	_play_clip(unit, "die")
	var naval: bool = unit.get_meta("naval", false)
	var t := _tween().set_parallel(true)
	if naval:
		t.tween_property(unit, "rotation:z", 0.5, 1.0)
		t.tween_property(unit, "position:y", unit.position.y - 0.25, 1.2).set_ease(Tween.EASE_IN)
	else:
		t.tween_property(unit, "rotation:x", PI / 2.2, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.chain().tween_property(unit, "scale", Vector3.ONE * 0.01, 0.6).set_delay(0.3)
	await t.finished
	unit.queue_free()


## Slides along [param points] (local positions), turning to face each step: a unit's move across the map.
func move(unit: Node3D, points: Array) -> void:
	if unit == null:
		return
	_play_clip(unit, "move")
	for p: Vector3 in points:
		face(unit, p)
		var t := _tween()
		var mid := unit.position.lerp(p, 0.5) + Vector3(0, 0.06, 0)
		t.tween_property(unit, "position", mid, 0.13)
		t.tween_property(unit, "position", p, 0.13)
		await t.finished


## Turns [param unit] (whose model faces +Z) towards [param point].
static func face(unit: Node3D, point: Vector3) -> void:
	var d := point - unit.position
	if Vector2(d.x, d.z).length() > 0.001:
		unit.rotation.y = atan2(d.x, d.z)


func _flight_time(kind: String) -> float:
	match kind:
		"bullets", "tracers":
			return 0.15
		"missile", "torpedo":
			return 0.7
		"bombs", "nuke":
			return 0.55
		"shell_flat":
			return 0.2
	return 0.45


## Flies one projectile from [param from] to [param to] and frees it when it lands.
func _projectile(kind: String, from: Vector3, to: Vector3, _last := false) -> void:
	var node := _projectile_mesh(kind)
	add_child(node)
	var arc := 0.0
	match kind:
		"arrow", "bolt":
			arc = 0.35
		"stone", "ball", "volley":
			arc = 0.55
		"shell":
			arc = 0.8
		"missile":
			arc = 0.6
		"bombs", "nuke":   # dropped from above the target
			from = to + Vector3(0, 0.9, 0)
			arc = 0.0
		"torpedo":
			from.y = to.y - 0.1
			to.y -= 0.1
	var duration := _flight_time(kind)
	var t := _tween()
	t.tween_method(func(f: float) -> void:
		var p := from.lerp(to, f) + Vector3(0, arc * 4.0 * f * (1.0 - f), 0)
		var ahead := from.lerp(to, minf(f + 0.02, 1.0)) + Vector3(0, arc * 4.0 * minf(f + 0.02, 1.0) * (1.0 - minf(f + 0.02, 1.0)), 0)
		node.position = p
		if ahead.distance_to(p) > 0.0001:
			node.look_at(global_transform * ahead, Vector3.UP, true)
		, 0.0, 1.0, duration)
	await t.finished
	node.queue_free()


func _projectile_mesh(kind: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh: Mesh
	match kind:
		"arrow", "bolt":
			var box := BoxMesh.new()
			box.size = Vector3(0.008, 0.008, 0.09 if kind == "arrow" else 0.06)
			mesh = box
			m.albedo_color = Color(0.85, 0.75, 0.55)
		"bullets", "tracers":
			var box := BoxMesh.new()
			box.size = Vector3(0.008, 0.008, 0.12)
			mesh = box
			m.albedo_color = Color(1.0, 0.9, 0.5)
		"missile", "torpedo":
			var box := BoxMesh.new()
			box.size = Vector3(0.022, 0.022, 0.1)
			mesh = box
			m.albedo_color = Color(0.9, 0.9, 0.92)
		_:
			var s := SphereMesh.new()
			s.radius = 0.025 if kind != "nuke" else 0.05
			s.height = s.radius * 2.0
			s.radial_segments = 6
			s.rings = 3
			mesh = s
			m.albedo_color = Color(0.25, 0.25, 0.27) if kind != "stone" else Color(0.6, 0.57, 0.52)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	node.mesh = mesh
	node.material_override = m
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A puff where a projectile lands: dust for arrows and stones, a fireball for shells and bombs.
func _burst(at: Vector3, kind: String) -> void:
	var fiery := kind in ["shell", "shell_flat", "ball", "volley", "missile", "torpedo", "bombs", "nuke", "tracers", "bullets"]
	var count := 12 if kind == "nuke" else (6 if fiery else 3)
	var size := 0.4 if kind == "nuke" else (0.07 if fiery else 0.04)
	for i in count:
		var puff := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = 7
		s.rings = 4
		puff.mesh = s
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if fiery and i % 2 == 0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.albedo_color = Color(1.0, 0.6, 0.2, 0.95) if fiery and i % 2 == 0 else Color(0.7, 0.68, 0.62, 0.85)
		puff.material_override = m
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.position = at + _jitter(size * 0.6)
		puff.scale = Vector3.ONE * size * 0.3
		add_child(puff)
		var t := _tween().set_parallel(true)
		t.tween_property(puff, "scale", Vector3.ONE * size * randf_range(0.9, 1.6), 0.45).set_ease(Tween.EASE_OUT)
		t.tween_property(puff, "position", puff.position + Vector3(0, size * 1.2, 0) + _jitter(size * 0.5), 0.6)
		t.tween_property(m, "albedo_color:a", 0.0, 0.6).set_delay(0.15)
		t.chain().tween_callback(puff.queue_free)


## A floating "-23" over a unit that rises and fades.
func _number(at: Vector3, damage: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = "-%d" % damage
	label.font_size = 64
	label.pixel_size = 0.005
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = at
	add_child(label)
	var t := _tween().set_parallel(true)
	t.tween_property(label, "position", at + Vector3(0, 0.35, 0), 1.1).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.6)
	t.chain().tween_callback(label.queue_free)


## Briefly tints every mesh in [param unit] with [param color].
func _flash(unit: Node3D, color: Color) -> void:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = Color(color.r, color.g, color.b, 0.7)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(unit, meshes)
	for mi in meshes:
		mi.material_overlay = overlay
	var t := _tween()
	t.tween_property(overlay, "albedo_color:a", 0.0, 0.35)
	t.tween_callback(func() -> void:
		for mi in meshes:
			if is_instance_valid(mi) and mi.material_overlay == overlay:
				mi.material_overlay = null)


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


## Plays [param clip] if the unit's model came with an AnimationPlayer that has it.
static func _play_clip(unit: Node3D, clip: String) -> void:
	var players := unit.find_children("*", "AnimationPlayer", true, false)
	for p: AnimationPlayer in players:
		if p.has_animation(clip):
			p.play(clip)
			return


static func _jitter(amount: float) -> Vector3:
	return Vector3(randf_range(-amount, amount), randf_range(-amount, amount) * 0.5, randf_range(-amount, amount))
