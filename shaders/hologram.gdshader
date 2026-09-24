shader_type spatial;
// Hologram: additive glowing edges, fine scanlines crawling upward, a brighter band
// sweeping through, and a little flicker.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.9, 1.0);
uniform float intensity = 1.6;
uniform float opacity = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float scan = 0.55 + 0.45 * sin(world_pos.y * 70.0 - TIME * 8.0);
	float band = smoothstep(0.93, 1.0, sin(world_pos.y * 2.5 - TIME * 2.2));
	float flicker = 0.88 + 0.12 * sin(TIME * 41.0) * sin(TIME * 17.0);
	float a = ((0.12 + fresnel) * scan * flicker + band * 0.7) * opacity;
	ALBEDO = mix(color, vec3(1.0), band * 0.5) * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
