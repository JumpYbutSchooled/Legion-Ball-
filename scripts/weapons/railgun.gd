extends "res://scripts/weapons/blade_weapon.gd"
## Slot 2: railgun. One big crystal blade on the right side.
## - Lock: the nearest (to the ball) living target whose screen position is inside the
##   crosshair circle becomes the lock; shots go to it instead of the crosshair.
## - Charge: hold fire for charge_time. Rings of warp sweep inward round the gun and
##   the facets near the tip spread out (less toward the back). Letting go cancels.
## - Fire: a thick beam, heavy damage, a big shove, and a dash-strength kick on the ball.
## - Reload: the blade turns purple, falls apart and shakes, pulling back together and
##   turning blue over reload_time, then snaps whole with a flash of blue light.

const WarpShader := preload("res://shaders/charge_warp.gdshader")
const FlareShader := preload("res://shaders/light_flare.gdshader")

enum Rail { IDLE, CHARGING, RELOADING }

@export var charge_time := 2.5
@export var reload_time := 5.0
@export var damage := 10.0
@export var hit_impulse := 40.0
## Ball velocity change on firing: same as a dash.
@export var knockback := 40.0
@export var shot_shake := 1.0

@export_group("Explosion")
@export var explosion_radius := 5.0
## Damage at the center of the blast (falls off to 0 at the edge).
@export var explosion_damage := 8.0
## Outward impulse on rigid bodies at the center.
@export var explosion_force := 30.0
## Crosshair circle radius in pixels; targets inside it can be locked.
@export var lock_radius_px := 70.0
## Targets further than this can't be locked.
@export var lock_range := 150.0
## Damage (hit and blast) is full out to falloff_start metres, dropping to falloff_min
## at falloff_end.
@export var falloff_start := 80.0
@export var falloff_end := 250.0
@export var falloff_min := 0.6

@export_group("Charge")
## How far the tip facets spread at full charge.
@export var charge_spread := 0.35
@export var charge_glow := 1.5
## Strength of the inward warp rings round the gun at full charge.
@export var charge_warp_strength := 0.08
## Rings per second sweeping inward, at no charge and at full charge.
@export var ring_rate_min := 0.5
@export var ring_rate_max := 2.0

@export_group("Reload")
@export var reload_start_color := Color(0.65, 0.2, 1.0)
@export var reload_end_color := Color(0.2, 0.45, 1.0)
@export var reload_flash_color := Color(0.25, 0.55, 1.0)

var rail_state := Rail.IDLE
## 0..1 while charging.
var charge := 0.0
## 0..1 while reloading.
var reload := 0.0
## The locked target (or null), and where it sits on screen.
var lock_target: Node3D = null
var lock_screen_pos := Vector2.ZERO

var _charge_warp: MeshInstance3D
var _warp_mat: ShaderMaterial
var _ring_phase := 0.0
## Flare + light on the tip that swells as it charges, so everyone can see a shot coming.
var _flare: MeshInstance3D
var _flare_mat: ShaderMaterial
var _flare_light: OmniLight3D
var _hum: AudioStreamPlayer3D


func _build() -> void:
	add_blade(1.0, 0.0, {
		"arc_radius": 0.9,
		"tip": Vector3(0.35, 0.0, -4.2),
		"max_width": 0.36,
		"max_thickness": 0.28,
		"segments": 11,
	})
	# Invisible bubble round the blade that pulls the view inward while charging.
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_warp_mat = ShaderMaterial.new()
	_warp_mat.shader = WarpShader
	# Before the blade, or the warp would paint over it (see muzzle_warp.gd).
	_warp_mat.render_priority = Material.RENDER_PRIORITY_MIN + 1
	_charge_warp = MeshInstance3D.new()
	_charge_warp.mesh = sphere
	_charge_warp.material_override = _warp_mat
	_charge_warp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge_warp.position = Vector3(0.6, 0.0, -1.8)
	_charge_warp.scale = Vector3.ONE * 3.6
	_charge_warp.visible = false
	add_child(_charge_warp)

	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 1.0)
	_flare_mat = ShaderMaterial.new()
	_flare_mat.shader = FlareShader
	_flare_mat.set_shader_parameter("aspect", 3.0)
	_flare = MeshInstance3D.new()
	_flare.set_instance_shader_parameter("color", color)
	_flare.mesh = quad
	_flare.material_override = _flare_mat
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.visible = false
	add_child(_flare)
	_flare_light = OmniLight3D.new()
	_flare_light.light_color = color
	_flare_light.omni_range = 9.0
	_flare_light.light_energy = 0.0
	_flare_light.visible = false
	add_child(_flare_light)


func handle_fire(pressed: bool, hit: Dictionary, delta: float) -> void:
	match rail_state:
		Rail.IDLE:
			if pressed and is_ready():
				rail_state = Rail.CHARGING
		Rail.CHARGING:
			if not pressed or not is_ready():
				rail_state = Rail.IDLE
			else:
				charge = minf(charge + delta / charge_time, 1.0)
				if charge >= 1.0:
					_fire(hit)


func get_crosshair() -> Dictionary:
	return {
		"kind": "rail",
		"radius": lock_radius_px,
		"circle": rail_state != Rail.RELOADING,
		"reloading": rail_state == Rail.RELOADING,
		"charge": charge,
		"locked": lock_target != null,
		"lock_pos": lock_screen_pos,
	}


func _on_exit() -> void:
	if rail_state == Rail.CHARGING:
		rail_state = Rail.IDLE


## Equipping it mid-reload flashes the reload colour, not orange.
func _equip_flash_color() -> Color:
	if rail_state == Rail.RELOADING:
		return reload_start_color.lerp(reload_end_color, reload)
	return color


func get_net_charge() -> float:
	return charge if rail_state == Rail.CHARGING else 0.0


func apply_net_charge(c: float) -> void:
	charge = c


func _update(delta: float) -> void:
	# Other players' charge comes from the network (apply_net_charge).
	if rail_state != Rail.CHARGING and (not manager or manager.is_multiplayer_authority()):
		charge = move_toward(charge, 0.0, delta * 2.0)

	if rail_state == Rail.RELOADING:
		reload = minf(reload + delta / reload_time, 1.0)
		if reload >= 1.0:
			rail_state = Rail.IDLE
			reload = 0.0
			flash(reload_flash_color)

	_update_lock()

	# Charge: spread and glow build slowly, strongest right at the end.
	var c := charge * charge
	_set_param("charge_spread", c * charge_spread)
	_set_param("charge_glow", c * charge_glow)
	var reloading := rail_state == Rail.RELOADING
	_set_param("reload_break", 1.0 - reload if reloading else 0.0)
	_set_param("override_amount", 1.0 if reloading else 0.0)
	_set_param("override_color", reload_start_color.lerp(reload_end_color, reload))

	_charge_warp.visible = visible and charge > 0.01
	_ring_phase += delta * lerpf(ring_rate_min, ring_rate_max, charge)
	_warp_mat.set_shader_parameter("phase", _ring_phase)
	_warp_mat.set_shader_parameter("strength", charge_warp_strength * c)
	_update_flare(c)


## The tip flare grows, brightens and starts to flicker as the charge nears full.
func _update_flare(c: float) -> void:
	var on := visible and charge > 0.02
	_flare.visible = on
	_flare_light.visible = on
	if _hum == null and is_inside_tree():
		var sfx := get_tree().root.get_node_or_null("Sfx")
		if sfx:
			_hum = sfx.call("make_loop", "charge", self)
	if _hum:
		if on and not _hum.playing:
			_hum.play()
		elif not on and _hum.playing:
			_hum.stop()
		_hum.volume_db = lerpf(-24.0, -4.0, charge)
		_hum.pitch_scale = lerpf(0.6, 2.2, c)
	if not on:
		return
	var tip: Vector3 = _blades[0].to_global(_blades[0].call("get_tip"))
	var flicker := 1.0 + 0.25 * sin(Time.get_ticks_msec() / 25.0) * c
	_flare.global_position = tip
	_flare.scale = Vector3.ONE * lerpf(0.4, 4.5, c) * flicker
	_flare.set_instance_shader_parameter("intensity", lerpf(2.0, 14.0, c))
	_flare.set_instance_shader_parameter("fade", clampf(charge * 3.0, 0.0, 1.0))
	_flare_light.global_position = tip
	_flare_light.light_energy = lerpf(0.5, 30.0, c) * flicker


## Locks the living target closest to the middle of the circle.
func _update_lock() -> void:
	lock_target = null
	if not is_ready() or rail_state == Rail.RELOADING or not manager.camera:
		return
	var found: Array = manager.targets_on_screen(lock_radius_px, lock_range)
	if not found.is_empty():
		lock_target = found[0]["target"]
		lock_screen_pos = found[0]["screen"]


func _fire(hit: Dictionary) -> void:
	rail_state = Rail.RELOADING
	reload = 0.0
	charge = 0.0
	kick(0)

	var blade := _blades[0]
	var tip: Vector3 = blade.to_global(blade.call("get_tip"))
	var target_point: Vector3 = manager.aim_point
	if lock_target:
		# Aim straight at the lock; whatever is actually in the way takes the hit.
		target_point = lock_target.call("get_aim_point")
		var dir := (target_point - tip).normalized()
		hit = manager.raycast(tip, target_point + dir * 0.5)
	var shot_dir := (target_point - tip).normalized()
	var end: Vector3 = hit["position"] if not hit.is_empty() else target_point

	# Thick beam, a big muzzle flare and a strong warp bubble.
	manager.spawn_beam(tip, shot_dir, tip.distance_to(end), 0.55, 0.35, 20.0, color)
	manager.spawn_beam(tip, shot_dir, 2.4, 1.3, 0.12, 24.0, color)
	var up := global_basis.y
	for angle in [55.0, -55.0, 125.0, -125.0]:
		manager.spawn_beam(tip, shot_dir.rotated(up, deg_to_rad(angle)), 0.9, 0.5, 0.1, 20.0, color)
	manager.spawn_warp(tip, 0.18, 2.2)
	manager.spawn_light(tip, 80.0, 20.0, 0.2, color)
	manager.play_sound("rail", tip, 2.0)

	if not hit.is_empty():
		var pos: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		# A star of long spikes bursting off the surface.
		manager.spawn_beam(pos, normal, 3.0, 2.0, 0.25, 30.0, color)
		for i in 8:
			var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
			manager.spawn_beam(pos, (normal + jitter * 1.2).normalized(), randf_range(1.5, 3.0), 1.0, 0.2, 30.0, color)
		var falloff := lerpf(1.0, falloff_min, clampf(inverse_lerp(falloff_start, falloff_end, tip.distance_to(pos)), 0.0, 1.0))
		manager.hit_object(hit["collider"], damage * falloff, pos, shot_dir, hit_impulse)
		# The blast: area damage, outward shove, particles, shockwave, warp, light.
		manager.spawn_explosion({
			"position": pos + normal * 0.3,
			"color": color,
			"radius": explosion_radius,
			"damage": explosion_damage * falloff,
			"force": explosion_force,
		})

	manager.knockback(shot_dir, knockback)
	manager.shake(shot_shake)
