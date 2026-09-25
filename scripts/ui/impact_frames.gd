extends CanvasLayer
## Impact frames on kills: a short run of held "manga" frames with tone shading
## (shaders/impact_frame.gdshader), plus hitstop (the game nearly freezes for the length
## of the effect) and camera shake.
## The sequence is an IMPLOSION into an EXPLOSION: the image gets sucked in and twisted
## toward the kill while a ring closes on it, it cracks in a white-hot flash, then
## everything is thrown back out behind a ring racing outward.
## Targets trigger it by calling the "impact_frames" group's trigger(world_pos, color).
## Can be switched off in Settings (the shake still plays).

const FrameShader := preload("res://shaders/impact_frame.gdshader")
const SettingsScript := preload("res://scripts/settings.gd")
const Sfx := preload("res://scripts/sfx.gd")

## The frames, in order. time: seconds held (real time). mode: 1 ink on paper, 2 tint on
## black. pinch: > 0 sucks in, < 0 throws out. ring: shock ring radius (0 = none).
## burst: lines fire outward from the ring (explosion) instead of pouring in. core: size
## of the white-hot centre.
const FRAMES := [
	# Implosion: sucked in, ring closing.
	{"time": 0.05, "mode": 2, "pinch": 0.25, "ring": 0.7, "burst": false, "core": 0.02},
	{"time": 0.05, "mode": 1, "pinch": 0.5, "ring": 0.42, "burst": false, "core": 0.03},
	{"time": 0.06, "mode": 2, "pinch": 0.85, "ring": 0.18, "burst": false, "core": 0.05},
	# The crack.
	{"time": 0.04, "mode": 1, "pinch": 0.0, "ring": 0.0, "burst": true, "core": 0.3},
	# Explosion: thrown out, ring racing away.
	{"time": 0.05, "mode": 2, "pinch": -0.45, "ring": 0.22, "burst": true, "core": 0.16},
	{"time": 0.06, "mode": 1, "pinch": -0.25, "ring": 0.5, "burst": true, "core": 0.1},
	{"time": 0.07, "mode": 2, "pinch": -0.1, "ring": 0.85, "burst": true, "core": 0.06},
]

## Receives add_shake().
@export var camera_rig: Node
## Game speed during the hitstop.
@export var hitstop_scale := 0.02
## How hard each frame jolts the whole image sideways (screen fraction).
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
	_start_usec = Time.get_ticks_usec()
	Engine.time_scale = hitstop_scale


func _process(_delta: float) -> void:
	if _start_usec < 0:
		return
	# Real time, so the effect runs at full speed while the game is in hitstop.
	var t := (Time.get_ticks_usec() - _start_usec) / 1_000_000.0
	var index := -1
	var edge := 0.0
	for i in FRAMES.size():
		edge += FRAMES[i]["time"]
		if t < edge:
			index = i
			break
	if index < 0:
		_rect.visible = false
		_start_usec = -1
		Engine.time_scale = 1.0  # End of hitstop.
		return
	_rect.visible = true
	if index == _frame:
		return
	# Each new frame: its own settings, fresh speed lines and a jolt (harder at the crack).
	_frame = index
	var f: Dictionary = FRAMES[index]
	_mat.set_shader_parameter("mode", f["mode"])
	_mat.set_shader_parameter("pinch", f["pinch"])
	_mat.set_shader_parameter("ring", f["ring"])
	_mat.set_shader_parameter("bursting", f["burst"])
	_mat.set_shader_parameter("core_size", f["core"])
	_mat.set_shader_parameter("seed", randf() * 100.0)
	var kick := 2.0 if f["core"] >= 0.3 else 1.0
	_mat.set_shader_parameter("jolt", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * jolt * kick)
	if f["core"] >= 0.3 and camera_rig and camera_rig.has_method("add_shake"):
		camera_rig.call("add_shake", 1.0)
