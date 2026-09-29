shader_type canvas_item;
// NAME CREATOR's cinematic overlay (scripts/ui/cinematic_overlay.gd): a soft radial
// darkening toward the screen edges, for trailer shots. Purely visual.

uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float radius : hint_range(0.1, 1.5) = 0.85;
uniform float softness : hint_range(0.05, 1.0) = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV - vec2(0.5);
	float dist = length(uv) * 2.0;
	float vignette = smoothstep(radius, radius - softness, dist);
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - vignette) * strength);
}
