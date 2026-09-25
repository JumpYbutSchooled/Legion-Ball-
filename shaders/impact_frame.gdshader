shader_type canvas_item;
// Anime-style impact frame, drawn as a short sequence of held frames
// (scripts/ui/impact_frames.gd): first an IMPLOSION (the image sucked in toward the kill,
// speed lines converging, a ring closing in), then the crack, then an EXPLOSION (the image
// thrown outward, lines bursting from a ring racing out).
// Shading is manga-style: the image is split into four tones, solid, halftone dots,
// cross-hatching and paper, instead of plain black and white.
// Mode 1: ink on paper (inverted). Mode 2: glowing tint on black.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int mode = 0;
uniform vec2 center = vec2(0.5);
uniform vec3 tint : source_color = vec3(1.0, 0.3, 0.25);
uniform float seed = 0.0;
// > 0 sucks the image in toward the kill point (implosion); < 0 throws it out.
uniform float pinch = 0.0;
// Shock ring radius (screen heights; 0 = none) and whether lines burst outward from it
// (explosion) or pour in toward it (implosion).
uniform float ring = 0.0;
uniform bool bursting = false;
// Size of the white-hot core on the kill point.
uniform float core_size = 0.08;
// Whole-image jolt in UV units.
uniform vec2 jolt = vec2(0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 0 = darkest tone .. 3 = lightest; screen-space patterns for the two middle tones.
float tone(float luma, vec2 px) {
	// Curved so a bright scene still spreads across all four tones.
	float level = floor(clamp(pow(luma, 1.8), 0.0, 0.999) * 4.0);
	if (level < 0.5) {
		return 0.0;
	}
	if (level < 1.5) {
		// Cross-hatching.
		float a = step(0.78, fract((px.x + px.y) / 6.0));
		float b = step(0.78, fract((px.x - px.y) / 6.0));
		return max(a, b);
	}
	if (level < 2.5) {
		// Halftone: dark dots on a light ground.
		vec2 cell = fract(px / 5.0) - 0.5;
		return step(0.3, length(cell));
	}
	return 1.0;
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 d = (SCREEN_UV - center) * aspect;
	float dist = length(d);
	vec2 dir = dist > 0.0001 ? d / dist : vec2(0.0);

	// Radial warp: sample further out (implosion) or further in (explosion), strongest
	// near the kill point, plus a twist while imploding.
	float falloff = exp(-dist * 2.2);
	float r = dist * (1.0 + pinch * falloff);
	float twist = max(pinch, 0.0) * falloff * 1.2;
	vec2 wd = vec2(dir.x * cos(twist) - dir.y * sin(twist), dir.x * sin(twist) + dir.y * cos(twist));
	vec2 uv = center + wd * r / aspect + jolt;

	vec3 col = texture(screen_tex, uv).rgb;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec2 px = FRAGCOORD.xy;
	float shade = tone(luma, px);

	// Speed lines, in two weights.
	float angle = atan(d.y, d.x) / 6.28318 + 0.5;
	float thin = step(0.62, hash(vec2(floor(angle * 200.0), seed)));
	float fat = step(0.84, hash(vec2(floor(angle * 50.0), seed + 7.0)));
	float jag = hash(vec2(floor(angle * 200.0), seed + 3.0)) * 0.12;
	float lines = max(thin, fat);
	if (ring > 0.0) {
		// Implosion: lines pour in from the edges and stop at the ring.
		// Explosion: lines start at the ring and shoot outward.
		lines *= bursting ? step(ring + jag, dist) * (1.0 - step(ring + 0.9, dist)) : step(ring + jag, dist);
	} else {
		lines *= smoothstep(0.04, 0.3, dist + jag);
	}
	// The ring itself, jagged.
	float ring_line = 0.0;
	if (ring > 0.0) {
		float w = 0.012 + 0.02 * hash(vec2(floor(angle * 36.0), seed + 5.0));
		ring_line = 1.0 - smoothstep(w * 0.6, w, abs(dist - ring));
	}
	float core = 1.0 - smoothstep(core_size * 0.7, core_size, dist + jag * 0.3);

	vec3 outc;
	if (mode == 1) {
		// Ink on paper: dark areas become paper, bright areas ink.
		outc = vec3(1.0 - shade);
		outc = mix(outc, vec3(0.0), lines);
		outc = mix(outc, vec3(0.0), max(core, ring_line));
	} else {
		// Channels pulled apart around the kill point for a colour fringe.
		vec2 split = wd * 0.012 / aspect;
		float lr = tone(dot(texture(screen_tex, uv + split).rgb, vec3(0.333)), px);
		float lb = tone(dot(texture(screen_tex, uv - split).rgb, vec3(0.333)), px);
		outc = vec3(lr, shade, lb) * tint * 1.7;
		outc = mix(outc, vec3(1.0), lines);
		outc = mix(outc, vec3(1.0), max(core, ring_line));
	}
	COLOR = vec4(outc, 1.0);
}
