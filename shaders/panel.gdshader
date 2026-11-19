shader_type spatial;
// World-space panelling for any face (walls, domes, towers): a base colour with seams
// every `cell` metres, picked per face from its normal so walls get them too. The seams
// are recessed (each panel's edge leans into them and catches the light) and every panel
// is a slightly different shade. `windows` > 0 turns the cells into lit office windows
// (city towers): some on, some off, flickering very slowly.
// A box that MapMerge has merged also gets its own bevelled, worn edges and grime at the
// foot of its walls (shaders/face.gdshaderinc).

#include "res://shaders/detail.gdshaderinc"
#include "res://shaders/face.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.3, 0.32, 0.36);
uniform vec3 line_color : source_color = vec3(0.45, 0.5, 0.56);
uniform float cell = 4.0;
uniform float line_width = 0.04;
uniform float line_glow = 0.0;
uniform float windows = 0.0;
uniform vec3 window_color : source_color = vec3(1.0, 0.82, 0.5);
uniform float roughness = 0.8;
uniform float metallic = 0.0;
// 1 = masonry: on walls the cells become blocks twice as long as they're tall, every other
// course shifted half a block (a running bond), instead of a square grid.
uniform float bond = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void vertex() {
	face_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	face_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	face_tangent = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 0.0)).xyz;
	face_uv = vec4(UV, UV2);
	face_rand = COLOR.r;
}

void fragment() {
	vec3 world_pos = face_world_pos;
	vec3 wn = normalize(face_normal);
	vec3 n = abs(wn);
	// The two world axes lying in this face.
	vec2 uv = n.y > 0.7 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	vec2 g = uv / cell;
	vec2 cell2 = vec2(cell);
	if (bond > 0.5 && n.y < 0.7) {
		cell2.x = cell * 2.0;
		g.x = g.x * 0.5 + 0.5 * mod(floor(g.y), 2.0);
	}
	vec2 fr = fract(g);
	vec2 f = abs(fr - 0.5);
	vec2 w = fwidth(g) + line_width;
	float seam = max(smoothstep(0.5 - w.x, 0.5, f.x), smoothstep(0.5 - w.y, 0.5, f.y));
	float dist = length(VERTEX);
	vec2 v = surface_variation(world_pos, dist);
	vec2 cell_id = floor(g);
	vec3 base = base_color * v.x;
	vec3 tilt = vec3(0.0);
	float rough = roughness;
	if (surface_detail > 0.0) {
		base *= 0.94 + 0.12 * face_hash(cell_id);
		// Each panel's edge leans into its seam (only where the seams are wide enough to see).
		float px = max(length(dFdx(uv)), length(dFdy(uv)));
		vec2 e = (0.5 - f) * cell2;
		float lip = (1.0 - smoothstep(0.0, 0.12, min(e.x, e.y))) * clamp(0.12 / (px * 1.5), 0.0, 1.0) * (1.0 - seam);
		vec2 to_seam = e.x < e.y ? vec2(fr.x > 0.5 ? 1.0 : -1.0, 0.0) : vec2(0.0, fr.y > 0.5 ? 1.0 : -1.0);
		vec3 dir = n.y > 0.7 ? vec3(to_seam.x, 0.0, to_seam.y) : (n.x > n.z ? vec3(0.0, to_seam.y, to_seam.x) : vec3(to_seam.x, to_seam.y, 0.0));
		tilt += dir * lip * 0.4;
	}
	vec3 col = mix(base, line_color, seam);
	vec3 glow = line_color * seam * line_glow;
	if (windows > 0.0 && n.y < 0.7) {
		float lit = step(1.0 - windows, hash(cell_id + floor(TIME * 0.02 + hash(cell_id) * 3.0)));
		// Window pane inside each cell, a frame of wall round it.
		float pane = step(max(f.x, f.y * 1.3), 0.34);
		col = mix(col, vec3(0.05, 0.07, 0.1), pane);
		glow += window_color * pane * lit * 1.6;
		// Glass: dark panes are mirror-smooth.
		rough = mix(rough, 0.12, pane);
	}
	if (surface_detail > 0.0 && face_uv.z > 0.0) {
		Face fc = face_read(max(length(dFdx(face_uv.xy)), length(dFdy(face_uv.xy))));
		float grime;
		float height;
		vec2 k = face_edge(fc, grime, height);
		vec2 s = sign(fc.p);
		tilt += (fc.t * s.x * k.x + fc.b * s.y * k.y) * 0.7;
		// (Glowing grids are light themselves: no wear, ground shade or dirt on those.)
		if (line_glow < 0.001) {
			float edge = max(k.x, k.y);
			if (edge > 0.02) {
				float chip = detail_noise(world_pos * (3.0 / max(face_bevel(fc) * 6.0, 1.0)) + face_rand * 13.0);
				float wear = smoothstep(0.45, 1.0, edge * (0.7 + chip * 0.6));
				col = mix(col, col * 1.22 + 0.04, wear * 0.65);
				rough -= wear * 0.2;
			}
			col *= mix(0.84, 1.04, smoothstep(0.0, 1.0, height));
			if (grime > 0.01) {
				col *= 1.0 - grime * (0.1 + 0.16 * detail_noise(world_pos * 0.5));
			}
		}
	}
	ALBEDO = col;
	EMISSION = glow;
	ROUGHNESS = clamp(rough + v.y, 0.04, 1.0);
	METALLIC = metallic;
	wn = normalize(wn + tilt * surface_detail);
	NORMAL = (VIEW_MATRIX * vec4(surface_bumped_normal(world_pos, wn, dist, 0.7), 0.0)).xyz;
	CLEARCOAT = 0.35 * surface_detail;
	CLEARCOAT_ROUGHNESS = 0.2;
}
