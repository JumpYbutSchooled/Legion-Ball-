shader_type spatial;
// The warped air round a rift: a flat ring just bigger than the rift that bends and
// swirls the picture behind it (read back from the screen), strongest near the rift's
// edge and fading out. Drawn after the rift so the rift itself isn't bent.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.028;
// Where the rift's edge sits in this quad's UV radius (the quad is bigger).
uniform float inner = 0.62;
uniform float time = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0 || r < inner - 0.02) {
		discard;
	}
	float band = 1.0 - smoothstep(inner, 1.0, r);
	float a = atan(p.y, p.x);
	// Pull in toward the rift and twist round it, rippling.
	vec2 radial = normalize(p) * (0.6 + 0.4 * sin(a * 5.0 + time * 4.0));
	vec2 twist = vec2(-p.y, p.x) / max(r, 0.001);
	vec2 offset = (radial + twist * 0.6) * band * strength;
	ALBEDO = texture(screen_tex, SCREEN_UV - offset).rgb;
	ALPHA = 1.0;
}
