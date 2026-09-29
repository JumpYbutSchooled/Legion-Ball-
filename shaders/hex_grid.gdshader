shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;
// Crystal Wall's new look (editing doc: "hexagonal grid texture, and be thin"): glowing
// hex-cell edges over a translucent panel, denser near the edges, clear in each cell.

uniform vec4 base_color : source_color = vec4(0.6, 0.45, 0.35, 0.45);
uniform vec4 edge_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float cell_size : hint_range(0.05, 2.0) = 0.42;
uniform float edge_width : hint_range(0.01, 0.3) = 0.07;
uniform float edge_glow : hint_range(0.0, 4.0) = 1.6;

// Distance from uv to the nearest edge of a hexagon grid cell (pointy-top hexes).
float hex_edge_dist(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = (dot(a, a) < dot(b, b)) ? a : b;
	vec2 p = abs(gv);
	float d = max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
	return h.x - d;
}

void fragment() {
	vec2 cell_uv = UV / cell_size;
	float d = hex_edge_dist(cell_uv);
	float edge = 1.0 - smoothstep(0.0, edge_width, abs(d));
	ALBEDO = mix(base_color.rgb, edge_color.rgb, edge);
	EMISSION = edge_color.rgb * edge * edge_glow;
	ALPHA = mix(base_color.a, 1.0, edge);
}
