shader_type spatial;
// Water (map_builder.gd water()): moats, canals, lakes, the sea. A flat box whose top is
// drawn as moving water: two layers of ripples drifting across each other tilt the surface,
// so the sky and the sun break up on it; deeper colour looking straight down, lighter and
// more mirror-like at a glancing angle; foam where it meets its own edges (the banks), from
// the box's face data (shaders/face.gdshaderinc). It glows faintly, so it still reads as
// water at night and in shade. On LOW it's a flat glossy colour.

#include "res://shaders/detail.gdshaderinc"
#include "res://shaders/face.gdshaderinc"

uniform vec3 color : source_color = vec3(0.12, 0.38, 0.6);
uniform float glow = 0.12;
// How choppy: 1 a pond, 2 open sea.
uniform float chop = 1.0;

void vertex() {
	face_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	face_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	face_tangent = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 0.0)).xyz;
	face_uv = vec4(UV, UV2);
	face_rand = COLOR.r;
}

float water_height(vec2 p, float t) {
	float a = detail_noise(vec3(p * 0.22 + vec2(t * 0.16, t * 0.07), t * 0.11));
	float b = detail_noise(vec3(p * 0.63 - vec2(t * 0.13, t * 0.21), t * 0.17 + 5.0));
	return a * 0.65 + b * 0.35;
}

void fragment() {
	vec3 wp = face_world_pos;
	vec3 wn = normalize(face_normal);
	float dist = length(VERTEX);
	vec3 col = color;
	float rough = 0.1;
	vec3 emit = color * glow;
	if (surface_detail > 0.0 && wn.y > 0.7) {
		float t = TIME;
		float near = 1.0 - smoothstep(60.0, 260.0, dist);
		float e = 0.35;
		float h = water_height(wp.xz, t);
		vec2 slope = vec2(water_height(wp.xz + vec2(e, 0.0), t) - h, water_height(wp.xz + vec2(0.0, e), t) - h) / e;
		wn = normalize(vec3(-slope.x, 1.0, -slope.y) * vec3(chop * 0.55 * (0.35 + 0.65 * near), 1.0, chop * 0.55 * (0.35 + 0.65 * near)));
		// Deeper looking straight down, paler toward the horizon; crests catch the light.
		float facing = clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0);
		col = mix(color * 1.25 + 0.05, color * 0.55, facing);
		col += vec3(0.25, 0.3, 0.3) * smoothstep(0.62, 0.9, h) * 0.35 * near;
		if (face_uv.z > 0.0) {
			// Foam against the banks: a ragged white line that breathes in and out.
			vec2 to_edge = face_uv.zw - abs(face_uv.xy);
			float bank = min(to_edge.x, to_edge.y);
			float reach = 0.5 + 0.9 * detail_noise(vec3(wp.xz * 0.5, t * 0.3)) + 0.25 * sin(t * 0.8 + wp.x * 0.3 + wp.z * 0.2);
			float foam = (1.0 - smoothstep(reach * 0.5, reach, bank)) * smoothstep(0.35, 0.65, detail_noise(vec3(wp.xz * 2.2, t * 0.5)) + 0.25);
			col = mix(col, vec3(0.92, 0.96, 0.98), foam * 0.85);
			rough = mix(rough, 0.7, foam);
			emit *= 1.0 - foam;
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.75;
	EMISSION = emit;
	NORMAL = (VIEW_MATRIX * vec4(wn, 0.0)).xyz;
}
