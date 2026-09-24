shader_type spatial;
// Invisible bubble that bends the view behind it, like a heat/shock ripple.
// Strongest around the middle of the sphere's slope, fading at the center and rim.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float ring = smoothstep(0.0, 0.45, facing) * (1.0 - smoothstep(0.55, 1.0, facing));
	vec2 offset = NORMAL.xy * ring * strength;
	ALBEDO = texture(screen_tex, SCREEN_UV - offset).rgb;
	ALPHA = 1.0;
}
