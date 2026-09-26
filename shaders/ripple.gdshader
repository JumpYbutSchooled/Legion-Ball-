shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// A white ripple spreading over a wall where a shot passed through it (scripts/wall_ripple.gd):
// three thin rings racing outward from the hole, fading as they go, over a soft glow.

uniform vec3 color : source_color = vec3(1.0);
uniform float intensity = 3.0;
instance uniform float progress = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float fade = 1.0 - progress;
	float rings = 0.0;
	for (int k = 0; k < 3; k++) {
		float at = progress * 1.1 - float(k) * 0.16;
		if (at > 0.0) {
			rings += smoothstep(0.05, 0.0, abs(r - at)) * (1.0 - float(k) * 0.25);
		}
	}
	// A bright core where it went through, shrinking fast.
	float core = smoothstep(0.25 * fade, 0.0, r) * fade * fade;
	float edge = smoothstep(1.0, 0.7, r);
	ALBEDO = color * intensity * (rings * fade * edge + core * 1.5);
}
