extends CanvasLayer
## Minimap, top-left. The level from above, turning with the camera so straight up is the
## way you're looking; taller walls draw brighter. Other players only show while you can
## actually see them (nothing in the way) or they're very close, then fade out where they
## were last seen, so the map doesn't give everyone's position away.
## Reads the level itself: every box collider under the arena's Map node, plus the map's
## outline() if it has one (sprawl_map.gd).

const UIStyle := preload("res://scripts/ui/ui_style.gd")

const SIZE := 220.0
const MARGIN := 20.0
## Metres from the centre of the minimap to its edge.
const RANGE := 130.0
## Players this close always show, wall or not.
const CLOSE := 25.0
## Seconds a player's last-seen dot takes to fade.
const FADE := 2.5
const CHECK_INTERVAL := 0.1
## Boxes with a footprint bigger than this are floors.
const FLOOR_AREA := 40000.0

var ball: RigidBody3D

var _panel: Control
var _font: Font
var _outline := PackedVector2Array()
var _floors: Array = []  # PackedVector2Array each
var _shapes: Array = []  # [footprint, top height], lowest first
var _collected := false
var _seen := {}  # peer id -> [last seen position (x, z), seconds since]
var _check_timer := 0.0


func _ready() -> void:
	layer = 4
	_font = UIStyle.font(true)
	_panel = Control.new()
	_panel.position = Vector2(MARGIN, MARGIN)
	_panel.size = Vector2(SIZE, SIZE)
	_panel.clip_contents = true
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_map)
	add_child(_panel)


func _process(delta: float) -> void:
	for id in _seen:
		_seen[id][1] += delta
	_panel.queue_redraw()


func _physics_process(delta: float) -> void:
	_check_timer -= delta
	var arena := _arena()
	if _check_timer > 0.0 or not ball or not arena:
		return
	_check_timer = CHECK_INTERVAL
	var alive: Dictionary = arena.get("alive")
	var space := ball.get_world_3d().direct_space_state
	var eye := ball.global_position + Vector3.UP * 0.5
	for other in arena.get_node("Players").get_children():
		if other == ball or not other is RigidBody3D:
			continue
		var id := int(String(other.name).trim_prefix("P"))
		if not alive.get(id, true):
			_seen.erase(id)
			continue
		var to: Vector3 = other.global_position + Vector3.UP * 0.5
		var in_sight := eye.distance_to(to) < CLOSE
		if not in_sight:
			var query := PhysicsRayQueryParameters3D.create(eye, to)
			query.exclude = [ball.get_rid()]
			var hit := space.intersect_ray(query)
			in_sight = hit.is_empty() or hit.get("collider") == other
		if in_sight:
			_seen[id] = [Vector2(to.x, to.z), 0.0]


func _arena() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.has_method("player_ball") else null


func _collect_level() -> void:
	_collected = true
	var arena := _arena()
	var map := arena.get_node_or_null("Map") if arena else null
	if not map:
		return
	var layout := map.get_node_or_null("Layout")
	if layout and layout.has_method("outline"):
		_outline = layout.call("outline")
	_collect(map)
	_shapes.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])


func _collect(node: Node) -> void:
	for child in node.get_children():
		_collect(child)
	var size := Vector3.ZERO
	if node is CSGBox3D and (node as CSGBox3D).use_collision:
		size = (node as CSGBox3D).size
	elif node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:
		size = ((node as CollisionShape3D).shape as BoxShape3D).size
	if size == Vector3.ZERO:
		return
	var xf: Transform3D = (node as Node3D).global_transform
	var poly := PackedVector2Array()
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		var p: Vector3 = xf * (corner * size / 2.0)
		poly.append(Vector2(p.x, p.z))
	if size.x * size.z > FLOOR_AREA:
		_floors.append(poly)
	else:
		_shapes.append([poly, (xf * Vector3(0, size.y / 2.0, 0)).y])


func _draw_map() -> void:
	var cam := get_viewport().get_camera_3d()
	if not ball or not cam:
		return
	if not _collected:
		_collect_level()
	var rect := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	var center := rect.size / 2.0
	# Turn the map so the camera's facing points straight up.
	var fwd := -cam.global_basis.z
	var facing := Vector2(fwd.x, fwd.z)
	if facing.length_squared() < 0.0001:
		var up := cam.global_basis.y
		facing = Vector2(up.x, up.z)
	var turn := -PI / 2.0 - facing.angle()
	var me := Vector2(ball.global_position.x, ball.global_position.z)
	var zoom := center.x / RANGE
	var to_screen := Transform2D(turn, Vector2(zoom, zoom), 0.0, center) * Transform2D(0.0, -me)

	_panel.draw_rect(rect, Color(0.02, 0.05, 0.08, 0.62))
	_panel.draw_set_transform_matrix(to_screen)
	var ground := Color(UIStyle.ACCENT, 0.07)
	if _outline.size() >= 3:
		_panel.draw_colored_polygon(_outline, ground)
	else:
		for poly in _floors:
			_panel.draw_colored_polygon(poly, ground)
	for shape in _shapes:
		var k := clampf(shape[1] / 40.0, 0.0, 1.0)
		_panel.draw_colored_polygon(shape[0], Color(UIStyle.ACCENT, lerpf(0.16, 0.75, k)))
	_panel.draw_set_transform_matrix(Transform2D.IDENTITY)

	# Other players, where they were last seen; pinned to the edge if off the map.
	var net := get_tree().root.get_node_or_null("Net")
	var arena := _arena()
	if arena:
		for other in arena.get_node("Players").get_children():
			var id := int(String(other.name).trim_prefix("P"))
			if other == ball or not _seen.has(id):
				continue
			var age: float = _seen[id][1]
			var alpha := clampf(1.0 - (age - CHECK_INTERVAL * 1.5) / FADE, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var pos: Vector2 = (to_screen * (_seen[id][0] as Vector2)).clamp(Vector2(6, 6), rect.size - Vector2(6, 6))
			var color: Color = net.call("player_color", id) if net else Color.WHITE
			_panel.draw_circle(pos, 5.5, Color(0, 0, 0, 0.6 * alpha))
			_panel.draw_circle(pos, 4.0, Color(color, alpha))

	# You: an arrow in the middle, always pointing up.
	_panel.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -8), center + Vector2(6, 6), center + Vector2(0, 3), center + Vector2(-6, 6),
	]), Color.WHITE)

	# North marker on the rim.
	var north := center + Vector2(0, -1).rotated(turn) * (center.x - 12.0)
	_panel.draw_string(_font, north + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIStyle.ACCENT)

	# Frame: hairline border, bright corner brackets and a header, like the speedometer.
	_panel.draw_rect(rect, Color(UIStyle.ACCENT, 0.25), false, 1.0)
	var b := 12.0
	for corner in [rect.position, Vector2(rect.end.x, 0), rect.end, Vector2(0, rect.end.y)]:
		var sx := 1.0 if corner.x == 0.0 else -1.0
		var sy := 1.0 if corner.y == 0.0 else -1.0
		_panel.draw_line(corner, corner + Vector2(b * sx, 0), UIStyle.ACCENT, 2.0)
		_panel.draw_line(corner, corner + Vector2(0, b * sy), UIStyle.ACCENT, 2.0)
	_panel.draw_string(_font, Vector2(10, 16), "// MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIStyle.TEXT_DIM)
