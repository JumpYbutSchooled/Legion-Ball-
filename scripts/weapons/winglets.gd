extends "res://scripts/weapons/simple_weapon.gd"
## WINGLETS (Skyborne / Mobility): two long flat wings straight out to the sides. In the
## air, press to flap: an extra jump (two per trip into the air, back on landing). Hold
## to glide: your fall is held to a gentle drift and you carry your speed.

@export var flap := 16.0
@export var glide_fall := 3.0

var _flaps := 2
var _gliding := false


func _build() -> void:
	cooldown = 0.2
	crosshair_shape = "chevron"
	var shape := {"arc_radius": 0.5, "tip": Vector3(3.0, 0.0, 0.4), "max_width": 0.35, "max_thickness": 0.06, "segments": 9}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, shape)


func _crosshair_extra(info: Dictionary) -> void:
	info["count"] = "x%d" % _flaps


func _fire(pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	var b := ball()
	var grounded: bool = not manager.raycast(b.global_position, b.global_position + Vector3.DOWN * 0.8).is_empty()
	if grounded:
		_flaps = 2
	if just and not grounded and _flaps > 0 and can_fire():
		_flaps -= 1
		start_cooldown()
		var v := b.linear_velocity
		manager.push_ball(Vector3(0.0, maxf(-v.y, 0.0) + flap, 0.0))
		for i in _blades.size():
			kick(i)
		manager.spawn_warp(b.global_position, 0.12, 2.5)
		manager.play_sound("jump", b.global_position, -2.0)
	_gliding = pressed and not grounded
	if _gliding and b.linear_velocity.y < -glide_fall:
		# Hold the fall to a drift: lift equal to the excess fall speed.
		b.linear_velocity.y = lerpf(b.linear_velocity.y, -glide_fall, 0.2)


func _update(_delta: float) -> void:
	_set_param("charge_spread", 0.25 if _gliding else 0.0)
	_set_param("charge_glow", 0.8 if _gliding else 0.0)


func refill() -> void:
	super.refill()
	_flaps = 2
