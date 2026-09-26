extends "res://scripts/weapons/simple_weapon.gd"
## ECHO RIFLE (Hunter / Mark): two parallel blades stacked on the right, one above the
## other. Semi-auto hitscan; every hit rings out again one second later for part of the
## damage (a delayed double tap), wherever the target has gone.
## A small magazine: empty it and it reloads (T reloads early).

@export var damage := 2.0
## The echo deals this fraction of the shot's damage.
@export var echo_fraction := 0.5
@export var magazine := 5
@export var reload_time := 2.4

var _ammo := 5
var _reload := 0.0


func _build() -> void:
	cooldown = 0.6
	lock_on = true
	lock_radius_px = 14.0
	crosshair_shape = "ring"
	_ammo = magazine
	var shape := {"arc_radius": 0.7, "tip": Vector3(0.45, 0.0, -3.0), "max_width": 0.14, "max_thickness": 0.12, "segments": 9}
	add_blade(1.0, 14.0, shape)
	add_blade(1.0, -14.0, shape)


## Reloading keeps going even while another weapon is out.
func _update(delta: float) -> void:
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			_reload = 0.0
			_ammo = magazine
			if is_ready():
				flash(color)
	_set_param("reload_break", clampf(_reload / reload_time, 0.0, 1.0))


func _crosshair_extra(info: Dictionary) -> void:
	info["ready"] = can_fire() and _reload == 0.0
	info["count"] = "RELOAD" if _reload > 0.0 else "%d/%d" % [_ammo, magazine]
	info["meter"] = 1.0 - _reload / reload_time if _reload > 0.0 else float(_ammo) / magazine


func manual_reload() -> void:
	if _reload == 0.0 and _ammo < magazine:
		_reload = reload_time
		manager.play_sound("vent", global_position, -8.0)


func refill() -> void:
	super.refill()
	_ammo = magazine
	_reload = 0.0


func _fire(pressed: bool, _just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not pressed or not can_fire() or _reload > 0.0:
		return
	start_cooldown()
	_ammo -= 1
	if _ammo <= 0:
		_reload = reload_time
	var i := randi() % 2
	kick(i)
	var from := tip(i)
	var dir: Vector3 = (target_point() - from).normalized()
	var shot := hitscan(from, dir, 900.0, damage, 5.0)
	tracer(from, shot["end"], 0.08, 6.0)
	flash_at(from, dir, 0.6)
	manager.play_sound("zap", from, -6.0)
	for hit in shot["hits"]:
		var target: Object = hit["collider"]
		if target.has_method("take_hit"):
			get_tree().create_timer(1.0).timeout.connect(_echo.bind(target))


## The echo: part of the hit again, a second later.
func _echo(target: Object) -> void:
	if not is_instance_valid(target) or not target.call("is_alive") or not manager:
		return
	var p: Vector3 = target.call("get_aim_point")
	manager.hit_object(target, damage * echo_fraction, p, Vector3.UP, 3.0)
	manager.spawn_light(p, 25.0, 5.0, 0.15, color)
	manager.spawn_warp(p, 0.1, 2.0)
	manager.play_sound("zap", p, -4.0)
