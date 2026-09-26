extends "res://scripts/weapons/simple_weapon.gd"
## SLIPSTREAM (Momentum / Speed): two long streamers trailing from the back. Hold to lay
## a glowing trail behind you (it lasts 4s): riding along it pushes you faster, and
## anyone else who crosses it gets cut. Loop it round a fight.

var _last := Vector3.INF
var _drop := 0.0


func _build() -> void:
	cooldown = 0.0
	crosshair_shape = "chevron"
	var shape := {"arc_radius": 0.4, "tip": Vector3(0.4, 0.2, 3.6), "max_width": 0.12, "max_thickness": 0.05, "segments": 10}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, shape)


func _fire(pressed: bool, _just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	if not pressed:
		_last = Vector3.INF
		return
	var here := ball().global_position + Vector3.DOWN * 0.4
	if _last == Vector3.INF:
		_last = here
		return
	_drop -= delta
	if _drop > 0.0 or here.distance_to(_last) < 2.0:
		return
	_drop = 0.12
	spawn("res://scripts/weapons/slip_trail.gd", {
		"position": _last, "to_point": here, "color": color, "lifetime": 6.0,
	})
	_last = here


func _update(_delta: float) -> void:
	_set_param("charge_glow", 1.5 if _was_pressed else 0.0)
