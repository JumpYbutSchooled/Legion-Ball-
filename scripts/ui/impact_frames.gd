extends CanvasLayer
## Impact frames on kills: a long run of held "manga" frames, plus hitstop (the game nearly
## freezes for the length of the effect) and camera shake.
## Drawn by shaders/impact_frame.gdshader on a full-screen quad on the camera, which casts
## the blast across the real scene: surfaces lit from the kill point, hard shadows behind
## players and walls, shafts over the sky, ink outlines, manga tones.
## The sequence: IMPLOSION (the world darkens and is sucked in and twisted toward the kill
## while a ring closes on it) -> the CRACK (black, then white) -> EXPLOSION (a blinding
## flash that lights everything, thrown outward behind a ring racing away, fading out).
## Targets trigger it by calling the "impact_frames" group's trigger(world_pos, color).
## Can be switched off in Settings (the shake still plays).

const FrameShader := preload("res://shaders/impact_frame.gdshader")
const SettingsScript := preload("res://scripts/settings.gd")
const Sfx := preload("res://scripts/sfx.gd")

## Key frames each side of the crack; the effect eases smoothly between them.
const IMPLODE := 12
const EXPLODE := 16

## Receives add_shake().
@export var camera_rig: Node
## Game speed during the hitstop.
@export var hitstop_scale := 0.02
## How hard each frame jolts the whole image sideways (screen fraction).
@export var jolt := 0.01

## Built in _build_frames(). Each: time (s, real time), mode (1 ink on paper, 2 tint on
## black), pinch, power (light; negative darkens), ring, burst, core.
var frames: Array = []
var _frame := -1
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _start_usec := -1
var _jolt_now := Vector2.ZERO
var _jolt_goal := Vector2.ZERO


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("impact_frames")
	_mat = ShaderMaterial.new()
	_mat.shader = FrameShader
	# Last of everything, over the whole screen.
	_mat.render_priority = Material.RENDER_PRIORITY_MAX
	_build_frames()


func _build_frames() -> void:
	frames.clear()
	# Implosion: darkening, sucked in harder and harder, the ring closing.
	for i in IMPLODE:
		var k := float(i) / (IMPLODE - 1)
		frames.append({
			"time": lerpf(0.04, 0.025, k), "mode": 2 if i % 2 == 0 else 1,
			"pinch": lerpf(0.1, 0.95, k * k), "power": lerpf(-0.2, -1.0, k),
			"ring": lerpf(0.95, 0.06, k), "burst": false, "core": lerpf(0.01, 0.05, k),
		})
	# The crack: collapsed to a black point, then a white-hot flash.
	frames.append({"time": 0.05, "mode": 1, "pinch": 0.0, "power": -1.0, "ring": 0.0, "burst": true, "core": 0.32})
	frames.append({"time": 0.04, "mode": 2, "pinch": 0.0, "power": 4.0, "ring": 0.0, "burst": true, "core": 0.45})
	# Explosion: blinding light fading, thrown out, the ring racing away.
	for i in EXPLODE:
		var k := float(i) / (EXPLODE - 1)
		frames.append({
			"time": lerpf(0.025, 0.045, k), "mode": 1 if i % 2 == 0 else 2,
			"pinch": lerpf(-0.55, -0.02, sqrt(k)), "power": lerpf(3.5, 0.9, k),
			"ring": lerpf(0.1, 1.1, sqrt(k)), "burst": true, "core": lerpf(0.22, 0.02, k),
		})


func trigger(world_pos: Vector3, color: Color) -> void:
	if camera_rig and camera_rig.has_method("add_shake"):
		camera_rig.call("add_shake", 1.0)
	if not SettingsScript.read(get_tree(), "impact_frames"):
		# No frames: just the crack and blast.
		Sfx.play_flat(get_tree(), "impact_boom", -2.0)
		return
	# The implosion sound is stretched to end exactly on the crack, where the blast plays.
	var implode_time := 0.0
	for i in IMPLODE:
		implode_time += frames[i]["time"]
	Sfx.play_flat(get_tree(), "implode", -3.0, 0.45 / implode_time)
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	_ensure_quad(camera)
	_frame = -1
	_jolt_now = Vector2.ZERO
	_jolt_goal = Vector2.ZERO
	var center := Vector2(0.5, 0.5)
	var kill := world_pos
	if camera.is_position_behind(world_pos):
		kill = camera.global_position - camera.global_basis.z * 10.0
	else:
		center = camera.unproject_position(world_pos) / get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("kill_pos", kill)
	_mat.set_shader_parameter("tint", color)
	_start_usec = Time.get_ticks_usec()
	Engine.time_scale = hitstop_scale
	_set_hud_hidden(true)


## The frame takes over the whole screen: hide the HUD layers beside it while it plays.
func _set_hud_hidden(hidden: bool) -> void:
	var parent := get_parent()
	if not parent:
		return
	for child in parent.get_children():
		var canvas := child as CanvasLayer
		if canvas and canvas != self and canvas.name != "PauseMenu":
			canvas.visible = not hidden


## The full-screen quad lives on the camera (like the motion blur).
func _ensure_quad(camera: Camera3D) -> void:
	if _quad and is_instance_valid(_quad) and _quad.get_parent() == camera:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_quad = MeshInstance3D.new()
	_quad.mesh = quad
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 16384.0
	_quad.visible = false
	camera.add_child(_quad)


func _process(_delta: float) -> void:
	if _start_usec < 0:
		return
	# Real time, so the effect runs at full speed while the game is in hitstop.
	var t := (Time.get_ticks_usec() - _start_usec) / 1_000_000.0
	var index := -1
	var edge := 0.0
	for i in frames.size():
		edge += frames[i]["time"]
		if t < edge:
			index = i
			break
	if index < 0 or not is_instance_valid(_quad):
		if is_instance_valid(_quad):
			_quad.visible = false
		_start_usec = -1
		Engine.time_scale = 1.0  # End of hitstop.
		_set_hud_hidden(false)
		return
	_quad.visible = true
	var f: Dictionary = frames[index]
	# Smooth: every rendered frame eases the warp, light, ring and core from this key
	# frame toward the next, so the suck-in and blow-out move continuously.
	var u := clampf(1.0 - (edge - t) / float(f["time"]), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var next: Dictionary = frames[mini(index + 1, frames.size() - 1)]
	# Don't blend across the crack: implosion and explosion snap, not fade.
	if next["burst"] != f["burst"]:
		next = f
	for key in ["pinch", "power", "ring"]:
		_mat.set_shader_parameter(key, lerpf(f[key], next[key], u))
	_mat.set_shader_parameter("core_size", lerpf(f["core"], next["core"], u))
	_jolt_now = _jolt_now.lerp(_jolt_goal, 0.5)
	_mat.set_shader_parameter("jolt", _jolt_now)
	if index == _frame:
		return
	# Each new key frame: ink/tint flip, fresh speed lines and a new jolt (harder at the crack).
	_frame = index
	_mat.set_shader_parameter("mode", f["mode"])
	_mat.set_shader_parameter("bursting", f["burst"])
	_mat.set_shader_parameter("seed", randf() * 100.0)
	var crack: bool = f["core"] >= 0.3
	if index == IMPLODE:
		Sfx.play_flat(get_tree(), "impact_boom", 0.0)
	_jolt_goal = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * jolt * (2.5 if crack else 1.0)
	if crack and camera_rig and camera_rig.has_method("add_shake"):
		camera_rig.call("add_shake", 1.0)
