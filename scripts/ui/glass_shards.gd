extends RefCounted
## A pane of glass breaking, for 2D UI (the speedometer's tier shatter, the start screen's
## buttons). build() cracks a shape the way real glass goes: cracks running out from the
## impact point, crossed by rough rings, so the shards are small near the hit and big at
## the edges. draw() shows it at progress k (0..1): first the cracks flash across the
## still-whole pane, then the shards burst outward, tumbling (a fake 3D flip that catches
## the light as they turn edge-on), with bright edges and glitter, and fade as they fall.
## Run k backwards and it reassembles. Each shard can carry its own piece of a picture
## (draw()'s texture: e.g. the old dial), so what was there is what breaks.

## Share of k spent on the crack flash before anything moves.
const CRACK := 0.1
const GRAVITY := 900.0

## Each: {poly: points round its centre, uv: matching texture coords (0..1 of the
## region's box), at: centre, vel, spin, flip (radians per k), axis (flip direction), glint}
var shards: Array = []
## Crack lines for the flash: [from, to, how far out (0..1)].
var cracks: Array = []
## Glitter: [from, velocity, size, phase].
var sparks: Array = []
var _box := Rect2()


## Crack `region` (a polygon, local coords) from `impact`. `power` scales how far the
## pieces fly; `spokes` / `rings` how finely it breaks.
func build(region: PackedVector2Array, impact: Vector2, power := 1.0, spokes := 13, rings := 4) -> void:
	shards.clear()
	cracks.clear()
	sparks.clear()
	_box = Rect2(region[0], Vector2.ZERO)
	for p in region:
		_box = _box.expand(p)
	var reach := 0.0
	for p in region:
		reach = maxf(reach, p.distance_to(impact))
	reach *= 1.15
	# Cracks out from the hit at uneven angles; rings at growing gaps (finer near the hit).
	var angles: Array[float] = []
	var a := randf() * TAU
	for i in spokes:
		angles.append(a)
		a += TAU / spokes * randf_range(0.55, 1.45)
	var total := a - angles[0]
	for i in angles.size():
		angles[i] = angles[0] + (angles[i] - angles[0]) * TAU / total
	var radii: Array[float] = [0.0]
	for r in rings:
		var k := float(r + 1) / rings
		radii.append(reach * pow(k, 1.35) * randf_range(0.9, 1.08))
	radii[-1] = reach
	# Each spoke's crack wanders a little at every ring (so they aren't ruler-straight).
	var bends: Array = []
	for i in spokes:
		var row: Array[Vector2] = []
		for r in radii.size():
			var ang := angles[i] + (randf_range(-0.12, 0.12) if r > 0 else 0.0)
			row.append(impact + Vector2.from_angle(ang) * radii[r])
		bends.append(row)
	for i in spokes:
		var j := (i + 1) % spokes
		for r in rings:
			var cell := PackedVector2Array()
			var inner_a: Vector2 = bends[i][r]
			var inner_b: Vector2 = bends[j][r]
			var outer_a: Vector2 = bends[i][r + 1]
			var outer_b: Vector2 = bends[j][r + 1]
			cell.append(inner_a)
			cell.append(outer_a)
			# The ring's crack between two spokes bows and kinks.
			var mid := (outer_a + outer_b) * 0.5
			cell.append(mid + (mid - impact).normalized() * radii[r + 1] * randf_range(-0.06, 0.08))
			cell.append(outer_b)
			if r > 0:
				cell.append(inner_b)
			# Big outer cells split once more along a rough diagonal.
			var pieces: Array = [cell]
			if r >= rings - 2 and randf() < 0.7:
				pieces = _split(cell)
			for piece in pieces:
				for clipped in Geometry2D.intersect_polygons(piece, region):
					_add_shard(clipped, impact, reach, power)
		# The flash: this spoke's crack, ring by ring.
		for r in rings:
			cracks.append([bends[i][r], bends[i][r + 1], float(r) / rings])
	# Glitter thrown off the hit.
	for s in int(22 * power):
		var dir := Vector2.from_angle(randf() * TAU)
		sparks.append([impact + dir * randf_range(0.0, reach * 0.25), dir * randf_range(180.0, 520.0) * power, randf_range(1.0, 2.6), randf() * TAU])


## Halves a cell along a line between two of its edges.
func _split(cell: PackedVector2Array) -> Array:
	var c := Vector2.ZERO
	for p in cell:
		c += p
	c /= cell.size()
	var dir := Vector2.from_angle(randf() * PI)
	var far := 10000.0
	var side := PackedVector2Array([c + dir * far, c + dir * far + dir.orthogonal() * far,
		c - dir * far + dir.orthogonal() * far, c - dir * far])
	var a := Geometry2D.intersect_polygons(cell, side)
	var b := Geometry2D.clip_polygons(cell, side)
	if a.is_empty() or b.is_empty():
		return [cell]
	return [a[0], b[0]]


func _add_shard(poly: PackedVector2Array, impact: Vector2, reach: float, power: float) -> void:
	if poly.size() < 3:
		return
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var local := PackedVector2Array()
	var uv := PackedVector2Array()
	for p in poly:
		local.append(p - c)
		uv.append((p - _box.position) / _box.size.max(Vector2.ONE))
	var out := (c - impact)
	var near := 1.0 - clampf(out.length() / reach, 0.0, 1.0)
	# Pieces by the hit fly hardest; everything kicks up a little.
	var vel := out.normalized() * randf_range(230.0, 480.0) * (0.55 + near) * power + Vector2(randf_range(-60, 60), randf_range(-260, -60)) * power
	shards.append({"poly": local, "uv": uv, "at": c, "vel": vel, "spin": randf_range(-7.0, 7.0) * (0.5 + near),
		"flip": randf_range(4.0, 11.0), "axis": Vector2.from_angle(randf() * TAU), "glint": randf() * TAU})


## Signed area of a polygon (shoelace).
static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return a * 0.5


## Draws the break at progress `k` on `ci`, around `origin`. `tint`: the glass colour.
## With `texture`, each shard shows its piece of it (stretched over the region's box).
func draw(ci: CanvasItem, origin: Vector2, k: float, tint: Color, texture: Texture2D = null) -> void:
	k = clampf(k, 0.0, 1.0)
	var crack := clampf(k / CRACK, 0.0, 1.0)
	var fly := clampf((k - CRACK) / (1.0 - CRACK), 0.0, 1.0)
	var t := fly  # seconds of flight it stands for (keeps the fall's shape)
	var fade := 1.0 - smoothstep(0.45, 1.0, fly)
	var light := Vector2(-0.6, -0.8)
	for s in shards:
		var poly: PackedVector2Array = s["poly"]
		var at: Vector2 = origin + s["at"] + s["vel"] * t + Vector2(0.0, GRAVITY) * t * t * 0.5
		var rot: float = s["spin"] * t
		# Fake 3D tumble: squash along a turning axis; edge-on it flashes.
		var flip := cos(s["flip"] * t)
		var axis: Vector2 = s["axis"]
		var pts := PackedVector2Array()
		for p in poly:
			var q := p.rotated(rot)
			var along := q.dot(axis)
			q += axis * along * (flip - 1.0)
			pts.append(at + q * (1.0 - fly * 0.55))
		var edge_on := 1.0 - absf(flip)
		var glint := pow(edge_on, 3.0) * (0.6 + 0.4 * sin(s["glint"] + t * 20.0)) if fly > 0.0 else 0.0
		# Full strength while whole (tint.a), a little see-through when turned.
		var face := Color(tint, tint.a * fade * (0.7 + 0.3 * absf(flip)))
		var lit := face.lerp(Color(1, 1, 1, face.a), clampf(glint, 0.0, 0.8))
		# Edge-on (or squashed flat) there's no face to fill, just the glinting edge below;
		# filling it would fail (a polygon with no area).
		var fillable := absf(flip) > 0.08 and pts.size() >= 3 and absf(_area(pts)) > 1.0
		if fillable and texture:
			var shine := 1.0 + glint * 0.8
			ci.draw_colored_polygon(pts, Color(shine, shine, shine, fade), s["uv"], texture)
			# A light glass sheen over the picture.
			ci.draw_colored_polygon(pts, Color(1, 1, 1, 0.06 * fade + glint * 0.35 * fade))
		elif fillable:
			ci.draw_colored_polygon(pts, lit)
		# Edges: bright on the side facing the light, thin elsewhere; the crack flash runs
		# along them before they move.
		for i in pts.size():
			var a2: Vector2 = pts[i]
			var b2: Vector2 = pts[(i + 1) % pts.size()]
			var n := (b2 - a2).orthogonal().normalized()
			var facing := clampf(n.dot(light) * 0.5 + 0.5, 0.0, 1.0)
			var alpha := fade * (0.1 + 0.45 * facing * facing + glint * 0.7)
			if fly <= 0.0:
				alpha = crack * 0.9
			ci.draw_line(a2, b2, Color(1, 1, 1, alpha), 1.0 + facing * 0.6, true)
	# The crack flash: lines racing out from the hit, then gone as it bursts.
	if crack < 1.0 or fly < 0.15:
		var flash := (1.0 - fly / 0.15) if fly > 0.0 else crack
		for c in cracks:
			var shown := clampf(crack * 1.4 - float(c[2]), 0.0, 1.0)
			if shown <= 0.0:
				continue
			var a3: Vector2 = origin + c[0]
			var b3: Vector2 = a3.lerp(origin + c[1], shown)
			ci.draw_line(a3, b3, Color(1, 1, 1, flash), 2.0, true)
	# Glitter.
	for sp in sparks:
		var p: Vector2 = origin + sp[0] + sp[1] * t + Vector2(0.0, GRAVITY * 0.6) * t * t * 0.5
		var tw := 0.5 + 0.5 * sin(sp[3] + t * 30.0)
		var size: float = sp[2] * (0.6 + tw)
		var col := Color(1, 1, 1, fade * tw * (1.0 if fly > 0.0 else 0.0))
		if col.a <= 0.01:
			continue
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -size * 2.0), p + Vector2(size * 0.6, 0),
			p + Vector2(0, size * 2.0), p + Vector2(-size * 0.6, 0)]), col)
