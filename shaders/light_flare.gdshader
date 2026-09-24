shader_type spatial;
// Lens-flare style burst drawn on a camera-facing quad: white-hot core, soft glow,
// a long horizontal streak and faint rays. Additive, so it only ever brightens.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.85, 1.0);
uniform float intensity = 5.0;
uniform float fade = 1.0;
// Quad width / height, so the core stays round on a wide quad.
uniform float aspect = 3.0;

void vertex() {
	// Face the camera, keeping the node's uniform scale.
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * s,
		INV_VIEW_MATRIX[1] * s,
		INV_VIEW_MATRIX[2] * s,
		MODEL_MATRIX[3]
	);
}

void fragment() {
	// -aspect..aspect across, -1..1 down.
	vec2 p = (UV - 0.5) * 2.0 * vec2(aspect, 1.0);
	float r = length(p);
	float core = exp(-r * r * 20.0);
	float glow = exp(-r * 3.5) * 0.6;
	float streak = exp(-abs(p.y) * 45.0) * exp(-abs(p.x) * 0.9);
	float rays = pow(abs(cos(atan(p.y, p.x) * 3.0)), 24.0) * exp(-r * 2.5) * 0.5;
	float a = (core * 2.0 + glow + streak + rays) * fade;
	ALBEDO = mix(color, vec3(1.0), clamp(core * 1.5, 0.0, 1.0)) * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
