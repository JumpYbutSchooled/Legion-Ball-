extends "res://scripts/weapons/simple_weapon.gd"
## JAMMER (Medical / Support): fire a beam that jams an opponent's weapons for a few
## seconds (and resets their current weapon's reload if it was mid-reload) - a hostile
## effect, so it isn't blocked between allies the way ordinary damage is. Doesn't jam
## another Jammer. 20s cooldown.

const JAM_TIME := 2.5
const RANGE := 90.0


func _build() -> void:
	cooldown = 20.0
	lock_on = true
	lock_radius_px = 18.0
	lock_range = RANGE
	crosshair_shape = "cross"
	add_blade(1.0, 30.0, {"arc_radius": 0.5, "tip": Vector3(0.6, 0.3, -2.2), "max_width": 0.16, "max_thickness": 0.1, "segments": 7})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just or not can_fire():
		return
	if not lock_target or not is_instance_valid(lock_target):
		manager.play_sound("ui_hover", ball().global_position, -8.0)
		return
	start_cooldown()
	var t := lock_target
	manager.apply_status(t, "jam", JAM_TIME)
	var w = t.get_node_or_null("Weapon")
	if w and w.call("slot_id", w.get("current")) != "jammer":
		var current = w.call("current_weapon")
		if current and current.has_method("manual_reload"):
			current.call("manual_reload")
	kick(0)
	manager.spawn_beam(tip(), (t.global_position - tip()).normalized(), tip().distance_to(t.global_position), 0.1, 0.2, 8.0, color)
	manager.play_sound("zap", tip(), -2.0)
