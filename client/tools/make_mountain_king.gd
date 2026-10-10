# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends SceneTree
## Generates the "In the Hall of the Mountain King" scenery model:
##   client/backgrounds/MountainKing/scenery.glb
## Run from client/:
##   godot --headless --xr-mode off --audio-driver Dummy -s tools/make_mountain_king.gd

const OUTPUT_RES := "res://backgrounds/MountainKing/scenery.glb"


func _init() -> void:
	print("Generating 'In the Hall of the Mountain King' background scenery...")
	var root := build_mountain_king_scene()
	_save_gltf(root, OUTPUT_RES)
	print("Done generating Mountain King background!")
	quit()


func build_mountain_king_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "MountainKing"

	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321

	# Materials
	var stone_mat := _material("CavernStone", 0.92)
	var floor_mat := _material("HallFloor", 0.88)
	var iron_mat := _material("BrazierIron", 0.65)
	iron_mat.metallic = 0.75

	# Ends with "lava" -> animated rolling glow shader from tileset_shaders.gd!
	var lava_mat := _material("CavernLava", 0.25)
	lava_mat.emission_enabled = true
	lava_mat.emission = Color(1.0, 0.42, 0.08)
	lava_mat.emission_energy_multiplier = 2.2

	# Ends with "sparkle" -> animated twinkling glints shader!
	var sparkle_mat := _material("TreasureSparkle", 0.25)
	sparkle_mat.emission_enabled = true
	sparkle_mat.emission = Color(0.9, 0.7, 1.0)
	sparkle_mat.emission_energy_multiplier = 2.0

	var ember_mat := _material("EmberMotes", 1.0)
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# 1. Cavern Floor & Paved Nave
	_build_floor(root, rng, floor_mat, stone_mat)

	# 2. Glowing Magma Chasms / Fissures along the flanks
	_build_magma_fissures(root, rng, lava_mat, stone_mat)

	# 3. Colonnade of Giant Stone Pillars & Vault Arches
	_build_colonnade(root, rng, stone_mat)

	# 4. The Mountain King's Monumental Throne & Stepped Dais
	_build_throne_and_dais(root, stone_mat, sparkle_mat)

	# 5. Giant Troll Guardians / Sentinel Monoliths
	_build_troll_guardians(root, stone_mat, lava_mat)

	# 6. Troll Hoard & Gem Crystals (Amethysts, Emeralds, Gold, Rubies)
	_build_gem_crystals(root, rng, sparkle_mat)

	# 7. Iron Braziers with Glowing Coals & Fire
	_build_braziers(root, iron_mat, lava_mat)

	# 8. Cavern Walls & Vault Stalactites
	_build_cavern_enclosure(root, rng, stone_mat)

	# 9. Floating Embers (node named "Embers" for background.json spin)
	_build_floating_embers(root, rng, ember_mat)

	return root


# region 1. Floor -----------------------------------------------------------------------------

func _build_floor(root: Node3D, rng: RandomNumberGenerator, floor_mat: StandardMaterial3D, rock_mat: StandardMaterial3D) -> void:
	var st := _begin()

	# Flat clean stone circle under player and table (r <= 2.6m at y = 0)
	var inner_segs := 32
	var r_inner := 2.6
	for i in inner_segs:
		var a1 := TAU * float(i) / float(inner_segs)
		var a2 := TAU * float(i + 1) / float(inner_segs)
		var v0 := Vector3.ZERO
		var v1 := Vector3(cos(a1) * r_inner, 0.0, sin(a1) * r_inner)
		var v2 := Vector3(cos(a2) * r_inner, 0.0, sin(a2) * r_inner)
		var col := Color(0.24, 0.22, 0.27).lerp(Color(0.20, 0.18, 0.23), float(i % 2) * 0.15)
		_add_tri(st, v0, v1, v2, col, Vector3.UP)

	# Carved flagstone terrace ring (r from 2.6m to 5.2m)
	var r_mid := 5.2
	var mid_segs := 40
	for i in mid_segs:
		var a1 := TAU * float(i) / float(mid_segs)
		var a2 := TAU * float(i + 1) / float(mid_segs)
		var v1_in := Vector3(cos(a1) * r_inner, 0.0, sin(a1) * r_inner)
		var v2_in := Vector3(cos(a2) * r_inner, 0.0, sin(a2) * r_inner)
		var v1_out := Vector3(cos(a1) * r_mid, -0.04, sin(a1) * r_mid)
		var v2_out := Vector3(cos(a2) * r_mid, -0.04, sin(a2) * r_mid)
		var c := Color(0.25, 0.22, 0.28).lerp(Color(0.21, 0.19, 0.24), float(i % 3) * 0.1)
		_add_tri(st, v1_in, v1_out, v2_out, c, Vector3.UP)
		_add_tri(st, v1_in, v2_out, v2_in, c, Vector3.UP)

	# Processional paved walkway leading north towards dais (z from +2 down to -14, x between -3.8 and +3.8)
	for z_step in 10:
		var z1 := 2.0 - float(z_step) * 1.6
		var z2 := z1 - 1.6
		var x_half := 3.8
		var p1 := Vector3(-x_half, -0.05, z1)
		var p2 := Vector3(x_half, -0.05, z1)
		var p3 := Vector3(x_half, -0.05, z2)
		var p4 := Vector3(-x_half, -0.05, z2)
		var c := Color(0.24, 0.22, 0.28).lerp(Color(0.29, 0.25, 0.33), float(z_step % 2) * 0.25)
		_add_tri(st, p1, p2, p3, c, Vector3.UP)
		_add_tri(st, p1, p3, p4, c, Vector3.UP)

	_add_mesh(root, "HallFloor", _done(st), floor_mat)

	# Surrounding rugged subterranean bedrock (stepped rock plates out to 65m)
	var rock_st := _begin()
	var outer_rings := 5
	var prev_r := r_mid
	for ring in outer_rings:
		var cur_r := prev_r + (8.0 + float(ring) * 3.5)
		var segs := 36 + ring * 8
		for i in segs:
			var a1 := TAU * float(i) / float(segs)
			var a2 := TAU * float(i + 1) / float(segs)
			var y1 := rng.randf_range(-0.3, 0.2) - float(ring) * 0.2
			var y2 := rng.randf_range(-0.3, 0.2) - float(ring) * 0.2
			var p1 := Vector3(cos(a1) * prev_r, y1, sin(a1) * prev_r)
			var p2 := Vector3(cos(a2) * prev_r, y2, sin(a2) * prev_r)
			var p3 := Vector3(cos(a2) * cur_r, y2 - 0.4, sin(a2) * cur_r)
			var p4 := Vector3(cos(a1) * cur_r, y1 - 0.4, sin(a1) * cur_r)
			var c := Color(0.19, 0.17, 0.23).darkened(rng.randf_range(0.0, 0.15))
			_add_tri(rock_st, p1, p4, p3, c, Vector3.UP)
			_add_tri(rock_st, p1, p3, p2, c, Vector3.UP)
		prev_r = cur_r

	_add_mesh(root, "Bedrock", _done(rock_st), rock_mat)


# region 2. Magma Chasms ----------------------------------------------------------------------

func _build_magma_fissures(root: Node3D, rng: RandomNumberGenerator, lava_mat: StandardMaterial3D, rock_mat: StandardMaterial3D) -> void:
	var lava_st := _begin()
	var crust_st := _begin()

	# Two prominent winding magma rivers flanking the hall:
	var sides: Array[float] = [-1.0, 1.0]
	for side: float in sides:
		var pts: Array[Vector3] = []
		var count := 18
		for i in count:
			var t: float = float(i) / float(count - 1)
			var z: float = lerp(8.0, -28.0, t)
			var x_base: float = (5.8 + sin(t * 4.5) * 1.8 + t * 3.0) * side
			var y: float = -0.45 - sin(t * 3.14159) * 0.25
			pts.append(Vector3(x_base, y, z))

		for i in count - 1:
			var p1 := pts[i]
			var p2 := pts[i + 1]
			var width := rng.randf_range(2.0, 3.2)
			var fwd := (p2 - p1).normalized()
			var right := fwd.cross(Vector3.UP).normalized() * (width * 0.5)

			var l1 := p1 - right
			var r1 := p1 + right
			var l2 := p2 - right
			var r2 := p2 + right

			# Bright molten lava core
			var hot_col := Color(1.0, 0.50, 0.10).lerp(Color(0.98, 0.22, 0.03), rng.randf_range(0.0, 0.35))
			_add_tri(lava_st, l1, r1, r2, hot_col, Vector3.UP)
			_add_tri(lava_st, l1, r2, l2, hot_col, Vector3.UP)

			# Raised basalt crust bank
			var crust_l1 := l1 + Vector3(-right.x * 0.5, 0.35, -right.z * 0.5)
			var crust_r1 := r1 + Vector3(right.x * 0.5, 0.35, right.z * 0.5)
			var crust_l2 := l2 + Vector3(-right.x * 0.5, 0.35, -right.z * 0.5)
			var crust_r2 := r2 + Vector3(right.x * 0.5, 0.35, right.z * 0.5)

			var crust_c := Color(0.18, 0.15, 0.20)
			_add_tri(crust_st, l1, crust_l1, crust_l2, crust_c, Vector3.UP)
			_add_tri(crust_st, l1, crust_l2, l2, crust_c, Vector3.UP)
			_add_tri(crust_st, r1, r2, crust_r2, crust_c, Vector3.UP)
			_add_tri(crust_st, r1, crust_r2, crust_r1, crust_c, Vector3.UP)

	# Arc of molten lava pooling behind the dais (z around -21 to -24)
	for i in 10:
		var a1 := PI * 0.15 + PI * 0.7 * float(i) / 10.0
		var a2 := PI * 0.15 + PI * 0.7 * float(i + 1) / 10.0
		var r1_lava := 8.5
		var r2_lava := 11.0
		var center := Vector3(0.0, -0.5, -17.5)
		var v1 := center + Vector3(cos(a1) * r1_lava, 0, -sin(a1) * r1_lava)
		var v2 := center + Vector3(cos(a2) * r1_lava, 0, -sin(a2) * r1_lava)
		var v3 := center + Vector3(cos(a2) * r2_lava, 0, -sin(a2) * r2_lava)
		var v4 := center + Vector3(cos(a1) * r2_lava, 0, -sin(a1) * r2_lava)
		var c := Color(1.0, 0.55, 0.08)
		_add_tri(lava_st, v1, v2, v3, c, Vector3.UP)
		_add_tri(lava_st, v1, v3, v4, c, Vector3.UP)

	_add_mesh(root, "MagmaFissures", _done(lava_st), lava_mat)
	_add_mesh(root, "FissureCrust", _done(crust_st), rock_mat)


# region 3. Colonnade & Arches ----------------------------------------------------------------

func _build_colonnade(root: Node3D, rng: RandomNumberGenerator, stone_mat: StandardMaterial3D) -> void:
	var st := _begin()

	# Main nave pillars (8 massive columns framing the path to the throne)
	var z_coords: Array[float] = [-3.5, -8.5, -13.5, -18.5]
	for z_pos: float in z_coords:
		var dist_out: float = 5.2 + abs(z_pos + 6.0) * 0.12
		_make_hall_pillar(st, rng, Vector3(-dist_out, 0.0, z_pos), 2.4, 22.0, 1.0)
		_make_hall_pillar(st, rng, Vector3(dist_out, 0.0, z_pos), 2.4, 22.0, -1.0)

		# Vault arch rib connecting pair overhead
		_make_vault_arch(st, Vector3(-dist_out, 20.0, z_pos), Vector3(dist_out, 20.0, z_pos), 4.8)

	# Secondary perimeter pillars supporting outer cavern
	var outer_coords: Array[Vector3] = [
		Vector3(-14.0, 0, -2.0), Vector3(14.0, 0, -2.0),
		Vector3(-16.0, 0, -12.0), Vector3(16.0, 0, -12.0),
		Vector3(-17.0, 0, -22.0), Vector3(17.0, 0, -22.0),
		Vector3(-12.0, 0, 7.0), Vector3(12.0, 0, 7.0),
		Vector3(-6.0, 0, 13.0), Vector3(6.0, 0, 13.0)
	]
	for pos: Vector3 in outer_coords:
		_make_hall_pillar(st, rng, pos, rng.randf_range(1.8, 2.5), rng.randf_range(18.0, 24.0), 0.0)

	_add_mesh(root, "PillarsAndArches", _done(st), stone_mat)


func _make_hall_pillar(st: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, base_r: float, height: float, inward_dir: float) -> void:
	var sides := 8
	var seg_heights: Array[float] = [0.0, 1.4, 4.5, 10.0, 16.0, height - 1.8, height]
	var seg_radii: Array[float] = [base_r * 1.4, base_r, base_r * 0.75, base_r * 0.68, base_r * 0.82, base_r * 1.25, base_r * 1.6]

	var rings: Array[Array] = []
	for s in seg_heights.size():
		var y: float = at.y + seg_heights[s]
		var r: float = seg_radii[s]
		var ring: Array[Vector3] = []
		for i in sides:
			var a: float = TAU * (float(i) + rng.randf_range(-0.15, 0.15)) / float(sides)
			var offset_x: float = (cos(a) * r) + (inward_dir * 0.5 if s >= 4 else 0.0)
			var offset_z: float = sin(a) * r
			ring.append(Vector3(at.x + offset_x, y, at.z + offset_z))
		rings.append(ring)

	for s in rings.size() - 1:
		var r1: Array = rings[s]
		var r2: Array = rings[s + 1]
		for i in sides:
			var j := (i + 1) % sides
			var v1: Vector3 = r1[i]
			var v2: Vector3 = r1[j]
			var v3: Vector3 = r2[j]
			var v4: Vector3 = r2[i]
			var col := Color(0.25, 0.23, 0.29).darkened(rng.randf_range(0.0, 0.18))
			var norm := (v2 - v1).cross(v4 - v1).normalized()
			_add_tri(st, v1, v2, v3, col, norm)
			_add_tri(st, v1, v3, v4, col, norm)


func _make_vault_arch(st: SurfaceTool, p1: Vector3, p2: Vector3, rise: float) -> void:
	var segs := 10
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / float(segs)
		var pos := p1.lerp(p2, t)
		pos.y += sin(t * PI) * rise
		pts.append(pos)

	for i in segs:
		var a := pts[i]
		var b := pts[i + 1]
		var w := 0.85
		var fwd := (b - a).normalized()
		var side := fwd.cross(Vector3.UP).normalized() * w
		var up := Vector3.UP * 1.1

		var v1 := a - side
		var v2 := a + side
		var v3 := b + side
		var v4 := b - side
		var col := Color(0.22, 0.20, 0.26)
		_add_tri(st, v1, v2, v3, col, -up)
		_add_tri(st, v1, v3, v4, col, -up)
		_add_tri(st, v1 + up, v3 + up, v2 + up, col, up)
		_add_tri(st, v1 + up, v4 + up, v3 + up, col, up)


# region 4. The Mountain King's Throne --------------------------------------------------------

func _build_throne_and_dais(root: Node3D, stone_mat: StandardMaterial3D, sparkle_mat: StandardMaterial3D) -> void:
	var st := _begin()
	var throne_center := Vector3(0.0, 0.0, -17.5)

	# Monumental stepped stone dais (3 broad tiers)
	var step_w: Array[float] = [12.0, 9.6, 7.4]
	var step_d: Array[float] = [7.5, 6.0, 4.6]
	var step_h: Array[float] = [0.45, 0.90, 1.35]
	for s in 3:
		var hw: float = step_w[s] * 0.5
		var hd: float = step_d[s] * 0.5
		var y: float = step_h[s]
		var y_prev: float = step_h[s - 1] if s > 0 else 0.0
		var c := Color(0.27, 0.24, 0.31).darkened(float(s) * 0.07)

		# Top slab
		var p1 := throne_center + Vector3(-hw, y, hd)
		var p2 := throne_center + Vector3(hw, y, hd)
		var p3 := throne_center + Vector3(hw, y, -hd)
		var p4 := throne_center + Vector3(-hw, y, -hd)
		_add_tri(st, p1, p2, p3, c, Vector3.UP)
		_add_tri(st, p1, p3, p4, c, Vector3.UP)

		# Front riser
		var rf1 := throne_center + Vector3(-hw, y_prev, hd)
		var rf2 := throne_center + Vector3(hw, y_prev, hd)
		_add_tri(st, rf1, rf2, p2, c.darkened(0.18), Vector3.BACK)
		_add_tri(st, rf1, p2, p1, c.darkened(0.18), Vector3.BACK)

	# Throne seat & base plinth (at y = 1.35m)
	var plinth_y := 1.35
	var seat_w := 4.2
	var seat_d := 3.0
	var p_hw := seat_w * 0.5
	var p_hd := seat_d * 0.5
	var base_box := _box(seat_w, 0.9, seat_d)
	_append(st, base_box, Transform3D(Basis(), throne_center + Vector3(0, plinth_y + 0.45, 0)), Color(0.23, 0.21, 0.27))

	# Massive carved armrests
	var arm_w := 0.85
	var arm_h := 1.4
	var arm_l := 2.8
	var left_arm := _box(arm_w, arm_h, arm_l)
	_append(st, left_arm, Transform3D(Basis(), throne_center + Vector3(-p_hw + arm_w * 0.5, plinth_y + 0.9 + arm_h * 0.5, 0)), Color(0.21, 0.19, 0.25))
	var right_arm := _box(arm_w, arm_h, arm_l)
	_append(st, right_arm, Transform3D(Basis(), throne_center + Vector3(p_hw - arm_w * 0.5, plinth_y + 0.9 + arm_h * 0.5, 0)), Color(0.21, 0.19, 0.25))

	# Grand towering backrest rising to y = 10.5m!
	var back_z := throne_center.z - p_hd + 0.5
	var back_pts_low: Array[Vector3] = [
		Vector3(-2.6, plinth_y + 0.9, back_z),
		Vector3(2.6, plinth_y + 0.9, back_z),
		Vector3(2.1, 7.8, back_z - 0.4),
		Vector3(-2.1, 7.8, back_z - 0.4)
	]
	var back_c := Color(0.20, 0.18, 0.24)
	_add_tri(st, back_pts_low[0], back_pts_low[1], back_pts_low[2], back_c, Vector3.FORWARD)
	_add_tri(st, back_pts_low[0], back_pts_low[2], back_pts_low[3], back_c, Vector3.FORWARD)

	# 5 Monumental jagged crown spires on top of backrest (Dovregubben's mountain crown)
	var crown_spikes: Array[Vector3] = [
		Vector3(-2.0, 7.8, back_z), Vector3(-1.4, 9.4, back_z - 0.2), Vector3(-0.8, 7.8, back_z),
		Vector3(-0.8, 7.8, back_z), Vector3(0.0, 11.2, back_z - 0.4), Vector3(0.8, 7.8, back_z),
		Vector3(0.8, 7.8, back_z), Vector3(1.4, 9.4, back_z - 0.2), Vector3(2.0, 7.8, back_z)
	]
	for k in range(0, crown_spikes.size(), 3):
		_add_tri(st, crown_spikes[k], crown_spikes[k + 1], crown_spikes[k + 2], Color(0.17, 0.15, 0.21), Vector3.FORWARD)

	_add_mesh(root, "MountainKingThrone", _done(st), stone_mat)

	# Heart of the Mountain King: Giant faceted troll ruby in throne crest (twinkles!)
	var ruby_st := _begin()
	var diamond := SphereMesh.new()
	diamond.radius = 0.72
	diamond.height = 1.45
	diamond.radial_segments = 8
	diamond.rings = 3
	_append(ruby_st, diamond, Transform3D(Basis(), Vector3(0.0, 8.8, back_z + 0.15)), Color(0.98, 0.12, 0.35))
	_add_mesh(root, "HeartOfMountainRuby", _done(ruby_st), sparkle_mat)


# region 5. Troll Guardians -------------------------------------------------------------------

func _build_troll_guardians(root: Node3D, stone_mat: StandardMaterial3D, eye_lava_mat: StandardMaterial3D) -> void:
	var st := _begin()
	var eye_st := _begin()

	# Two colossal stone troll sentinels flanking the dais at x = -5.8 and +5.8, z = -15.5
	var positions: Array[Vector3] = [Vector3(-5.8, 0.45, -15.5), Vector3(5.8, 0.45, -15.5)]
	for i in positions.size():
		var at: Vector3 = positions[i]
		var facing_sign := 1.0 if i == 0 else -1.0
		var c := Color(0.21, 0.19, 0.25)

		# Stone pedestal
		_append(st, _box(2.4, 1.1, 2.4), Transform3D(Basis(), at + Vector3(0, 0.55, 0)), c.darkened(0.12))

		# Heavy troll legs / torso
		_append(st, _box(2.0, 2.6, 1.6), Transform3D(Basis(), at + Vector3(0, 2.4, 0)), c)

		# Hunchbacked broad troll shoulders
		_append(st, _box(3.0, 1.6, 1.8), Transform3D(Basis(), at + Vector3(0, 4.2, -0.2)), c.darkened(0.05))

		# Horned carved rock head
		var head_pos: Vector3 = at + Vector3(0, 5.6, 0.2)
		_append(st, _box(1.5, 1.5, 1.5), Transform3D(Basis(), head_pos), c)

		# Glowing magma eyes
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.18
		eye_mesh.height = 0.35
		eye_mesh.radial_segments = 5
		eye_mesh.rings = 2
		_append(eye_st, eye_mesh, Transform3D(Basis(), head_pos + Vector3(-0.42, 0.12, 0.75)), Color(1.0, 0.45, 0.06))
		_append(eye_st, eye_mesh, Transform3D(Basis(), head_pos + Vector3(0.42, 0.12, 0.75)), Color(1.0, 0.45, 0.06))

		# Massive stone war-hammer resting on dais
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.14
		shaft.bottom_radius = 0.14
		shaft.height = 5.5
		shaft.radial_segments = 6
		_append(st, shaft, Transform3D(Basis(), at + Vector3(facing_sign * 1.5, 2.8, 0.9)), Color(0.30, 0.24, 0.18))

		var hammer_head := _box(1.1, 1.6, 1.1)
		_append(st, hammer_head, Transform3D(Basis(), at + Vector3(facing_sign * 1.5, 5.2, 0.9)), Color(0.18, 0.17, 0.22))

	_add_mesh(root, "TrollGuardians", _done(st), stone_mat)
	_add_mesh(root, "GuardianEyes", _done(eye_st), eye_lava_mat)


# region 6. Gem Crystals & Gold Hoard ---------------------------------------------------------

func _build_gem_crystals(root: Node3D, rng: RandomNumberGenerator, sparkle_mat: StandardMaterial3D) -> void:
	var st := _begin()

	# Crystal clusters: flanking the throne dais, along the nave walkway, and near the table
	var clusters: Array[Vector3] = [
		# Near throne & dais
		Vector3(-4.8, 0.7, -14.8), Vector3(4.8, 0.7, -14.8),
		Vector3(-4.0, 1.35, -16.8), Vector3(4.0, 1.35, -16.8),
		Vector3(0.0, 1.45, -14.6),
		# Along processional nave
		Vector3(-3.9, 0.0, -7.5), Vector3(3.9, 0.0, -7.5),
		Vector3(-4.5, 0.0, -12.0), Vector3(4.5, 0.0, -12.0),
		# Near table edge (visible from VR player spot!)
		Vector3(-2.8, 0.0, -1.8), Vector3(2.8, 0.0, -1.8),
		Vector3(-3.2, 0.0, 0.8), Vector3(3.2, 0.0, 0.8),
		# Fissure banks
		Vector3(-6.5, -0.1, -4.5), Vector3(6.8, -0.1, -4.5),
		Vector3(-7.5, -0.1, -11.0), Vector3(7.5, -0.1, -11.0)
	]

	var gem_colors: Array[Color] = [
		Color(0.75, 0.30, 0.98), # Royal Amethyst
		Color(0.22, 0.92, 0.45), # Troll Emerald
		Color(1.0, 0.82, 0.18),  # Mountain Gold
		Color(0.98, 0.18, 0.30), # Dovre Ruby
		Color(0.28, 0.70, 1.0)   # Glacial Sapphire
	]

	for cluster_pos: Vector3 in clusters:
		var num_gems := rng.randi_range(5, 9)
		for g in num_gems:
			var height := rng.randf_range(1.0, 2.6)
			var radius := rng.randf_range(0.20, 0.42)
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(0.2, 1.5)
			var pos: Vector3 = cluster_pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			var tilt_axis := Vector3(rng.randfn(), 0, rng.randfn()).normalized()
			var tilt_angle := rng.randf_range(0.12, 0.38)

			var xform := Transform3D(Basis(tilt_axis, tilt_angle), pos)
			var color: Color = gem_colors[rng.randi() % gem_colors.size()]
			_make_crystal_spire(st, xform, radius, height, color)

	_add_mesh(root, "GemCrystals", _done(st), sparkle_mat)


func _make_crystal_spire(st: SurfaceTool, xform: Transform3D, radius: float, height: float, color: Color) -> void:
	var sides := 6
	var base_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	var apex := xform * Vector3(0, height, 0)

	var mid_y := height * 0.74
	for i in sides:
		var a := TAU * float(i) / float(sides)
		base_ring.append(xform * Vector3(cos(a) * radius, 0, sin(a) * radius))
		mid_ring.append(xform * Vector3(cos(a) * radius * 0.88, mid_y, sin(a) * radius * 0.88))

	for i in sides:
		var j := (i + 1) % sides
		var v1: Vector3 = base_ring[i]
		var v2: Vector3 = base_ring[j]
		var v3: Vector3 = mid_ring[j]
		var v4: Vector3 = mid_ring[i]
		var norm := (v2 - v1).cross(v4 - v1).normalized()
		_add_tri(st, v1, v2, v3, color, norm)
		_add_tri(st, v1, v3, v4, color, norm)
		# Pointed faceted crystal apex cap
		var cap_norm := (v3 - apex).cross(v4 - apex).normalized()
		_add_tri(st, v4, v3, apex, color.lightened(0.22), cap_norm)


# region 7. Braziers --------------------------------------------------------------------------

func _build_braziers(root: Node3D, iron_mat: StandardMaterial3D, lava_mat: StandardMaterial3D) -> void:
	var iron_st := _begin()
	var fire_st := _begin()

	var brazier_locs: Array[Vector3] = [
		Vector3(-3.8, 0.0, -2.5), Vector3(3.8, 0.0, -2.5),
		Vector3(-4.4, 0.0, -7.5), Vector3(4.4, 0.0, -7.5),
		Vector3(-5.0, 0.0, -12.5), Vector3(5.0, 0.0, -12.5),
		Vector3(-3.4, 0.45, -14.5), Vector3(3.4, 0.45, -14.5)
	]

	for pos: Vector3 in brazier_locs:
		# Heavy octagonal iron bowl on tripod legs
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.75
		bowl.bottom_radius = 0.40
		bowl.height = 0.65
		bowl.radial_segments = 8
		_append(iron_st, bowl, Transform3D(Basis(), pos + Vector3(0, 1.35, 0)), Color(0.26, 0.24, 0.28))

		# 3 heavy iron legs
		for leg in 3:
			var a := TAU * float(leg) / 3.0
			var leg_mesh := CylinderMesh.new()
			leg_mesh.top_radius = 0.07
			leg_mesh.bottom_radius = 0.10
			leg_mesh.height = 1.45
			leg_mesh.radial_segments = 4
			var leg_xform := Transform3D(Basis.from_euler(Vector3(0.22, a, 0)), pos + Vector3(cos(a) * 0.4, 0.72, sin(a) * 0.4))
			_append(iron_st, leg_mesh, leg_xform, Color(0.21, 0.19, 0.23))

		# Glowing hot embers mound in bowl
		var coals := SphereMesh.new()
		coals.radius = 0.68
		coals.height = 0.55
		coals.radial_segments = 8
		coals.rings = 3
		_append(fire_st, coals, Transform3D(Basis(), pos + Vector3(0, 1.50, 0)), Color(1.0, 0.48, 0.08))

		# Vibrant flame spires
		var flame := CylinderMesh.new()
		flame.top_radius = 0.03
		flame.bottom_radius = 0.42
		flame.height = 1.05
		flame.radial_segments = 6
		_append(fire_st, flame, Transform3D(Basis(), pos + Vector3(0, 1.95, 0)), Color(1.0, 0.72, 0.18))

	_add_mesh(root, "IronBraziers", _done(iron_st), iron_mat)
	_add_mesh(root, "BrazierFlames", _done(fire_st), lava_mat)


# region 8. Cavern Enclosure & Stalactites -----------------------------------------------------

func _build_cavern_enclosure(root: Node3D, rng: RandomNumberGenerator, stone_mat: StandardMaterial3D) -> void:
	var st := _begin()

	# Outer cliff walls encircling the hall (r = 48 to 65m, height up to 34m)
	var count := 32
	var prev_top := Vector3.ZERO
	var prev_bot := Vector3.ZERO
	for i in count + 1:
		var a := TAU * float(i % count) / float(count)
		var r_bot := rng.randf_range(48.0, 62.0)
		var r_top := r_bot - rng.randf_range(6.0, 12.0)
		var h := rng.randf_range(28.0, 36.0)

		var bot := Vector3(cos(a) * r_bot, -0.5, sin(a) * r_bot)
		var top := Vector3(cos(a) * r_top, h, sin(a) * r_top)

		if i > 0:
			var c := Color(0.18, 0.16, 0.22).darkened(rng.randf_range(0.0, 0.15))
			var norm := (bot - prev_bot).cross(top - prev_bot).normalized()
			_add_tri(st, prev_bot, bot, top, c, norm)
			_add_tri(st, prev_bot, top, prev_top, c, norm)

		prev_top = top
		prev_bot = bot

	# Giant ceiling stalactites hanging over the perimeter and vault
	for i in 50:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(10.0, 48.0)
		var ceiling_y := rng.randf_range(24.0, 32.0)
		var length := rng.randf_range(5.0, 13.0)
		var base_r := rng.randf_range(0.9, 2.4)
		var at := Vector3(cos(a) * dist, ceiling_y, sin(a) * dist)
		_make_stalactite(st, rng, at, base_r, length)

	_add_mesh(root, "CavernWallsAndCeiling", _done(st), stone_mat)


func _make_stalactite(st: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, base_r: float, length: float) -> void:
	var sides := 5
	var tip := at - Vector3(0, length, 0)
	var ring: Array[Vector3] = []
	for i in sides:
		var a := TAU * (float(i) + rng.randf_range(-0.1, 0.1)) / float(sides)
		ring.append(at + Vector3(cos(a) * base_r, 0, sin(a) * base_r))

	for i in sides:
		var j := (i + 1) % sides
		var v1: Vector3 = ring[i]
		var v2: Vector3 = ring[j]
		var norm := (v2 - v1).cross(tip - v1).normalized()
		var col := Color(0.21, 0.19, 0.25).darkened(rng.randf_range(0.0, 0.1))
		_add_tri(st, v1, v2, tip, col, norm)


# region 9. Floating Embers -------------------------------------------------------------------

func _build_floating_embers(root: Node3D, rng: RandomNumberGenerator, ember_mat: StandardMaterial3D) -> void:
	# Node name "Embers" is rotated by background.json: "spin": {"Embers": 0.35}
	var embers_node := Node3D.new()
	embers_node.name = "Embers"
	root.add_child(embers_node)
	embers_node.owner = root

	var st := _begin()
	var dot := SphereMesh.new()
	dot.radius = 0.08
	dot.height = 0.16
	dot.radial_segments = 4
	dot.rings = 2

	# 220 ember particles scattered around the hall
	for i in 220:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(2.5, 24.0)
		var y := rng.randf_range(0.8, 6.5)
		var pos := Vector3(cos(a) * dist, y, sin(a) * dist)
		var scale := rng.randf_range(0.6, 2.0)
		var brightness := rng.randf_range(0.7, 1.0)
		var tint := Color(1.0 * brightness, rng.randf_range(0.40, 0.70) * brightness, 0.08)
		_append(st, dot, Transform3D(Basis().scaled(Vector3.ONE * scale), pos), tint)

	_add_mesh(embers_node, "EmberDots", _done(st), ember_mat)


# region Mesh & Save Helpers ------------------------------------------------------------------

func _box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, normal: Vector3) -> void:
	var n := normal
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


func _append(st: SurfaceTool, primitive: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var nbasis := xform.basis.inverse().transposed()
	for index in indices:
		st.set_color(color)
		st.set_normal((nbasis * normals[index]).normalized())
		st.add_vertex(xform * verts[index])


func _done(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


func _material(mat_name: String, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	return m


func _add_mesh(parent: Node, node_name: String, mesh: ArrayMesh, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	mesh.surface_set_material(0, material)
	instance.mesh = mesh
	parent.add_child(instance)
	var o: Node = parent
	while o.get_parent() != null:
		o = o.get_parent()
	instance.owner = o
	return instance


func _save_gltf(root: Node3D, res_path: String) -> void:
	var path := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"
	doc.lossy_quality = 0.88
	var state := GLTFState.new()
	var error := doc.append_from_scene(root, state)
	if error == OK:
		error = doc.write_to_filesystem(state, path)
	var triangles := 0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			triangles += mesh.surface_get_array_len(s) / 3 if mesh.surface_get_array_index_len(s) == 0 else mesh.surface_get_array_index_len(s) / 3
	if error != OK:
		push_error("Couldn't write %s: error %d" % [path, error])
	else:
		print("Successfully wrote %s (%d triangles, %d KB)" % [res_path, triangles, FileAccess.get_file_as_bytes(path).size() / 1024])
	root.free()
