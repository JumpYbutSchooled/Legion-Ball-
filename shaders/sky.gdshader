shader_type sky;
// The game's sky (graphics.gd swaps it in for each map's plain gradient sky, keeping that
// map's own colours): the same top-to-horizon gradient and sun glow as before, plus
// drifting clouds lit by the sun (two layers: billowing cumulus and thin high streaks), a
// hot sun disc with a halo, stars that twinkle on dark skies, a moon, and nebula clouds
// and a galaxy band out in space.
// The picture the lighting and reflections use (the cubemap pass) is the plain gradient,
// so every map is lit exactly as it was; the clouds and stars are only in the sky you see.
// (The engine's half-resolution sky pass would be the place for the clouds, but it comes
// back blank on this renderer, so they're worked out per pixel with few noise octaves.)

// Seconds since the game started (graphics.gd keeps it going). Not the built-in TIME: a sky
// shader that reads TIME has its lighting cubemap redone every single frame.
global uniform float sky_clock;

uniform vec3 top_color : source_color = vec3(0.3, 0.5, 0.85);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.8, 0.55);
uniform vec3 ground_bottom_color : source_color = vec3(0.3, 0.22, 0.14);
uniform vec3 ground_horizon_color : source_color = vec3(0.95, 0.75, 0.5);
uniform float sky_curve = 0.12;
uniform float ground_curve = 0.02;
uniform float sun_angle_max = 0.7;
uniform float sun_curve = 0.15;
uniform float energy = 1.0;

// 0 = clear sky .. 1 = overcast.
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
// How bright the clouds' lit side is (night skies turn it right down), and their shade.
uniform float cloud_light = 1.0;
uniform vec3 cloud_shade : source_color = vec3(0.45, 0.5, 0.62);
uniform float cloud_speed = 0.006;
// Thin high streaks above the cumulus.
uniform float cirrus : hint_range(0.0, 1.0) = 0.35;
// Stars (dark skies), a moon, and space's nebulas.
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float moon : hint_range(0.0, 1.0) = 0.0;
// 0 hides the sun's disc and halo (night maps: their "sun" is the moonlight).
uniform float sun_disc : hint_range(0.0, 1.0) = 1.0;
uniform vec3 moon_dir = vec3(-0.4, 0.5, -0.76);
uniform float nebula : hint_range(0.0, 1.0) = 0.0;
uniform vec3 nebula_a : source_color = vec3(0.35, 0.12, 0.6);
uniform vec3 nebula_b : source_color = vec3(0.05, 0.4, 0.55);

// Whole-number hashes (the cells of the noise below): integer maths, so there are none of
// the streaks a fract-and-multiply hash leaves across a cloud deck.
float hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

float hash31(vec3 p) {
	uvec3 q = uvec3(ivec3(p)) * uvec3(1597334673u, 3812015801u, 2798796415u);
	uint n = (q.x ^ q.y ^ q.z) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}
float noise2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x),
			mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
			mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = turn * p * 2.03 + vec2(17.0, 5.0);
		a *= 0.5;
	}
	return v;
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = p * 2.07 + vec3(11.0, 3.0, 7.0);
		a *= 0.5;
	}
	return v;
}

// A lighter fbm for the parts that only need a rough shape.
float fbm2_low(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 3; i++) {
		v += a * noise2(p);
		p = turn * p * 2.03 + vec2(17.0, 5.0);
		a *= 0.5;
	}
	return v / 0.875;
}

// The cumulus's big shapes at `uv` on the cloud deck (0 clear .. 1 thick), without the
// fine detail (enough for working out which side is lit).
float cloud_shape(vec2 uv, float t) {
	return fbm2(uv * 0.9 + vec2(t, t * 0.35));
}

float cloud_density(float shape, vec2 uv, float t) {
	float detail = fbm2_low(uv * 3.1 - vec2(t * 1.7, 0.0));
	float d = shape * 0.78 + detail * 0.22;
	float lo = mix(0.78, 0.3, cloud_cover);
	return smoothstep(lo, lo + 0.26, d);
}

// The plain gradient sky and sun glow (what the old sky drew).
vec3 base_sky(vec3 dir, vec3 sun_dir, vec3 sun_col, bool sun_on) {
	float v_angle = acos(clamp(dir.y, -1.0, 1.0));
	float c = 1.0 - v_angle / (PI * 0.5);
	vec3 sky = mix(horizon_color, top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	if (sun_on) {
		float sun_angle = acos(clamp(dot(sun_dir, dir), -1.0, 1.0));
		if (sun_angle < sun_angle_max) {
			float c2 = sun_angle / sun_angle_max;
			sky = mix(sun_col, sky, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
		}
	}
	c = (v_angle - PI * 0.5) / (PI * 0.5);
	vec3 ground = mix(ground_horizon_color, ground_bottom_color, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	return mix(ground, sky, step(0.0, dir.y)) * energy;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun_dir = LIGHT0_DIRECTION;
	bool sun_on = LIGHT0_ENABLED && LIGHT0_ENERGY > 0.02;
	vec3 sun_col = LIGHT0_COLOR * min(LIGHT0_ENERGY, 2.0);
	vec3 col = base_sky(dir, sun_dir, sun_col, sun_on);
	if (!AT_CUBEMAP_PASS) {
		float up = clamp(dir.y, 0.0, 1.0);
		if (sun_on && sun_disc > 0.01 && dir.y > -0.05) {
			// The sun itself: a hot disc and a tight halo round it.
			float cs = dot(dir, sun_dir);
			float disc = smoothstep(0.9993, 0.99975, cs);
			float halo = pow(max(cs, 0.0), 420.0) * 0.9 + pow(max(cs, 0.0), 60.0) * 0.22;
			col += sun_col * (disc * 6.0 + halo) * sun_disc;
		}
		if (nebula > 0.01) {
			// Space: drifting dust clouds in two colours, and a brighter band across the sky.
			float n1 = fbm3(dir * 2.2 + vec3(3.0, 1.0, 7.0));
			float n2 = fbm3(dir * 3.7 + vec3(9.0, 4.0, 2.0));
			float band = exp(-pow(dot(dir, normalize(vec3(0.35, 0.8, -0.48))) * 3.2, 2.0));
			vec3 dust = nebula_a * smoothstep(0.42, 0.85, n1) + nebula_b * smoothstep(0.48, 0.9, n2);
			col += dust * nebula * (0.35 + band * 1.1) + mix(nebula_a, nebula_b, 0.5) * band * 0.12 * nebula;
		}
		if (stars > 0.01) {
			// One star at most per cell of a grid wrapped round the sky; a few big bright ones.
			float seen = stars * (dir.y > 0.0 ? 1.0 : 0.35);
			for (int layer = 0; layer < 2; layer++) {
				float cells = layer == 0 ? 190.0 : 70.0;
				vec3 g = dir * cells;
				vec3 id = floor(g);
				float h = hash31(id + float(layer) * 31.0);
				if (h > (layer == 0 ? 0.985 : 0.992)) {
					vec3 centre = id + vec3(0.5) + (vec3(hash31(id + 1.7), hash31(id + 5.3), hash31(id + 9.1)) - 0.5) * 0.6;
					float d = length(g - centre);
					float twinkle = 0.65 + 0.35 * sin(sky_clock * (1.5 + h * 37.0) + h * 80.0);
					float size = layer == 0 ? 0.16 : 0.22;
					vec3 tint = mix(vec3(1.0, 0.86, 0.72), vec3(0.72, 0.84, 1.0), fract(h * 91.0));
					col += tint * smoothstep(size, 0.0, d) * twinkle * seen * (layer == 0 ? 1.4 : 3.2);
				}
			}
		}
		if (moon > 0.01) {
			vec3 md = normalize(moon_dir);
			float cm = dot(dir, md);
			float disc = smoothstep(0.9985, 0.9989, cm);
			// Craters: darker blotches fixed to the disc.
			float marks = noise3(dir * 90.0) * 0.35 + noise3(dir * 30.0) * 0.3;
			col = mix(col, vec3(0.92, 0.94, 1.0) * (1.25 - marks) * moon, disc);
			col += vec3(0.5, 0.6, 0.85) * pow(max(cm, 0.0), 180.0) * 0.35 * moon;
		}
		// The clouds, on a flat deck overhead (closer together toward the horizon).
		if (dir.y > -0.02 && (cloud_cover > 0.01 || cirrus > 0.01)) {
			vec2 uv = dir.xz / (dir.y + 0.16);
			float t = sky_clock * cloud_speed;
			float fade = smoothstep(-0.02, 0.2, dir.y);
			float d = 0.0;
			vec3 cumulus = vec3(0.0);
			if (cloud_cover > 0.01) {
				float shape = cloud_shape(uv, t);
				d = cloud_density(shape, uv, t);
				if (d > 0.002) {
					// Lit from the sun: thinner toward it means brighter (a cheap self-shadow).
					vec2 to_sun = sun_on ? normalize(sun_dir.xz + vec2(0.0001)) * 0.22 : vec2(0.15, 0.1);
					float lo = mix(0.78, 0.3, cloud_cover);
					float toward = smoothstep(lo, lo + 0.26, cloud_shape(uv + to_sun, t));
					float lit = clamp(1.0 - toward * 0.85 + (1.0 - d) * 0.35, 0.0, 1.0);
					vec3 sun_tint = sun_on ? mix(vec3(1.0), sun_col / max(max(sun_col.r, sun_col.g), max(sun_col.b, 0.001)), 0.7) : vec3(0.75, 0.8, 0.95);
					vec3 bright = mix(horizon_color, sun_tint, 0.62) * (0.55 + 0.75 * cloud_light);
					vec3 dark = mix(cloud_shade, top_color, 0.35) * (0.3 + 0.5 * cloud_light);
					cumulus = mix(dark, bright, lit);
					// Silver lining: the edges glow when the sun is behind them.
					if (sun_on) {
						float behind = pow(max(dot(dir, sun_dir), 0.0), 6.0);
						cumulus += sun_col * behind * (1.0 - d) * 0.9 * cloud_light;
					}
				}
			}
			// High, thin streaks, stretched along the wind.
			float ci = 0.0;
			if (cirrus > 0.01) {
				float streak = fbm2_low(uv * vec2(0.35, 1.5) + vec2(t * 0.6, 4.0));
				ci = smoothstep(0.5, 0.85, streak) * cirrus * 0.5;
			}
			vec3 wisp = mix(horizon_color, vec3(1.0), 0.5) * (0.5 + 0.5 * cloud_light);
			vec3 cloud_col = mix(wisp, cumulus, clamp(d * 4.0, 0.0, 1.0));
			col = mix(col, cloud_col, clamp(max(d * 0.94, ci), 0.0, 1.0) * fade);
		}
		// A little brighter right at the horizon, where the air is thickest.
		col += horizon_color * pow(1.0 - up, 9.0) * 0.1 * step(0.0, dir.y);
	}
	COLOR = col;
}