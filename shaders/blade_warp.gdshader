shader_type spatial;
// Clear crystal blade: refracts and warps what's behind it, with a faint tint.
// Every flat facet gets its own brightness and slowly drifts in and out along its
// normal, so the polygons read clearly and shimmer like loose shards.
// UV.x runs along the blade: 0 = back point, 1 = tip.
//
// Driven by the weapon scripts:
// - Enter/exit wave: a glowing wave runs back point -> tip. Exiting, facets behind it
//   break off, drift out and fade; entering, facets ahead of it fly in and join.
//   The blade is grey while this runs, then flashes its colour when equipped.
// - Charge: facets near the tip spread out and jitter, less so toward the back.
// - Reload: every facet is scattered and shaking, recolored by override_color,
//   pulling back together as reload_break falls to 0.
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 color : source_color = vec3(0.3, 0.8, 1.0);
// How strongly the blade bends the view behind it.
uniform float refraction = 0.06;
uniform float warp_amount = 0.008;
uniform float warp_speed = 3.0;
// How much of the tint the see-through body gets.
uniform float tint = 0.14;
uniform float edge_glow = 1.0;
uniform float flow_glow = 0.12;

// Per-facet look and motion.
uniform float facet_variation = 0.35;
uniform float facet_move = 0.018;
uniform float facet_speed = 2.2;

// Enter/exit wave. wave_pos < 0 means no wave: the blade is whole.
uniform float wave_pos = -1.0;
uniform bool wave_assembling = false;
uniform float wave_width = 0.1;
uniform float wave_glow = 4.0;
// How far along the blade (in 0..1 units) a facet takes to fully break away.
uniform float break_length = 0.3;
// How far broken facets drift out.
uniform float scatter = 0.3;

// Grey while switching, and a colour flash once equipped/reloaded.
uniform float grey = 0.0;
uniform vec3 grey_color : source_color = vec3(0.62, 0.62, 0.64);
uniform float flash_amount = 0.0;
uniform vec3 flash_color : source_color = vec3(0.3, 0.8, 1.0);

// Railgun charge and reload.
uniform float charge_spread = 0.0;
uniform float charge_glow = 0.0;
uniform float reload_break = 0.0;
uniform float reload_scatter = 0.35;
uniform float override_amount = 0.0;
uniform vec3 override_color : source_color = vec3(0.65, 0.2, 1.0);

// Tip opening: facets toward the tip splay outward like petals (grapple, gatling shots).
uniform float tip_open = 0.0;
// Stretch: facets slide forward toward the tip, more the nearer the tip (Scatter heat).
uniform float extend = 0.0;

varying vec3 local_pos;
// Flat: the whole triangle shares these, so it acts as one polygon.
varying flat vec3 face_normal;
varying flat float broken;
varying flat float on_wave;
varying flat float tip_weight;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	face_normal = NORMAL;
	float seed = hash3(floor(NORMAL * 64.0));
	// Each facet bobs along its own normal with its own phase.
	VERTEX += NORMAL * sin(TIME * facet_speed + seed * 6.2831) * facet_move;

	// Signed distance from the wave: positive = still ahead of it (toward the tip).
	float ahead = UV.x - wave_pos;
	float past = wave_assembling ? max(ahead, 0.0) : max(-ahead, 0.0);
	broken = wave_pos < 0.0 ? 0.0 : clamp(past / break_length, 0.0, 1.0);
	on_wave = wave_pos < 0.0 ? 0.0 : exp(-(ahead * ahead) / (wave_width * wave_width));
	// Broken facets drift out along their normal and lift a little, each at its own rate.
	float drift = broken * broken * scatter * (0.6 + seed * 0.8);
	VERTEX += (NORMAL + vec3(0.0, 0.5, 0.0)) * drift;

	// Fast per-facet shake, shared by charge and reload.
	vec3 jitter = vec3(
		sin(TIME * 23.0 + seed * 40.0),
		sin(TIME * 29.0 + seed * 17.0),
		sin(TIME * 19.0 + seed * 31.0)
	);
	// Charge: spread strongest at the tip, fading toward the back.
	tip_weight = smoothstep(0.2, 1.0, UV.x);
	float spread = charge_spread * tip_weight;
	VERTEX += NORMAL * spread * (0.5 + seed) + jitter * spread * 0.15;
	// Reload: everything scattered and shaking, settling as reload_break falls.
	VERTEX += (NORMAL + vec3(0.0, 0.3, 0.0)) * reload_break * reload_break * reload_scatter * (0.6 + seed * 0.8);
	VERTEX += jitter * reload_break * 0.06;
	// Tip opening: push the front facets out sideways from the blade's length
	// (the blade runs along -Z in its own space), strongest right at the tip.
	float open_w = smoothstep(0.3, 1.0, UV.x);
	vec3 across = vec3(NORMAL.x, NORMAL.y, 0.0);
	if (length(across) > 0.001) {
		VERTEX += normalize(across) * tip_open * open_w;
	}
	// Stretch: whole facets slide forward, the ones near the tip furthest.
	VERTEX.z -= extend * tip_weight;

	local_pos = VERTEX;
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - facing, 2.5);
	float facet = hash3(floor(face_normal * 64.0));

	vec3 base = mix(color, override_color, override_amount);
	base = mix(base, grey_color, grey);

	// Rippling offset so the view through the blade shimmers.
	vec2 wobble = vec2(
		sin(local_pos.z * 14.0 + TIME * warp_speed * 3.0),
		cos(local_pos.x * 11.0 + local_pos.z * 6.0 - TIME * warp_speed * 2.3)
	);
	vec2 offset = NORMAL.xy * refraction + wobble * warp_amount;
	vec3 behind = texture(screen_tex, SCREEN_UV + offset).rgb;

	// Bands of energy running forward along the blade.
	float flow = smoothstep(0.8, 1.0, sin(-local_pos.z * 7.0 + TIME * 9.0) * 0.5 + 0.5);

	vec3 col = mix(behind, behind * base * 1.8, tint + override_amount * 0.35);
	// Grey while switching: drain the colour out of what's seen through it too.
	col = mix(col, vec3(dot(col, vec3(0.333))), grey * 0.8);
	// Each polygon slightly lighter or darker than its neighbours.
	col *= mix(1.0 - facet_variation, 1.0 + facet_variation, facet);
	col += base * (fresnel * edge_glow + flow * flow_glow);
	// The wave front glows, and breaking facets flare as they go.
	col += base * wave_glow * (on_wave + broken * (1.0 - broken) * 2.0);
	col += base * charge_glow * (0.3 + tip_weight);
	col += flash_color * flash_amount * 12.0;

	ALBEDO = col;
	ALPHA = 1.0 - broken;
}
