shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
// The map "being simulated into existence" (scripts/map_intro.gd): every box drawn as a
// glowing blue wireframe (its edges, plus a faint grid on its faces), cut off above
// `reveal` so the level grows upward out of the floor, with a hot band at the growing edge.

uniform vec3 color : source_color = vec3(0.3, 0.72, 1.0);
uniform float reveal = 0.0;
uniform float intensity = 2.0;
uniform float grid = 4.0;
instance uniform vec3 box_size = vec3(1.0);

varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (world_pos.y > reveal) {
		discard;
	}
	// How far this point is from each pair of faces: on a face one of these is ~0; along
	// an edge two of them are.
	vec3 d = box_size * 0.5 - abs(local_pos);
	vec3 w = fwidth(local_pos) * 1.5 + 0.06;
	vec3 near = 1.0 - smoothstep(vec3(0.0), w, d);
	float edges = clamp(near.x * near.y + near.y * near.z + near.z * near.x, 0.0, 1.0);
	// Faint world grid on the faces.
	vec3 g = abs(fract(world_pos / grid) - 0.5);
	vec3 gw = fwidth(world_pos / grid) * 1.2;
	vec3 lines = smoothstep(0.5 - gw, vec3(0.5), g);
	// Fade the grid out where its lines crowd closer than a pixel or so (glancing walls,
	// far away), or it shimmers.
	float crowd = 1.0 - smoothstep(0.08, 0.25, max(max(gw.x, gw.y), gw.z));
	float mesh = max(max(lines.x, lines.y), lines.z) * 0.22 * crowd;
	// The growing edge burns bright.
	float band = smoothstep(reveal - 3.0, reveal, world_pos.y);
	float a = clamp(edges + mesh + band * 0.35, 0.0, 1.0) + 0.03;
	ALBEDO = color * intensity * a;
}
