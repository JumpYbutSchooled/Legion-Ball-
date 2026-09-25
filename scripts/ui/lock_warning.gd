extends CanvasLayer
## Tints the screen edges red while another player's railgun is locked onto you, pulsing
## and growing stronger as their shot charges. The lock comes over the network from the
## shooter (player_sync.gd is_locking()).

const WarningShader := preload("res://shaders/lock_warning.gdshader")

## Tint while locked with no charge, and at full charge.
const BASE := 0.45
const FULL := 1.0
const PULSE_RATE := 10.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _strength := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 3
	_mat = ShaderMaterial.new()
	_mat.shader = WarningShader
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	_t += delta
	var goal := _lock_level()
	# Snaps on fast, fades off a little slower.
	_strength = move_toward(_strength, goal, delta * (8.0 if goal > _strength else 3.0))
	_rect.visible = _strength > 0.01
	if _rect.visible:
		var pulse := 0.8 + 0.2 * sin(_t * PULSE_RATE)
		_mat.set_shader_parameter("strength", clampf(_strength * pulse, 0.0, 1.0))


## 0 if nobody is locked on; otherwise BASE..FULL by the strongest locker's charge.
func _lock_level() -> float:
	var scene := get_tree().current_scene
	var players := scene.get_node_or_null("Players") if scene else null
	if not players:
		return 0.0
	var me := multiplayer.get_unique_id()
	var level := 0.0
	for ball in players.get_children():
		var sync := ball.get_node_or_null("Sync")
		if sync and sync.has_method("is_locking") and sync.call("is_locking", me):
			level = maxf(level, lerpf(BASE, FULL, sync.call("lock_charge")))
	return level
