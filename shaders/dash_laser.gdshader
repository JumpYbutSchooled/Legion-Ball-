shader_type spatial;
// Additive glowing crystal. Faceted brightness comes from the flat face normals.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.3, 0.8, 1.0);
uniform float intensity = 2.5;
uniform float fade = 1.0;

// 0 at the ball, 1 at the tail.
varying float along;

void vertex() {
	along = VERTEX.y + 0.5;
}

void fragment() {
	// Facets facing the camera glow hot, edge-on facets stay colored.
	float facing = abs(dot(NORMAL, VIEW));
	float a = fade * (1.0 - along * 0.5) * (0.35 + facing);
	ALBEDO = mix(color, vec3(1.0), facing * facing * 0.4) * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
