extends "res://scripts/weapons/simple_weapon.gd"
## BEAM LANCE (Marksman / Long Range): two long blades converging to a point far in front.
## Hold for a steady laser. Every tick on the same target it burns hotter (up to 5x);
## switch targets and it starts over. It overheats after 3s of firing.

@export var tick := 0.1
@export var base_damage := 0.3
@export var max_ramp := 5.0
@export var burn_time := 3.0

var heat := 0.0
var _tick := 0.0
var _ramp := 1.0
var _last: Object = null
var _firing := false


func _build() -> void:
	cooldown = 1.5
	lock_on = true
	crosshair_shape = "dot"
	var shape := {"arc_radius": 0.6, "tip": Vector3(-0.1, 0.0, -4.4), "max_width": 0.16, "max_thickness": 0.12, "segments": 11}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, shape)


func _crosshair_extra(info: Dictionary) -> void:
	info["meter"] = 1.0 - heat
	info["count"] = "x%.1f" % _ramp if _firing else ""


func _fire(pressed: bool, _just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	_firing = pressed and can_fire()
	if not _firing:
		heat = maxf(heat - delta / burn_time, 0.0)
		_ramp = 1.0
		_last = null
		return
	heat += delta / burn_time
	if heat >= 1.0:
		heat = 0.0
		start_cooldown()
		manager.play_sound("vent", global_position, -4.0)
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = tick
	var from := (tip(0) + tip(1)) * 0.5
	var dir: Vector3 = (target_point() - from).normalized()
	var hit: Dictionary = manager.raycast(from, from + dir * 700.0)
	var end: Vector3 = hit["position"] if not hit.is_empty() else from + dir * 700.0
	var collider: Object = hit["collider"] if not hit.is_empty() else null
	if collider and collider.has_method("take_hit"):
		_ramp = minf(_ramp + 0.25, max_ramp) if collider == _last else 1.0
		_last = collider
		manager.hit_object(collider, base_damage * _ramp, end, dir, 1.0)
	else:
		_ramp = 1.0
		_last = null
	manager.spawn_beam(from, dir, from.distance_to(end), lerpf(0.12, 0.4, (_ramp - 1.0) / (max_ramp - 1.0)), tick * 1.4, 8.0 + _ramp * 3.0, color)
	manager.spawn_light(end, 10.0 + _ramp * 6.0, 4.0, tick, color)


func _update(_delta: float) -> void:
	_set_param("charge_glow", heat * 2.0 if _firing else 0.0)


func refill() -> void:
	super.refill()
	heat = 0.0
