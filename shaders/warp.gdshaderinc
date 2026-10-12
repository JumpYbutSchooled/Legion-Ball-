// Shared by the warp shaders (muzzle / blast bubbles, the railgun charge, rifts, crystal
// blades): how they read back the picture behind them.
// - A prism split: red bends a little less than green, blue a little more, so strong
//   warps fringe with colour at their edges like thick glass or a shockwave.
// - Offsets are corrected for the screen's shape, so a round warp bends roundly on a
//   wide screen instead of stretched sideways.

const float WARP_SPLIT = 0.22;

vec2 warp_aspect(vec2 offset, vec2 viewport) {
	return offset * vec2(viewport.y / max(viewport.x, 1.0), 1.0);
}

vec3 warp_sample(sampler2D tex, vec2 uv, vec2 offset) {
	return vec3(
		texture(tex, uv + offset * (1.0 - WARP_SPLIT)).r,
		texture(tex, uv + offset).g,
		texture(tex, uv + offset * (1.0 + WARP_SPLIT)).b);
}
