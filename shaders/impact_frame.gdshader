shader_type canvas_item;
// Anime-style impact frame. Mode 1: the image thresholded and inverted (black on white)
// with thick black speed lines. Mode 2: a black frame with bright shapes in the tint
// colour, split into offset colour channels, and white speed lines. A burst sits on the
// kill point in both, and every frame punches the image in toward it and jolts it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int mode = 0;
uniform vec2 center = vec2(0.5);
uniform vec3 tint : source_color = vec3(1.0, 0.3, 0.25);
uniform float seed = 0.0;
// Zoom toward the kill point (0 = none), and a whole-image jolt in UV units.
uniform float zoom = 0.0;
uniform vec2 jolt = vec2(0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = center + (SCREEN_UV - center) * (1.0 - zoom) + jolt;
	vec3 col = texture(screen_tex, uv).rgb;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float ink = step(0.5, luma);

	vec2 d = SCREEN_UV - center;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(d);
	float angle = atan(d.y, d.x) / 6.28318 + 0.5;
	// Two layers of speed lines: dense thin ones and sparse fat ones.
	float thin = step(0.6, hash(vec2(floor(angle * 180.0), seed)));
	float fat = step(0.82, hash(vec2(floor(angle * 45.0), seed + 7.0)));
	float lines = max(thin, fat) * smoothstep(0.04, 0.3, dist + hash(vec2(floor(angle * 180.0), seed + 3.0)) * 0.15);
	float core = 1.0 - smoothstep(0.05, 0.14, dist);
	// Jagged ring of spikes around the core.
	float spikes = step(dist, 0.12 + 0.08 * hash(vec2(floor(angle * 24.0), seed + 11.0)));

	vec3 outc;
	if (mode == 1) {
		outc = vec3(1.0 - ink);
		outc = mix(outc, vec3(0.0), lines);
		outc = mix(outc, vec3(0.0), max(core, spikes));
	} else {
		// Channels pulled apart around the kill point.
		vec2 split = normalize(d + 0.0001) * 0.012;
		float r = step(0.5, dot(texture(screen_tex, uv + split).rgb, vec3(0.333)));
		float b = step(0.5, dot(texture(screen_tex, uv - split).rgb, vec3(0.333)));
		outc = vec3(r, ink, b) * tint * 1.6;
		outc = mix(outc, vec3(1.0), lines);
		outc = mix(outc, vec3(1.0), max(core, spikes));
	}
	COLOR = vec4(outc, 1.0);
}
