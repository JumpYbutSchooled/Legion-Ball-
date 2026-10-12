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
	float dist = length(VERTEX);
	vec2 v = surface_variation(world_pos, dist);
	ALBEDO = mix(color_a, color_b, checker) * v.x;
	ROUGHNESS = clamp(0.88 + v.y, 0.0, 1.0);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// Floors (mostly grass and sand): gentle bumps, no gloss (a sun glint on a bumpy
	// glossy floor broke up into sparkly noise).
	NORMAL = (VIEW_MATRIX * vec4(surface_bumped_normal(world_pos, wn, dist, 0.45), 0.0)).xyz;
}
