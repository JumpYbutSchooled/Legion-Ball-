extends "res://scripts/weapons/simple_weapon.gd"
## PIERCER (Marksman / Long Range): one thin blade low on the right, reaching far
## forward. Press for a three-round burst; every round punches straight through every
## player and target in a line (walls still stop it).

@export var damage := 3.0

var _burst := 0
var _burst_timer := 0.0


func _build() -> void:
	cooldown = 0.9
	lock_on = true
	lock_radius_px = 16.0
	crosshair_shape = "cross"
	add_blade(1.0, -20.0, {"arc_radius": 0.5, "tip": Vector3(0.6, -0.4, -5.0), "max_width": 0.1, "max_thickness": 0.08, "segments": 12})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	if _burst > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst -= 1
			_burst_timer = 0.08
			_round()
		return
	if just and can_fire():
		start_cooldown()
		_burst = 3
		_burst_timer = 0.0


func _round() -> void:
	kick(0)
	var from := tip()
	var dir: Vector3 = (target_point() - from).normalized()
	var shot := hitscan(from, dir, 900.0, damage, 6.0, true)
	tracer(from, shot["end"], 0.07, 9.0)
	flash_at(from, dir, 0.6)
	for hit in shot["hits"]:
		manager.spawn_beam(hit["position"], dir, 2.0, 0.3, 0.1, 16.0, color)
	manager.play_sound("zap", from, -2.0)
	manager.recoil(dir, 0.5)
