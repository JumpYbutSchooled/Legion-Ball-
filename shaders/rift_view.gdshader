shader_type spatial;
// A rift: an upright oval with a crackling, flame-like rim in its colour
// (teal or magenta) and a soft halo round it. Linked, the middle shows what's through the
// other rift (that rift's camera renders into `view`, lined up with the screen, so it
// looks like a hole in the wall). Unlinked, the middle is a closed, swirling membrane.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform sampler2D view : source_color, filter_linear;
uniform bool linked = false;
uniform vec3 rim_color : source_color = vec3(0.1, 0.55, 1.0);
uniform float time = 0.0;
// The oval fills this much of the quad (the rest is room for the halo).
uniform float fill = 0.78;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / fill;
	float r = length(p);
	float a = atan(p.y, p.x);
	// The rim wobbles: flames licking round the edge, always moving.
	float flame = noise(vec2(a * 5.0, time * 2.2)) * 0.6 + noise(vec2(a * 13.0 - time * 3.0, time)) * 0.4;
	float edge = 1.0 + (flame - 0.5) * 0.09;
	if (r > edge + 0.22) {
		discard;
	}
	vec3 col;
	float alpha = 1.0;
	if (r < edge - 0.07) {
		if (linked) {
			col = texture(view, SCREEN_UV).rgb;
		} else {
			// Closed: a slow swirl of the rift's colour.
			float swirl = noise(vec2(a * 3.0 + r * 6.0 - time * 1.5, r * 4.0 - time)) ;
			col = mix(rim_color * 0.2, rim_color * 1.2, swirl * (1.0 - r * 0.7));
		}
		// The colour bleeds in a little from the edge.
		col = mix(col, rim_color * 1.5, smoothstep(edge - 0.3, edge - 0.07, r) * 0.55);
	} else if (r < edge + 0.02) {
		// The bright ring itself, crackling.
		float crackle = 0.8 + 0.4 * noise(vec2(a * 20.0, time * 8.0));
		col = mix(rim_color * 2.0, vec3(1.0), 0.25) * crackle * 1.6;
	} else {
		// Soft halo fading out past the rim.
		float k = 1.0 - smoothstep(edge + 0.02, edge + 0.22, r);
		col = rim_color * 1.4;
		alpha = k * (0.55 + 0.3 * flame);
	}
	ALBEDO = col;
	ALPHA = alpha;
}
