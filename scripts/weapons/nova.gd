extends "res://scripts/weapons/blade_weapon.gd"
## Slot 5: Nova, a charged blast around the ball. Four blades crossed in an X (the lower
## pair shallower so they clear the floor). Hold fire to charge (rings of warp close in
## round the ball and the blade tips spread); release to detonate. The blast grows with
## charge: it damages and throws everything nearby, staggers targets (they freeze in
## place), and launches the ball up.
## Combos: stagger drones so the Railgun can't miss; launch up, then Scatter or Swarm
## from the air.

const WarpShader := preload("res://shaders/charge_warp.gdshader")

@export var charge_time := 1.2
@export var cooldown := 1.5
## Blast radius, damage, force and ball launch at no charge and at full charge.
@export var radius_min := 4.0
@export var radius_max := 12.0
@export var damage_min := 3.0
@export var damage_max := 10.0
@export var force_min := 10.0
@export var force_max := 40.0
@export var launch_min := 6.0
@export var launch_max := 16.0
@export var stagger_time := 2.0
@export var charge_spread := 0.3
@export var charge_warp_strength := 0.1

var charge := 0.0
var _charging := false
var _cooldown := 0.0
var _was_pressed := false
var _ring_phase := 0.0
var _warp: MeshInstance3D
var _warp_mat: ShaderMaterial


func _build() -> void:
	var shape := {
		"arc_radius": 0.85,
		"tip": Vector3(0.35, 0.0, -1.8),
		"max_width": 0.3,
		"max_thickness": 0.24,
		"segments": 8,
	}
	for angle in [55.0, -28.0]:
		for side in [1.0, -1.0]:
			add_blade(side, angle, shape)
	# Charge warp round the ball itself.
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_warp_mat = ShaderMaterial.new()
	_warp_mat.shader = WarpShader
	_warp = MeshInstance3D.new()
	_warp.mesh = sphere
	_warp.material_override = _warp_mat
	_warp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warp.scale = Vector3.ONE * 4.0
	_warp.visible = false
	add_child(_warp)


func handle_fire(pressed: bool, _hit: Dictionary, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var released := _was_pressed and not pressed
	_was_pressed = pressed
	if not is_ready():
		_charging = false
		return
	if pressed and _cooldown == 0.0:
		_charging = true
		charge = minf(charge + delta / charge_time, 1.0)
	elif released and _charging:
		_detonate()


func _on_exit() -> void:
	_charging = false


func get_crosshair() -> Dictionary:
	return {
		"kind": "nova",
		"charge": charge,
		"ready": _cooldown == 0.0,
		"cooldown": 1.0 - _cooldown / cooldown,
	}


func _update(delta: float) -> void:
	if not _charging:
		charge = move_toward(charge, 0.0, delta * 3.0)
	var c := charge * charge
	_set_param("charge_spread", c * charge_spread)
	_set_param("charge_glow", c * 1.5)
	_warp.visible = visible and charge > 0.01
	_ring_phase += delta * lerpf(0.6, 2.4, charge)
	_warp_mat.set_shader_parameter("phase", _ring_phase)
	_warp_mat.set_shader_parameter("strength", charge_warp_strength * c)


func _detonate() -> void:
	var k := charge
	_charging = false
	charge = 0.0
	_cooldown = cooldown
	for i in _blades.size():
		kick(i)

	var ball: RigidBody3D = manager.ball
	manager.spawn_explosion({
		"position": ball.global_position,
		"color": color,
		"radius": lerpf(radius_min, radius_max, k),
		"damage": lerpf(damage_min, damage_max, k),
		"force": lerpf(force_min, force_max, k),
		"stagger_time": stagger_time,
		"spark_count": int(lerpf(80.0, 260.0, k)),
		"spark_speed": lerpf(14.0, 30.0, k),
		"chunk_count": int(lerpf(8.0, 24.0, k)),
		"light_energy": lerpf(80.0, 260.0, k),
		"warp_strength": lerpf(0.15, 0.4, k),
		"flat_sparks": true,
	})

	manager.push_ball(Vector3.UP * lerpf(launch_min, launch_max, k))
	manager.shake(lerpf(0.5, 1.0, k))
