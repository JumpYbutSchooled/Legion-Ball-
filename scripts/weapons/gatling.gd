extends "res://scripts/weapons/blade_weapon.gd"
## Slot 1: six-blade hitscan gatling. Three crescent blades on each side, rolled at
## different angles round the ball like a barrel cluster. Hold fire to shoot; blades go
## top right, top left, middle right, middle left, bottom right, bottom left, repeat.
## Each shot: tracer, muzzle flare + warp bubble + light, bright impact flare + light,
## damage via take_hit(), a shove on rigid bodies, a little kickback and camera shake.
## Magazine: after `magazine` shots it reloads by itself, playing the railgun's reload
## (broken apart, purple to blue, reforming with a flash).

## Emitted on every shot with the index of the blade that fired (firing order).
signal fired(blade_index: int)

## Roll of each blade row round the forward axis, in degrees: top, middle, bottom.
## Mirrored for the left side. Bottom is shallower so those blades clear the floor.
@export var row_angles := PackedFloat32Array([40.0, 0.0, -28.0])
@export var fire_interval := 0.06
@export var damage := 0.6
## Full damage out to falloff_start metres, dropping to falloff_min at falloff_end.
@export var falloff_start := 50.0
@export var falloff_end := 180.0
@export var falloff_min := 0.4
## Impulse given to rigid bodies that get hit.
@export var hit_impulse := 4.0
## Impulse pushing the ball backward per shot.
@export var recoil_impulse := 0.35
## Camera shake added per shot (0..1 trauma).
@export var shot_shake := 0.3
## Small lock-on circle (pixels): a target inside it gets every shot, like the railgun.
@export var lock_radius_px := 16.0
## Targets further than this can't be locked (you can still hit them by aiming).
## Unlimited: anyone you can see, however far.
@export var lock_range := INF
## Shots per magazine (about 1.8s of fire), and seconds to reload.
@export var magazine := 30
@export var reload_time := 1.6
@export var reload_start_color := Color(0.65, 0.2, 1.0)
@export var reload_end_color := Color(0.2, 0.45, 1.0)
@export var reload_flash_color := Color(0.25, 0.55, 1.0)

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
var lock_target: Node3D = null
var lock_screen_pos := Vector2.ZERO
var ammo := 30
var reloading := false
## 0..1 while reloading.
var reload := 0.0


func _build() -> void:
	# Each blade's tip flicks open a little as it fires.
	kick_open = 0.14
	ammo = magazine
	# Row by row, right then left, which is also the firing order.
	for angle in row_angles:
		for side in [1.0, -1.0]:
			add_blade(side, angle)


func handle_fire(pressed: bool, hit: Dictionary, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	lock_target = null
	if is_ready():
		var found: Array = manager.targets_on_screen(lock_radius_px, lock_range, true)
		if not found.is_empty():
			lock_target = found[0]["target"]
			lock_screen_pos = found[0]["screen"]
	if pressed and is_ready() and _cooldown == 0.0 and not reloading:
		_fire(hit)


## The reload keeps going even while another weapon is out.
func _update(delta: float) -> void:
	if reloading:
		reload = minf(reload + delta / reload_time, 1.0)
		if reload >= 1.0:
			reloading = false
			reload = 0.0
			ammo = magazine
			if is_ready():
				flash(reload_flash_color)
	_set_param("reload_break", 1.0 - reload if reloading else 0.0)
	_set_param("override_amount", 1.0 if reloading else 0.0)
	_set_param("override_color", reload_start_color.lerp(reload_end_color, reload))


func _equip_flash_color() -> Color:
	if reloading:
		return reload_start_color.lerp(reload_end_color, reload)
	return color


func get_crosshair() -> Dictionary:
	return {
		"kind": "gatling",
		"radius": lock_radius_px,
		"locked": lock_target != null and is_instance_valid(lock_target),
		"lock_pos": lock_screen_pos,
		"ammo": float(ammo) / magazine,
		"reloading": reloading,
		"reload": reload,
	}


func _fire(hit: Dictionary) -> void:
	_cooldown = fire_interval
	var index := _next
	_next = (_next + 1) % _blades.size()
	kick(index)
	fired.emit(index)

	var blade := _blades[index]
	var tip: Vector3 = blade.to_global(blade.call("get_tip"))
	var aim: Vector3 = manager.aim_point
	if lock_target and is_instance_valid(lock_target):
		# Locked: aim straight at it; whatever is actually in the way takes the hit.
		aim = lock_target.call("get_aim_point")
		var to := (aim - tip).normalized()
		hit = manager.raycast(tip, aim + to * 0.5)
		if not hit.is_empty():
			aim = hit["position"]
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
		var falloff := lerpf(1.0, falloff_min, clampf(inverse_lerp(falloff_start, falloff_end, tip.distance_to(pos)), 0.0, 1.0))
		manager.hit_object(hit["collider"], damage * falloff, pos, shot_dir, hit_impulse * falloff)

	# Recoil from the ball's middle: a blade tip can be past a spot on the floor right in
	# front of you, and measuring from there pushed you forward.
	manager.recoil(aim - manager.ball.global_position, recoil_impulse)
	manager.shake(shot_shake)
	manager.play_sound("zap", tip, -8.0)
	ammo -= 1
	if ammo <= 0:
		_start_reload()


func _start_reload() -> void:
	reloading = true
	reload = 0.0
	manager.play_sound("vent", global_position, -8.0)


## T: reload a part-used magazine early.
func manual_reload() -> void:
	if not reloading and ammo < magazine:
		_start_reload()


func get_net_reload() -> float:
	return reload if reloading else -1.0


## Other players' reload: start it and follow its progress (it finishes, with the flash,
## in _update like our own).
func apply_net_reload(value: float) -> void:
	if value >= 0.0:
		reloading = true
		reload = value
