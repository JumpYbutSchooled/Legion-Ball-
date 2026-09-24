shader_type spatial;
// Glowing expanding shell: bright at the silhouette, see-through in the middle.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 color : source_color = vec3(0.1, 0.95, 1.0);
uniform float intensity = 4.0;
uniform float fade = 1.0;

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = mix(color, vec3(1.0), rim * 0.4) * intensity;
	ALPHA = clamp(rim * fade, 0.0, 1.0);
}
