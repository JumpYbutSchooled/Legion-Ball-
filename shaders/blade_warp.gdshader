shader_type spatial;
// Energy blade: clear glass in the middle (it bends what's behind it, barely tinted),
// with the colour gathered at the outer edges: a bright rim and a glowing hex pattern
// along them, the facets showing only out there, and everything stronger toward the
// tip. Each flat facet still drifts in and out along its normal like a loose shard.
// UV2 (energy_blade_mesh.gd): x = metres along the blade, y = across its width (-1..1).
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

#include "res://shaders/warp.gdshaderinc"

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

// The look: how far in from the edges the colour reaches, the hex cells' size (m),
// and how much stronger the tip is than the back.
uniform float edge_reach = 0.3;
uniform float hex_size = 0.085;
uniform float tip_boost = 1.1;
// Ribbon style (unused now; was the shared blade model): a clear glass body whose outline glows
// softly (border_width metres in from the edge) with a thin white-hot rim, and raised 3D
// polygon tiles floating along its edges (marked by UV.y = 1; UV2 = their own random value,
// how far out from their middle), each a clear lens bending what's behind it its own way,
// outlined in the weapon's colour.
uniform bool ribbon_style = false;
uniform float chevron_period = 0.06;
uniform float border_width = 0.07;

// Animations every weapon shares (simple_weapon.gd):
// - fire_pulse: a discharge racing from the back point to the tip (0..1, < 0 = none),
//   facets popping out as it passes; fire_glow: the flare after a shot, fading.
// - recharge: how full the blade is again after firing (1 = ready): past the fill line
//   it's drained and dim, with a bright front where it's refilling.
// - use_amount: held / in use: the energy flows faster and brighter and it hums.
uniform float fire_pulse = -1.0;
uniform float fire_glow = 0.0;
uniform float recharge = 1.0;
uniform float use_amount = 0.0;

varying vec3 local_pos;
// Ribbon style: where this is on the blade's own flat plane (metres), for its polygons.
varying vec2 plane_uv;
varying vec2 blade_uv;
// Where this point sits on the blade before any animation moves it (the cells stick to it).
varying vec3 rest_pos;
// How wide the blade is here (metres): a sheet, or a thin prong.
varying float part_width;
// Flat: the whole triangle shares these, so it acts as one polygon.
varying flat vec3 face_normal;
varying flat float broken;
varying flat float on_wave;
varying flat float tip_weight;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	blade_uv = UV2;
	plane_uv = CUSTOM1.xy;
	rest_pos = VERTEX;
	// The triangle's own flat normal (energy_blade_mesh.gd stores it in CUSTOM0; NORMAL is
	// smoothed for the glass), so facets still move as whole polygons.
	vec3 fn = length(CUSTOM0.xyz) > 0.5 ? CUSTOM0.xyz : NORMAL;
	face_normal = fn;
	part_width = CUSTOM0.a;
	float seed = hash3(floor(fn * 64.0));
	// Each facet bobs along its own normal with its own phase.
	VERTEX += fn * sin(TIME * facet_speed + seed * 6.2831) * facet_move;

	// Signed distance from the wave: positive = still ahead of it (toward the tip).
	float ahead = UV.x - wave_pos;
	float past = wave_assembling ? max(ahead, 0.0) : max(-ahead, 0.0);
	broken = wave_pos < 0.0 ? 0.0 : clamp(past / break_length, 0.0, 1.0);
	on_wave = wave_pos < 0.0 ? 0.0 : exp(-(ahead * ahead) / (wave_width * wave_width));
	// Broken facets drift out along their normal and lift a little, each at its own rate.
	float drift = broken * broken * scatter * (0.6 + seed * 0.8);
	VERTEX += (fn + vec3(0.0, 0.5, 0.0)) * drift;

	// Fast per-facet shake, shared by charge and reload.
	vec3 jitter = vec3(
		sin(TIME * 23.0 + seed * 40.0),
		sin(TIME * 29.0 + seed * 17.0),
		sin(TIME * 19.0 + seed * 31.0)
	);
	// Charge: spread strongest at the tip, fading toward the back.
	tip_weight = smoothstep(0.2, 1.0, UV.x);
	float spread = charge_spread * tip_weight;
	VERTEX += fn * spread * (0.5 + seed) + jitter * spread * 0.15;
	// Reload: everything scattered and shaking, settling as reload_break falls.
	VERTEX += (fn + vec3(0.0, 0.3, 0.0)) * reload_break * reload_break * reload_scatter * (0.6 + seed * 0.8);
	VERTEX += jitter * reload_break * 0.06;
	// Tip opening: push the front facets out sideways from the blade's length
	// (the blade runs along -Z in its own space), strongest right at the tip.
	float open_w = smoothstep(0.3, 1.0, UV.x);
	vec3 across = vec3(fn.x, fn.y, 0.0);
	if (length(across) > 0.001) {
		VERTEX += normalize(across) * tip_open * open_w;
	}
	// Stretch: whole facets slide forward, the ones near the tip furthest.
	VERTEX.z -= extend * tip_weight;
	// Firing: facets pop outward as the discharge passes them.
	if (fire_pulse >= 0.0) {
		float d = UV.x - fire_pulse;
		VERTEX += fn * exp(-(d * d) / 0.012) * 0.06;
	}
	// In use: a fine hum.
	VERTEX += jitter * use_amount * 0.008;

	local_pos = VERTEX;
}

vec3 cell_hash(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// The blade's cells: a 3D Voronoi pattern on loosely jittered points, so wherever the
// blade's surface cuts through it the cells come out as hexagons and pentagons (mostly),
// the same size everywhere and never stretched. x: distance to the nearest cell border,
// y: a random value for this cell.
vec2 blade_cells(vec3 x) {
	vec3 n = floor(x);
	vec3 f = fract(x);
	vec3 mg = vec3(0.0);
	vec3 mr = vec3(0.0);
	float md = 8.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 g = vec3(float(i), float(j), float(k));
				vec3 r = g + cell_hash(n + g) * 0.65 + 0.175 - f;
				float d = dot(r, r);
				if (d < md) {
					md = d;
					mr = r;
					mg = g;
				}
			}
		}
	}
	md = 8.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 g = mg + vec3(float(i), float(j), float(k));
				vec3 r = g + cell_hash(n + g) * 0.65 + 0.175 - f;
				if (dot(mr - r, mr - r) > 0.00001) {
					md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
				}
			}
		}
	}
	return vec2(md, cell_hash(n + mg).x);
}

// (Unused since the cells; kept for reference.) Distance to the nearest hex cell edge.
float hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, vec2(0.5, 0.8660254)), q.x);
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - facing, 2.5);
	float facet = hash3(floor(face_normal * 64.0));

	vec3 base = mix(color, override_color, override_amount);
	base = mix(base, grey_color, grey);

	// Where the colour lives: the outer edges of the blade's width, and its silhouette.
	float across = abs(blade_uv.y);
	// (The silhouette only right at the very edge, or wide angled sheets glow all over.)
	float outer = max(smoothstep(1.0 - edge_reach, 1.0, across), smoothstep(0.6, 0.97, 1.0 - facing) * 0.75);
	// Ribbon style: how far in from the panel's edge this is (metres), and the outline band.
	float edge_d = (1.0 - across) * part_width * 0.5;
	float rim_band = 0.0;
	if (ribbon_style) {
		float aa = fwidth(edge_d) + 0.003;
		outer = 1.0 - smoothstep(0.0, border_width + aa, edge_d);
		outer *= outer;
		rim_band = 1.0 - smoothstep(0.006, 0.006 + aa * 1.5, edge_d);
	}
	// ...and how strong it is along the blade: faint at the back, bright at the tip.
	float tipw = mix(0.35, 0.35 + tip_boost, pow(clamp(UV.x, 0.0, 1.0), 1.4));
	if (ribbon_style) {
		tipw = mix(0.85, 1.35, smoothstep(0.4, 1.0, UV.x));
	}

	// The cells: hexagons and pentagons worked out in 3D on the blade itself, so they're
	// never stretched. Glowing seams between them; each cell its own plate of glass.
	vec2 cell = blade_cells(rest_pos / hex_size);
	float hw = fwidth(cell.x) * 1.2 + 0.03;
	float hex = 1.0 - smoothstep(0.0, hw, cell.x);
	float plate = cell.y;
	vec2 lens = vec2(0.0);
	if (ribbon_style) {
		// The middle: perfect hexagons and pentagons on a honeycomb laid in the blade's own
		// flat plane (so never stretched), with clear gaps between them. Each is a lens bending
		// the view its own way, drawn by its coloured outline. (The edge polygons are real tiles.)
		vec2 q = plane_uv / hex_size;
		vec2 sz = vec2(1.0, 1.7320508);
		vec2 ha = mod(q, sz) - sz * 0.5;
		vec2 hb = mod(q - sz * 0.5, sz) - sz * 0.5;
		vec2 g = dot(ha, ha) < dot(hb, hb) ? ha : hb;
		float rnd = hash3(vec3(q - g, 3.7));
		float sides = rnd < 0.25 ? 5.0 : 6.0;
		if (sides < 5.5) {
			float sp = rnd * 25.0;
			g = mat2(vec2(cos(sp), sin(sp)), vec2(-sin(sp), cos(sp))) * g;
		}
		float an = PI / sides;
		float bn = mod(atan(g.x, g.y) + 8.0 * PI, 2.0 * an) - an;
		float sd = length(g) * cos(bn) - 0.4 * cos(an);
		float aa = fwidth(sd) * 1.5 + 0.004;
		hex = (1.0 - smoothstep(0.012, 0.012 + aa, abs(sd))) * (1.0 - outer);
		bool inside = sd < 0.0;
		plate = inside ? rnd : 0.5;
		lens = inside ? g * 2.0 : vec2(0.0);
	}

	bool tile = ribbon_style && UV.y > 0.5;
	float tile_rim = clamp(blade_uv.y, 0.0, 1.0);
	if (tile) {
		plate = blade_uv.x;
		outer = 0.0;
	}
	// Clear glass: the view behind, bent (more through the middle, and each plate its own
	// way), barely tinted.
	vec2 wobble = vec2(
		sin(local_pos.z * 14.0 + TIME * warp_speed * 3.0),
		cos(local_pos.x * 11.0 + local_pos.z * 6.0 - TIME * warp_speed * 2.3)
	);
	vec2 offset = NORMAL.xy * refraction * (1.2 - outer * 0.5) + wobble * warp_amount
		+ (vec2(plate, fract(plate * 7.31)) - 0.5) * refraction * (ribbon_style ? 1.4 : 0.35) + lens * refraction;
	vec3 behind = warp_sample(screen_tex, SCREEN_UV, warp_aspect(offset, VIEWPORT_SIZE) * 1.4);


	// Energy flowing toward the tip (faster and brighter while in use).
	float flow = smoothstep(0.8, 1.0, sin(-local_pos.z * 7.0 + TIME * (9.0 + use_amount * 14.0)) * 0.5 + 0.5);

	vec3 col = mix(behind, behind * base * 1.6, tint * 0.25 + outer * 0.3 + override_amount * 0.35);
	// Out at the edges the glass itself is coloured (saturated, not see-through white).
	col = mix(col, base * 0.5, outer * 0.35);
	if (ribbon_style) {
		// The panel itself: clear, barely tinted; the outline band coloured glass.
		col = behind * mix(vec3(1.0), base, 0.06);
		col = mix(col, behind * base * 0.6 + base * 0.15, outer * 0.8);
	}
	if (tile) {
		// A floating tile: clear glass (its own bend, above), only its outline coloured.
		rim_band = 0.0;
		col = behind * mix(vec3(1.0), base, 0.12);
	}
	col = mix(col, vec3(dot(col, vec3(0.333))), grey * 0.8);
	// Every cell a slightly different plate (more so out at the edges).
	col *= mix(1.0 - facet_variation * (0.35 + outer * 0.5), 1.0 + facet_variation * (0.35 + outer * 0.5), plate);
	// The glow: rim, hex lines and flow, gathered at the edges and the tip (bright enough
	// to bloom).
	// The very rim: a thin white-hot line.
	float rim_line = ribbon_style ? rim_band : smoothstep(0.86, 1.0, across);
	// Thin prongs are all edge: they glow as softer coloured streaks, not white-hot.
	float sheet = ribbon_style ? 1.0 : smoothstep(0.05, 0.3, part_width);
	float glow = outer * edge_glow * 2.2 + fresnel * 0.7 + hex * (0.16 + outer * 2.6) + flow * flow_glow * (0.3 + outer * 3.0);
	if (ribbon_style) {
		glow = outer * edge_glow * 0.55 + hex * 0.5 + flow * flow_glow * outer * 1.5;
		if (tile) {
			float line = smoothstep(0.74, 0.97, tile_rim);
			glow = line * (1.0 + 0.5 * blade_uv.x) + flow * flow_glow * line * 2.0;
		}
	}
	glow *= tipw * (1.0 + use_amount * 0.6) * mix(0.45, 1.0, sheet);
	col += base * min(glow, 3.2);
	col += mix(base, vec3(1.0), 0.55) * rim_line * (ribbon_style ? 1.5 : 1.6) * min(tipw, 1.4) * sheet;
	if (tile) {
		// The outline's core runs white-hot on the edge row, more so toward the spike's point.
		col += mix(base, vec3(1.0), 0.7) * smoothstep(0.9, 1.0, tile_rim) * smoothstep(0.6, 0.95, blade_uv.x) * (0.4 + 0.6 * smoothstep(0.5, 1.0, UV.x));
	}
	// The wave front glows, and breaking facets flare as they go.
	col += base * wave_glow * (on_wave + broken * (1.0 - broken) * 2.0);
	col += base * charge_glow * (0.3 + tip_weight) * (0.4 + outer);
	// Firing: the discharge band racing to the tip, then the flare fading.
	if (fire_pulse >= 0.0) {
		float d = UV.x - fire_pulse;
		col += base * exp(-(d * d) / 0.006) * 5.0 * (0.5 + outer);
	}
	col += base * fire_glow * 1.6 * tipw * (0.3 + outer);
	// Recharging: past the fill line the blade is drained (just glass and a faint edge),
	// with a bright front where it's filling back up.
	if (recharge < 1.0) {
		float drained = smoothstep(recharge - 0.02, recharge + 0.04, UV.x);
		col = mix(col, behind * 0.85 + base * outer * 0.2, drained * 0.85);
		float f = UV.x - recharge;
		col += base * exp(-(f * f) / 0.002) * 3.0 * (0.4 + outer);
	}
	col += flash_color * flash_amount * 12.0;

	ALBEDO = col;
	ALPHA = 1.0 - broken;
}