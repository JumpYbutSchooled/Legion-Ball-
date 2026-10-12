shader_type spatial;
// The weapons' pentagons (scripts/weapons/pentagon_skin.gd): each weapon's own blades
// (energy_blade_mesh.gd) drawn as flat pentagons spread over their surface, all pointing
// along the blade, a left blade the mirror image of its right. They're frosted, tinted glass that filters and bends what's behind it (more so
// further in), with faint seams, and the blade's outline glowing and blooming in its colour.
// Each drifts and sways a little on its own.
// Per vertex (pentagon_skin.gd): UV = (along the blade 0 back .. 1 point, near the outline
// 1 .. 0 in the middle); UV2 = (0 at its middle .. 1 at its rim, which blade: 0, each blade
// has its own material); CUSTOM0 =
// the pentagon's centre and size; CUSTOM1 = its normal (off the shell) and its own random
// value (shared by its mirror images).
//
// Driven by blade_weapon.gd (and the same names the other blade shaders take):
// - Firing (blade_pulse_a / _b, one pair per blade): a wave rolls down the blade that fired,
//   from the back to the point, each pentagon riding round a circle as it passes (out off
//   the shell, back, in, forward to rest), swelling and glowing; fire_glow is the flare after.
// - Equip (wave_pos, wave_assembling): a wave runs back to point gathering the pentagons in
//   from scattered; each overshoots home and springs back.
// - Put away: every pentagon breaks away from the others at once, each flashing and fading
//   out on its own.
// - Switching (switching): the old weapon's pentagons scatter into a cloud for the first part
//   of the time, the new weapon's cloud fades in as the old one fades out, then gathers with
//   the equip wave, so nothing vanishes in between.
// - recharge, charge_spread / charge_glow, reload_break (+ override_colour), tip_open,
//   extend, use_amount, grey, flash: as the other blade shaders.
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 color : source_color = vec3(0.3, 0.8, 1.0);
// How strongly the clear pentagons bend the view behind them (the inner ones most).
uniform float refraction = 0.05;
// How frosted the glass is (pixels of softening).
uniform float frost = 2.5;
// How far each pentagon drifts on its own (metres, for a full-size one), and how fast.
uniform float drift = 0.014;
uniform float drift_speed = 1.0;

uniform float wave_pos = -1.0;
uniform bool wave_assembling = false;
uniform bool switching = false;
uniform float wave_glow = 2.5;
// How much of the blade (0..1) a pentagon takes to fly home once the equip wave reaches it.
uniform float break_length = 0.4;
// How far the pentagons overshoot home before springing back.
uniform float bounce = 2.2;

uniform float grey = 0.0;
uniform vec3 grey_color : source_color = vec3(0.62, 0.62, 0.64);
uniform float flash_amount = 0.0;
uniform vec3 flash_color : source_color = vec3(0.3, 0.8, 1.0);
uniform float charge_spread = 0.0;
uniform float charge_glow = 0.0;
uniform float reload_break = 0.0;
uniform float override_amount = 0.0;
uniform vec3 override_color : source_color = vec3(0.65, 0.2, 1.0);
uniform float tip_open = 0.0;
uniform float extend = 0.0;
uniform float blade_pulse_a[6];
uniform float blade_pulse_b[6];
// How much of the blade's length a pentagon takes to ride round its circle as a fire wave
// passes, and the circle's size (metres, for a full-size pentagon).
uniform float pulse_span = 0.5;
uniform float pulse_radius = 0.14;
uniform float fire_glow = 0.0;
uniform float recharge = 1.0;
uniform float use_amount = 0.0;

// blade_weapon.gd's WAVE_END, and how much of a switch is the old weapon scattering.
const float WAVE_END = 1.4;
const float SWITCH_SPLIT = 0.4;

varying float v_u;
varying float v_edge;
varying float v_rim;
varying flat float v_seed;
varying float v_push;
varying float v_alpha;
varying float v_flash;
varying float v_front;
varying float v_tipw;

// `v` turned `a` radians about the unit axis `k`.
vec3 turn(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

// A fire wave at `pulse` (0 back .. past 1, < 0 none): how far round its circle the
// pentagon at `u` is (0..1; 0 / 1 = at rest).
float wave_phase(float pulse, float u) {
	return pulse < 0.0 ? 0.0 : clamp((pulse - u) / pulse_span, 0.0, 1.0);
}

void vertex() {
	vec3 c = CUSTOM0.xyz;
	float size = CUSTOM0.w;
	vec3 bn = normalize(CUSTOM1.xyz);
	float seed = CUSTOM1.w;
	float u = UV.x;
	int blade = clamp(int(UV2.y + 0.5), 0, 5);
	v_u = u;
	v_edge = UV.y;
	v_rim = UV2.x;
	v_seed = seed;
	vec3 rel = VERTEX - c;
	// Out from the ball's forward axis, where this pentagon is.
	vec3 away = normalize(vec3(c.xy, 0.0) + vec3(0.0001, 0.0, 0.0));
	float k = clamp(size / 0.05, 0.3, 1.2);
	float t = TIME * drift_speed;

	// Its own drift: bobbing off the shell on a slow swell that runs along the blade, and
	// swaying sideways on its own timing (mirror images move as mirror images).
	vec3 side_dir = normalize(cross(bn, vec3(0.0, 0.0, 1.0)) + vec3(0.0, 0.0001, 0.0));
	vec3 off = bn * sin(t * 1.6 - u * 7.0 + seed * 2.5) * drift * k;
	off += side_dir * sin(t * 1.15 + seed * 6.283 + u * 3.0) * drift * 0.7 * k;
	off += vec3(0.0, 0.0, 1.0) * sin(t * 0.9 + seed * 4.0) * drift * 0.5 * k;

	// Fired: each pentagon on the blade that fired rides the wave round a circle (out off the
	// shell, back, in, and forward to rest) as it rolls from the back of the blade to the point.
	vec3 roll = vec3(0.0);
	float push = 0.0;
	for (int w = 0; w < 2; w++) {
		float ph = wave_phase(w == 0 ? blade_pulse_a[blade] : blade_pulse_b[blade], u);
		float ang = ph * TAU;
		roll += (bn * sin(ang) + vec3(0.0, 0.0, 1.0) * (1.0 - cos(ang)) * 0.5) * pulse_radius * k;
		push = max(push, sin(ph * PI));
	}
	v_push = push;
	off += roll;
	rel *= 1.0 + push * 0.35;

	// Equip / put away / switch: how scattered it is (0 home .. 1 scattered; past 1 flies
	// further, below 0 is the overshoot past home), how visible, and its own flash.
	float s = 0.0;
	float alpha = 1.0;
	float flash = 0.0;
	float front = 0.0;
	if (wave_pos >= 0.0) {
		float q = clamp(wave_pos / WAVE_END, 0.0, 1.0);
		if (wave_assembling) {
			float w = wave_pos;
			if (switching) {
				// Waits, unseen, while the old weapon scatters into the very same places.
				w = q < SWITCH_SPLIT ? -1.0 : (q - SWITCH_SPLIT) / (1.0 - SWITCH_SPLIT) * WAVE_END;
			}
			// Fades in, still scattered, as the old weapon's cloud fades out (weapons differ in
			// shape, so their clouds cross over rather than match exactly).
			float fade_in = switching ? smoothstep(SWITCH_SPLIT - 0.05, SWITCH_SPLIT + 0.08, q) : 1.0;
			if (w < 0.0) {
				s = 1.0;
				alpha = fade_in;
			} else {
				float home = clamp((w - u) / break_length, 0.0, 1.0);
				// Ease out with an overshoot: past home, then springs back.
				float m = home - 1.0;
				float arrive = 1.0 + (bounce + 1.0) * m * m * m + bounce * m * m;
				s = 1.0 - arrive;
				alpha = switching ? fade_in : smoothstep(0.0, 0.3, home);
				front = exp(-((w - u) * (w - u)) / 0.012);
			}
		} else if (switching) {
			// Breaks away with the others, all at once (each a beat apart), then hands over.
			float a = clamp((clamp(q / SWITCH_SPLIT, 0.0, 1.0) - seed * 0.3) / 0.7, 0.0, 1.0);
			s = a * a * (3.0 - 2.0 * a);
			alpha = 1.0 - smoothstep(SWITCH_SPLIT - 0.08, SWITCH_SPLIT + 0.05, q);
		} else {
			// Put away: flies off from the others, flashing and fading out on its own.
			float a = clamp((q - seed * 0.4) / 0.6, 0.0, 1.0);
			s = a * a * 1.7;
			flash = exp(-((a - 0.15) * (a - 0.15)) / 0.006) * step(0.001, a);
			alpha = 1.0 - smoothstep(0.3, 0.9, a);
		}
	}
	v_alpha = alpha;
	v_flash = flash;
	v_front = front * alpha;
	// Scattered: lifted off and out round the ball, turned, a little smaller (still easy to
	// see, so a switch reads as the same cloud of pentagons reforming).
	off += (bn * 0.7 + away * 0.45 + vec3(0.0, 0.12, 0.2)) * (0.3 + seed * 0.25) * s;
	rel = turn(rel, bn, s * (seed - 0.5) * 3.0) * (1.0 - 0.3 * clamp(s, 0.0, 1.0));

	// Charge, reload, tip opening, stretch, the hum while in use.
	float tipw = smoothstep(0.2, 1.0, u);
	v_tipw = tipw;
	vec3 jitter = vec3(sin(TIME * 23.0 + seed * 40.0), sin(TIME * 29.0 + seed * 17.0), sin(TIME * 19.0 + seed * 31.0));
	off += (bn + away * 0.5) * charge_spread * tipw + jitter * charge_spread * tipw * 0.08;
	off += (bn * 0.8 + away * 0.5) * reload_break * reload_break * 0.3;
	off += jitter * reload_break * 0.03;
	off += away * tip_open * smoothstep(0.3, 1.0, u);
	off.z -= extend * tipw;
	off += jitter * use_amount * 0.004;

	VERTEX = c + rel + off;
}
void fragment() {
	vec3 base = mix(color, override_color, override_amount);
	base = mix(base, grey_color, grey);
	float e = v_edge;
	float inner = 1.0 - e;
	// The view behind, bent by the glass (more further in) and frosted: a few taps round the
	// bent spot. One plain sample per tap, no colour split, so there's no rainbow fringe.
	vec2 o = NORMAL.xy * (0.5 + inner * 1.3) * refraction * vec2(VIEWPORT_SIZE.y / max(VIEWPORT_SIZE.x, 1.0), 1.0);
	vec2 px = frost / VIEWPORT_SIZE;
	vec3 behind = (texture(screen_tex, SCREEN_UV + o + vec2(px.x, px.y)).rgb
		+ texture(screen_tex, SCREEN_UV + o + vec2(-px.x, px.y * 0.4)).rgb
		+ texture(screen_tex, SCREEN_UV + o + vec2(px.x * 0.4, -px.y)).rgb
		+ texture(screen_tex, SCREEN_UV + o + vec2(-px.x * 0.6, -px.y * 0.6)).rgb) * 0.25;
	float outline = smoothstep(0.7, 0.96, v_rim);
	float facing = abs(dot(NORMAL, VIEW));

	// Tinted glass filtering the view (deeper toward the edge), a sheen at glancing angles,
	// soft seams between the pentagons and the blade's outline glowing.
	vec3 col = behind * mix(vec3(1.0), base, 0.32 + e * 0.2) * 0.95 + base * 0.04;
	col += base * pow(1.0 - facing, 3.0) * 0.25;
	// The blade's outline (the pentagons out at its edge) carries the glow; each pentagon's
	// own rim is only a faint seam.
	float edge_glow = smoothstep(0.3, 0.85, e);
	float glow = edge_glow * edge_glow * 1.6 + outline * (0.1 + edge_glow * 0.45) + 0.12;
	glow *= mix(0.85, 1.3, v_tipw) * (1.0 + use_amount * 0.6);
	col += base * glow;
	col += mix(base, vec3(1.0), 0.55) * smoothstep(0.9, 1.0, v_rim) * edge_glow * 0.5;

	col += base * v_push * 2.6;
	col += base * fire_glow * 1.2 * (0.3 + e);
	col += base * charge_glow * (0.3 + v_tipw) * (0.4 + e);
	// The equip wave's front, and each pentagon's own flash as it breaks away.
	col += base * wave_glow * v_front;
	col += mix(base, vec3(1.0), 0.6) * v_flash * 3.5;
	// Recharging: past the fill line just clear glass and a faint outline, with a bright
	// front where it's filling back up.
	if (recharge < 1.0) {
		float drained = smoothstep(recharge - 0.02, recharge + 0.04, v_u);
		col = mix(col, behind * 0.9 + base * outline * 0.25, drained * 0.85);
		float f = v_u - recharge;
		col += base * exp(-(f * f) / 0.002) * 3.0 * (0.4 + e);
	}
	col += flash_color * flash_amount * (0.3 + e * 0.7);

	ALBEDO = col;
	ALPHA = v_alpha;
}
