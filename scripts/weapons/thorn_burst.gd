extends "res://scripts/weapons/simple_weapon.gd"
## THORN BURST (Brawler / Close Quarters): many tiny spikes all over the ball, pointing
## out. Hold to charge (0.8s), release: 120 shards burst out all round you (45m),
## hitting harder the longer you charged.

@export var charge_time := 0.8


func _build() -> void:
	cooldown = 1.0
	crosshair_shape = "ring"
	crosshair_radius = 20.0
	var shape := {"arc_radius": 0.15, "tip": Vector3(0.9, 0.3, -0.6), "max_width": 0.08, "max_thickness": 0.08, "segments": 3}
	for roll in [-150.0, -100.0, -50.0, 0.0, 50.0, 100.0, 150.0]:
		for side in [1.0, -1.0]:
			add_blade(side, roll, shape)


func _fire(pressed: bool, _just: bool, released: bool, _hit: Dictionary, delta: float) -> void:
	if pressed and can_fire():
		charge = minf(charge + delta / charge_time, 1.0)
	elif released and charge > 0.05:
		_burst()


func _update(_delta: float) -> void:
	_set_param("charge_spread", charge * 0.5)
	_set_param("charge_glow", charge * 1.8)


func _burst() -> void:
	var k := charge
	charge = 0.0
	start_cooldown()
	var center := ball().global_position
	for i in _blades.size():
		kick(i)
	var n := 40
	for i in n:
		var a := TAU * i / n
		for tilt in [-0.3, 0.0, 0.3]:
			var dir := Vector3(cos(a + tilt * 0.2), tilt, sin(a + tilt * 0.2)).normalized()
			var shot := hitscan(center + dir * 0.8, dir, 45.0, lerpf(1.0, 3.0, k), 6.0)
			manager.spawn_beam(center + dir * 0.8, dir, (center + dir * 0.8).distance_to(shot["end"]), 0.06, 0.1, 6.0, color)
	manager.spawn_light(center, 60.0, 12.0, 0.15, color)
	manager.spawn_warp(center, 0.2, 6.0)
	manager.play_sound("shotgun", center, 0.0)
	manager.shake(0.4)
