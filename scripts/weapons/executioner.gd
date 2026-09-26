extends "res://scripts/weapons/simple_weapon.gd"
## EXECUTIONER (Hunter / Mark): one broad cleaver held high behind the ball, edge
## forward. Press to lunge and chop everything in front of you (6m): a heavy hit that
## does TRIPLE damage to anyone below 30% health.

@export var damage := 6.0
var _swing_in := -1.0


func _build() -> void:
	cooldown = 1.2
	crosshair_shape = "chevron"
	crosshair_radius = 14.0
	add_blade(1.0, 70.0, {"arc_radius": 1.1, "tip": Vector3(0.2, 1.3, -2.6), "max_width": 0.6, "max_thickness": 0.22, "segments": 10})


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	if _swing_in >= 0.0:
		_swing_in -= delta
		if _swing_in < 0.0:
			_chop()
	if just and can_fire():
		start_cooldown()
		# Lunge first; the chop lands a moment later.
		manager.push_ball(aim_dir() * 45.0 + Vector3.UP * 3.0)
		_swing_in = 0.15
		manager.play_sound("dash", ball().global_position, -6.0)


func _chop() -> void:
	kick(0)
	var center := ball().global_position
	var fwd := aim_dir()
	for t in targets_near(center, 9.0):
		var p: Vector3 = t.call("get_aim_point")
		if (p - center).normalized().dot(fwd) < 0.2:
			continue
		var dmg := damage * (3.0 if _low_health(t) else 1.0)
		manager.hit_object(t, dmg, p, fwd, 20.0)
		manager.spawn_beam(p, Vector3.UP, 2.5, 1.0, 0.2, 24.0, color)
	# The cleaver's arc.
	for i in 5:
		var a := lerpf(-0.9, 0.9, i / 4.0)
		var d := fwd.rotated(Vector3.UP, a)
		manager.spawn_beam(center + d * 1.5, d, 4.0, 0.5, 0.12, 12.0, color)
	manager.play_sound("shotgun", center, -2.0)
	manager.shake(0.5)


## Below 30% health: a player (the arena's synced health) or a practice target.
func _low_health(t: Node) -> bool:
	var scene := get_tree().current_scene
	if t.has_method("is_blocking") and scene and "health" in scene:
		var id := t.get_multiplayer_authority()
		var full: float = scene.call("max_health_of", id) if scene.has_method("max_health_of") else 100.0
		return float(scene.get("health").get(id, full)) < full * 0.3
	if "_health" in t and "max_health" in t:
		return float(t.get("_health")) < float(t.get("max_health")) * 0.3
	return false
