extends "res://scripts/weapons/simple_weapon.gd"
## HYPER DASH (Momentum / Speed): four blades swept back like a jet's wings. Hold to charge
## a super dash for 3 s (the meter fills); at full charge, release to launch where you're
## looking at top speed. You keep going (your dash and other weapons are off meanwhile)
## until you hit a wall or a player, and a big explosion goes off around you.

const CHARGE_TIME := 3.0
## The longest a super dash can last before it fizzles into a smaller blast.
const MAX_TIME := 3.5

var _rushing := false


func _build() -> void:
	cooldown = 8.0
	crosshair_shape = "chevron"
	var wing := {"arc_radius": 0.45, "tip": Vector3(1.3, 0.1, 1.2), "max_width": 0.22, "max_thickness": 0.12, "segments": 7}
	for side in [1.0, -1.0]:
		add_blade(side, 0.0, wing)
		add_blade(side, 180.0, wing)


func _crosshair_extra(info: Dictionary) -> void:
	info["meter"] = charge


func _update(_delta: float) -> void:
	_set_param("charge_glow", charge * 3.0)


func _fire(pressed: bool, _just: bool, released: bool, _hit: Dictionary, delta: float) -> void:
	if _rushing or not can_fire():
		charge = 0.0
		return
	if pressed:
		var was := charge
		charge = minf(charge + delta / CHARGE_TIME, 1.0)
		if was < 1.0 and charge >= 1.0:
			manager.play_sound("equip", ball().global_position, -2.0)
			manager.spawn_light(ball().global_position, 40.0, 6.0, 0.2, color)
	elif released:
		if charge >= 1.0:
			_launch()
		charge = 0.0


func _launch() -> void:
	start_cooldown()
	var b := ball()
	var dir := look_dir()
	_rushing = true
	if not b.is_connected("rush_ended", _on_rush_ended):
		b.connect("rush_ended", _on_rush_ended)
	b.call("start_rush", dir, float(b.get("top_speed")), MAX_TIME)
	for i in _blades.size():
		kick(i)
	manager.spawn_warp(b.global_position, 0.5, 8.0)
	manager.spawn_beam(b.global_position, -dir, 12.0, 0.8, 0.3, 14.0, color)
	manager.play_sound("rail", b.global_position, 2.0)
	manager.shake(0.8)


func _on_rush_ended(pos: Vector3, hit: Node3D, into_wall: bool) -> void:
	if not _rushing:
		return
	_rushing = false
	var big := hit != null or into_wall
	manager.spawn_explosion({
		"position": pos, "color": color, "radius": 14.0 if big else 8.0, "damage": 10.0 if big else 5.0,
		"force": 70.0 if big else 35.0, "spark_count": 420 if big else 180, "chunk_count": 40,
		"light_energy": 320.0, "warp_strength": 0.5, "sound": "boom",
	})
	if hit and hit.has_method("take_hit"):
		manager.hit_object(hit, 6.0, pos, ball().linear_velocity.normalized(), 60.0)
	manager.shake(1.0)
