extends Label3D
## Floating damage number for the local shooter: how much a hit did and how far away it
## was ("32  18m"). Hits on the same target in quick succession (Scatter pellets, Gatling
## bursts) add into one number that pops each time it grows. Rises and fades, then frees
## itself. Damage is shown as it would be against a player (practice targets included).
## Spawned by the weapon manager (weapon.gd, report_damage).

## Seconds a number keeps collecting hits before it starts to float away.
const MERGE_TIME := 0.25
const LIFETIME := 1.1

var target: Object
var total := 0.0
var distance := 0.0
var color := Color.WHITE

var _t := 0.0
var _pop := 0.0
var _base: Vector3


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.0016
	font_size = 30
	outline_size = 10
	outline_modulate = Color(0.02, 0.02, 0.05, 0.9)
	render_priority = 10
	top_level = true
	_base = position
	_refresh()


## Another hit on the same target: add it on and restart the merge window.
func add(amount: float, dist: float) -> void:
	total += amount
	distance = dist
	_t = minf(_t, MERGE_TIME * 0.5)
	_pop = 1.0
	_refresh()


func can_merge() -> bool:
	return _t < MERGE_TIME


func _refresh() -> void:
	text = "%d  %dm" % [roundi(total), roundi(distance)]
	# Bigger hits read hotter: white -> yellow -> red.
	var heat := clampf(total / 100.0, 0.0, 1.0)
	modulate = color.lerp(Color(1.0, 0.85, 0.2), clampf(heat * 2.0, 0.0, 1.0)).lerp(Color(1.0, 0.25, 0.2), clampf(heat * 2.0 - 1.0, 0.0, 1.0))


func _process(delta: float) -> void:
	_t += delta
	_pop = move_toward(_pop, 0.0, delta * 6.0)
	var rise := maxf(_t - MERGE_TIME, 0.0)
	global_position = _base + Vector3.UP * (0.6 + rise * 1.6)
	pixel_size = 0.0016 * (1.0 + _pop * 0.5)
	modulate.a = clampf((LIFETIME - _t) / 0.3, 0.0, 1.0)
	if _t >= LIFETIME:
		queue_free()
