shader_type spatial;
// A plain coloured surface (what map_builder's solid() makes) with the shared world-space
// detail on top. MapMerge swaps the maps' plain materials for this when it merges them.

#include "res://shaders/detail.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.8);
uniform float roughness = 0.85;
uniform float metallic = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 v = surface_variation(world_pos, length(VERTEX));
	ALBEDO = albedo * v.x;
	ROUGHNESS = clamp(roughness + v.y, 0.0, 1.0);
	METALLIC = metallic;
}
