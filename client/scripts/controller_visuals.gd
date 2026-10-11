# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node3D
## What you see of a controller in your hand: the controller itself - the real one, as the headset's runtime draws it
## (Quest Touch, Index, Vive wand... through OpenXR render models: XR_EXT_render_model, which SteamVR provides, or
## Meta's XR_FB_render_model through the OpenXR vendors plugin, on the Quest and Meta's PC runtime), or a plain
## stand-in when the runtime has no model - and, optionally, floating labels saying what each
## button does, named the way that controller names them (A / B / X / Y, trackpad, menu...).
## Lives under an XRController3D using the "aim" pose; set [member is_right] before adding it.

const LABEL_COLOR := Color(0.95, 0.97, 1.0)
const BUTTON_COLOR := Color(1.0, 0.85, 0.4)

var is_right := true
var labels_shown := true:
	set(value):
		labels_shown = value
		if _labels != null:
			_labels.visible = value
var profile := ""            # the interaction profile the runtime says this controller is

var _manager: Node3D         # OpenXRRenderModelManager (when the engine has it)
var _meta_holder: Node3D     # Meta's model (OpenXRFbRenderModel) is made for the grip pose: this holds it there
var _meta_model: Node3D
var _fallback: Node3D        # our stand-in, while there's no render model
var _labels: Node3D
var _rows: Array = []        # [[button, what it does], ...] on show
var _label_nodes: Array[Label3D] = []


func _ready() -> void:
	_add_render_models()
	if _manager == null:   # the session may still be starting: look again in a moment
		get_tree().create_timer(3.0).timeout.connect(_add_render_models)
	_fallback = _make_fallback()
	add_child(_fallback)
	_labels = Node3D.new()
	_labels.name = "ButtonLabels"
	_labels.visible = labels_shown
	add_child(_labels)


## The runtime's controller models, when OpenXR is running and the runtime has render models (XR_EXT_render_model).
## Without them the manager would only complain every frame, so it's left out and the stand-in stays.
func _add_render_models() -> void:
	if _manager != null or _meta_model != null:
		return
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized():
		return
	if _add_meta_model():
		return
	if not ClassDB.class_exists("OpenXRRenderModelManager") or not Engine.has_singleton("OpenXRRenderModelExtension"):
		return
	var extension: Object = Engine.get_singleton("OpenXRRenderModelExtension")
	if not extension.call("is_active"):
		return
	_manager = ClassDB.instantiate("OpenXRRenderModelManager") as Node3D
	_manager.name = "RenderModels"
	_manager.set("tracker", 3 if is_right else 2)   # RENDER_MODEL_TRACKER_RIGHT_HAND / LEFT_HAND
	_manager.set("make_local_to_pose", "aim")      # our controller node follows the aim pose
	add_child(_manager)
	print("Controller models from the runtime (%s hand)" % ("right" if is_right else "left"))


## Meta's runtime (Quest, and Quest Link on the PC): XR_FB_render_model, from the OpenXR vendors plugin.
func _add_meta_model() -> bool:
	if not ClassDB.class_exists("OpenXRFbRenderModel") or not Engine.has_singleton("OpenXRFbRenderModelExtension"):
		return false
	var extension: Object = Engine.get_singleton("OpenXRFbRenderModelExtension")
	if not extension.call("is_enabled"):
		return false
	_meta_holder = Node3D.new()
	_meta_holder.name = "MetaModel"
	add_child(_meta_holder)
	_meta_model = ClassDB.instantiate("OpenXRFbRenderModel") as Node3D
	_meta_model.set("render_model_type", 1 if is_right else 0)   # MODEL_CONTROLLER_RIGHT / LEFT
	_meta_holder.add_child(_meta_model)
	print("Controller models from Meta's runtime (%s hand)" % ("right" if is_right else "left"))
	return true


## Whether the runtime is drawing the real controller (a render model has arrived).
func has_real_model() -> bool:
	if _meta_model != null:
		return bool(_meta_model.call("has_render_model_node"))
	return _manager != null and _manager.get_child_count() > 0


## Meta's model sits on the grip pose; we follow the aim pose, so it's offset by the difference between the two.
func _place_meta_model() -> void:
	var tracker := XRServer.get_tracker("right_hand" if is_right else "left_hand") as XRPositionalTracker
	if tracker == null:
		return
	var aim := tracker.get_pose("aim")
	var grip := tracker.get_pose("grip")
	if aim == null or grip == null or not aim.has_tracking_data or not grip.has_tracking_data:
		return
	_meta_holder.transform = aim.transform.affine_inverse() * grip.transform


func _process(_delta: float) -> void:
	_fallback.visible = not has_real_model()
	if _meta_holder != null:
		_place_meta_model()
	# The labels stand upright beside the controller as you see it, whichever way the controller is turned
	if _labels.visible and not _label_nodes.is_empty():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var basis := camera.global_transform.basis.orthonormalized()
			# Both columns to the right of their controller: the left hand's past the wrist card on it
			var anchor := global_position + basis.x * (0.045 if is_right else 0.1) + basis.y * 0.035
			_labels.global_transform = Transform3D(basis, anchor)


## The labels: [[button name, what it does], ...], top to bottom. Rebuilt only when they change.
func set_rows(rows: Array) -> void:
	if rows == _rows:
		return
	_rows = rows.duplicate(true)
	for node in _label_nodes:
		node.queue_free()
	_label_nodes.clear()
	for i in rows.size():
		var row: Array = rows[i]
		var label := Label3D.new()
		label.text = "%s:  %s" % [row[0], row[1]]
		label.font_size = 28
		label.pixel_size = 0.0003
		label.outline_size = 10
		label.outline_modulate = Color(0.02, 0.03, 0.06, 0.95)
		label.modulate = LABEL_COLOR
		label.no_depth_test = true          # readable through the controller and the table
		label.render_priority = 2
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# A column beside the controller, on the outside, from just above it downwards
		label.position = Vector3(0, -i * 0.0125, 0)
		_labels.add_child(label)
		_label_nodes.append(label)


## The labels' texts on show (for tests).
func label_texts() -> Array[String]:
	var out: Array[String] = []
	for node in _label_nodes:
		out.append(node.text)
	return out


## A plain controller shape: a handle angled back under a ring, in dark grey.
func _make_fallback() -> Node3D:
	var root := Node3D.new()
	root.name = "StandIn"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.17, 0.2)
	material.roughness = 0.6
	var handle := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.016
	capsule.height = 0.11
	handle.mesh = capsule
	handle.material_override = material
	handle.position = Vector3(0, -0.035, 0.06)
	handle.rotation_degrees = Vector3(-35, 0, 0)
	root.add_child(handle)
	var head := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.028
	cylinder.bottom_radius = 0.03
	cylinder.height = 0.022
	head.mesh = cylinder
	head.material_override = material
	head.position = Vector3(0, 0.0, 0.025)
	head.rotation_degrees = Vector3(-10, 0, 0)
	root.add_child(head)
	var tip := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.006
	sphere.height = 0.012
	tip.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.4, 0.9, 1.0) if is_right else Color(0.6, 0.6, 0.65)
	tip.material_override = glow
	tip.position = Vector3(0, 0.0, 0.0)
	root.add_child(tip)
	return root


## The names this controller gives its buttons: {ax, by, stick, menu}, from its interaction profile.
static func button_names(profile_path: String, right: bool) -> Dictionary:
	var names := {"ax": "A" if right else "X", "by": "B" if right else "Y", "stick": "Thumbstick", "menu": "Menu",
		"trigger": "Trigger", "grip": "Grip"}
	if profile_path.contains("valve/index"):
		names["ax"] = "A"
		names["by"] = "B"
	elif profile_path.contains("htc/vive_controller"):
		names["ax"] = ""
		names["by"] = ""
		names["stick"] = "Trackpad"
	elif profile_path.contains("microsoft/motion_controller"):
		names["ax"] = ""
		names["by"] = ""
	elif profile_path.contains("khr/generic"):
		names["ax"] = "Button 1"
		names["by"] = "Button 2"
	return names
