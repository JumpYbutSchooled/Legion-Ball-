extends CanvasLayer
## Impact frames on kills: a few frames of high-contrast "manga" flashes (inverted, then
## black with coloured silhouettes, then inverted) with speed lines bursting from the kill,
## plus hitstop (the game nearly freezes for the length of the effect) and camera shake.
## Targets trigger it by calling the "impact_frames" group's trigger(world_pos, color).
## Can be switched off in Settings (the shake still plays).

const FrameShader := preload("res://shaders/impact_frame.gdshader")
const SettingsScript := preload("res://scripts/settings.gd")
const Sfx := preload("res://scripts/sfx.gd")

## Receives add_shake().
@export var camera_rig: Node
## Seconds (real time) each frame is held, alternating inverted / colour.
@export var frame_times := PackedFloat32Array([0.07, 0.06, 0.06, 0.05, 0.06, 0.05])
## Game speed during the hitstop.
@export var hitstop_scale := 0.02
## How hard each frame punches in toward the kill (screen fraction), and jolts sideways.
@export var zoom_punch := 0.12
@export var jolt := 0.012

var _frame := -1

var _rect: ColorRect
var _mat: ShaderMaterial
var _start_usec := -1


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("impact_frames")
	_mat = ShaderMaterial.new()
	_mat.shader = FrameShader
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func trigger(world_pos: Vector3, color: Color) -> void:
	if camera_rig and camera_rig.has_method("add_shake"):
		camera_rig.call("add_shake", 1.0)
	Sfx.play_flat(get_tree(), "kill", -2.0)
	if not SettingsScript.read(get_tree(), "impact_frames"):
		return
	_frame = -1
	var camera := get_viewport().get_camera_3d()
	var center := Vector2(0.5, 0.5)
	if camera and not camera.is_position_behind(world_pos):
		center = camera.unproject_position(world_pos) / get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("tint", color)
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_start_usec = Time.get_ticks_usec()
	Engine.time_scale = hitstop_scale


func _process(_delta: float) -> void:
	if _start_usec < 0:
		return
	# Real time, so the effect runs at full speed while the game is in hitstop.
	var t := (Time.get_ticks_usec() - _start_usec) / 1_000_000.0
	var mode := 0
	var edge := 0.0
	var index := -1
	for i in frame_times.size():
		edge += frame_times[i]
		if t < edge:
			mode = 1 if i % 2 == 0 else 2
			index = i
			break
	if mode == 0:
		_rect.visible = false
		_start_usec = -1
		Engine.time_scale = 1.0  # End of hitstop.
		return
	_rect.visible = true
	_mat.set_shader_parameter("mode", mode)
	if index != _frame:
		# Each new frame: fresh lines, a punch in (weaker each time) and a jolt.
		_frame = index
		var k := 1.0 - float(index) / frame_times.size()
		_mat.set_shader_parameter("seed", randf() * 100.0)
		_mat.set_shader_parameter("zoom", zoom_punch * k)
		_mat.set_shader_parameter("jolt", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * jolt * k)
