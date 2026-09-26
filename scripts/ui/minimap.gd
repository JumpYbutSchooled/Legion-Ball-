extends CanvasLayer
## Minimap, top-left. The whole level from above, north up, fitted into the box; taller
## walls draw brighter. You're the arrow, pointing the way the camera looks. Other players
## only show while you can actually see them (nothing in the way) or they're very close,
## then fade out where they were last seen, so the map doesn't give everyone's position
## away.
## Reads the level itself: every box collider under the arena's Map node, plus the map's
## outline() if it has one (sprawl_map.gd).

const UIStyle := preload("res://scripts/ui/ui_style.gd")

const SIZE := 220.0
const MARGIN := 20.0
## Space round the map inside the box (the top has the "// MAP" header).
const PAD := 20.0
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
## The whole level's extent (x, z), fitted into the box.
var _bounds := Rect2()
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
	# The level's extent: its outline, else its floors, else everything.
	var points := PackedVector2Array(_outline)
	if points.is_empty():
		for poly in _floors:
			points.append_array(poly)
	if points.is_empty():
		for shape in _shapes:
			points.append_array(shape[0])
	if not points.is_empty():
		_bounds = Rect2(points[0], Vector2.ZERO)
		for p in points:
			_bounds = _bounds.expand(p)


func _collect(node: Node) -> void:
	for child in node.get_children():
		_collect(child)
	# Roofs and ceilings (map_builder.gd no_minimap) would hide everything under them.
	if node.has_meta("no_minimap"):
		return
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
	# The whole level, north up, fitted inside the box.
	var span := maxf(maxf(_bounds.size.x, _bounds.size.y), 1.0)
	var zoom := (SIZE - PAD * 2.0) / span
	var to_screen := Transform2D(0.0, Vector2(zoom, zoom), 0.0, center + Vector2(0.0, 4.0)) * Transform2D(0.0, -_bounds.get_center())

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
		var col := Color(UIStyle.ACCENT, lerpf(0.16, 0.75, k))
		_panel.draw_colored_polygon(shape[0], col)
		# Zoomed out this far, thin walls are under a pixel wide: outline the tall ones.
		if k > 0.5:
			var loop := PackedVector2Array(shape[0])
			loop.append(loop[0])
			_panel.draw_polyline(loop, col, -1.0)
	# The level's edge.
	var edges: Array = [_outline] if _outline.size() >= 3 else _floors
	for loop_points in edges:
		var edge := PackedVector2Array(loop_points)
		edge.append(edge[0])
		_panel.draw_polyline(edge, Color(UIStyle.ACCENT, 0.8), -1.0)
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

	# HUNTER'S SIGIL tags (only ours exist on this computer): a pulsing red diamond, seen
	# through walls, pinned to the edge if off the map.
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 120.0)
	for mark in get_tree().get_nodes_in_group("sigil_marks"):
		var mp: Vector3 = (mark as Node3D).global_position
		var spot: Vector2 = (to_screen * Vector2(mp.x, mp.z)).clamp(Vector2(8, 8), rect.size - Vector2(8, 8))
		var r := 7.0 * pulse
		var diamond := PackedVector2Array([spot + Vector2(0, -r), spot + Vector2(r, 0), spot + Vector2(0, r), spot + Vector2(-r, 0)])
		var red: Color = mark.get("color")
		_panel.draw_colored_polygon(diamond, Color(red, 0.85))
		diamond.append(diamond[0])
		_panel.draw_polyline(diamond, Color.WHITE, 1.5)

	# You: an arrow where you are, pointing the way the camera looks.
	var fwd := -cam.global_basis.z
	var facing := Vector2(fwd.x, fwd.z)
	if facing.length_squared() < 0.0001:
		var up := cam.global_basis.y
		facing = Vector2(up.x, up.z)
	var me: Vector2 = to_screen * Vector2(ball.global_position.x, ball.global_position.z)
	_panel.draw_set_transform_matrix(Transform2D(facing.angle() + PI / 2.0, me))
	var arrow := PackedVector2Array([Vector2(0, -7), Vector2(5, 5), Vector2(0, 2.5), Vector2(-5, 5)])
	_panel.draw_colored_polygon(arrow, Color.WHITE)
	_panel.draw_set_transform_matrix(Transform2D.IDENTITY)

	# North is always up.
	_panel.draw_string(_font, Vector2(SIZE - 18.0, 16.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIStyle.ACCENT)

	# Frame: hairline border, bright corner brackets and a header, like the speedometer.
	_panel.draw_rect(rect, Color(UIStyle.ACCENT, 0.25), false, 1.0)
	var b := 12.0
	for corner in [rect.position, Vector2(rect.end.x, 0), rect.end, Vector2(0, rect.end.y)]:
		var sx := 1.0 if corner.x == 0.0 else -1.0
		var sy := 1.0 if corner.y == 0.0 else -1.0
		_panel.draw_line(corner, corner + Vector2(b * sx, 0), UIStyle.ACCENT, 2.0)
		_panel.draw_line(corner, corner + Vector2(0, b * sy), UIStyle.ACCENT, 2.0)
	_panel.draw_string(_font, Vector2(10, 16), "// MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIStyle.TEXT_DIM)
