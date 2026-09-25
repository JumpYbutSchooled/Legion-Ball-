shader_type spatial;
// Solid stand-in for a weapon blade, used only while an impact frame plays
// (scripts/ui/impact_frames.gd). The real blade (blade_warp.gdshader) is see-through,
// so it never reaches the depth and normal buffers the impact frame shades from; this
// copy has the exact same shape and motion (the vertex code below mirrors blade_warp's)
// and writes them. Never seen itself: the impact frame covers the whole screen.
render_mode cull_disabled, depth_draw_always, shadows_disabled;

uniform float facet_move = 0.018;
uniform float facet_speed = 2.2;
uniform float wave_pos = -1.0;
uniform bool wave_assembling = false;
uniform float break_length = 0.3;
uniform float scatter = 0.3;
uniform float charge_spread = 0.0;
uniform float reload_break = 0.0;
uniform float reload_scatter = 0.35;
uniform float tip_open = 0.0;
uniform float extend = 0.0;

varying flat float broken;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	float seed = hash3(floor(NORMAL * 64.0));
	VERTEX += NORMAL * sin(TIME * facet_speed + seed * 6.2831) * facet_move;
	float ahead = UV.x - wave_pos;
	float past = wave_assembling ? max(ahead, 0.0) : max(-ahead, 0.0);
	broken = wave_pos < 0.0 ? 0.0 : clamp(past / break_length, 0.0, 1.0);
	float drift = broken * broken * scatter * (0.6 + seed * 0.8);
	VERTEX += (NORMAL + vec3(0.0, 0.5, 0.0)) * drift;
	vec3 jitter = vec3(
		sin(TIME * 23.0 + seed * 40.0),
		sin(TIME * 29.0 + seed * 17.0),
		sin(TIME * 19.0 + seed * 31.0)
	);
	float tip_weight = smoothstep(0.2, 1.0, UV.x);
	float spread = charge_spread * tip_weight;
	VERTEX += NORMAL * spread * (0.5 + seed) + jitter * spread * 0.15;
	VERTEX += (NORMAL + vec3(0.0, 0.3, 0.0)) * reload_break * reload_break * reload_scatter * (0.6 + seed * 0.8);
	VERTEX += jitter * reload_break * 0.06;
	float open_w = smoothstep(0.3, 1.0, UV.x);
	vec3 across = vec3(NORMAL.x, NORMAL.y, 0.0);
	if (length(across) > 0.001) {
		VERTEX += normalize(across) * tip_open * open_w;
	}
	VERTEX.z -= extend * tip_weight;
}

void fragment() {
	// Facets that have broken away (faded out on the real blade) don't count.
	if (broken > 0.5) {
		discard;
	}
	ALBEDO = vec3(0.0);
}
