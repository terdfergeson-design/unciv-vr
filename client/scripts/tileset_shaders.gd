# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends RefCounted
## Animated materials for tileset pieces. A piece's material is swapped for one of these when its
## name is (or ends with) one of the names below, so a modder only has to name a Blender material.
##   Steam   puffs rising and growing in a loop
##   Geyser  the same, erupting high every so often (Old Faithful)
##   Smoke   darker puffs billowing up slowly and drifting with the wind (Krakatoa)
##   Lava    glowing, its brightness rolling across the surface
##   Sparkle glints twinkling on and off
##   Shimmer glowing water, gently rippling in brightness
##   Water   still water: its shine fades on tiles out of sight (hex_map.gd sets INSTANCE_CUSTOM.r there)
## The puff shaders need each puff's vertices to carry the puff's centre: UV = (centre.x, centre.z),
## UV2 = (centre.y, height of the whole plume), vertex colour alpha = how far up the plume (0..1).
## They're cheap (a few lines per vertex), and work in MultiMeshes like every other piece.

const PUFF := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform float speed = 0.12;          // trips up the plume per second
uniform float erupt_every = 0.0;     // seconds between eruptions; 0 = a steady plume
uniform float drift = 0.0;           // how far the top of the plume blows sideways
uniform vec2 wind = vec2(0.8, 0.6);
varying float rise;

void vertex() {
	vec3 centre = vec3(UV.x, UV2.x, UV.y);
	float height = UV2.y;
	float t = COLOR.a;
	float base_y = centre.y - t * height;
	float seed = fract(sin(dot(centre.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float nt = fract(t + TIME * speed);
	float h = height;
	float boost = 1.0;
	if (erupt_every > 0.0) {
		float cycle = mod(TIME, erupt_every) / erupt_every;
		float burst = smoothstep(0.0, 0.06, cycle) * (1.0 - smoothstep(0.22, 0.5, cycle));
		h = height * mix(0.32, 1.35, burst);
		boost = mix(0.55, 1.3, burst);
	}
	// puffs grow on the way up, and shrink away at the very top and bottom of each trip
	float size_now = mix(0.45, 1.3, nt) * boost * smoothstep(0.0, 0.15, nt) * (1.0 - smoothstep(0.78, 1.0, nt));
	float size_was = mix(0.45, 1.3, t);
	vec3 local = (VERTEX - centre) * (size_now / size_was);
	float wobble = sin(TIME * 1.3 + seed * 6.28) * 0.015 * nt;
	vec3 blown = vec3(wind.x, 0.0, wind.y) * drift * nt * nt;
	VERTEX = vec3(centre.x + wobble, base_y + nt * h, centre.z - wobble) + blown + local;
	rise = nt;
	COLOR.a = 1.0;
}

void fragment() {
	ALBEDO = COLOR.rgb * mix(1.0, 0.82, rise);
	ROUGHNESS = 1.0;
}
"""

const GLOW := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float speed = 2.0;
uniform float depth = 0.3;          // how much the brightness swings
uniform float ripple = 18.0;        // how fast it changes across the surface
uniform float twinkle = 0.0;        // 1: short bright glints instead of a smooth roll
varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	float wave = sin(TIME * speed + model_pos.x * ripple + model_pos.z * ripple * 0.7 + model_pos.y * 11.0) * 0.5 + 0.5;
	if (twinkle > 0.0) {
		wave = pow(wave, 6.0);
	}
	ALBEDO = COLOR.rgb * (1.0 - depth * 0.5 + depth * wave);
}
"""

const WATER := """
shader_type spatial;
render_mode cull_disabled;

uniform float roughness = 0.45;
uniform float specular = 0.4;
varying float lit;

void vertex() {
	lit = 1.0 - clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);   // the map sets r = 1 on tiles out of sight
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = mix(1.0, roughness, lit);
	SPECULAR = specular * lit;
}
"""

static var _shaders := {}


## An animated material standing in for [param original] (by its name), or null to keep the original.
static func material_for(original: Material) -> Material:
	if original == null:
		return null
	var kind := ""
	var name := original.resource_name.to_lower()
	for candidate: String in ["steam", "geyser", "smoke", "lava", "sparkle", "shimmer", "water"]:
		if name == candidate or name.ends_with(candidate):
			kind = candidate
	if kind == "":
		return null
	var m := ShaderMaterial.new()
	m.resource_name = original.resource_name
	match kind:
		"steam":
			m.shader = _shader("puff", PUFF)
			m.set_shader_parameter("speed", 0.16)
		"geyser":
			m.shader = _shader("puff", PUFF)
			m.set_shader_parameter("speed", 0.35)
			m.set_shader_parameter("erupt_every", 14.0)
		"smoke":
			m.shader = _shader("puff", PUFF)
			m.set_shader_parameter("speed", 0.06)
			m.set_shader_parameter("drift", 0.35)
		"lava":
			m.shader = _shader("glow", GLOW)
			m.set_shader_parameter("speed", 2.4)
			m.set_shader_parameter("depth", 0.55)
		"sparkle":
			m.shader = _shader("glow", GLOW)
			m.set_shader_parameter("speed", 3.0)
			m.set_shader_parameter("depth", 1.4)
			m.set_shader_parameter("ripple", 60.0)
			m.set_shader_parameter("twinkle", 1.0)
		"water":
			m.shader = _shader("water", WATER)
			if original is BaseMaterial3D:
				m.set_shader_parameter("roughness", (original as BaseMaterial3D).roughness)
				m.set_shader_parameter("specular", (original as BaseMaterial3D).metallic_specular)
		"shimmer":
			m.shader = _shader("glow", GLOW)
			m.set_shader_parameter("speed", 1.6)
			m.set_shader_parameter("depth", 0.3)
			m.set_shader_parameter("ripple", 14.0)
	return m


static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var shader := Shader.new()
		shader.code = code
		_shaders[key] = shader
	return _shaders[key]
