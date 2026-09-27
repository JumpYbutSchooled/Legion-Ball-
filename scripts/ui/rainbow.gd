extends Node
## Cycles its parent's colour through the rainbow (the OWNER tag). Works on a Label
## (font colour) or a Label3D (modulate). Rich text uses the [rainbow] BBCode instead
## (bbcode()).

const SPEED := 0.35

var _offset := 0.0


## Puts a rainbow on `label` (a Label or Label3D), or takes it off.
static func set_on(label: Node, on: bool) -> void:
	var existing := label.get_node_or_null("Rainbow")
	if on and not existing:
		var r: Node = load("res://scripts/ui/rainbow.gd").new()
		r.name = "Rainbow"
		label.add_child(r)
	elif not on and existing:
		existing.queue_free()


## `text` in rainbow BBCode, for a RichTextLabel.
static func bbcode(text: String) -> String:
	return "[rainbow freq=0.25 sat=0.75 val=1.0]%s[/rainbow]" % text


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_offset = randf()


func _process(_delta: float) -> void:
	var c := Color.from_hsv(fposmod(Time.get_ticks_msec() / 1000.0 * SPEED + _offset, 1.0), 0.7, 1.0)
	var p := get_parent()
	if p is Label3D:
		(p as Label3D).modulate = c
	elif p is Label:
		(p as Label).add_theme_color_override("font_color", c)
