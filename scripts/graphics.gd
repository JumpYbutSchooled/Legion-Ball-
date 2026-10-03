extends RefCounted
## Graphics and audio options from Settings, applied to the game:
##   - quality presets (LOW / MEDIUM / HIGH / ULTRA) that set the individual options below
##   - sun shadows, anti-aliasing, ambient occlusion, reflections, indirect light (ULTRA),
##     render scale (with FSR upscaling below 100%), frame cap
##   - volume channels: Master, SFX and Music
## apply() runs at startup, whenever a setting changes, and when a map loads (the map
## brings its own sun and environment).

## What each preset sets.
const PRESETS := {
	"LOW": {"shadows": false, "aa": "OFF", "ssao": false, "ssr": false, "ssil": false, "render_scale": 0.75},
	"MEDIUM": {"shadows": true, "aa": "FXAA", "ssao": false, "ssr": false, "ssil": false, "render_scale": 1.0},
	"HIGH": {"shadows": true, "aa": "MSAA 2X", "ssao": true, "ssr": false, "ssil": false, "render_scale": 1.0},
	"ULTRA": {"shadows": true, "aa": "MSAA 4X", "ssao": true, "ssr": true, "ssil": true, "render_scale": 1.0},
}
const AA_MODES := ["OFF", "FXAA", "MSAA 2X", "MSAA 4X", "TAA"]
## How far the sun's shadows reach (metres), per preset.
const SHADOW_DISTANCE := {"LOW": 0.0, "MEDIUM": 180.0, "HIGH": 320.0, "ULTRA": 520.0}
## The look laid over every map (_grade): sun brighter, flat sky light lower.
const SUN_BOOST := 1.35
const AMBIENT_CUT := 0.45
const EXPOSURE := 0.95
const EXPOSURE_INDOOR := 1.2
const CONTRAST := 1.05
## Near-white suns are warmed this much toward SUN_WARM (sunny side warm, shade cool).
const SUN_WARM := Color(1.0, 0.9, 0.76)
const SUN_WARMTH := 0.35
const SUN_MAX_ELEVATION := 0.84  # radians, about 48 degrees
const SATURATION := 1.1
const VignetteShader := preload("res://shaders/vignette.gdshader")


## Everything, from the current settings.
static func apply(tree: SceneTree) -> void:
	if not tree or DisplayServer.get_name() == "headless":
		return
	var s := tree.root.get_node_or_null("Settings")
	if not s:
		return
	var get := func(key: String) -> Variant: return s.call("get_value", key)
	var viewport := tree.root.get_viewport()
	var aa: String = get.call("aa")
	viewport.msaa_3d = {"MSAA 2X": Viewport.MSAA_2X, "MSAA 4X": Viewport.MSAA_4X}.get(aa, Viewport.MSAA_DISABLED)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "FXAA" else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = aa == "TAA"
	var scale: float = get.call("render_scale")
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = clampf(scale, 0.5, 1.0)
	Engine.max_fps = int(get.call("max_fps"))
	viewport.use_debanding = true
	# Surface detail on the map materials (shaders/detail.gdshaderinc): off on LOW.
	RenderingServer.global_shader_parameter_set("surface_detail", 0.0 if get.call("graphics_preset") == "LOW" else 1.0)
	apply_scene(tree)
	apply_audio(tree)


## The loaded map's own sun and environment.
static func apply_scene(tree: SceneTree) -> void:
	var scene := tree.current_scene
	var s := tree.root.get_node_or_null("Settings")
	if not scene or not s or DisplayServer.get_name() == "headless":
		return
	var env_node := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
	# Roofed maps (the house, the dome...) are lit by their lamps: a sun shadow would
	# black them out.
	var layout := scene.get_node_or_null("Map/Layout")
	var indoor: bool = layout != null and layout.has_method("is_indoor") and layout.call("is_indoor")
	if env_node and env_node.environment:
		var env := env_node.environment
		_grade(env, sun, indoor or not sun or sun.light_energy < 0.05)
		env.ssao_enabled = s.call("get_value", "ssao")
		env.ssr_enabled = s.call("get_value", "ssr")
		env.ssil_enabled = s.call("get_value", "ssil")
		if env.ssr_enabled:
			env.ssr_max_steps = 48
			env.ssr_fade_in = 0.2
			env.ssr_fade_out = 2.0
		var fancy: bool = s.call("get_value", "graphics_preset") != "LOW"
		_vignette(scene, fancy)
	if sun:
		var on: bool = s.call("get_value", "shadows") and not indoor
		sun.shadow_enabled = on
		if on:
			var preset: String = s.call("get_value", "graphics_preset")
			sun.directional_shadow_max_distance = SHADOW_DISTANCE.get(preset, 320.0)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.shadow_blur = 1.5 if preset == "ULTRA" else 1.0
			sun.shadow_opacity = 0.85


## The game's look, laid over each map's own lighting (once per environment): a filmic
## tonemap, less flat sky light so the sunny and shady sides of things differ, deeper
## ambient occlusion in corners, glow only from things that are actually bright, distance
## haze tinted by the sky, and a touch more contrast and colour.
static func _grade(env: Environment, sun: DirectionalLight3D, indoor: bool) -> void:
	var sun_energy := sun.light_energy if sun else 0.0
	if sun and not sun.has_meta("graded") and not indoor:
		sun.set_meta("graded", true)
		sun.light_energy *= SUN_BOOST
		if sun.light_color.s < 0.15:
			sun.light_color = sun.light_color.lerp(SUN_WARM, SUN_WARMTH)
		# A sun no higher than SUN_MAX_ELEVATION, so things cast real shadows across the
		# floor instead of a dot under themselves (same compass direction).
		var dir := -sun.global_basis.z
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length() < 0.01:
			flat = Vector3(0.6, 0.0, 0.8)
		if asin(-dir.y) > SUN_MAX_ELEVATION:
			var down := flat.normalized() * cos(SUN_MAX_ELEVATION) + Vector3.DOWN * sin(SUN_MAX_ELEVATION)
			var up := Vector3.UP if absf(down.y) < 0.99 else Vector3.FORWARD
			sun.global_basis = Basis.looking_at(down, up)
	if env.has_meta("graded"):
		return
	env.set_meta("graded", true)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	# Lamp-lit maps: the filmic curve darkens their mid-tones, so a little more exposure.
	env.tonemap_exposure = EXPOSURE_INDOOR if indoor else EXPOSURE
	env.tonemap_agx_contrast = 1.35
	env.tonemap_agx_white = 12.0
	if not indoor:
		# Weak suns (night maps) keep more of their sky light.
		env.ambient_light_energy *= lerpf(0.85, AMBIENT_CUT, clampf((sun_energy - 0.5) / 0.7, 0.0, 1.0))
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.4
	env.ssao_power = 1.7
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.4
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.8
	if env.fog_enabled and not indoor:
		env.fog_aerial_perspective = 0.35
		env.fog_sun_scatter = 0.12
		env.fog_density = maxf(env.fog_density, 0.0006)
	var saturation := env.adjustment_saturation if env.adjustment_enabled else 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = CONTRAST
	env.adjustment_saturation = saturation * SATURATION


## A soft darkening at the screen's edges, under the HUD (off on LOW).
static func _vignette(scene: Node, on: bool) -> void:
	var layer := scene.get_node_or_null("Vignette") as CanvasLayer
	if not layer and on:
		layer = CanvasLayer.new()
		layer.name = "Vignette"
		layer.layer = -1
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = VignetteShader  # the cinematic overlay's, much gentler
		mat.set_shader_parameter("strength", 0.3)
		mat.set_shader_parameter("radius", 1.25)
		mat.set_shader_parameter("softness", 0.8)
		rect.material = mat
		layer.add_child(rect)
		scene.add_child(layer)
	if layer:
		layer.visible = on


## Master / SFX / Music volumes (the buses are made if they don't exist yet).
static func apply_audio(tree: SceneTree) -> void:
	ensure_buses()
	var s := tree.root.get_node_or_null("Settings")
	if not s:
		return
	_set_bus("Master", s.call("get_value", "master_volume"))
	_set_bus("SFX", s.call("get_value", "sfx_volume"))


static func ensure_buses() -> void:
	for bus in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


static func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
