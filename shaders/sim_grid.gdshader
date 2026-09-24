shader_type canvas_item;
// Main menu backdrop: a dark "simulation space" with a perspective grid floor sliding
// toward the viewer, a faint horizon glow, a slow scan bar, scanlines and a vignette.

uniform vec3 accent : source_color = vec3(0.35, 0.9, 1.0);
uniform vec3 base_top : source_color = vec3(0.01, 0.02, 0.04);
uniform vec3 base_bottom : source_color = vec3(0.02, 0.06, 0.09);
uniform float horizon = 0.58;

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(base_top, base_bottom, uv.y);

	// Perspective floor below the horizon: grid cells shrink with distance and scroll in.
	if (uv.y > horizon) {
		float depth = (uv.y - horizon) / (1.0 - horizon);
		float z = 1.0 / max(depth, 0.001);
		vec2 floor_uv = vec2((uv.x - 0.5) * z * 2.2, z + TIME * 0.6);
		// Distance to the nearest cell edge, antialiased by screen-space derivatives.
		vec2 edge = 0.5 - abs(fract(floor_uv) - 0.5);
		vec2 w = fwidth(floor_uv) * 1.2;
		vec2 lines = 1.0 - smoothstep(vec2(0.0), w, edge);
		float grid = max(lines.x, lines.y);
		col += accent * grid * 0.35 * smoothstep(0.0, 0.6, depth);
	}

	// Horizon glow.
	col += accent * exp(-abs(uv.y - horizon) * 40.0) * 0.35;
	// Slow scan bar sweeping down.
	float bar = fract(TIME * 0.08);
	col += accent * exp(-abs(uv.y - bar) * 120.0) * 0.08;
	// Scanlines and a touch of noise.
	col *= 0.9 + 0.1 * sin(FRAGCOORD.y * 3.14159);
	col += (fract(sin(dot(FRAGCOORD.xy + TIME, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.02;
	// Vignette.
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 1.4;
	COLOR = vec4(col, 1.0);
}
