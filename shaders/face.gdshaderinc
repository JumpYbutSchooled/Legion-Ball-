// What the map shaders know about the box face they're drawing, and what they do with it:
// bevelled, worn edges; big faces split into equal panels with recessed seams; grime
// where a wall meets the ground. (Include after detail.gdshaderinc.)
//
// MapMerge (scripts/map_merge.gd) bakes this into every box's vertices as it merges a map:
//   UV      this point on its face, in metres from the face's middle (x along the face's
//           tangent, y along its "up": the box's own up on a wall)
//   UV2     half the face's size, in metres
//   CUSTOM0 the tangent, in world space
//   COLOR.r a random number for the box
// A mesh without it (anything not merged: a loose box, a moving one) has UV2 = 0, and
// every function here leaves it alone.

varying vec3 face_world_pos;
varying vec3 face_normal;
varying vec3 face_tangent;
varying vec4 face_uv;
varying float face_rand;

struct Face {
	vec2 p;          // on the face, metres from its middle
	vec2 half_size;
	vec3 n;          // world normal
	vec3 t;          // world: the face's x axis
	vec3 b;          // world: the face's y axis (up, on a wall)
	float px;        // metres per pixel here
};

// (px: how many metres one pixel covers here; the caller works it out with dFdx/dFdy.)
Face face_read(float px) {
	Face f;
	f.p = face_uv.xy;
	f.half_size = face_uv.zw;
	f.n = normalize(face_normal);
	f.t = normalize(face_tangent - f.n * dot(face_tangent, f.n));
	f.b = cross(f.n, f.t);
	f.px = max(px, 0.00001);
	return f;
}

float face_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p))) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

// Everything here is sized from the face it's on, not in fixed metres: the maps run from
// crates a metre across to walls a hundred and fifty metres high, seen from anywhere
// between touching and half a kilometre off, and a seam that reads on one would vanish (or
// swamp) the other. So a bevel is a fraction of the face's short side, and a face is split
// into a handful of panels whatever its size.

// How wide this face's bevel is, metres.
float face_bevel(Face f) {
	return clamp(min(f.half_size.x, f.half_size.y) * 0.09, 0.03, 1.3);
}

// How much of the box's own edge shows here, per axis: 1 on the edge, falling to 0 a
// bevel's width in. The edge a wall stands on is left out (it's in a corner, not exposed).
// `grime` comes back 1 at the foot of a wall, fading up it; `height` is how far up the
// wall this is (0 foot .. 1 top; 0.5 on a floor or roof).
vec2 face_edge(Face f, out float grime, out float height) {
	vec2 to_edge = f.half_size - abs(f.p);
	float bevel = face_bevel(f);
	vec2 k = 1.0 - smoothstep(vec2(0.0), vec2(bevel), to_edge);
	grime = 0.0;
	height = 0.5;
	if (abs(f.n.y) < 0.5 && abs(f.b.y) > 0.5) {
		bool lower = (f.b.y > 0.0) == (f.p.y < 0.0);
		float h = lower ? to_edge.y : f.half_size.y * 2.0 - to_edge.y;
		height = clamp(h / (f.half_size.y * 2.0), 0.0, 1.0);
		float low = 1.0 - smoothstep(0.0, clamp(f.half_size.y * 0.7, 0.8, 9.0), h);
		grime = low * low;
		if (lower) {
			k.y = 0.0;
		}
	}
	// Thinner than a pixel and a half: fade it out rather than let it shimmer.
	return k * clamp(bevel / (f.px * 1.5), 0.0, 1.0);
}

// The face split into panels: a few across its short side, however big it is (walls:
// wider than tall, like dressed stone, every other course shifted half a block when
// `stagger` is set). Returns the distance in metres to the nearest seam between two
// panels (large if there's none near); `away` points along the face from that seam to
// here; `id` numbers this panel; `cell` is a panel's size in metres and `local` this
// point inside its panel (metres from its corner).
float face_panels(Face f, bool stagger, out vec2 away, out vec2 id, out vec2 cell, out vec2 local) {
	vec2 size = f.half_size * 2.0;
	float want = clamp(min(size.x, size.y) * 0.5, 3.0, 8.0);
	bool wall = abs(f.n.y) < 0.5;
	vec2 count = max(vec2(1.0), floor(size / (wall ? vec2(want * 1.5, want) : vec2(want)) + 0.5));
	cell = size / count;
	vec2 g = (f.p + f.half_size) / cell;
	float row = min(floor(g.y), count.y - 1.0);
	bool shifted = stagger && wall && count.y > 1.5 && count.x > 1.5 && mod(row, 2.0) > 0.5;
	if (shifted) {
		g.x += 0.5;
	}
	id = vec2(floor(g.x), row);
	local = fract(g) * cell;
	vec2 r = floor(g + 0.5);
	vec2 d = abs(g - r) * cell;
	// The first and last lines are the face's own edges, not seams.
	if (!shifted && (r.x < 0.5 || r.x > count.x - 0.5)) {
		d.x = 1000.0;
	}
	if (r.y < 0.5 || r.y > count.y - 0.5) {
		d.y = 1000.0;
	}
	away = d.x < d.y ? vec2(g.x > r.x ? 1.0 : -1.0, 0.0) : vec2(0.0, g.y > r.y ? 1.0 : -1.0);
	return min(d.x, d.y);
}

// A recessed line `half_width` metres either side of distance 0: x = how much groove is
// here (0..1), y = how much of the bevelled lip beside it. Both fade out when they'd be
// thinner than the pixels.
vec2 face_groove(float dist_m, float half_width, float lip_width, float px) {
	float groove = (1.0 - smoothstep(half_width, half_width + px, dist_m)) * clamp(half_width * 2.0 / px, 0.0, 1.0);
	float lip = (1.0 - smoothstep(half_width, half_width + lip_width, dist_m)) * clamp(lip_width / (px * 1.5), 0.0, 1.0);
	return vec2(groove, lip * (1.0 - groove));
}