shader_type spatial;
// Block shield built from the ball's own polygons (scripts/shield.gd).
// out_amount: faces lift off the ball and fly out to the shell, each a little out of step.
// grow: faces widen until they meet, closing into a solid faceted shell.
// Each vertex carries its face's center (UV.xy + UV2.x) so whole faces move together.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.55, 0.4, 1.0);
uniform float intensity = 2.2;
uniform float out_amount = 0.0;
uniform float grow = 0.0;
uniform float fade = 1.0;
// A burst of light across the shell (a parried hit).
uniform float flash = 0.0;
uniform float ball_radius = 0.5;
uniform float shell_radius = 1.7;

varying flat float seed;
varying vec3 local_pos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 center = vec3(UV.x, UV.y, UV2.x);
	seed = hash3(floor(center * 97.0));
	vec3 dir = normalize(center);
	// Staggered: some faces leave a little before others.
	float o = clamp(out_amount * 1.35 - seed * 0.35, 0.0, 1.0);
	o = o * o * (3.0 - 2.0 * o);
	float r = mix(ball_radius, shell_radius, o);
	// At the shell, scaling a face by shell/ball makes it tile exactly; a touch more overlaps.
	float g = clamp(grow * 1.3 - seed * 0.3, 0.0, 1.0);
	float s = mix(1.0, shell_radius / ball_radius * 1.04, g);
	VERTEX = dir * r + (VERTEX - center) * s;
	local_pos = VERTEX;
}

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - facing, 2.0);
	float shimmer = 0.5 + 0.5 * sin(TIME * 9.0 + seed * 40.0);
	float a = (0.18 + rim * 0.9 + shimmer * 0.12 + flash) * fade;
	ALBEDO = mix(color, vec3(1.0), rim * 0.35 + flash * 0.6) * intensity * (0.8 + seed * 0.5);
	ALPHA = clamp(a, 0.0, 1.0);
}
