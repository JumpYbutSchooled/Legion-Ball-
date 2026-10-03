shader_type canvas_item;
// "Liquid glass" panels (ui_style.gd glass()): whatever is behind the panel, blurred and
// tinted, bent a little near the rounded edges like thick glass, with a soft sheen and a
// thin lit rim (brightest at the top left). The panel's own rounded StyleBox only gives
// the shape (and its smooth corners); this draws everything inside it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(100.0, 100.0);
uniform float radius = 18.0;
uniform vec4 tint : source_color = vec4(0.02, 0.05, 0.08, 0.6);
uniform vec4 rim : source_color = vec4(0.35, 0.9, 1.0, 0.55);
uniform float blur = 2.6;
uniform float bend = 9.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = size * 0.5;
	vec2 p = local - half_size;
	float d = round_box(p, half_size, radius);  // negative inside, 0 on the edge
	float inside = clamp(-d, 0.0, 60.0);
	// Thick-glass bend: near the edge the background is pulled in toward the middle.
	float edge = 1.0 - smoothstep(0.0, 22.0, inside);
	vec2 out_dir = p / max(half_size, vec2(1.0));
	vec2 uv = SCREEN_UV - out_dir * edge * edge * bend * SCREEN_PIXEL_SIZE * 2.0;
	// Frosted: five soft samples of the mipmapped screen.
	vec2 o = SCREEN_PIXEL_SIZE * 6.0;
	vec3 bg = textureLod(screen_tex, uv, blur).rgb * 0.4;
	bg += textureLod(screen_tex, uv + vec2(o.x, o.y), blur).rgb * 0.15;
	bg += textureLod(screen_tex, uv + vec2(-o.x, o.y), blur).rgb * 0.15;
	bg += textureLod(screen_tex, uv + vec2(o.x, -o.y), blur).rgb * 0.15;
	bg += textureLod(screen_tex, uv + vec2(-o.x, -o.y), blur).rgb * 0.15;
	vec3 col = mix(bg, tint.rgb, tint.a);
	// Frost: glass lifts what's behind it a little. Sheen: lighter toward the top, a glow
	// just inside the edge, and a soft diagonal highlight across the upper part.
	col += 0.025;
	float v = clamp(local.y / max(size.y, 1.0), 0.0, 1.0);
	col += (1.0 - v) * 0.05;
	col += edge * edge * 0.08;
	float streak = (local.x + local.y * 1.6) / max(size.x + size.y * 1.6, 1.0);
	col += smoothstep(0.18, 0.3, streak) * (1.0 - smoothstep(0.3, 0.46, streak)) * 0.035;
	// The rim, lit from the top left.
	float line = 1.0 - smoothstep(0.6, 1.8, abs(d + 1.0));
	float lit = 0.45 + 0.55 * clamp(dot(normalize(p + 0.0001), normalize(vec2(-0.55, -1.0))), 0.0, 1.0);
	col = mix(col, rim.rgb, line * rim.a * lit);
	COLOR = vec4(col, COLOR.a);
}
