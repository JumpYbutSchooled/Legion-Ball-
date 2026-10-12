shader_type spatial;
// Invisible bubble that bends the view behind it, like a heat/shock ripple: a smooth lens
// that's strongest around the middle of the sphere's slope and fades to nothing at the
// centre and the rim (so it has no visible edge), with a prism colour split and a faint
// bright caustic where it bends hardest (shaders/warp.gdshaderinc).
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

#include "res://shaders/warp.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Per-instance, so every bubble can share one material (set_instance_shader_parameter).
instance uniform float strength = 0.0;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	// A smooth bump over the slope: zero at the rim and the centre, peaking between.
	float ring = pow(sin(PI * clamp(facing, 0.0, 1.0)), 1.6) * smoothstep(0.0, 0.2, facing);
	vec2 offset = warp_aspect(NORMAL.xy * ring * strength, VIEWPORT_SIZE);
	vec3 col = warp_sample(screen_tex, SCREEN_UV, -offset);
	col *= 1.0 + ring * ring * min(strength * 2.0, 0.1);
	ALBEDO = col;
	ALPHA = 1.0;
}
