extends CanvasLayer
## The loadout along the bottom of the screen (local player; added by local_view.gd): one
## cell per weapon with its key and name in its own colour, the one in hand lit and raised,
## dimmed while it's put away. Redrawn only when the loadout, the weapon in hand or whether
## it's drawn changes.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const InputSetup := preload("res://scripts/input_setup.gd")
const CELL := Vector2(132, 42)
const GAP := 6.0

var weapon: Node

var _root: Control
var _font: Font
var _font_bold: Font
var _key := ""


func _ready() -> void:
	layer = 3
	_font = UIStyle.font()
	_font_bold = UIStyle.font(true)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_bar)
	add_child(_root)


func _process(_delta: float) -> void:
	if not weapon:
		return
	var mod := get_tree().root.get_node_or_null("Mod")
	_root.visible = not (mod and mod.get("picture_mode"))
	var key := "%s|%d|%s|%d|%s" % [weapon.get("slot_ids"), weapon.get("current"), weapon.call("is_drawn"), weapon.call("unlocked_count"), _root.size]
	if key != _key:
		_key = key
		_root.queue_redraw()


func _draw_bar() -> void:
	if not weapon:
		return
	var count: int = weapon.call("unlocked_count")
	var current: int = weapon.get("current")
	var drawn: bool = weapon.call("is_drawn")
	var size: int = weapon.get("loadout_size")
	# Juggernaut carries every weapon: just the one in hand then.
	var slots: Array = range(count) if count <= 9 else [current]
	var total := slots.size() * CELL.x + (slots.size() - 1) * GAP
	var x := (_root.size.x - total) / 2.0
	var y := _root.size.y - CELL.y - 14.0
	for slot in slots:
		var info: Dictionary = weapon.call("slot_info", slot)
		var col: Color = info.get("color", Color.WHITE)
		var on: bool = slot == current
		var rect := Rect2(Vector2(x, y - (5.0 if on and drawn else 0.0)), CELL)
		_root.draw_rect(rect, Color(0.02, 0.05, 0.08, 0.62 if on else 0.4))
		_root.draw_rect(rect, Color(col, (0.95 if drawn else 0.5) if on else 0.2), false, 2.0 if on else 1.0)
		_root.draw_rect(Rect2(rect.position, Vector2(3.0, CELL.y)), Color(col, 0.9 if on else 0.4))
		var key_text := str(slot + 1) if slot < size else str(slot - size + 7)
		_root.draw_string(_font_bold, rect.position + Vector2(10, 17), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9 if on else 0.45))
		var name := String(info.get("name", "?"))
		_root.draw_string(_font_bold if on else _font, rect.position + Vector2(10, 35), name, HORIZONTAL_ALIGNMENT_LEFT, CELL.x - 14.0, 13,
			Color(col.lerp(Color.WHITE, 0.35), 1.0 if on and drawn else 0.55))
		x += CELL.x + GAP
