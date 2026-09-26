extends "res://scripts/weapons/simple_weapon.gd"
## ECHO RIFLE (Hunter / Mark): two parallel blades stacked on the right, one above the
## other. Semi-auto hitscan; every hit rings out again one second later for the same
## damage (a delayed double tap), wherever the target has gone.

@export var damage := 3.0


func _build() -> void:
	cooldown = 0.35
	lock_on = true
	crosshair_shape = "ring"
	var shape := {"arc_radius": 0.7, "tip": Vector3(0.45, 0.0, -3.0), "max_width": 0.14, "max_thickness": 0.12, "segments": 9}
	add_blade(1.0, 14.0, shape)
	add_blade(1.0, -14.0, shape)


func _fire(pressed: bool, _just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not pressed or not can_fire():
		return
	start_cooldown()
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


## The echo: the same hit again, a second later.
func _echo(target: Object) -> void:
	if not is_instance_valid(target) or not target.call("is_alive") or not manager:
		return
	var p: Vector3 = target.call("get_aim_point")
	manager.hit_object(target, damage, p, Vector3.UP, 3.0)
	manager.spawn_light(p, 25.0, 5.0, 0.15, color)
	manager.spawn_warp(p, 0.1, 2.0)
	manager.play_sound("zap", p, -4.0)
