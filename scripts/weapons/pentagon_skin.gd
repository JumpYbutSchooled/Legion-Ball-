extends RefCounted
## Turns a blade's body (energy_blade_mesh.gd: a cross-section swept along a path) into the
## pentagon look: equal flat pentagons in a tidy grid over its whole surface, each lying on
## it, one corner pointing along the blade, mirror-symmetric top to bottom. The body itself
## isn't drawn, just the pentagons, by shaders/pentagon_blade.gdshader (which animates them:
## fire waves, equip / switch / put-away, the tail, their drift).
## Per vertex, as the shader reads it: UV = (along the blade 0 back .. 1 point, near the
## outline 1 .. 0 in the middle); UV2 = (0 at a pentagon's middle .. 1 at its rim, which
## blade: always 0, each blade has its own material); CUSTOM0 = the pentagon's centre and
## size; CUSTOM1 = its normal and its own random value (shared with its mirror image).
## Built once per blade shape and shared; a left blade wears the mirror image of its right.
## Every pentagon is the same size (corner radius, metres), laid in a tidy grid: rows evenly
## spaced along the blade, and in each row evenly spaced round its cross-section, every other
## row sitting between the last one's (like a honeycomb), the top half mirrored onto the
## bottom. STEP is the distance between neighbours' middles (times the size).
const SIZE := 0.032
const STEP := 2.5
static var _cache := {}
## The background thread's queue (warm()): key -> [path, rings], in order; the finished
## arrays, key -> arrays.
static var _queued := {}
static var _order: Array = []
static var _ready_arrays := {}
static var _lock := Mutex.new()
static var _wake := Semaphore.new()
static var _thread: Thread
static var _stop := false


## The pentagon mesh for a blade body swept along ``path`` (``rings``: its cross-section corners
## at each path point, corner 0 the outer side edge, going over the top), cached under ``key``.
static func skin(path: PackedVector3Array, rings: Array, key: String) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	# Worked out ahead of time on the background thread (warm()): just make the mesh. If it
	# hasn't got to this one yet, it's done here instead (and skipped there).
	_lock.lock()
	var arrays: Variant = _ready_arrays.get(key)
	_ready_arrays.erase(key)
	_queued.erase(key)
	_lock.unlock()
	if arrays == null:
		arrays = _compute(path, rings)
	var out := _finish(arrays)
	_cache[key] = out
	return out


## Queues blade `key`'s pentagons to be worked out on one low-priority background thread
## (one core, so the game itself never has to wait for a core), so skin() has nothing left
## to do.
static func warm(key: String, path: PackedVector3Array, rings: Array) -> void:
	_lock.lock()
	var known := _cache.has(key) or _queued.has(key) or _ready_arrays.has(key)
	if not known:
		_queued[key] = [path, rings]
		_order.append(key)
	_lock.unlock()
	if known:
		return
	if _thread == null:
		_thread = Thread.new()
		_thread.start(_work, Thread.PRIORITY_LOW)
	_wake.post()


## The background thread: works the queue until it's told to stop.
static func _work() -> void:
	while true:
		_wake.wait()
		while true:
			_lock.lock()
			if _stop:
				_lock.unlock()
				return
			var key := ""
			var job: Array = []
			while not _order.is_empty():
				key = _order.pop_front()
				if _queued.has(key):
					job = _queued[key]
					break
			_lock.unlock()
			if job.is_empty():
				break
			var arrays := _compute(job[0], job[1])
			_lock.lock()
			# Still wanted (skin() may have done it itself meanwhile).
			if _queued.has(key):
				_queued.erase(key)
				_ready_arrays[key] = arrays
			_lock.unlock()


## True once the background thread has nothing left queued.
static func reap() -> bool:
	_lock.lock()
	var idle := _queued.is_empty()
	_lock.unlock()
	return idle


## Stops the background thread (on quit).
static func shutdown() -> void:
	if _thread == null:
		return
	_lock.lock()
	_stop = true
	_lock.unlock()
	_wake.post()
	_thread.wait_to_finish()
	_thread = null

## The same pentagons mirrored onto the left (x flipped), cached too.
static func mirrored(right: ArrayMesh, key: String) -> ArrayMesh:
	var k := key + "|L"
	if _cache.has(k):
		return _cache[k]
	var out := ArrayMesh.new()
	if right.get_surface_count() > 0:
		var arrays := right.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var c0: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		var c1: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
		for i in v.size():
			v[i].x = -v[i].x
			n[i].x = -n[i].x
			c0[i * 4] = -c0[i * 4]
			c1[i * 4] = -c1[i * 4]
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
		out.custom_aabb = out.get_aabb().grow(0.6)
	_cache[k] = out
	return out


## The pentagons as mesh arrays (no engine objects made, so it can run on any thread).
static func _compute(path: PackedVector3Array, rings: Array) -> Array:
	var along := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		along.append(along[i - 1] + path[i].distance_to(path[i - 1]))
	var total := maxf(along[along.size() - 1], 0.001)
	var step := SIZE * STEP
	var row_step := step * 0.866
	var placed: Array = []  # [centre, normal, u, edge, length dir, seed]
	var d := row_step * 0.5
	var row := 0
	while d < total - row_step * 0.25:
		var i := clampi(along.bsearch(d) - 1, 0, path.size() - 2)
		var f := clampf((d - along[i]) / maxf(along[i + 1] - along[i], 1e-6), 0.0, 1.0)
		var centre := path[i].lerp(path[i + 1], f)
		var length_dir := (path[i + 1] - path[i]).normalized()
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		var n := r0.size()
		# The cross-section here, as a closed outline from the outer edge over the top.
		var ring := PackedVector3Array()
		for k in n:
			ring.append(r0[k].lerp(r1[k], f))
		ring.append(ring[0])
		var per := PackedFloat32Array([0.0])
		for k in n:
			per.append(per[k] + ring[k + 1].distance_to(ring[k]))
		var perim := per[n]
		var u := d / total
		var outward := ring[0] - centre
		var half_w := maxf(outward.length(), 0.0001)
		outward /= half_w
		if perim > SIZE * 0.6:
			var half := perim * 0.5
			var count := int(round(half / step))
			# Every other row has one on each side edge; the rows between sit between them.
			var on_rims := row % 2 == 1
			var spots: Array = []
			if count < 1:
				if not on_rims:
					spots.append(0.0)
			else:
				for k in (count + 1 if on_rims else count):
					spots.append((float(k) if on_rims else float(k) + 0.5) / count * half)
			for k in spots.size():
				var at: float = spots[k]
				var seed := fposmod(sin(row * 78.233 + k * 37.719) * 43758.5453, 1.0)
				# This spot over the top, and its mirror image underneath (one, on an edge).
				var both := [at] if at < 0.001 or absf(at - half) < 0.001 else [at, perim - at]
				for a in both:
					var spot := _on_outline(ring, per, a)
					var p: Vector3 = spot[0]
					var across := absf((p - centre).dot(outward)) / half_w
					var edge := smoothstep(0.55, 0.95, across)
					if u < 0.06 or u > 0.94:
						edge = 1.0
					placed.append([p, spot[1], u, edge, length_dir, seed])
		d += row_step
		row += 1
	# The mesh: each pentagon a flat fan, one corner pointing along the blade.
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	for e in placed:
		var c: Vector3 = e[0]
		var nn: Vector3 = e[1]
		var dir: Vector3 = e[4]
		var a := (dir - nn * dir.dot(nn))
		if a.length() < 0.05:
			a = Vector3.UP - nn * Vector3.UP.dot(nn)
		a = a.normalized()
		var b := nn.cross(a).normalized()
		var pent := PackedVector3Array()
		for k in 5:
			var ang := TAU * k / 5.0
			pent.append(c + (a * cos(ang) + b * sin(ang)) * SIZE)
		var face_uv := Vector2(e[2], e[3])
		var sd: float = e[5]
		for k in 5:
			for q in [[c, 0.0], [pent[k], 1.0], [pent[(k + 1) % 5], 1.0]]:
				v.append(q[0])
				nrm.append(nn)
				uv.append(face_uv)
				uv2.append(Vector2(q[1], 0.0))
				c0.append_array(PackedFloat32Array([c.x, c.y, c.z, SIZE]))
				c1.append_array(PackedFloat32Array([nn.x, nn.y, nn.z, sd]))
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = v
	out_arrays[Mesh.ARRAY_NORMAL] = nrm
	out_arrays[Mesh.ARRAY_TEX_UV] = uv
	out_arrays[Mesh.ARRAY_TEX_UV2] = uv2
	out_arrays[Mesh.ARRAY_CUSTOM0] = c0
	out_arrays[Mesh.ARRAY_CUSTOM1] = c1
	return out_arrays


## The mesh from _compute()'s arrays.
static func _finish(out_arrays: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	if (out_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return out
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays, [], {},
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	# Room for the pentagons' drift and the waves pushing them about.
	out.custom_aabb = out.get_aabb().grow(0.6)
	return out


## The point ``at`` metres round the closed outline ``ring`` (``per``: lengths to each corner),
## and the outline's outward normal there (at a corner, between its two sides').
static func _on_outline(ring: PackedVector3Array, per: PackedFloat32Array, at: float) -> Array:
	var n := ring.size() - 1
	var mid := Vector3.ZERO
	for k in n:
		mid += ring[k]
	mid /= n
	at = fposmod(at, per[n])
	var k := clampi(per.bsearch(at, false) - 1, 0, n - 1)
	var f := clampf((at - per[k]) / maxf(per[k + 1] - per[k], 1e-6), 0.0, 1.0)
	var p := ring[k].lerp(ring[k + 1], f)
	var side_n := func(j: int) -> Vector3:
		var e := ring[(j + 1) % n] - ring[j % n]
		var m := (ring[(j + 1) % n] + ring[j % n]) * 0.5 - mid
		var out := m - e * (m.dot(e) / maxf(e.length_squared(), 1e-12))
		return out.normalized() if out.length() > 1e-6 else m.normalized()
	var normal: Vector3 = side_n.call(k)
	if f < 0.02:
		normal = (normal + side_n.call((k - 1 + n) % n)).normalized()
	elif f > 0.98:
		normal = (normal + side_n.call((k + 1) % n)).normalized()
	return [p, normal]