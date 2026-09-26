extends "res://scripts/weapons/simple_weapon.gd"
## WINGLETS (Skyborne / Mobility): two long flat wings straight out to the sides. In the
## air, press to flap: an extra jump (three per trip into the air, back on landing). Hold
## to glide: your fall is held to a slow drift and you pick up speed the way you look,
## steering with the camera.

@export var flap := 22.0
@export var glide_fall := 1.5
@export var flaps := 3
## Forward speed gained per second while gliding, up to glide_speed.
@export var glide_accel := 30.0
@export var glide_speed := 70.0

var _flaps := 3
var _gliding := false


func _build() -> void:
	cooldown = 0.2
	crosshair_shape = "chevron"
	var shape := {"arc_radius": 0.5, "tip": Vector3(3.0, 0.0, 0.4), "max_width": 0.35, "max_thickness": 0.06, "segments": 9}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, shape)


func _crosshair_extra(info: Dictionary) -> void:
	info["count"] = "x%d" % _flaps


func _fire(pressed: bool, just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	var b := ball()
	var grounded: bool = not manager.raycast(b.global_position, b.global_position + Vector3.DOWN * 0.8).is_empty()
	if grounded:
		_flaps = flaps
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
	if _gliding:
		# Glide the way the camera looks: carve round toward it and speed up.
		var look := look_dir()
		var flat := Vector3(look.x, 0.0, look.z)
		if flat.length() > 0.01:
			flat = flat.normalized()
			var v := b.linear_velocity
			var ground_v := Vector3(v.x, 0.0, v.z)
			var speed := minf(maxf(ground_v.length(), 20.0) + glide_accel * delta, maxf(glide_speed, ground_v.length()))
			var turned := ground_v.normalized().slerp(flat, minf(delta * 3.0, 1.0)) if ground_v.length() > 1.0 else flat
			b.linear_velocity = Vector3(turned.x * speed, v.y, turned.z * speed)


func _update(_delta: float) -> void:
	_set_param("charge_spread", 0.25 if _gliding else 0.0)
	_set_param("charge_glow", 0.8 if _gliding else 0.0)


func refill() -> void:
	super.refill()
	_flaps = flaps
