shader_type spatial;
// Anime-style impact frame, drawn as a full-screen quad on the camera, last of all.
// Works from the scene's real depth and normals, so the blast is actually cast across
// the world from the kill point:
// - Lighting: every surface is lit (or, while imploding, darkened) by the kill point,
//   depending on which way it faces and how far it is.
// - Shadows: a ray is marched from each pixel back to the kill point through the depth
//   buffer; anything in between (players, walls, cubes) casts a hard shadow.
// - Shafts: over the sky, rays stream out from the kill point and objects in front of it
//   cut dark shafts through them.
// - Ink outlines round every object, from jumps in depth and bends in the surface.
// - Manga tones: solid, cross-hatching, halftone dots, paper.
// Driven frame by frame by scripts/ui/impact_frames.gd (implosion -> crack -> explosion).
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

// 1: ink on paper. 2: glowing tint on black.
uniform int mode = 1;
uniform vec3 kill_pos = vec3(0.0);
// The kill point on screen (UV), worked out by the script.
uniform vec2 center = vec2(0.5);
uniform vec3 tint : source_color = vec3(1.0, 0.3, 0.25);
uniform float seed = 0.0;
// > 0 sucks the image in toward the kill point (implosion); < 0 throws it out.
uniform float pinch = 0.0;
// How strongly the kill point lights the world; negative darkens instead (implosion).
uniform float power = 1.0;
// Reach of the light, in metres.
uniform float light_range = 45.0;
// Shock ring radius (screen heights; 0 = none), and whether lines burst outward from it.
uniform float ring = 0.0;
uniform bool bursting = false;
uniform float core_size = 0.05;
uniform vec2 jolt = vec2(0.0);

// Kept low for speed; each pixel starts its march at a slightly different point
// (jitter), which hides the banding fewer steps would otherwise cause.
const int SHADOW_STEPS = 12;
const int SHAFT_STEPS = 10;

void vertex() {
	// QuadMesh of size 2 covers clip space exactly.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// View-space position of whatever is at `uv`.
vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = max(texture(depth_tex, uv).r, 1e-7);
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

bool is_sky(vec2 uv) {
	return texture(depth_tex, uv).r < 1e-6;
}

// 0..1 lighting into four manga tones: solid, hatching, dots, paper.
float tone(float v, vec2 px) {
	float level = floor(clamp(v, 0.0, 0.999) * 4.0);
	if (level < 0.5) {
		return 0.0;
	}
	if (level < 1.5) {
		float a = step(0.78, fract((px.x + px.y) / 6.0));
		float b = step(0.78, fract((px.x - px.y) / 6.0));
		return max(a, b);
	}
	if (level < 2.5) {
		vec2 cell = fract(px / 5.0) - 0.5;
		return step(0.3, length(cell));
	}
	return 1.0;
}

void fragment() {
	vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec2 px = FRAGCOORD.xy;
	vec2 d = (SCREEN_UV - center) * aspect;
	float dist = length(d);
	vec2 dir = dist > 0.0001 ? d / dist : vec2(0.0);

	// Radial warp (sucked in with a twist, or thrown out), strongest near the kill.
	float falloff = exp(-dist * 2.2);
	float r = dist * (1.0 + pinch * falloff);
	float twist = max(pinch, 0.0) * falloff * 1.2;
	vec2 wd = vec2(dir.x * cos(twist) - dir.y * sin(twist), dir.x * sin(twist) + dir.y * cos(twist));
	vec2 uv = clamp(center + wd * r / aspect + jolt, vec2(0.001), vec2(0.999));

	vec3 kv = (VIEW_MATRIX * vec4(kill_pos, 1.0)).xyz;
	float lit = 0.0;
	float outline = 0.0;
	bool sky = is_sky(uv);

	if (!sky) {
		vec3 p = view_pos(uv, INV_PROJECTION_MATRIX);
		vec3 n = normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
		vec3 to_light = kv - p;
		float ld = length(to_light);
		// Wrapped, so surfaces side-on to the blast still catch some of it.
		float lambert = clamp((dot(n, to_light / ld) + 0.4) / 1.4, 0.0, 1.0);
		float atten = 1.0 / (1.0 + (ld * ld) / (light_range * light_range));

		// Shadow ray: march toward the kill point; if the depth buffer shows something
		// in front of the ray, this pixel can't see the blast.
		// Skipped where the blast is too weak to matter anyway.
		float shadow = 0.0;
		float jitter = hash(px + seed);
		bool worth = lambert * atten * abs(power) > 0.03;
		for (int i = 0; i < SHADOW_STEPS && worth; i++) {
			float t = (float(i) + jitter) / float(SHADOW_STEPS);
			vec3 s = mix(p, kv, t * 0.97);
			vec4 clip = PROJECTION_MATRIX * vec4(s, 1.0);
			if (clip.w <= 0.0) {
				break;
			}
			vec2 suv = clip.xy / clip.w * 0.5 + 0.5;
			if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
				break;
			}
			if (is_sky(suv)) {
				continue;
			}
			float scene_z = view_pos(suv, INV_PROJECTION_MATRIX).z;
			// Something nearer the camera than the ray, but not a whole world away.
			if (scene_z > s.z + 0.25 && scene_z < s.z + 8.0) {
				shadow = 1.0;
				break;
			}
		}
		lit = lambert * atten * (1.0 - shadow);
		lit = power >= 0.0 ? lit * power : 1.0 - lit * -power * 3.0;
		lit = clamp(lit, 0.0, 1.0);
		if (power < 0.0) {
			lit *= 0.55;
		}

		// Ink outlines: jumps in depth, and sharp bends in the surface.
		vec2 o = 1.5 / VIEWPORT_SIZE;
		float edge = 0.0;
		// Two neighbours (right and below) are enough to find every edge.
		for (int k = 0; k < 2; k++) {
			vec2 off = k == 0 ? vec2(o.x, 0.0) : vec2(0.0, o.y);
			vec2 nuv = uv + off;
			if (is_sky(nuv)) {
				edge = 1.0;
				continue;
			}
			float nz = view_pos(nuv, INV_PROJECTION_MATRIX).z;
			edge = max(edge, step(0.04 * -p.z + 0.1, abs(nz - p.z)));
			vec3 nn = normalize(texture(normal_tex, nuv).xyz * 2.0 - 1.0);
			edge = max(edge, step(dot(n, nn), 0.75));
		}
		outline = edge;
	} else {
		// Sky: rays streaming from the kill point, with dark shafts where something in
		// front of it blocks them.
		float blocked = 0.0;
		// Stop short of the kill point itself, so whatever it sits on doesn't count.
		float sj = hash(px + seed + 17.0);
		for (int i = 0; i < SHAFT_STEPS; i++) {
			vec2 suv = mix(uv, center, (float(i) + sj) / float(SHAFT_STEPS) * 0.9);
			if (!is_sky(suv) && view_pos(suv, INV_PROJECTION_MATRIX).z > kv.z + 1.5) {
				blocked = 1.0;
				break;
			}
		}
		lit = power >= 0.0 ? (1.0 - blocked) * clamp(power, 0.0, 1.0) : blocked * 0.6;
		// Faint scene brightness underneath so the horizon still reads.
		lit = max(lit, dot(texture(screen_tex, uv).rgb, vec3(0.3)) * 0.35);
	}

	float shade = tone(lit, px);

	// Speed lines, in two weights.
	float angle = atan(d.y, d.x) / 6.28318 + 0.5;
	float thin = step(0.62, hash(vec2(floor(angle * 200.0), seed)));
	float fat = step(0.84, hash(vec2(floor(angle * 50.0), seed + 7.0)));
	float jag = hash(vec2(floor(angle * 200.0), seed + 3.0)) * 0.12;
	float lines = max(thin, fat);
	if (ring > 0.0) {
		lines *= bursting ? step(ring + jag, dist) * (1.0 - step(ring + 0.9, dist)) : step(ring + jag, dist);
	} else {
		lines *= smoothstep(0.04, 0.3, dist + jag);
	}
	// Lines only over the background, so the lit world stays readable.
	lines *= sky ? 1.0 : 0.25;
	float ring_line = 0.0;
	if (ring > 0.0) {
		float w = 0.012 + 0.02 * hash(vec2(floor(angle * 36.0), seed + 5.0));
		ring_line = 1.0 - smoothstep(w * 0.6, w, abs(dist - ring));
	}
	float core = 1.0 - smoothstep(core_size * 0.7, core_size, dist + jag * 0.3);

	vec3 outc;
	if (mode == 1) {
		outc = vec3(shade);
		outc = mix(outc, vec3(0.0), max(outline, lines));
		outc = mix(outc, vec3(0.0), max(core, ring_line));
	} else {
		outc = shade * tint * 1.8;
		outc = mix(outc, vec3(1.0), max(outline, lines));
		outc = mix(outc, vec3(1.0), max(core, ring_line));
	}
	ALBEDO = outc;
	ALPHA = 1.0;
}
