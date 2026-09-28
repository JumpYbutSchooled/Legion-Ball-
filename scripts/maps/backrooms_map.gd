extends "res://scripts/maps/map_builder.gd"
## "The Backrooms": seven levels stacked on top of each other, joined up, going on forever.
##   Level 0   The Lobby            yellow wallpaper, damp carpet, humming lights
##   Level 1   Habitable Zone       bare concrete, pillars, puddles, crates
##   Level 2   Pipe Dreams          cramped dark corridors lined with pipes
##   Level 3   Electrical Station   brick halls full of humming machines
##   Level 4   Abandoned Office     cubicles, desks, blue carpet
##   Level 5   Terror Hotel         long red-carpeted corridors, doors, sconces
##   Level 37  The Poolrooms        white tiles, warm water, pools everywhere
## Each level repeats sideways forever (a WIDTH block that loops, see map_builder.gd).
## Glitching holes in every floor drop you down into the level below; stairwells climb
## back up. Fall through the Poolrooms' drains and you land back in the Lobby: it loops
## top to bottom too. The fog and light shift to each level's colours, and its name
## comes up as you arrive.

const SteamScript := preload("res://scripts/steam.gd")

const WIDTH := 192.0
const HALF := WIDTH / 2.0
const CELL := 12.0
const CELLS := 16
## Each level's layer, top to bottom; the whole stack loops every LAYER * LEVELS.
const LAYER := 16.0
const NAMES := ["LEVEL 0  //  THE LOBBY", "LEVEL 1  //  HABITABLE ZONE", "LEVEL 2  //  PIPE DREAMS",
	"LEVEL 3  //  ELECTRICAL STATION", "LEVEL 4  //  ABANDONED OFFICE", "LEVEL 5  //  TERROR HOTEL",
	"LEVEL 37  //  THE POOLROOMS"]
const LEVELS := 7
## Ceiling height of each level.
const CEILINGS := [9.0, 11.0, 7.5, 9.0, 8.5, 9.0, 13.0]
## Fog and ambient colour of each level (blended as you move between them).
const FOG := [Color(0.62, 0.57, 0.34), Color(0.42, 0.42, 0.4), Color(0.2, 0.14, 0.1), Color(0.3, 0.2, 0.18),
	Color(0.4, 0.45, 0.5), Color(0.35, 0.12, 0.1), Color(0.75, 0.88, 0.95)]
const AMBIENT := [Color(1.0, 0.94, 0.7), Color(0.75, 0.75, 0.72), Color(0.6, 0.42, 0.3), Color(0.75, 0.6, 0.55),
	Color(0.7, 0.78, 0.9), Color(0.85, 0.45, 0.35), Color(0.95, 1.0, 1.0)]

## Per level: [floor, wall, wall 2, ceiling, light panel, trim] materials.
var _mats: Array = []
## Holes from level k down into level k + 1 (the last one's lead back to level 0): cells.
var _drops: Array = []
## Stairwells up from level k + 1 into level k: the two cells the stairs run through.
var _stairs: Array = []
var _pools := {}  # Poolrooms: cells that are pools.
var _level_label: Label
var _shown_level := -1
var _env: Environment
var _label_fade := 0.0
## Levels the player has been on (all seven: the NO_CLIP achievement).
var _visited := {}


func is_indoor() -> bool:
	return true


## Only the neighbouring blocks on the same level are drawn (each level is closed in).
func wrap_visual_offsets() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for off in _wrap_offsets():
		if off.y == 0.0:
			out.append(off)
	return out


func wrap_view_range() -> float:
	return 150.0


## Top of the floor of level `k`.
func floor_y(k: int) -> float:
	return LAYER * LEVELS / 2.0 - LAYER * (k + 1) + 1.0


func _build() -> void:
	_wrap = Vector3(WIDTH, LAYER * LEVELS, WIDTH)
	_ceiling = 1.0e6
	_fall = -1.0e6
	_outline = rect_outline(Rect2(-HALF, -HALF, WIDTH, WIDTH))
	_rng.seed = 8008
	_make_materials()
	_plan_links()
	for k in LEVELS:
		_build_level(k)
	var taken := {}
	for k in LEVELS:
		for c in _floor_holes(k):
			taken[c] = true
		for c in _ceiling_holes(k):
			taken[c] = true
	var i := 0
	while _spawns.size() < 8 and i < 200:
		var c := Vector2i((2 + i * 5) % CELLS, (3 + i * 7) % CELLS)
		i += 1
		if not taken.has(c):
			_spawns.append(_cell_centre(c, floor_y(0) + 1.0))


func _make_materials() -> void:
	_mats = [
		[checker(Color(0.5, 0.43, 0.27), Color(0.47, 0.4, 0.25), 1.2), panel(Color(0.8, 0.74, 0.44), Color(0.72, 0.66, 0.38), 1.5),
			solid(Color(0.76, 0.7, 0.42), 0.95), checker(Color(0.86, 0.84, 0.74), Color(0.8, 0.78, 0.68), 3.0),
			glow(Color(1.0, 0.98, 0.85), 3.5), solid(Color(0.6, 0.52, 0.34), 0.8)],
		[checker(Color(0.45, 0.45, 0.44), Color(0.42, 0.42, 0.41), 4.0), solid(Color(0.58, 0.58, 0.56), 0.9),
			solid(Color(0.5, 0.5, 0.48), 0.9), solid(Color(0.4, 0.4, 0.4), 0.9),
			glow(Color(1.0, 0.85, 0.6), 2.5), solid(Color(0.55, 0.42, 0.25), 0.8)],
		[checker(Color(0.2, 0.2, 0.2), Color(0.17, 0.17, 0.17), 2.0), solid(Color(0.28, 0.27, 0.26), 0.6, 0.4),
			solid(Color(0.24, 0.22, 0.2), 0.6, 0.4), solid(Color(0.15, 0.14, 0.13), 0.8),
			glow(Color(1.0, 0.5, 0.2), 2.5), solid(Color(0.55, 0.3, 0.15), 0.4, 0.7)],
		[checker(Color(0.35, 0.33, 0.32), Color(0.32, 0.3, 0.29), 3.0), panel(Color(0.45, 0.2, 0.15), Color(0.35, 0.16, 0.12), 1.0),
			solid(Color(0.42, 0.2, 0.15), 0.9), solid(Color(0.25, 0.25, 0.26), 0.8),
			glow(Color(0.7, 0.85, 1.0), 3.0), solid(Color(0.4, 0.42, 0.45), 0.4, 0.6)],
		[checker(Color(0.3, 0.36, 0.45), Color(0.28, 0.33, 0.42), 1.0), solid(Color(0.85, 0.85, 0.82), 0.8),
			solid(Color(0.55, 0.58, 0.6), 0.8), checker(Color(0.88, 0.88, 0.86), Color(0.82, 0.82, 0.8), 2.0),
			glow(Color(0.9, 0.95, 1.0), 3.0), solid(Color(0.45, 0.35, 0.25), 0.7)],
		[checker(Color(0.45, 0.06, 0.06), Color(0.4, 0.05, 0.05), 1.5), panel(Color(0.3, 0.17, 0.1), Color(0.24, 0.13, 0.08), 2.0),
			solid(Color(0.85, 0.78, 0.6), 0.8), solid(Color(0.8, 0.74, 0.58), 0.8),
			glow(Color(1.0, 0.65, 0.35), 2.5), solid(Color(0.25, 0.13, 0.07), 0.6)],
		[checker(Color(0.95, 0.97, 0.98), Color(0.82, 0.92, 0.96), 1.5), checker(Color(0.96, 0.97, 0.98), Color(0.85, 0.93, 0.97), 1.5),
			solid(Color(0.92, 0.95, 0.96), 0.2), checker(Color(0.96, 0.97, 0.98), Color(0.88, 0.94, 0.97), 1.5),
			glow(Color(0.9, 1.0, 1.0), 2.0), glow(Color(0.3, 0.75, 0.95), 0.9)],
	]


## Which cells hold the holes down and the stairwells up, per level. Kept apart from
## each other so a level's hole never lands on a stairwell.
func _plan_links() -> void:
	var taken := {}
	for k in LEVELS:
		var drops: Array[Vector2i] = []
		while drops.size() < 3:
			var c := Vector2i(_rng.randi_range(1, CELLS - 2), _rng.randi_range(1, CELLS - 2))
			if not taken.has(c):
				taken[c] = true
				drops.append(c)
		_drops.append(drops)
	for k in LEVELS - 1:
		while true:
			var c := Vector2i(_rng.randi_range(1, CELLS - 3), _rng.randi_range(1, CELLS - 2))
			var d := c + Vector2i(1, 0)
			if not taken.has(c) and not taken.has(d):
				taken[c] = true
				taken[d] = true
				_stairs.append([c, d])
				break
	for i in 26:
		var c := Vector2i(_rng.randi_range(0, CELLS - 1), _rng.randi_range(0, CELLS - 1))
		if not taken.has(c):
			_pools[c] = true


func _cell_centre(c: Vector2i, y: float) -> Vector3:
	return Vector3(-HALF + (c.x + 0.5) * CELL, y, -HALF + (c.y + 0.5) * CELL)


## Cells missing from level k's floor (holes down, the stairwell from below).
func _floor_holes(k: int) -> Dictionary:
	var holes := {}
	for c in _drops[k]:
		holes[c] = true
	if k < _stairs.size():
		for c in _stairs[k]:
			holes[c] = true
	return holes


## Cells missing from level k's ceiling (where the level above drops into it, and its
## stairwell up).
func _ceiling_holes(k: int) -> Dictionary:
	var holes := {}
	for c in _drops[posmod(k - 1, LEVELS)]:
		holes[c] = true
	if k >= 1:
		for c in _stairs[k - 1]:
			holes[c] = true
	return holes


## A slab over every cell of the level except `holes`: one box per run of cells along
## each row.
func _slab(y: float, thick: float, mat: Material, holes: Dictionary, minimap: bool) -> void:
	for row in CELLS:
		var start := -1
		for col in CELLS + 1:
			var solid_cell := col < CELLS and not holes.has(Vector2i(col, row))
			if solid_cell and start < 0:
				start = col
			elif not solid_cell and start >= 0:
				var x0 := -HALF + start * CELL
				var x1 := -HALF + col * CELL
				box(Vector3((x0 + x1) / 2.0, y, -HALF + (row + 0.5) * CELL), Vector3(x1 - x0, thick, CELL), mat, 0.0, 0.0, minimap)
				start = -1


func _build_level(k: int) -> void:
	var m: Array = _mats[k]
	var y := floor_y(k)
	var h: float = CEILINGS[k]
	var floor_holes := _floor_holes(k)
	var pools := k == LEVELS - 1
	var skip_floor := floor_holes.duplicate()
	if pools:
		for c in _pools:
			skip_floor[c] = true
	_slab(y - 0.5, 1.0, m[0], skip_floor, true)
	_slab(y + h + 0.5, 1.0, m[3], _ceiling_holes(k), false)
	if pools:
		# Pools: the floor drops 2 m, with warm water filling them.
		for c in _pools:
			if floor_holes.has(c):
				continue
			var p := _cell_centre(c, y - 2.5)
			box(p, Vector3(CELL, 1.0, CELL), m[1])
			deco(p + Vector3(0, 1.6, 0), Vector3(CELL, 0.1, CELL), m[5])
	# Glitchy edges round the holes down: a dark flicker you can see coming.
	var glitch := glow(Color(0.35, 0.15, 0.6), 2.0)
	for c in _drops[k]:
		var p := _cell_centre(c, y + 0.05)
		for s: float in [-1.0, 1.0]:
			deco(p + Vector3(s * CELL / 2.0, 0, 0), Vector3(0.4, 0.1, CELL), glitch)
			deco(p + Vector3(0, 0, s * CELL / 2.0), Vector3(CELL, 0.1, 0.4), glitch)
	# The stairs up from this level into the one above.
	if k >= 1:
		var pair: Array = _stairs[k - 1]
		var a := _cell_centre(pair[0], y)
		var rise := floor_y(k - 1) - y
		stairs(Vector3(a.x - CELL / 2.0 + 0.5, y, a.z), Vector2(1, 0), 20, rise / 20.0, (CELL * 2.0 - 1.0) / 20.0, CELL - 2.0, m[5])
	var reserved := {}
	for c in floor_holes:
		reserved[c] = true
	for c in _ceiling_holes(k):
		reserved[c] = true
	match k:
		0: _maze(k, y, h, 0.42, 0.08, reserved)
		1: _habitable(k, y, h, reserved)
		2: _pipes(k, y, h, reserved)
		3: _electrical(k, y, h, reserved)
		4: _office(k, y, h, reserved)
		5: _hotel(k, y, h, reserved)
		6: _poolrooms(k, y, h, reserved)
	# Light panels on the ceiling (some dead).
	for i in CELLS:
		for j in CELLS:
			var c := Vector2i(i, j)
			if reserved.has(c) or _rng.randf() > 0.8:
				continue
			deco(_cell_centre(c, y + h - 0.05), Vector3(2.4, 0.1, 1.2), m[4])


## Does a wall along a cell edge touch a reserved cell (a hole or a stairwell)?
func _touches(reserved: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	return reserved.has(a) or reserved.has(b)


func _edge_wall(k: int, y: float, h: float, a: Vector2, b: Vector2, doorway: float) -> void:
	var m: Array = _mats[k]
	var mat: Material = m[1] if _rng.randf() < 0.7 else m[2]
	if _rng.randf() < doorway:
		var d := (b - a) / 3.0
		var top := minf(6.5, h - 1.0)
		wall(a, a + d, y, h, 0.5, mat)
		wall(b - d, b, y, h, 0.5, mat)
		wall(a + d, b - d, y + top, h - top, 0.5, mat)
	else:
		wall(a, b, y, h, 0.5, mat)
	var mid := (a + b) / 2.0
	deco(Vector3(mid.x, y + 0.3, mid.y), Vector3((b - a).length(), 0.6, 0.7), m[5], -(b - a).angle())


## The classic maze: any cell edge might be a wall, some with doorways; a few pillars.
func _maze(k: int, y: float, h: float, wall_chance: float, pillar_chance: float, reserved: Dictionary) -> void:
	for i in CELLS:
		for j in CELLS:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var here := Vector2i(i, j)
			if _rng.randf() < wall_chance and not _touches(reserved, here, Vector2i(i, j - 1)):
				_edge_wall(k, y, h, Vector2(x, z), Vector2(x + CELL, z), 0.35)
			if _rng.randf() < wall_chance and not _touches(reserved, here, Vector2i(i - 1, j)):
				_edge_wall(k, y, h, Vector2(x, z), Vector2(x, z + CELL), 0.35)
			if _rng.randf() < pillar_chance and not reserved.has(here):
				pillar(Vector2(x + CELL / 2.0, z + CELL / 2.0), y, 2.2, h, _mats[k][1])


## Level 1: big concrete halls: fewer walls, thick pillars, puddles and crates.
func _habitable(k: int, y: float, h: float, reserved: Dictionary) -> void:
	_maze(k, y, h, 0.18, 0.0, reserved)
	var puddle := glow(Color(0.35, 0.5, 0.6), 0.5)
	var crate := solid(Color(0.55, 0.4, 0.22), 0.8)
	for i in CELLS:
		for j in CELLS:
			var c := Vector2i(i, j)
			if reserved.has(c):
				continue
			var p := _cell_centre(c, y)
			var roll := _rng.randf()
			if roll < 0.25:
				pillar(Vector2(p.x, p.z), y, 3.0, h, _mats[k][1])
			elif roll < 0.35:
				deco(p + Vector3(_rng.randf_range(-3, 3), 0.05, _rng.randf_range(-3, 3)), Vector3(_rng.randf_range(3, 6), 0.05, _rng.randf_range(2, 5)), puddle)
			elif roll < 0.45:
				box(p + Vector3(0, 1.5, 0), Vector3(3.0, 3.0, 3.0), crate, _rng.randf())
				box(p + Vector3(0.5, 4.0, 0), Vector3(2.0, 2.0, 2.0), crate, _rng.randf())


## Level 2: tight corridors, pipes running along the walls.
func _pipes(k: int, y: float, h: float, reserved: Dictionary) -> void:
	_maze(k, y, h, 0.55, 0.0, reserved)
	var pipe: Material = _mats[k][5]
	for j in CELLS:
		for i in CELLS:
			if reserved.has(Vector2i(i, j)) or _rng.randf() > 0.35:
				continue
			var p := _cell_centre(Vector2i(i, j), y)
			for level: float in [h - 0.8, h - 1.8]:
				deco(p + Vector3(0, level, -CELL / 2.0 + 0.8), Vector3(CELL, 0.5, 0.5), pipe)
			deco(p + Vector3(-CELL / 2.0 + 0.8, h / 2.0, 0), Vector3(0.4, h, 0.4), pipe)


## Level 3: brick halls with machines humming in them.
func _electrical(k: int, y: float, h: float, reserved: Dictionary) -> void:
	_maze(k, y, h, 0.32, 0.0, reserved)
	var metal := solid(Color(0.45, 0.47, 0.5), 0.4, 0.7)
	var lamp_on := glow(Color(0.3, 1.0, 0.4), 4.0)
	var lamp_warn := glow(Color(1.0, 0.25, 0.2), 4.0)
	for i in CELLS:
		for j in CELLS:
			var c := Vector2i(i, j)
			if reserved.has(c) or _rng.randf() > 0.3:
				continue
			var p := _cell_centre(c, y)
			var size := Vector3(_rng.randf_range(3, 5), _rng.randf_range(3, 6), _rng.randf_range(2, 4))
			box(p + Vector3(0, size.y / 2.0, 0), size, metal, _rng.randi_range(0, 3) * PI / 2.0)
			deco(p + Vector3(0, size.y + 0.2, 0), Vector3(0.4, 0.4, 0.4), lamp_on if _rng.randf() < 0.7 else lamp_warn)


## Level 4: open-plan office: cubicles (low partitions), desks, the odd full wall.
func _office(k: int, y: float, h: float, reserved: Dictionary) -> void:
	_maze(k, y, h, 0.12, 0.0, reserved)
	var partition := solid(Color(0.55, 0.6, 0.65), 0.9)
	var desk := solid(Color(0.6, 0.48, 0.32), 0.7)
	for i in CELLS:
		for j in CELLS:
			var c := Vector2i(i, j)
			if reserved.has(c):
				continue
			var p := _cell_centre(c, y)
			wall(Vector2(p.x - CELL / 2.0 + 1.0, p.z - CELL / 2.0 + 1.0), Vector2(p.x + CELL / 2.0 - 1.0, p.z - CELL / 2.0 + 1.0), y, 3.0, 0.3, partition)
			wall(Vector2(p.x - CELL / 2.0 + 1.0, p.z - CELL / 2.0 + 1.0), Vector2(p.x - CELL / 2.0 + 1.0, p.z + 2.0), y, 3.0, 0.3, partition)
			box(p + Vector3(-2.0, 1.2, -3.0), Vector3(4.0, 0.3, 2.0), desk)
			box(p + Vector3(-2.0, 0.6, -3.0), Vector3(3.6, 1.2, 0.3), desk)


## Level 5: long hotel corridors (every other row of edges walled, with gaps), doors
## along them, sconces.
func _hotel(k: int, y: float, h: float, reserved: Dictionary) -> void:
	var door := solid(Color(0.35, 0.18, 0.08), 0.6)
	var brass := glow(Color(1.0, 0.7, 0.3), 3.0)
	for j in CELLS:
		if j % 2 == 1:
			continue
		for i in CELLS:
			if _rng.randf() < 0.12 or _touches(reserved, Vector2i(i, j), Vector2i(i, j - 1)):
				continue
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			wall(Vector2(x, z), Vector2(x + CELL, z), y, h, 0.6, _mats[k][1])
			for s: float in [-1.0, 1.0]:
				deco(Vector3(x + CELL / 2.0, y + 3.5, z + s * 0.35), Vector3(3.0, 7.0, 0.1), door)
				deco(Vector3(x + CELL / 2.0 + 2.8, y + 6.0, z + s * 0.4), Vector3(0.4, 0.6, 0.2), brass)


## The Poolrooms: white tiled halls with pools sunk into the floor, arches between them.
func _poolrooms(k: int, y: float, h: float, reserved: Dictionary) -> void:
	for i in CELLS:
		for j in CELLS:
			var c := Vector2i(i, j)
			if reserved.has(c) or _pools.has(c) or _rng.randf() > 0.3:
				continue
			var p := _cell_centre(c, y)
			for sx: float in [-1.0, 1.0]:
				pillar(Vector2(p.x + sx * (CELL / 2.0 - 1.0), p.z - CELL / 2.0 + 1.0), y, 1.6, h, _mats[k][1])
			box(p + Vector3(0, h - 2.0, -CELL / 2.0 + 1.0), Vector3(CELL - 0.4, 1.6, 1.6), _mats[k][1])


## Every frame (not on the server): shift the fog and light to the level the camera's on,
## and put its name up when it changes.
func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	if _env == null:
		var world := get_tree().current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if not world:
			return
		_env = world.environment
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_make_label()
	var level := clampi(int((LAYER * LEVELS / 2.0 - cam.global_position.y) / LAYER), 0, LEVELS - 1)
	var t := 1.0 - exp(-2.0 * delta)
	_env.fog_light_color = _env.fog_light_color.lerp(FOG[level], t)
	_env.ambient_light_color = _env.ambient_light_color.lerp(AMBIENT[level], t)
	if level != _shown_level:
		_shown_level = level
		_visited[level] = true
		if _visited.size() == LEVELS:
			SteamScript.achieve(get_tree(), "NO_CLIP")
		_level_label.text = NAMES[level]
		_label_fade = 4.0
	_label_fade = maxf(_label_fade - delta, 0.0)
	_level_label.modulate.a = clampf(_label_fade, 0.0, 1.0)


func _make_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_level_label = Label.new()
	_level_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_level_label.position = Vector2(-400, 150)
	_level_label.custom_minimum_size = Vector2(800, 0)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 30)
	_level_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_level_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_level_label)
