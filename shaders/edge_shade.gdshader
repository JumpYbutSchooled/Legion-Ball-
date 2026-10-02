shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;
// Full-screen pass (graphics.gd puts it in every map, off on LOW): a soft dark line where
// two surfaces meet (a corner, a step, an object in front of a wall), so the game's boxes
// read as solid shapes instead of melting into each other. One pass, a few samples per
// pixel, faded out with distance so far detail doesn't buzz.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform float strength = 0.5;
uniform float fade_start = 40.0;
uniform float fade_end = 160.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 normal_at(vec2 uv) {
	return texture(normal_tex, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 px = 1.5 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float d = linear_depth(uv, INV_PROJECTION_MATRIX);
	vec3 n = normal_at(uv);
	float edge = 0.0;
	vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	for (int i = 0; i < 4; i++) {
		vec2 o = uv + offs[i];
		float dn = linear_depth(o, INV_PROJECTION_MATRIX);
		// Something nearer in front (a silhouette) or a crease between faces.
		edge = max(edge, smoothstep(0.02, 0.08, (d - dn) / d));
		edge = max(edge, smoothstep(0.25, 0.6, 1.0 - dot(n, normal_at(o))));
	}
	edge *= 1.0 - smoothstep(fade_start, fade_end, d);
	vec3 col = texture(screen_tex, uv).rgb;
	ALBEDO = col * (1.0 - edge * strength);
}
