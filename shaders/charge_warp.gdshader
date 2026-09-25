shader_type spatial;
// Invisible sphere of distortion: rings that keep sweeping in from the rim to the
// center, pulling the view inward as they pass. Used for the railgun charge.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.0;
// Advanced by the script; each whole step moves a ring from the rim to the center.
uniform float phase = 0.0;
uniform float ring_width = 0.1;

const int RINGS = 3;

void fragment() {
	// 0 at the sphere's rim, 1 at its center (as seen from the camera).
	float facing = abs(dot(NORMAL, VIEW));
	float amount = 0.0;
	for (int i = 0; i < RINGS; i++) {
		float r = fract(phase + float(i) / float(RINGS));
		float d = facing - r;
		// Fade each ring in at the rim and weaken it as it closes on the center.
		amount += exp(-(d * d) / (ring_width * ring_width)) * smoothstep(0.0, 0.15, r) * (1.0 - r * 0.6);
	}
	// Sampling further out along the normal squeezes the image toward the center.
	vec2 offset = NORMAL.xy * amount * strength;
	ALBEDO = texture(screen_tex, SCREEN_UV + offset).rgb;
	ALPHA = 1.0;
}
