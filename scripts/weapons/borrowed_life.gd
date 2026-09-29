extends "res://scripts/weapons/simple_weapon.gd"
## BORROWED LIFE (Medical / Support): heal yourself now, pay it back later. Heals 25 HP
## right away; 20 seconds after, the same amount comes back out of you (never below 1 HP
## on its own - arena.gd _host_heal). 1 minute cooldown.

const AMOUNT := 25.0
const DELAY := 20.0


func _build() -> void:
	cooldown = 60.0
	crosshair_shape = "ring"
	add_blade(1.0, 0.0, {"arc_radius": 0.4, "tip": Vector3(0.3, 0.4, -2.2), "max_width": 0.16, "max_thickness": 0.1, "segments": 6})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	start_cooldown()
	var b := ball()
	var m := manager
	manager.heal(b, AMOUNT)
	kick(0)
	manager.spawn_light(b.global_position, 16.0, 5.0, 0.12, color)
	manager.play_sound("shield", b.global_position, 0.0)
	get_tree().create_timer(DELAY).timeout.connect(func() -> void:
		if is_instance_valid(b) and is_instance_valid(m) and b.call("is_alive"):
			m.heal(b, -AMOUNT))
