shader_type spatial;
// The maps' floors: world-space squares in two shades, so you can see the ball moving
// across them. What the squares are depends on `kind` (map_builder.gd picks it from the
// colours): paving slabs with joints between them, each its own shade and polish; mown
// grass in soft-edged squares; or sand, where the squares barely show under wind ripples.
// A floor slab that MapMerge has merged also gets its own bevelled edge
// (shaders/face.gdshaderinc).

#include "res://shaders/detail.gdshaderinc"
#include "res://shaders/face.gdshaderinc"

uniform vec3 color_a : source_color = vec3(0.20, 0.23, 0.28);
uniform vec3 color_b : source_color = vec3(0.27, 0.31, 0.37);
uniform float cell_size = 2.0;
// 0 paving  1 grass  2 sand.
uniform int kind = 0;

void vertex() {
	face_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	face_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	face_tangent = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 0.0)).xyz;
	face_uv = vec4(UV, UV2);
	face_rand = COLOR.r;
}

void fragment() {
	vec3 wp = face_world_pos;
	vec3 wn = normalize(face_normal);
	vec3 an = abs(wn);
	// The two world axes lying in this face (a floor: x and z).
	vec2 uv = an.y > 0.7 ? wp.xz : (an.x > an.z ? wp.zy : wp.xy);
	vec2 g = uv / cell_size;
	vec2 cell = floor(g);
	float checker = mod(cell.x + cell.y, 2.0);
	float dist = length(VERTEX);
	vec2 v = surface_variation(wp, dist);
	float px = max(length(dFdx(uv)), length(dFdy(uv)));
	float near = 1.0 - smoothstep(25.0, 80.0, dist);
	vec3 col;
	float rough = 0.88;
	float bump = 0.45;
	vec3 tilt = vec3(0.0);
	if (surface_detail <= 0.0) {
		col = mix(color_a, color_b, checker);
	} else if (kind == 1) {
		// Grass: the squares' edges blend into each other; patches and blades of colour.
		vec2 e = abs(fract(g) - 0.5);
		float inside = 1.0 - smoothstep(0.5 - 0.45 / cell_size, 0.5, max(e.x, e.y));
		col = mix((color_a + color_b) * 0.5, mix(color_a, color_b, checker), inside);
		float patches = detail_noise(wp * 0.3 + 40.0);
		float blades = detail_noise(wp * vec3(7.0, 2.0, 7.0));
		col *= (0.84 + 0.3 * patches) * (0.93 + 0.14 * blades * near);
		rough = 0.96;
		bump = 0.8;
	} else if (kind == 2) {
		// Sand: the squares only just show; long ripples, bent by the wind.
		col = mix((color_a + color_b) * 0.5, mix(color_a, color_b, checker), 0.4);
		vec2 across = vec2(0.8, 0.6);
		float bend = detail_noise(wp * 0.11) * 9.0;
		float phase = dot(wp.xz, across) * 2.3 + bend;
		// The ripples come and go in patches (smooth sand between them).
		float rippled = smoothstep(0.3, 0.7, detail_noise(wp * 0.06 + 70.0)) * near;
		col *= 1.0 + 0.035 * sin(phase) * rippled;
		tilt += vec3(across.x, 0.0, across.y) * cos(phase) * 0.14 * rippled * an.y;
		// Drifts: broad lighter and darker sweeps.
		col *= 0.88 + 0.24 * detail_noise(wp * 0.045 + 9.0);
		rough = 0.97;
		bump = 0.7;
	} else {
		// Paving: each slab its own shade and polish, a joint between them.
		col = mix(color_a, color_b, checker);
		col *= 0.94 + 0.12 * face_hash(cell);
		vec2 f = fract(g);
		vec2 e = (0.5 - abs(f - 0.5)) * cell_size;
		vec2 gl = face_groove(min(e.x, e.y), clamp(cell_size * 0.008, 0.02, 0.1), clamp(cell_size * 0.045, 0.08, 0.5), px);
		col *= 1.0 - gl.x * 0.5;
		// The slab's edge leans down into the joint.
		vec2 to_joint = e.x < e.y ? vec2(f.x > 0.5 ? 1.0 : -1.0, 0.0) : vec2(0.0, f.y > 0.5 ? 1.0 : -1.0);
		vec3 dir = an.y > 0.7 ? vec3(to_joint.x, 0.0, to_joint.y) : (an.x > an.z ? vec3(0.0, to_joint.y, to_joint.x) : vec3(to_joint.x, to_joint.y, 0.0));
		tilt += dir * gl.y * 0.4;
		rough = mix(0.7 + 0.16 * face_hash(cell + 7.0), 0.95, gl.x);
		bump = 0.3;
	}
	col *= v.x;
	if (surface_detail > 0.0 && face_uv.z > 0.0) {
		Face fc = face_read(max(length(dFdx(face_uv.xy)), length(dFdy(face_uv.xy))));
		float grime;
		float height;
		vec2 k = face_edge(fc, grime, height);
		vec2 s = sign(fc.p);
		tilt += (fc.t * s.x * k.x + fc.b * s.y * k.y) * 0.6;
		col *= mix(0.86, 1.03, smoothstep(0.0, 1.0, height)) * (1.0 - grime * 0.15);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough + v.y, 0.0, 1.0);
	wn = normalize(wn + tilt * surface_detail);
	NORMAL = (VIEW_MATRIX * vec4(surface_bumped_normal(wp, wn, dist, bump), 0.0)).xyz;
}
