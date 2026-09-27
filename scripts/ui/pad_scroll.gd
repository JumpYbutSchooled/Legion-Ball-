extends Node
## Controller scrolling for a menu ScrollContainer: add one as a child of the scroll area
## (attach()). The right stick scrolls it, and moving focus with the d-pad / left stick
## keeps the focused button in view.

## Pixels a second at full tilt.
const SPEED := 1600.0
const DEADZONE := 0.2


## Sets up `scroll` for controllers.
static func attach(scroll: ScrollContainer) -> void:
	scroll.follow_focus = true
	var pad: Node = load("res://scripts/ui/pad_scroll.gd").new()
	pad.name = "PadScroll"
	scroll.add_child(pad)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var scroll := get_parent() as ScrollContainer
	if not scroll or not scroll.is_visible_in_tree():
		return
	var y := 0.0
	for device in Input.get_connected_joypads():
		var v := Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
		if absf(v) > absf(y):
			y = v
	if absf(y) < DEADZONE:
		return
	# Eased so small tilts scroll slowly.
	var k := (absf(y) - DEADZONE) / (1.0 - DEADZONE)
	scroll.scroll_vertical += int(signf(y) * k * k * SPEED * delta)
