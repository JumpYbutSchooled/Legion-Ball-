shader_type spatial;
// World-space panelling for any face (walls, domes, towers): a base colour with thin
// seams every `cell` metres, picked per face from its normal so walls get them too.
// `windows` > 0 turns the cells into lit office windows (city towers): some on, some off,
// flickering very slowly.

uniform vec3 base_color : source_color = vec3(0.3, 0.32, 0.36);
uniform vec3 line_color : source_color = vec3(0.45, 0.5, 0.56);
uniform float cell = 4.0;
uniform float line_width = 0.04;
uniform float line_glow = 0.0;
uniform float windows = 0.0;
uniform vec3 window_color : source_color = vec3(1.0, 0.82, 0.5);
uniform float roughness = 0.8;
uniform float metallic = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	// The two world axes lying in this face.
	vec2 uv = n.y > 0.7 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	vec2 g = uv / cell;
	vec2 f = abs(fract(g) - 0.5);
	vec2 w = fwidth(g) + line_width;
	float seam = max(smoothstep(0.5 - w.x, 0.5, f.x), smoothstep(0.5 - w.y, 0.5, f.y));
	vec3 col = mix(base_color, line_color, seam);
	vec3 glow = line_color * seam * line_glow;
	if (windows > 0.0 && n.y < 0.7) {
		vec2 cell_id = floor(g);
		float lit = step(1.0 - windows, hash(cell_id + floor(TIME * 0.02 + hash(cell_id) * 3.0)));
		// Window pane inside each cell, a frame of wall round it.
		float pane = step(max(f.x, f.y * 1.3), 0.34);
		col = mix(col, vec3(0.05, 0.07, 0.1), pane);
		glow += window_color * pane * lit * 1.6;
	}
	ALBEDO = col;
	EMISSION = glow;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
