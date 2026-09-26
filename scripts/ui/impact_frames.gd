extends CanvasLayer
## Impact frames on kills: a long run of held "manga" frames, plus hitstop (the game nearly
## freezes for the length of the effect) and camera shake.
## Drawn by shaders/impact_frame.gdshader on a full-screen quad on the camera, which casts
## the blast across the real scene: surfaces lit from the kill point, hard shadows behind
## players and walls, shafts over the sky, ink outlines, manga tones. Weapon blades and
## shields are included through solid stand-ins (_add_proxies).
## The sequence: IMPLOSION (the world darkens and is sucked in and twisted toward the kill
## while a ring closes on it) -> the CRACK (black, then white) -> EXPLOSION (a blinding
## flash that lights everything, thrown outward behind a ring racing away, fading out).
## Every weapon has its own version, scaled to how hard it hits (PROFILES): the Gatling's
## is a quick flicker, the Scatter's is mostly blast, the Tether's mostly pull, Nova's is
## huge, and the Railgun gets the full-length original. The weapon is whichever one last
## dealt damage (weapon.gd, last_hit_id).
## Targets trigger it by calling the "impact_frames" group's trigger(world_pos, color).
## Online, every player sees every kill's frames (arena.gd _on_killed).
## Can be switched off in Settings (the shake still plays).

const FrameShader := preload("res://shaders/impact_frame.gdshader")
const BladeDepthShader := preload("res://shaders/blade_depth.gdshader")
const ShieldDepthShader := preload("res://shaders/shield_depth.gdshader")
## Settings copied from each real blade/shield to its solid stand-in, every frame.
const BLADE_PARAMS := ["wave_pos", "wave_assembling", "charge_spread", "reload_break", "tip_open", "extend"]
const SHIELD_PARAMS := ["out_amount", "grow", "fade", "shell_radius"]
const SettingsScript := preload("res://scripts/settings.gd")
const Sfx := preload("res://scripts/sfx.gd")

## Per weapon id (weapon_info.gd); weapons with none play the Railgun's:
##   implode / explode: key frames each side of the crack (fewer = shorter)
##   speed: frame time multiplier    pull: implosion strength    blast: explosion strength
##   core: size of the crack flash   volume: blast sound (dB)     shake: camera shake
const PROFILES := {
	"gatling": {"implode": 4, "explode": 6, "speed": 0.8, "pull": 0.35, "blast": 0.5, "core": 0.6, "volume": -6.0, "shake": 0.5},
	"railgun": {"implode": 12, "explode": 16, "speed": 1.0, "pull": 1.0, "blast": 1.0, "core": 1.0, "volume": 6.0, "shake": 1.0},
	"scatter": {"implode": 4, "explode": 12, "speed": 1.0, "pull": 0.5, "blast": 1.0, "core": 1.0, "volume": 1.0, "shake": 0.9},
	"tether": {"implode": 8, "explode": 7, "speed": 1.0, "pull": 0.9, "blast": 0.6, "core": 0.8, "volume": -2.0, "shake": 0.7},
	"nova": {"implode": 10, "explode": 14, "speed": 1.0, "pull": 0.9, "blast": 0.95, "core": 1.1, "volume": 4.0, "shake": 1.0},
	"swarm": {"implode": 5, "explode": 8, "speed": 0.9, "pull": 0.5, "blast": 0.65, "core": 0.7, "volume": -3.0, "shake": 0.6},
	# Staff weapons: Rain of God plays the Railgun's; Tears of an Angel a bright, quick
	# flurry; Pillars of God's is the biggest.
	"rain_of_god": {"implode": 12, "explode": 16, "speed": 1.0, "pull": 1.0, "blast": 1.0, "core": 1.0, "volume": 6.0, "shake": 1.0},
	"tears_of_an_angel": {"implode": 6, "explode": 12, "speed": 0.85, "pull": 0.6, "blast": 1.2, "core": 0.9, "volume": 2.0, "shake": 0.8},
	"pillars_of_god": {"implode": 26, "explode": 36, "speed": 1.25, "pull": 1.6, "blast": 1.8, "core": 2.2, "volume": 12.0, "shake": 2.0},
}

## Receives add_shake().
@export var camera_rig: Node
## The local weapon manager, to know which weapon got the kill.
@export var weapon: Node
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
var _profile: Dictionary = PROFILES["railgun"]
var _implode := 12
## Solid stand-ins for the see-through blades and shields: [real mesh, stand-in, params].
var _proxies: Array = []
var _playing_id := ""
## Where the kill happened, re-projected every frame (the camera may turn).
var _kill_world := Vector3.ZERO


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("impact_frames")
	_mat = ShaderMaterial.new()
	_mat.shader = FrameShader
	# Last of everything, over the whole screen.
	_mat.render_priority = Material.RENDER_PRIORITY_MAX
	_build_frames(PROFILES["railgun"])


## The implosion -> crack -> explosion sequence, shaped by a weapon profile.
func _build_frames(p: Dictionary) -> void:
	_profile = p
	frames.clear()
	var implode: int = p["implode"]
	var explode: int = p["explode"]
	var speed: float = p["speed"]
	var pull: float = p["pull"]
	var blast: float = p["blast"]
	var core: float = p["core"]
	_implode = implode
	# Implosion: darkening, sucked in harder and harder, the ring closing.
	for i in implode:
		var k := float(i) / maxf(implode - 1, 1)
		frames.append({
			"time": lerpf(0.04, 0.025, k) * speed, "mode": 2 if i % 2 == 0 else 1,
			"pinch": lerpf(0.1, 0.95, k * k) * pull, "power": lerpf(-0.2, -1.0, k) * pull,
			"ring": lerpf(0.95, 0.06, k), "burst": false, "core": lerpf(0.01, 0.05, k) * core,
		})
	# The crack: collapsed to a black point, then a white-hot flash.
	frames.append({"time": 0.05 * speed, "mode": 1, "pinch": 0.0, "power": -1.0, "ring": 0.0, "burst": true, "core": 0.32 * core})
	frames.append({"time": 0.04 * speed, "mode": 2, "pinch": 0.0, "power": 4.0 * blast, "ring": 0.0, "burst": true, "core": 0.45 * core})
	# Explosion: blinding light fading, thrown out, the ring racing away.
	for i in explode:
		var k := float(i) / maxf(explode - 1, 1)
		frames.append({
			"time": lerpf(0.025, 0.045, k) * speed, "mode": 1 if i % 2 == 0 else 2,
			"pinch": lerpf(-0.55, -0.02, sqrt(k)) * blast, "power": lerpf(3.5, 0.9, k) * blast,
			"ring": lerpf(0.1, 1.1, sqrt(k)), "burst": true, "core": lerpf(0.22, 0.02, k) * core,
		})


## `weapon_id`: the weapon whose version to play ("" = our own last hit). `hitstop`:
## also slow the game down (off for other players' kills; see arena.gd _on_killed).
func trigger(world_pos: Vector3, color: Color, weapon_id := "", hitstop := true) -> void:
	if weapon_id == "":
		weapon_id = weapon.get("last_hit_id") if weapon else "railgun"
	# The same blast asking again straight away (the orbital strike's own frames, then
	# its kill a moment later): let the first one play on.
	if _start_usec >= 0 and weapon_id == _playing_id and Time.get_ticks_usec() - _start_usec < 800_000:
		return
	_playing_id = weapon_id
	_build_frames(PROFILES.get(weapon_id, PROFILES["railgun"]))
	var shake: float = _profile["shake"]
	var volume: float = _profile["volume"]
	if camera_rig and camera_rig.has_method("add_shake"):
		camera_rig.call("add_shake", shake)
	if not SettingsScript.read(get_tree(), "impact_frames"):
		# No frames: just the crack and blast.
		Sfx.play_flat(get_tree(), "impact_boom", volume - 2.0)
		return
	# The implosion sound is stretched to end exactly on the crack, where the blast plays.
	var implode_time := 0.0
	for i in _implode:
		implode_time += frames[i]["time"]
	# (Capped so the short ones don't turn squeaky; they just overlap the blast.)
	Sfx.play_flat(get_tree(), "implode", -3.0 + minf(volume, 0.0), clampf(0.45 / implode_time, 0.8, 2.0))
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	_ensure_quad(camera)
	_frame = -1
	_jolt_now = Vector2.ZERO
	_jolt_goal = Vector2.ZERO
	_kill_world = world_pos
	_aim_at_kill(camera)
	_mat.set_shader_parameter("tint", color)
	_start_usec = Time.get_ticks_usec()
	if hitstop:
		Engine.time_scale = hitstop_scale
	_set_hud_hidden(true)
	_add_proxies()


## Points the effect at the kill as seen from the camera right now. Called every frame
## while it plays, so turning the camera keeps the blast on the kill instead of leaving it
## stuck where it first appeared on screen.
func _aim_at_kill(camera: Camera3D) -> void:
	var center := Vector2(0.5, 0.5)
	var kill := _kill_world
	if camera.is_position_behind(_kill_world):
		# Behind us: centre it on a point just ahead, so it still plays round the view.
		kill = camera.global_position - camera.global_basis.z * 10.0
	else:
		center = camera.unproject_position(_kill_world) / get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("kill_pos", kill)


## Weapon blades and shields are see-through, so they're missing from the depth and
## normal buffers this effect shades from. While it plays, each visible one gets a solid
## copy with the same shape and motion (shaders/blade_depth, shield_depth) so it's lit,
## shadowed and outlined like everything else. The effect covers the whole screen, so
## the copies themselves are never seen.
func _add_proxies() -> void:
	_clear_proxies()
	for blade in get_tree().get_nodes_in_group("impact_blades"):
		_add_proxy(blade, BladeDepthShader, BLADE_PARAMS)
	for shield in get_tree().get_nodes_in_group("impact_shields"):
		_add_proxy(shield, ShieldDepthShader, SHIELD_PARAMS)


func _add_proxy(source: MeshInstance3D, shader: Shader, params: Array) -> void:
	if not source.is_visible_in_tree() or not source.mesh:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var proxy := MeshInstance3D.new()
	proxy.mesh = source.mesh
	proxy.material_override = mat
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.extra_cull_margin = source.extra_cull_margin
	source.add_child(proxy)
	_proxies.append([source, proxy, params])
	_sync_proxy(_proxies[-1])


func _sync_proxy(entry: Array) -> void:
	var source: MeshInstance3D = entry[0]
	var proxy: MeshInstance3D = entry[1]
	var from := source.material_override as ShaderMaterial
	var to := proxy.material_override as ShaderMaterial
	if not from:
		return
	for param in entry[2]:
		var value = from.get_shader_parameter(param)
		if value != null:
			to.set_shader_parameter(param, value)


func _clear_proxies() -> void:
	for entry in _proxies:
		if is_instance_valid(entry[1]):
			entry[1].queue_free()
	_proxies.clear()


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
		_clear_proxies()
		return
	_quad.visible = true
	var camera := _quad.get_parent() as Camera3D
	if camera:
		_aim_at_kill(camera)
	# Keep the stand-ins moving with the real blades and shields.
	for entry in _proxies:
		if is_instance_valid(entry[0]) and is_instance_valid(entry[1]):
			entry[1].visible = entry[0].visible
			_sync_proxy(entry)
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
	var crack: bool = index == _implode or index == _implode + 1
	if index == _implode:
		Sfx.play_flat(get_tree(), "impact_boom", _profile["volume"], 1.0 + (1.0 - float(_profile["blast"])) * 0.5)
	_jolt_goal = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * jolt * (2.5 if crack else 1.0)
	if crack and camera_rig and camera_rig.has_method("add_shake"):
		camera_rig.call("add_shake", _profile["shake"])
