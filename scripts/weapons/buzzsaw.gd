extends "res://scripts/weapons/simple_weapon.gd"
## BUZZSAW (Brawler / Close Quarters): eight small blades in a flat disc round the
## middle. Hold to spin them up: anyone who touches you (2.4m) gets shredded several
## times a second, harder the faster you're going. Ram people.

var _spin := 0.0
var _speed := 0.0
var _tick := 0.0


func _build() -> void:
	cooldown = 0.0
	crosshair_shape = "ring"
	crosshair_radius = 18.0
	var shape := {"arc_radius": 0.35, "tip": Vector3(1.5, 0.0, 0.0), "max_width": 0.2, "max_thickness": 0.05, "segments": 4}
	for i in 4:
		for side in [1.0, -1.0]:
			add_blade(side, 0.0, shape)


func _crosshair_extra(info: Dictionary) -> void:
	info["charge"] = _speed


func _fire(pressed: bool, _just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	_speed = move_toward(_speed, 1.0 if pressed else 0.0, delta * (3.0 if pressed else 1.5))
	if _speed < 0.5:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.15
	var b := ball()
	var dmg := 0.5 + b.linear_velocity.length() / 40.0
	for t in targets_near(b.global_position, 2.4):
		var p: Vector3 = t.call("get_aim_point")
		manager.hit_object(t, dmg, p, (p - b.global_position).normalized(), 8.0)
		manager.spawn_beam(p, (p - b.global_position).normalized(), 1.0, 0.4, 0.08, 16.0, color)
	if fmod(Time.get_ticks_msec() / 1000.0, 0.45) < 0.16:
		manager.play_sound("zap", b.global_position, -12.0)


func _update(delta: float) -> void:
	# The disc turns flat round the ball; spun up, it's a blur.
	_spin += delta * lerpf(1.5, 30.0, _speed)
	for i in _blades.size():
		var a := _spin + TAU * i / _blades.size()
		_blades[i].transform = Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
	_set_param("charge_glow", _speed * 1.6)
