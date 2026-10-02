shader_type spatial;
// World-space checkerboard so you can see the ball moving across the floor.

#include "res://shaders/detail.gdshaderinc"

uniform vec3 color_a : source_color = vec3(0.20, 0.23, 0.28);
uniform vec3 color_b : source_color = vec3(0.27, 0.31, 0.37);
uniform float cell_size = 2.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_pos.xz / cell_size);
	float checker = mod(cell.x + cell.y, 2.0);
	vec2 v = surface_variation(world_pos, length(VERTEX));
	ALBEDO = mix(color_a, color_b, checker) * v.x;
	ROUGHNESS = clamp(0.85 + v.y, 0.0, 1.0);
}
