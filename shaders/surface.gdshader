shader_type spatial;
// A plain coloured surface (what map_builder's solid() makes), finished like something
// that was built: MapMerge swaps the maps' plain materials for this when it merges them,
// and bakes each box's face into its vertices (shaders/face.gdshaderinc), so every box
// gets a soft bevel and worn, paler edges, big faces are split into equal panels with
// recessed seams (each a slightly different shade), walls are grimier toward the ground,
// and metal gets rivets. On top of that, the shared world-space detail
// (shaders/detail.gdshaderinc). All of it is off on LOW (surface_detail 0).

#include "res://shaders/detail.gdshaderinc"
#include "res://shaders/face.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.8);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
// 0 built (panels, worn edges)  1 organic (grass, leaves: soft and mottled)  2 metal plate
// 3 bare earth (sand, dirt: drifts and wind ripples, nothing built).
uniform int kind = 0;
void vertex() {
	face_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	face_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	face_tangent = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 0.0)).xyz;
	face_uv = vec4(UV, UV2);
	face_rand = COLOR.r;
}

void fragment() {
	float dist = length(VERTEX);
	vec2 v = surface_variation(face_world_pos, dist);
	vec3 col = albedo * v.x;
	float rough = roughness + v.y;
	vec3 wn = normalize(face_normal);
	if (surface_detail > 0.0 && face_uv.z > 0.0) {
		Face f = face_read(max(length(dFdx(face_uv.xy)), length(dFdy(face_uv.xy))));
		// Every box a touch lighter or darker than its neighbours.
		col *= 0.94 + face_rand * 0.12;
		vec3 tilt = vec3(0.0);
		float grime;
		float height;
		vec2 k = face_edge(f, grime, height);
		vec2 s = sign(f.p);
		tilt += (f.t * s.x * k.x + f.b * s.y * k.y) * 0.7;
		float edge = max(k.x, k.y);
		if (kind == 1) {
			// Leaves and turf: patches of lighter and darker growth, a fine speckle up close.
			float patches = detail_noise(face_world_pos * 0.3 + 31.0);
			float speckle = detail_noise(face_world_pos * 5.0);
			col *= (0.8 + 0.4 * patches) * (0.93 + 0.14 * speckle * (1.0 - smoothstep(20.0, 60.0, dist)));
			// Lighter along the top edges, where the light gets in.
			col *= 1.0 + edge * 0.12;
			rough = 0.96;
		} else if (kind == 3) {
			// Sand and dirt: broad drifts of lighter and darker, wind ripples in patches.
			float near = 1.0 - smoothstep(25.0, 80.0, dist);
			vec2 across = vec2(0.8, 0.6);
			float phase = dot(face_world_pos.xz, across) * 2.3 + detail_noise(face_world_pos * 0.11) * 9.0;
			float rippled = smoothstep(0.3, 0.7, detail_noise(face_world_pos * 0.06 + 70.0)) * near * step(0.7, f.n.y);
			col *= (0.88 + 0.24 * detail_noise(face_world_pos * 0.045 + 9.0)) * (1.0 + 0.035 * sin(phase) * rippled);
			tilt += vec3(across.x, 0.0, across.y) * cos(phase) * 0.14 * rippled;
			rough = 0.97;
		} else {
			vec2 away;
			vec2 id;
			vec2 cell;
			vec2 local;
			float seam = face_panels(f, kind == 0, away, id, cell, local);
			float small = min(cell.x, cell.y);
			vec2 gl = face_groove(seam, clamp(small * 0.007, 0.012, 0.1), clamp(small * 0.04, 0.06, 0.5), f.px);
			float tone = face_hash(id + face_rand * 97.0);
			col *= 0.93 + 0.14 * tone;
			rough += (tone - 0.5) * 0.12;
			col *= 1.0 - gl.x * 0.55;
			rough = mix(rough, 0.95, gl.x);
			// Each panel's edge leans down into the seam.
			tilt -= (f.t * away.x + f.b * away.y) * gl.y * 0.55;
			// Exposed edges are worn pale and smooth, in chips.
			if (edge > 0.02) {
				float chip = detail_noise(face_world_pos * (3.0 / max(face_bevel(f) * 6.0, 1.0)) + face_rand * 13.0);
				float wear = smoothstep(0.45, 1.0, edge * (0.7 + chip * 0.6));
				col = mix(col, col * 1.22 + 0.04, wear * 0.65);
				rough -= wear * 0.2;
			}
			if (kind == 2) {
				// Rivets a little way in from each plate's corners.
				float inset = clamp(small * 0.07, 0.15, 0.8);
				float radius = inset * 0.22;
				vec2 q = min(local, cell - local);
				float rivet = (1.0 - smoothstep(radius, radius + f.px, length(q - vec2(inset)))) * clamp(radius / (f.px * 1.5), 0.0, 1.0);
				col *= 1.0 - rivet * 0.4;
				rough = mix(rough, 0.25, rivet);
			} else {
				// Rain streaks down tall walls.
				float tall = step(abs(f.n.y), 0.5) * smoothstep(6.0, 20.0, f.half_size.y * 2.0);
				if (tall > 0.01) {
					float streak = detail_noise(vec3(dot(face_world_pos, f.t) * 0.9, face_world_pos.y * 0.06, face_rand * 20.0));
					col *= 1.0 - tall * smoothstep(0.55, 0.9, streak) * 0.1 * (0.4 + 0.6 * height);
				}
			}
		}
		// Walls are darker toward the ground (less sky reaches them) and dirtier at the foot.
		col *= mix(0.84, 1.04, smoothstep(0.0, 1.0, height));
		if (grime > 0.01) {
			col *= 1.0 - grime * (0.1 + 0.16 * detail_noise(face_world_pos * 0.5));
		}
		wn = normalize(wn + tilt * surface_detail);
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metallic;
	// Fine bumps, and a glossy clear coat on top (shiny highlights, like an arena's
	// polished surfaces).
	bool soft = kind == 1 || kind == 3;
	NORMAL = (VIEW_MATRIX * vec4(surface_bumped_normal(face_world_pos, wn, dist, soft ? 0.6 : 1.0), 0.0)).xyz;
	CLEARCOAT = (soft ? 0.0 : 0.28) * surface_detail;
	CLEARCOAT_ROUGHNESS = 0.3;
}