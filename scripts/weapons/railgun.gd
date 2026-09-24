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

enum Rail { IDLE, CHARGING, RELOADING }

@export var charge_time := 3.0
@export var reload_time := 6.0
@export var damage := 12.0
@export var hit_impulse := 40.0
## Ball velocity change on firing: same as a dash.
@export var knockback := 40.0
@export var shot_shake := 1.0

@export_group("Explosion")
@export var explosion_radius := 7.0
## Damage at the center of the blast (falls off to 0 at the edge).
@export var explosion_damage := 12.0
## Outward impulse on rigid bodies at the center.
@export var explosion_force := 30.0
## Crosshair circle radius in pixels; targets inside it can be locked.
@export var lock_radius_px := 70.0

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
	_charge_warp = MeshInstance3D.new()
	_charge_warp.mesh = sphere
	_charge_warp.material_override = _warp_mat
	_charge_warp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge_warp.position = Vector3(0.6, 0.0, -1.8)
	_charge_warp.scale = Vector3.ONE * 3.6
	_charge_warp.visible = false
	add_child(_charge_warp)


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


func _update(delta: float) -> void:
	if rail_state != Rail.CHARGING:
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


func _update_lock() -> void:
	lock_target = null
	if not is_ready() or rail_state == Rail.RELOADING or not manager.camera:
		return
	var camera: Camera3D = manager.camera
	var center := camera.get_viewport().get_visible_rect().size / 2.0
	var ball_pos: Vector3 = manager.ball.global_position
	var best := INF
	for target in get_tree().get_nodes_in_group("lock_targets"):
		if not target.call("is_alive"):
			continue
		var p: Vector3 = target.call("get_aim_point")
		if camera.is_position_behind(p):
			continue
		var screen := camera.unproject_position(p)
		if screen.distance_to(center) > lock_radius_px:
			continue
		var dist := p.distance_to(ball_pos)
		if dist < best:
			best = dist
			lock_target = target
			lock_screen_pos = screen


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

	if not hit.is_empty():
		var pos: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		# A star of long spikes bursting off the surface.
		manager.spawn_beam(pos, normal, 3.0, 2.0, 0.25, 30.0, color)
		for i in 8:
			var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
			manager.spawn_beam(pos, (normal + jitter * 1.2).normalized(), randf_range(1.5, 3.0), 1.0, 0.2, 30.0, color)
		manager.hit_object(hit["collider"], damage, pos, shot_dir, hit_impulse)
		# The blast: area damage, outward shove, particles, shockwave, warp, light.
		manager.spawn_explosion({
			"position": pos + normal * 0.3,
			"color": color,
			"radius": explosion_radius,
			"damage": explosion_damage,
			"force": explosion_force,
		})

	manager.knockback(shot_dir, knockback)
	manager.shake(shot_shake)
