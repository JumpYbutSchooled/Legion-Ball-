extends CanvasLayer
## NAME CREATOR only, practice (moderation.gd practice_toggle_cinematic): a widescreen
## letterbox and a soft vignette, for lining up trailer shots. Purely visual - no
## gameplay effect. Created on demand by moderation.gd the first time it's turned on, as
## a child of the arena, and just hidden (not freed) when it's turned off.

const BAR_RATIO := 0.12
const VIGNETTE_SHADER := "res://shaders/vignette.gdshader"


func _ready() -> void:
	layer = 90  # Above the HUD, so the bars cover it if picture mode is off.
	visible = false
	var top := ColorRect.new()
	top.color = Color.BLACK
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.anchor_bottom = BAR_RATIO
	add_child(top)
	var bottom := ColorRect.new()
	bottom.color = Color.BLACK
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.anchor_top = 1.0 - BAR_RATIO
	add_child(bottom)
	var vignette := ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load(VIGNETTE_SHADER)
	vignette.material = mat
	add_child(vignette)


func set_enabled(on: bool) -> void:
	visible = on
