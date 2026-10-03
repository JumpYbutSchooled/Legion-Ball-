extends Node
## The owner tag's moving colours: pink -> white -> light blue and back. On a Label (font
## colour) or a Label3D (modulate) the whole tag flows through them; rich text gets a
## gradient that sweeps across the letters ([owner] BBCode, scripts/ui/owner_fx.gd - see
## bbcode() and install()).

const SPEED := 0.35
const PINK := Color(1.0, 0.55, 0.8)
const WHITE := Color(1.0, 1.0, 1.0)
const BLUE := Color(0.5, 0.82, 1.0)
const OwnerFx := preload("res://scripts/ui/owner_fx.gd")

var _offset := 0.0


## Puts the moving colours on `label` (a Label or Label3D), or takes them off.
static func set_on(label: Node, on: bool) -> void:
	var existing := label.get_node_or_null("Rainbow")
	if on and not existing:
		var r: Node = load("res://scripts/ui/rainbow.gd").new()
		r.name = "Rainbow"
		label.add_child(r)
	elif not on and existing:
		existing.queue_free()


## `text` with the sweeping gradient, for a RichTextLabel that has had install() run.
static func bbcode(text: String) -> String:
	return "[owner]%s[/owner]" % text


## Lets a RichTextLabel draw [owner] text.
static func install(label: RichTextLabel) -> void:
	for fx in label.custom_effects:
		if fx is OwnerFx:
			return
	label.install_effect(OwnerFx.new())


## The gradient at `t` (wraps every 1.0): pink, white, light blue, white, pink.
static func color_at(t: float) -> Color:
	var k := fposmod(t, 1.0) * 4.0
	if k < 1.0:
		return PINK.lerp(WHITE, k)
	if k < 2.0:
		return WHITE.lerp(BLUE, k - 1.0)
	if k < 3.0:
		return BLUE.lerp(WHITE, k - 2.0)
	return WHITE.lerp(PINK, k - 3.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_offset = randf()


func _process(_delta: float) -> void:
	var c := color_at(Time.get_ticks_msec() / 1000.0 * SPEED + _offset)
	var p := get_parent()
	if p is Label3D:
		(p as Label3D).modulate = c
	elif p is Label:
		(p as Label).add_theme_color_override("font_color", c)
