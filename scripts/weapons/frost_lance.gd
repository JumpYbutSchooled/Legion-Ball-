extends "res://scripts/weapons/simple_weapon.gd"
## FROST LANCE (Frost / Control): one long needle under the ball, pointing straight
## ahead. Hold to charge (1s), release to fire a freezing beam: damage grows with charge,
## every hit CHILLS (40% slower for 3s), and a full charge also FREEZES for 1s.

@export var charge_time := 1.0
@export var damage_min := 2.0
@export var damage_max := 6.0


func _build() -> void:
	cooldown = 0.8
	crosshair_shape = "diamond"
	add_blade(1.0, 0.0, {"arc_radius": 0.5, "tip": Vector3(0.0, -0.75, -4.6), "max_width": 0.12, "max_thickness": 0.1, "segments": 12})


func _fire(pressed: bool, _just: bool, released: bool, _hit: Dictionary, delta: float) -> void:
	if pressed and can_fire():
		charge = minf(charge + delta / charge_time, 1.0)
	elif released and charge > 0.05:
		_release()


func _update(_delta: float) -> void:
	_set_param("charge_glow", charge * charge * 2.0)
	_set_param("charge_spread", charge * 0.2)


func _release() -> void:
	var k := charge
	charge = 0.0
	start_cooldown()
	kick(0)
	var from := tip()
	var dir: Vector3 = (manager.aim_point - from).normalized()
	var shot := hitscan(from, dir, 300.0, lerpf(damage_min, damage_max, k), 8.0)
	tracer(from, shot["end"], lerpf(0.15, 0.45, k), lerpf(6.0, 18.0, k))
	flash_at(from, dir, 0.8 + k)
	for hit in shot["hits"]:
		status(hit["collider"], "chill", 3.0, Vector3(0.6, 0, 0))
		if k >= 0.99:
			status(hit["collider"], "freeze", 1.0)
		manager.spawn_light(hit["position"], 30.0, 6.0, 0.2, color)
	manager.play_sound("rail" if k >= 0.99 else "zap", from, -4.0)
	manager.shake(0.2 + k * 0.4)
