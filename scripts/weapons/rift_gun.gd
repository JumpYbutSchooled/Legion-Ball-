extends "res://scripts/weapons/simple_weapon.gd"
## RIFT GUN (Riftworks / Rifts, its own category): two Gatling blades, teal on the left and
## magenta on the right. Left click opens the TEAL rift on whatever surface you aim at, right
## click (or LT) the MAGENTA one; a new one replaces the old one of that colour. Roll into
## either and come out of the other at the same speed. Practice only for now: online it
## doesn't fire.

const Rift := preload("res://scripts/weapons/rift.gd")
const TEAL := Color(0.1, 0.95, 0.8)
const MAGENTA := Color(0.95, 0.15, 0.85)
const RANGE := 400.0

var _rifts := [null, null]


func _build() -> void:
	cooldown = 0.25
	crosshair_shape = "ring"
	crosshair_radius = 9.0
	kick_open = 0.14
	# Two Gatling blades: blue on the left (left click), orange on the right (right click).
	add_blade(-1.0, 0.0)
	add_blade(1.0, 0.0)


func _update(_delta: float) -> void:
	# Each blade its own colour (the base gives every blade the weapon's colour).
	for i in _blades.size():
		var mat := _blades[i].material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("color", TEAL if i == 0 else MAGENTA)

func _crosshair_extra(info: Dictionary) -> void:
	if _online():
		info["count"] = "PRACTICE ONLY"
	else:
		info["count"] = "%s %s" % ["TEAL" if _alive(0) else "-", "MAGENTA" if _alive(1) else "-"]


func _online() -> bool:
	var net := get_tree().root.get_node_or_null("Net")
	return net != null and net.get("online")


func _alive(i: int) -> bool:
	return _rifts[i] != null and is_instance_valid(_rifts[i])


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if _online() or not can_fire():
		return
	var which := -1
	if just:
		which = 0
	elif Input.is_action_just_pressed("fire_alt") or Input.is_action_just_pressed("reload"):
		which = 1
	if which < 0:
		return
	start_cooldown()
	var from: Vector3 = manager.camera.global_position if manager.camera else ball().global_position
	var hit: Dictionary = manager.raycast(from, from + look_dir() * RANGE)
	var colour: Color = TEAL if which == 0 else MAGENTA
	kick(which)
	if hit.is_empty() or not hit["collider"] is StaticBody3D:
		manager.play_sound("ui_hover", ball().global_position, -6.0)
		return
	var frame := Rift.frame_for(hit["position"], hit["normal"], look_dir(), get_world_3d().direct_space_state)
	var old = _rifts[which]
	if old and is_instance_valid(old):
		old.queue_free()
	var rift := Rift.new()
	rift.color = colour
	rift.ball = ball()
	rift.transform = frame
	ball().get_parent().add_child(rift)
	_rifts[which] = rift
	var other = _rifts[1 - which]
	if other and is_instance_valid(other):
		rift.partner = other
		other.partner = rift
	manager.spawn_beam(tip(0), (hit["position"] - tip(0)).normalized(), tip(0).distance_to(hit["position"]), 0.12, 0.2, 8.0, colour)
	manager.spawn_warp(hit["position"], 0.3, 6.0)
	manager.play_sound("zap", hit["position"], -2.0)


## Rifts go when the weapon's owner leaves the map (they're not networked).
func _exit_tree() -> void:
	for p in _rifts:
		if p and is_instance_valid(p):
			p.queue_free()
