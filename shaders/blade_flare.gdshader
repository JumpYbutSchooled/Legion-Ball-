shader_type spatial;
// Glowing copy of a blade: puffed out along its normals, brightest at the silhouette,
// white-hot in the middle of the flash. Additive, so it only ever brightens.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.3, 0.8, 1.0);
uniform float intensity = 6.0;
uniform float fade = 1.0;
// How far the glow shell is pushed out from the blade surface.
uniform float grow = 0.05;

void vertex() {
	VERTEX += NORMAL * grow;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float glow = (0.35 + rim) * fade;
	ALBEDO = mix(color, vec3(1.0), fade * 0.5) * intensity;
	ALPHA = clamp(glow, 0.0, 1.0);
}
