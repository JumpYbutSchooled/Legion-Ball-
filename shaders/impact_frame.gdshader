shader_type canvas_item;
// Anime-style impact frame. Mode 1: the image thresholded and inverted (black on white)
// with black speed lines. Mode 2: a black frame with bright shapes in the tint colour
// and white speed lines. A burst sits on the kill point in both.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int mode = 0;
uniform vec2 center = vec2(0.5);
uniform vec3 tint : source_color = vec3(1.0, 0.3, 0.25);
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float ink = step(0.55, luma);

	vec2 d = SCREEN_UV - center;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(d);
	float angle = atan(d.y, d.x) / 6.28318 + 0.5;
	float lines = step(0.72, hash(vec2(floor(angle * 110.0), seed))) * smoothstep(0.06, 0.45, dist);
	float core = 1.0 - smoothstep(0.03, 0.09, dist);

	vec3 outc;
	if (mode == 1) {
		outc = vec3(1.0 - ink);
		outc = mix(outc, vec3(0.0), lines);
		outc = mix(outc, vec3(0.0), core);
	} else {
		outc = mix(vec3(0.0), tint, ink);
		outc = mix(outc, vec3(1.0), lines);
		outc = mix(outc, vec3(1.0), core);
	}
	COLOR = vec4(outc, 1.0);
}
