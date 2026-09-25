extends "res://scripts/weapons/blade_weapon.gd"
## Slot 6: Swarm, homing missiles. Two small blades raised behind the ball.
## Hold fire to paint targets inside the wide paint zone (nearest first, one every
## paint_interval, up to max_paints); release to launch one homing missile per painted
## target (or a pair straight at the crosshair if nothing is painted).
## Missiles MARK what they hit: marked targets take double damage from every weapon.
## Combos: mark a group, then switch to Railgun or Gatling to shred them.

## Matches swarm_missile.gd's speed, for the launch velocity.
const MISSILE_SPEED := 38.0

@export var paint_radius_px := 170.0
## Targets further than this can't be painted.
@export var paint_range := 90.0
@export var paint_interval := 0.25
@export var max_paints := 4
@export var cooldown := 1.2
## How long a missile stays marked on its target after it hits.
@export var mark_time := 3.0

## Currently painted targets, in paint order.
var painted: Array[Node3D] = []
var _painting := false
var _paint_timer := 0.0
var _cooldown := 0.0
var _was_pressed := false
var _next_blade := 0


func _build() -> void:
	var shape := {
		"arc_radius": 0.7,
		"tip": Vector3(0.3, 0.0, -1.6),
		"max_width": 0.2,
		"max_thickness": 0.16,
		"segments": 8,
	}
	for side in [1.0, -1.0]:
		add_blade(side, 35.0, shape)


func handle_fire(pressed: bool, _hit: Dictionary, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var released := _was_pressed and not pressed
	_was_pressed = pressed
	_prune()
	if not is_ready():
		_painting = false
		painted.clear()
		return
	if pressed and _cooldown == 0.0:
		if not _painting:
			_painting = true
			_paint_timer = 0.0
		_paint_timer -= delta
		if _paint_timer <= 0.0 and painted.size() < max_paints:
			_paint_timer = paint_interval
			_paint_next()
	elif released and _painting:
		_launch()


func _on_exit() -> void:
	_painting = false
	painted.clear()


func get_crosshair() -> Dictionary:
	var marks: Array[Vector2] = []
	for target in painted:
		var p: Vector3 = target.call("get_aim_point")
		if not manager.camera.is_position_behind(p):
			marks.append(manager.screen_pos(p))
	return {
		"kind": "swarm",
		"radius": paint_radius_px,
		"painting": _painting,
		"marks": marks,
		"max": max_paints,
		"ready": _cooldown == 0.0,
	}


func _update(_delta: float) -> void:
	# Blades glow brighter the more targets are painted.
	_set_param("charge_glow", float(painted.size()) / max_paints * 1.2)


func _prune() -> void:
	for i in range(painted.size() - 1, -1, -1):
		var t = painted[i]
		if not is_instance_valid(t) or not t.call("is_alive"):
			painted.remove_at(i)


## Paints a new target if there is one, otherwise stacks another missile on the one
## nearest the center (so it isn't useless against a single enemy).
func _paint_next() -> void:
	var found: Array = manager.targets_on_screen(paint_radius_px, paint_range)
	if found.is_empty():
		return
	var pick: Dictionary = found[0]
	for entry in found:
		if not painted.has(entry["target"]):
			pick = entry
			break
	painted.append(pick["target"])
	manager.spawn_light(pick["point"], 12.0, 3.0, 0.1, color)


func _launch() -> void:
	_painting = false
	_cooldown = cooldown
	var aim: Vector3 = manager.aim_point
	var targets: Array = painted.duplicate()
	painted.clear()
	var count := targets.size() if not targets.is_empty() else 2
	for i in count:
		var blade := _blades[_next_blade]
		kick(_next_blade)
		_next_blade = (_next_blade + 1) % _blades.size()
		var tip: Vector3 = blade.to_global(blade.call("get_tip"))
		# Launch up and out to the blade's side, then they curve in.
		var toward := (aim - tip).normalized()
		var out := (tip - global_position).normalized()
		var launch := (toward + out * 0.8 + Vector3.UP * 0.6).normalized()
		var props := {
			"position": tip,
			"color": color,
			"mark_time": mark_time,
			"aim_point": aim,
			"has_aim_point": true,
			"velocity": launch * MISSILE_SPEED,
			"target_path": String(targets[i].get_path()) if not targets.is_empty() else "",
		}
		manager.spawn_missile(props)
		manager.spawn_beam(tip, launch, 0.8, 0.45, 0.06, 14.0, color)
		manager.spawn_light(tip, 30.0, 6.0, 0.06, color)
		manager.play_sound("missile", tip, -6.0)
	manager.shake(0.35)
