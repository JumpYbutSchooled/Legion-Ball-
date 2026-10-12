// Shared surface detail for the map shaders: soft world-space blotches (a few metres
// across) and a finer grain, so big flat faces read as real material instead of plastic.
// No textures, a handful of maths per pixel. `surface_detail` (0..1, set by the graphics
// preset; LOW turns it off) scales all of it; the grain fades out with distance so it
// never shimmers.

global uniform float surface_detail;

float detail_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise, 0..1.
float detail_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(detail_hash(i), detail_hash(i + vec3(1, 0, 0)), f.x),
			mix(detail_hash(i + vec3(0, 1, 0)), detail_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(detail_hash(i + vec3(0, 0, 1)), detail_hash(i + vec3(1, 0, 1)), f.x),
			mix(detail_hash(i + vec3(0, 1, 1)), detail_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// x: brightness multiplier for the albedo, y: roughness offset.
vec2 surface_variation(vec3 world_pos, float view_dist) {
	if (surface_detail <= 0.0) {
		return vec2(1.0, 0.0);
	}
	float macro = detail_noise(world_pos * 0.14) - 0.5;
	float grain = 0.0;
	if (view_dist < 90.0) {
		grain = (detail_noise(world_pos * 1.7) - 0.5) * (1.0 - smoothstep(25.0, 90.0, view_dist));
	}
	float shade = 1.0 + (macro * 0.24 + grain * 0.08) * surface_detail;
	return vec2(shade, grain * 0.18 * surface_detail);
}

// Fine bumps for the light to catch (a Rocket League-style surface texture without any
// image files): a small noise height field whose slope tilts the surface normal. Fades
// out with distance (and off on LOW). Returns the bumped world-space normal.
float detail_bump_height(vec3 p) {
	return detail_noise(p * 1.15);
}

vec3 surface_bumped_normal(vec3 world_pos, vec3 world_normal, float view_dist, float amount) {
	if (surface_detail <= 0.0 || view_dist > 70.0) {
		return world_normal;
	}
	float fade = (1.0 - smoothstep(28.0, 70.0, view_dist)) * surface_detail * amount;
	float e = 0.12;
	float h0 = detail_bump_height(world_pos);
	vec3 g = vec3(
		detail_bump_height(world_pos + vec3(e, 0.0, 0.0)) - h0,
		detail_bump_height(world_pos + vec3(0.0, e, 0.0)) - h0,
		detail_bump_height(world_pos + vec3(0.0, 0.0, e)) - h0) / e;
	g -= world_normal * dot(g, world_normal);
	return normalize(world_normal - g * 0.07 * fade);
}
