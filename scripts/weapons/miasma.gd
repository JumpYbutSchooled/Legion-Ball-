extends "res://scripts/weapons/simple_weapon.gd"
## MIASMA (Medical / Support): throw a cloud of smoke that heals everyone inside it -
## friend or foe - splitting 5 HP/s among however many are in it. 30s recharge.

const RADIUS := 10.0
const LIFETIME := 6.0


func _build() -> void:
	cooldown = 30.0
	crosshair_shape = "ring"
	crosshair_radius = 16.0
	add_blade(1.0, 0.0, {"arc_radius": 0.45, "tip": Vector3(0.2, 0.5, -2.0), "max_width": 0.2, "max_thickness": 0.12, "segments": 7})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	var pos := target_point()
	spawn("res://scripts/weapons/miasma_cloud.gd", {"position": pos, "radius": RADIUS, "lifetime": LIFETIME})
	kick(0)
	manager.spawn_warp(pos, 0.3, 6.0)
	manager.play_sound("shield", pos, -2.0)
