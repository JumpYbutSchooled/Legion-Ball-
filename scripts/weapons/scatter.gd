extends "res://scripts/weapons/blade_weapon.gd"
## Slot 3: Scatter, a crystal shotgun that runs on heat. Four short blades splayed low.
## Each shot throws a cone of hitscan pellets (strongest up close, fading with range),
## centred on any target you can see inside the crosshair circle (aim assist),
## and kicks the ball the opposite way to where you look, including up and down:
## look at the floor and fire to shotgun-jump.
## Heat: every shot adds heat; it bleeds off shortly after you stop firing. As it heats,
## the facets get excited and stretch forward toward the tip, glowing white-hot.
## Hit 100% and it OVERHEATS: locked out while it vents all the way back to cold,
## playing the railgun's reload (broken apart, purple to blue, reforming with a flash).
## Hold to fire as fast as it allows.
## Combos: pull in with Tether and fire point-blank; jump with it and follow with Nova.

@export var pellets := 10
## Cone half-angle, in degrees.
@export var spread_deg := 3.5
## Aim assist: if a target you can see is within this many degrees of the crosshair, the
## whole cone is centred on it. Shown as the crosshair circle.
@export var assist_deg := 9.0
## Slow, pump-action pace: every shot can kill up close.
@export var fire_interval := 0.7
@export var max_range := 120.0

@export_group("Heat")
## Heat added per shot (1 = overheated): 0.34 gives three shots.
@export var heat_per_shot := 0.34
## Heat lost per second once you've stopped firing for cool_delay seconds.
@export var cool_rate := 0.6
@export var cool_delay := 0.3
## Heat lost per second while venting an overheat (all the way to 0).
@export var vent_rate := 0.5
@export var hot_color := Color(1.0, 0.45, 0.12)
## How far the facets spread out and slide forward at full heat.
@export var heat_spread := 0.22
@export var heat_extend := 0.9
## Overheat venting looks like the railgun's reload.
@export var reload_start_color := Color(0.65, 0.2, 1.0)
@export var reload_end_color := Color(0.2, 0.45, 1.0)
@export var reload_flash_color := Color(0.25, 0.55, 1.0)
@export_group("")
## 10 pellets x 2.6 = a one-shot on a player at point-blank if every pellet lands.
@export var pellet_damage := 2.6
## Pellets do full damage up to falloff_start, falling to falloff_min by falloff_end
## (and staying there out to max_range).
@export var falloff_start := 15.0
@export var falloff_end := 70.0
@export var falloff_min := 0.25
@export var pellet_impulse := 6.0
## Ball velocity change per shot, opposite the way the camera is looking.
@export var self_knockback := 8.0
@export var shot_shake := 0.5
@export var muzzle_intensity := 16.0
@export var flash_energy := 50.0

## 0 cold .. 1 overheated.
var heat := 0.0
var overheated := false
var _cooldown := 0.0
var _since_shot := 0.0
## 1 right after a shot, easing to 0: the crosshair's spread bloom.
var _bloom := 0.0


func _build() -> void:
	var shape := {
		"arc_radius": 0.8,
		"tip": Vector3(0.3, 0.0, -2.2),
		"max_width": 0.3,
		"max_thickness": 0.22,
		"segments": 8,
	}
	for angle in [18.0, -22.0]:
		for side in [1.0, -1.0]:
			add_blade(side, angle, shape)


func handle_fire(pressed: bool, _hit: Dictionary, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if pressed and is_ready() and not overheated and _cooldown == 0.0:
		_fire()


## Heat keeps cooling even while another weapon is out.
func _update(delta: float) -> void:
	_bloom = move_toward(_bloom, 0.0, delta / fire_interval * 0.5)
	_since_shot += delta
	if overheated:
		heat = move_toward(heat, 0.0, vent_rate * delta)
		if heat == 0.0:
			overheated = false
			if is_ready():
				flash(reload_flash_color)  # Reformed, like the railgun's reload.
	elif _since_shot > cool_delay:
		heat = move_toward(heat, 0.0, cool_rate * delta)

	if overheated:
		# Railgun-style reload while venting: fully broken apart and shaking, purple
		# turning blue, pulling back together as the heat drains.
		var progress := 1.0 - heat
		_set_param("override_color", reload_start_color.lerp(reload_end_color, progress))
		_set_param("override_amount", 1.0)
		_set_param("reload_break", heat)
		_set_param("charge_spread", 0.0)
		_set_param("charge_glow", 0.0)
		_set_param("extend", 0.0)
	else:
		# Heating up: the facets get excited (spread and jitter toward the tip) and
		# stretch forward, glowing toward white-hot.
		var glow := pow(heat, 1.5)
		_set_param("override_color", hot_color)
		_set_param("override_amount", clampf(glow * 1.1, 0.0, 1.0))
		_set_param("reload_break", 0.0)
		_set_param("charge_spread", glow * heat_spread)
		_set_param("charge_glow", glow * 1.5)
		_set_param("extend", glow * heat_extend)


## Equipping it while it vents flashes the vent colour.
func _equip_flash_color() -> Color:
	if overheated:
		return reload_start_color.lerp(reload_end_color, 1.0 - heat)
	return color


func get_crosshair() -> Dictionary:
	return {
		"kind": "scatter",
		"radius": manager.angle_to_pixels(assist_deg),
		"bloom": _bloom,
		"ready": not overheated and _cooldown == 0.0,
		"heat": heat,
		"overheated": overheated,
	}


## T: vent the heat now (locked out until it's cold, like an overheat).
func manual_reload() -> void:
	if not overheated and heat > 0.05:
		_on_overheat()


func refill() -> void:
	heat = 0.0
	overheated = false
	_cooldown = 0.0


## Heat, plus 1 while venting an overheat (so other players see both).
func get_net_reload() -> float:
	return heat + (1.0 if overheated else 0.0)


func apply_net_reload(value: float) -> void:
	if value < 0.0:
		return
	var was_venting := overheated
	overheated = value >= 1.0
	heat = clampf(value - 1.0 if overheated else value, 0.0, 1.0)
	if was_venting and not overheated and is_ready():
		flash(reload_flash_color)  # Reformed, like our own vent ending.


func _on_overheat() -> void:
	overheated = true
	# Vent: a burst of hot spikes off every blade, a warp pop and a jolt.
	for blade in _blades:
		var tip: Vector3 = blade.to_global(blade.call("get_tip"))
		var mid: Vector3 = blade.global_position.lerp(tip, 0.5)
		manager.spawn_beam(mid, (mid - global_position).normalized() + Vector3.UP * 0.5, 1.2, 0.5, 0.25, 14.0, hot_color)
	manager.spawn_warp(global_position, 0.12, 2.5)
	manager.spawn_light(global_position, 40.0, 8.0, 0.25, hot_color)
	manager.shake(0.5)
	manager.play_sound("vent", global_position, -4.0)


func _fire() -> void:
	_cooldown = fire_interval
	_bloom = 1.0
	_since_shot = 0.0
	heat = minf(heat + heat_per_shot, 1.0)
	var aim: Vector3 = manager.aim_point
	# Aim assist: centre the cone on the visible target nearest the crosshair.
	var assisted: Array = manager.targets_on_screen(manager.angle_to_pixels(assist_deg), max_range, true)
	if not assisted.is_empty():
		aim = assisted[0]["point"]
	var center: Vector3 = manager.ball.global_position
	var aim_dir := (aim - center).normalized()
	# Two axes across the aim direction, for spreading the pellets.
	var side := aim_dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(aim_dir).normalized()

	var tips: Array[Vector3] = []
	for i in _blades.size():
		kick(i)
		tips.append(_blades[i].to_global(_blades[i].call("get_tip")))
	for tip in tips:
		manager.spawn_beam(tip, aim_dir, 1.0, 0.6, 0.07, muzzle_intensity, color)
	manager.spawn_warp(center + aim_dir * 2.0, 0.1, 1.6)
	manager.spawn_light(center + aim_dir * 2.2, flash_energy, 12.0, 0.08, color)
	manager.play_sound("shotgun", center + aim_dir * 2.0, -3.0)

	var lights_left := 3  # A few impact lights is plenty; dozens would be wasteful.
	for p in pellets:
		# Even-ish spread: random radius (sqrt for uniform area) at a random angle.
		var r := tan(deg_to_rad(spread_deg)) * sqrt(randf())
		var a := randf() * TAU
		var dir := (aim_dir + (side * cos(a) + up * sin(a)) * r).normalized()
		# Pellets fly from the middle of the ball (a blade tip can already be past a target
		# that's point-blank); the visible tracer still leaves from a blade tip.
		var hit: Dictionary = manager.raycast(center, center + dir * max_range)
		var end: Vector3 = hit["position"] if not hit.is_empty() else center + dir * max_range
		var from := tips[p % tips.size()]
		manager.spawn_beam(from, (end - from).normalized(), from.distance_to(end), 0.06, 0.08, 4.0, color)
		if hit.is_empty():
			continue
		var pos: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var dist := center.distance_to(pos)
		var falloff := lerpf(1.0, falloff_min, clampf(inverse_lerp(falloff_start, falloff_end, dist), 0.0, 1.0))
		manager.spawn_beam(pos, normal, 0.3, 0.25, 0.06, 18.0, color)
		if lights_left > 0:
			lights_left -= 1
			manager.spawn_light(pos + normal * 0.2, 15.0, 4.0, 0.06, color)
		manager.hit_object(hit["collider"], pellet_damage * falloff, pos, dir, pellet_impulse * falloff)

	# Full 3D kick opposite the view: look down and fire to jump.
	var look: Vector3 = -manager.camera.global_basis.z
	manager.push_ball(-look * self_knockback)
	manager.shake(shot_shake)
	if heat >= 1.0:
		_on_overheat()
