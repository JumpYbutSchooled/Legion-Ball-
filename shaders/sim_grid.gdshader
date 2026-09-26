shader_type canvas_item;
// Main menu backdrop: a dark "simulation space" with a perspective grid floor sliding
// toward the viewer, a twinkling starfield, a rotating dashed ring rising behind the
// horizon, a faint horizon glow, a slow scan bar, scanlines and a vignette.
// `glitch` (0..1, driven by main_menu.gd) tears the image into shifted bands with an
// RGB split, for the bursts of static.

uniform vec3 accent : source_color = vec3(0.35, 0.9, 1.0);
uniform vec3 base_top : source_color = vec3(0.01, 0.02, 0.04);
uniform vec3 base_bottom : source_color = vec3(0.02, 0.06, 0.09);
uniform float horizon = 0.58;
uniform float glitch = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 scene(vec2 uv, float aspect) {
	vec3 col = mix(base_top, base_bottom, uv.y);

	// Stars above the horizon: one per cell at most, twinkling at its own rate.
	if (uv.y < horizon) {
		vec2 cell_uv = vec2(uv.x * aspect, uv.y) * 90.0;
		vec2 cell = floor(cell_uv);
		float h = hash(cell);
		if (h > 0.93) {
			vec2 star = cell + vec2(hash(cell + 1.3), hash(cell + 7.1));
			float d = length(cell_uv - star);
			float twinkle = 0.5 + 0.5 * sin(TIME * (1.0 + h * 4.0) + h * 40.0);
			col += mix(vec3(1.0), accent, h) * smoothstep(0.12, 0.0, d) * twinkle * 0.7
				* smoothstep(horizon, horizon - 0.25, uv.y);
		}
	}

	// A big wireframe ring behind the horizon, its dashes turning slowly.
	vec2 rp = vec2((uv.x - 0.5) * aspect, uv.y - horizon) / 0.34;
	float r = length(rp);
	float ring = smoothstep(0.012, 0.0, abs(r - 1.0));
	float ang = atan(rp.y, rp.x);
	float dashes = step(0.45, fract(ang * 9.549 + TIME * 0.15));
	float inner = smoothstep(0.006, 0.0, abs(r - 0.86)) * step(0.7, fract(ang * 19.1 - TIME * 0.3));
	if (uv.y < horizon) {
		col += accent * (ring * mix(0.25, 0.6, dashes) + inner * 0.3);
	}

	// Perspective floor below the horizon: grid cells shrink with distance and scroll in.
	if (uv.y > horizon) {
		float depth = (uv.y - horizon) / (1.0 - horizon);
		float z = 1.0 / max(depth, 0.001);
		vec2 floor_uv = vec2((uv.x - 0.5) * z * 2.2, z + TIME * 0.6);
		// Distance to the nearest cell edge, antialiased by screen-space derivatives.
		vec2 edge = 0.5 - abs(fract(floor_uv) - 0.5);
		vec2 w = fwidth(floor_uv) * 1.2;
		vec2 lines = 1.0 - smoothstep(vec2(0.0), w, edge);
		float grid = max(lines.x, lines.y);
		// Now and then a line pulses brighter as it rolls toward you.
		float pulse = step(0.9, hash(vec2(floor(floor_uv.y), 3.0))) * 1.5;
		col += accent * grid * (0.35 + pulse * lines.x) * smoothstep(0.0, 0.6, depth);
	}

	// Horizon glow.
	col += accent * exp(-abs(uv.y - horizon) * 40.0) * 0.35;
	// Slow scan bar sweeping down.
	float bar = fract(TIME * 0.08);
	col += accent * exp(-abs(uv.y - bar) * 120.0) * 0.08;
	return col;
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec3 col;
	if (glitch > 0.001) {
		// Tear: bands of the screen slide sideways, with the red and blue pulled apart.
		float band = floor(uv.y * 24.0 + floor(TIME * 30.0) * 7.0);
		float shift = (hash(vec2(band, floor(TIME * 20.0))) - 0.5) * 0.08 * glitch;
		shift *= step(0.6, hash(vec2(band, 2.0)));
		vec2 guv = vec2(uv.x + shift, uv.y);
		float split = 0.006 * glitch;
		col = vec3(
			scene(guv + vec2(split, 0.0), aspect).r,
			scene(guv, aspect).g,
			scene(guv - vec2(split, 0.0), aspect).b);
	} else {
		col = scene(uv, aspect);
	}
	// Scanlines and a touch of noise.
	col *= 0.9 + 0.1 * sin(FRAGCOORD.y * 3.14159);
	col += (hash(FRAGCOORD.xy + TIME) - 0.5) * 0.02;
	// Vignette.
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 1.4;
	COLOR = vec4(col, 1.0);
}
