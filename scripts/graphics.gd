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
	apply_scene(tree)
	apply_audio(tree)


## The loaded map's own sun and environment.
static func apply_scene(tree: SceneTree) -> void:
	var scene := tree.current_scene
	var s := tree.root.get_node_or_null("Settings")
	if not scene or not s or DisplayServer.get_name() == "headless":
		return
	var env_node := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node and env_node.environment:
		var env := env_node.environment
		env.ssao_enabled = s.call("get_value", "ssao")
		env.ssr_enabled = s.call("get_value", "ssr")
		env.ssil_enabled = s.call("get_value", "ssil")
		if env.ssr_enabled:
			env.ssr_max_steps = 48
			env.ssr_fade_in = 0.2
			env.ssr_fade_out = 2.0
	var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		# Roofed maps (the house, the dome...) are lit by their lamps: a sun shadow would
		# black them out.
		var layout := scene.get_node_or_null("Map/Layout")
		var indoor: bool = layout != null and layout.has_method("is_indoor") and layout.call("is_indoor")
		var on: bool = s.call("get_value", "shadows") and not indoor
		sun.shadow_enabled = on
		if on:
			var preset: String = s.call("get_value", "graphics_preset")
			sun.directional_shadow_max_distance = SHADOW_DISTANCE.get(preset, 320.0)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.shadow_blur = 1.5 if preset == "ULTRA" else 1.0
			sun.shadow_opacity = 0.85


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
