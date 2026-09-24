extends "res://scripts/weapons/blade_weapon.gd"
## Slot 1: six-blade hitscan gatling. Three crescent blades on each side, rolled at
## different angles round the ball like a barrel cluster. Hold fire to shoot; blades go
## top right, top left, middle right, middle left, bottom right, bottom left, repeat.
## Each shot: tracer, muzzle flare + warp bubble + light, bright impact flare + light,
## damage via take_hit(), a shove on rigid bodies, a little kickback and camera shake.

## Emitted on every shot with the index of the blade that fired (firing order).
signal fired(blade_index: int)

## Roll of each blade row round the forward axis, in degrees: top, middle, bottom.
## Mirrored for the left side. Bottom is shallower so those blades clear the floor.
@export var row_angles := PackedFloat32Array([40.0, 0.0, -28.0])
@export var fire_interval := 0.06
@export var damage := 1.0
## Impulse given to rigid bodies that get hit.
@export var hit_impulse := 4.0
## Impulse pushing the ball backward per shot.
@export var recoil_impulse := 0.35
## Camera shake added per shot (0..1 trauma).
@export var shot_shake := 0.3

@export_group("Muzzle")
@export var flash_energy := 40.0
@export var muzzle_intensity := 14.0
@export var muzzle_warp_strength := 0.08

@export_group("Impact")
@export var impact_intensity := 20.0
@export var impact_size := 0.35
@export var impact_light_energy := 25.0

var _next := 0
var _cooldown := 0.0


func _build() -> void:
	# Each blade's tip flicks open a little as it fires.
	kick_open = 0.14
	# Row by row, right then left, which is also the firing order.
	for angle in row_angles:
		for side in [1.0, -1.0]:
			add_blade(side, angle)


func handle_fire(pressed: bool, hit: Dictionary, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if pressed and is_ready() and _cooldown == 0.0:
		_fire(hit)


func get_crosshair() -> Dictionary:
	return {"kind": "gatling"}


func _fire(hit: Dictionary) -> void:
	_cooldown = fire_interval
	var index := _next
	_next = (_next + 1) % _blades.size()
	kick(index)
	fired.emit(index)

	var blade := _blades[index]
	var tip: Vector3 = blade.to_global(blade.call("get_tip"))
	var aim: Vector3 = manager.aim_point
	var shot_dir := (aim - tip).normalized()

	# Tracer.
	manager.spawn_beam(tip, shot_dir, tip.distance_to(aim), 0.1, 0.1, 3.0, color)
	# Muzzle flare: a long forward spike plus two short angled ones, a warp bubble and a light.
	var up := global_basis.y
	manager.spawn_beam(tip, shot_dir, 1.3, 0.7, 0.06, muzzle_intensity, color)
	manager.spawn_beam(tip, shot_dir.rotated(up, deg_to_rad(50)), 0.55, 0.3, 0.05, muzzle_intensity, color)
	manager.spawn_beam(tip, shot_dir.rotated(up, deg_to_rad(-50)), 0.55, 0.3, 0.05, muzzle_intensity, color)
	manager.spawn_warp(tip, muzzle_warp_strength, 1.0)
	manager.spawn_light(tip, flash_energy, 12.0, 0.07, color)

	if not hit.is_empty():
		var pos: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		# Small, hot star burst round the surface normal.
		manager.spawn_beam(pos, normal, impact_size, impact_size * 0.7, 0.07, impact_intensity, color)
		for i in 2:
			var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
			var d := (normal + jitter * 0.8).normalized()
			manager.spawn_beam(pos, d, impact_size * 0.7, impact_size * 0.5, 0.06, impact_intensity, color)
		manager.spawn_light(pos + normal * 0.2, impact_light_energy, 5.0, 0.07, color)
		manager.hit_object(hit["collider"], damage, pos, shot_dir, hit_impulse)

	manager.recoil(shot_dir, recoil_impulse)
	manager.shake(shot_shake)
