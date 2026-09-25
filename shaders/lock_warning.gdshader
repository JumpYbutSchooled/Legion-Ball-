shader_type canvas_item;
// Red glow round the screen edges: clear in the middle, strongest in the corners.

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.08, 0.08, 1.0);

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.55, 1.25, length(d));
	COLOR = vec4(tint.rgb, edge * strength * 0.85);
}
