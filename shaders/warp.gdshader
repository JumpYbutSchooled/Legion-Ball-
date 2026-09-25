shader_type canvas_item;
// Full-screen speed warp: fisheye bend, radial blur, chromatic aberration, and an
// expanding shockwave ring on dash. Strength goes above 1 for the dash burst.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0, 4.0) = 0.0;
// 0 -> 1 as the shockwave ring expands; 1 = off.
uniform float shock_progress : hint_range(0.0, 1.0) = 1.0;
uniform float shock_power = 0.15;
uniform float shock_width = 0.1;
// How hard the screen bends toward the edges, per unit of strength.
uniform float bend = 0.18;
uniform float blur_amount = 0.16;
uniform float aberration = 0.02;

void fragment() {
	vec2 dir0 = SCREEN_UV - vec2(0.5);
	float dist0 = length(dir0);

	// Fisheye bend: pull samples toward the center, more at the edges,
	// so the world stretches outward like you're being sucked forward.
	vec2 dir = dir0 * (1.0 - bend * strength * dist0 * dist0);
	float dist = length(dir);
	vec2 radial = dir / max(dist, 1e-4);
	vec2 uv = vec2(0.5) + dir;

	// Shockwave: a ring that pushes the image outward as it expands and fades.
	float ring_r = shock_progress * 0.9;
	float ring = exp(-pow((dist0 - ring_r) / shock_width, 2.0)) * (1.0 - shock_progress);
	uv -= radial * ring * shock_power;

	float edge = smoothstep(0.1, 0.7, dist0);

	// Radial blur toward the center, stronger at the edges.
	float blur = strength * blur_amount * edge;
	vec3 col = vec3(0.0);
	const int SAMPLES = 20;
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		col += texture(screen_tex, uv - dir * blur * t).rgb;
	}
	col /= float(SAMPLES);

	// Chromatic aberration, extra along the shock ring.
	float ca = strength * aberration * edge + ring * 0.04;
	col.r = mix(col.r, texture(screen_tex, uv - dir * ca).r, 0.8);
	col.b = mix(col.b, texture(screen_tex, uv + dir * ca).b, 0.8);

	COLOR = vec4(col, 1.0);
}
