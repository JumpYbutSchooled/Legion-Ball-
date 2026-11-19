shader_type spatial;
// The ball: a faceted shell of hexagons and pentagons (scripts/goldberg_ball_mesh.gd)
// with light in the seams between them. ball.gd dresses it in a skin (profile.gd SKINS):
// the faces' two colours, how shiny they are, the seam light's colour and strength, and a
// pattern that moves over it. A rim of the seam colour catches its silhouette, so a ball
// reads against any floor; `status` lays a pulsing glow over all of it (marked, stunned,
// chilled: ball.gd show_status).
// Per vertex: UV.x = 0 at a face's middle .. 1 at its edge, UV.y = the face's own random
// number, UV2.x = 1 on a pentagon.

uniform vec3 base : source_color = vec3(0.07, 0.08, 0.1);
uniform vec3 accent : source_color = vec3(0.13, 0.14, 0.18);
uniform vec3 seam : source_color = vec3(0.35, 0.9, 1.0);
uniform float glow = 2.6;
uniform float rough = 0.22;
uniform float metal = 0.5;
// 0 plain  1 pulse: a band of light sweeping round  2 molten: the seams breathe and spill
// into the faces  3 prism: every face its own slowly turning colour  4 galaxy: stars in
// the faces.
uniform int pattern = 0;
uniform vec3 status : source_color = vec3(1.0, 0.82, 0.2);
uniform float status_amount = 0.0;

varying vec3 local_pos;

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float edge = UV.x;
	float id = UV.y;
	float pent = UV2.x;
	vec3 col = mix(base, accent, pent);
	// Each face a touch different, like cut stone.
	col *= 0.9 + 0.2 * id;
	float line = smoothstep(0.8, 0.94, edge);
	float halo = smoothstep(0.45, 0.94, edge) * 0.25;
	vec3 light = seam;
	float power = glow;
	float r = rough;
	if (pattern == 1) {
		// A band of light sweeping from pole to pole.
		float band = fract(local_pos.y * 0.9 + TIME * 0.45);
		float sweep = smoothstep(0.0, 0.12, band) * (1.0 - smoothstep(0.12, 0.3, band));
		power *= 0.55 + 1.6 * sweep;
		col += seam * sweep * 0.12;
	} else if (pattern == 2) {
		// Molten: the light breathes, face by face, and creeps in from the seams.
		float breath = 0.55 + 0.45 * sin(TIME * (1.2 + id * 1.6) + id * 40.0);
		halo = smoothstep(0.25, 0.94, edge) * (0.35 + 0.45 * breath);
		power *= 0.6 + 0.8 * breath;
	} else if (pattern == 3) {
		// Prism: every face its own colour, all of them slowly turning.
		vec3 tint = hue(id + TIME * 0.07 + local_pos.y * 0.3);
		col = mix(col, tint, 0.6);
		light = mix(seam, tint, 0.5);
	} else if (pattern == 4) {
		// Galaxy: a few stars in each face (fixed to the ball, so they roll with it) and a
		// drift of colour behind them.
		vec3 cell = floor(local_pos * 34.0);
		float star = step(0.985, hash13(cell)) * (0.5 + 0.5 * sin(TIME * 3.0 + hash13(cell + 7.0) * 30.0));
		col += mix(seam, vec3(1.0), 0.5) * star * 1.5 * (1.0 - line);
		col += seam * 0.1 * sin(local_pos.x * 5.0 + local_pos.y * 3.0 + TIME * 0.4);
	}
	// The rim: brighter where the surface turns away.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 emit = light * (line * power + halo * power * 0.35 + rim * 0.55 * min(power, 3.0));
	// A status: the whole ball pulses in its colour.
	if (status_amount > 0.0) {
		float pulse = 0.6 + 0.4 * sin(TIME * 11.0);
		emit += status * status_amount * pulse * (0.9 + line * 2.0);
		col = mix(col, status, 0.25 * status_amount);
	}
	ALBEDO = mix(col, vec3(0.02), line * 0.7);
	ROUGHNESS = mix(r, 0.6, line);
	METALLIC = metal * (1.0 - line);
	EMISSION = emit;
}
