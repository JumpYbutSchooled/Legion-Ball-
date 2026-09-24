shader_type spatial;
// Camera motion blur. Drawn as a full-screen quad at the very start of the transparent pass,
// so the blades, beams and sparks drawn after it stay crisp.
// Each pixel's world position is rebuilt from depth, projected with last frame's camera,
// and the image is smeared along the difference. Pixels around the ball are masked out
// so the thing the camera follows stays sharp.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// World -> clip, this frame and last frame, both built the same way by the script.
uniform mat4 curr_view_proj;
uniform mat4 prev_view_proj;
// 1.0 = blur across the full frame-to-frame motion; lower is subtler.
uniform float strength = 0.5;
// Longest smear allowed, in screen-height fractions.
uniform float max_blur = 0.04;
// Ball mask, in screen UV and screen-height units.
uniform vec2 mask_center = vec2(0.5);
uniform float mask_radius = 0.0;

const int SAMPLES = 10;

void vertex() {
	// QuadMesh of size 2 covers clip space exactly.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// Sky has zero depth (reversed Z); nudge it so it reprojects as "very far away".
	float depth = max(texture(depth_tex, SCREEN_UV).r, 1e-6);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	world.xyz /= world.w;

	vec4 curr = curr_view_proj * vec4(world.xyz, 1.0);
	vec4 prev = prev_view_proj * vec4(world.xyz, 1.0);
	vec2 curr_uv = curr.xy / curr.w * 0.5 + 0.5;
	vec2 prev_uv = prev.xy / prev.w * 0.5 + 0.5;
	vec2 vel = (curr_uv - prev_uv) * strength;
	// The script's matrices have Y the other way round from SCREEN_UV; detect and fix.
	if (abs((1.0 - curr_uv.y) - SCREEN_UV.y) < abs(curr_uv.y - SCREEN_UV.y)) {
		vel.y = -vel.y;
	}

	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float len = length(vel * vec2(aspect, 1.0));
	if (len > max_blur) {
		vel *= max_blur / len;
	}

	// Keep the ball and its blades sharp.
	if (mask_radius > 0.0) {
		float to_ball = length((SCREEN_UV - mask_center) * vec2(aspect, 1.0));
		vel *= smoothstep(mask_radius, mask_radius * 1.6, to_ball);
	}

	vec3 col = vec3(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1) - 0.5;
		col += texture(screen_tex, SCREEN_UV - vel * t).rgb;
	}
	ALBEDO = col / float(SAMPLES);
	ALPHA = 1.0;
}
