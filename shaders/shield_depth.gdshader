shader_type spatial;
// Solid stand-in for a shield shell (the Q shield or the owner's gold one), used only
// while an impact frame plays (scripts/ui/impact_frames.gd). The real shield
// (shield.gdshader) is additive glow, so it never reaches the depth and normal buffers
// the impact frame shades from; this copy has the same shape (the vertex code mirrors
// shield.gdshader's) and writes them. Never seen itself: the impact frame covers the
// whole screen.
render_mode cull_disabled, depth_draw_always, shadows_disabled;

uniform float out_amount = 0.0;
uniform float grow = 0.0;
uniform float fade = 1.0;
uniform float ball_radius = 0.5;
uniform float shell_radius = 1.7;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 center = vec3(UV.x, UV.y, UV2.x);
	float seed = hash3(floor(center * 97.0));
	vec3 dir = normalize(center);
	float o = clamp(out_amount * 1.35 - seed * 0.35, 0.0, 1.0);
	o = o * o * (3.0 - 2.0 * o);
	float r = mix(ball_radius, shell_radius, o);
	float g = clamp(grow * 1.3 - seed * 0.3, 0.0, 1.0);
	float s = mix(1.0, shell_radius / ball_radius * 1.04, g);
	VERTEX = dir * r + (VERTEX - center) * s;
}

void fragment() {
	// Still sitting on the ball (or nearly faded): nothing to add.
	if (fade < 0.3) {
		discard;
	}
	ALBEDO = vec3(0.0);
}
