extends "res://scripts/maps/map_builder.gd"
## Shared builder for the superspeedways (Daytona 500, Talladega): a stadium oval with
## two straights along X and two banked turns. The banking eases in from the straights'
## gentle tilt to the full angle over the first and last part of each turn, and a tall
## retaining wall runs round the outside edge (down to the ground, so there's nothing to
## fall under). Grandstands tower over the front straight; a wall round the whole site
## keeps everyone in. A map sets the numbers below in _setup() and adds its own infield
## and trackside touches in _decorate().

## Straight length, turn radius (to the centre line), track width, and banking.
var straight := 380.0
var turn_radius := 150.0
var track_width := 36.0
var turn_bank := deg_to_rad(31.0)
var straight_bank := deg_to_rad(3.0)
## Share of each turn spent easing the banking in (and out again).
var bank_ease := 0.25
var segments := 40
var wall_height := 4.5
var stand_tiers := 9

var _asphalt: Material
var _apron: Material
var _wall: Material
var _grass: Material
var _stand: Material
var _stripe: Material


## Overridden: set the numbers above (and materials if you like).
func _setup() -> void:
	pass


## Overridden: infield buildings, wrecks, lights...
func _decorate() -> void:
	pass


func _build() -> void:
	_asphalt = checker(Color(0.16, 0.16, 0.18), Color(0.19, 0.19, 0.21), 8.0)
	_apron = solid(Color(0.26, 0.26, 0.28))
	_wall = panel(Color(0.85, 0.86, 0.9), Color(0.2, 0.35, 0.8), 6.0)
	_grass = checker(Color(0.2, 0.42, 0.18), Color(0.22, 0.46, 0.2), 12.0)
	_stand = panel(Color(0.5, 0.52, 0.58), Color(0.35, 0.37, 0.42), 3.0)
	_stripe = glow(Color(1.0, 0.95, 0.85), 1.4)
	_setup()
	var half_x := straight / 2.0 + turn_radius + track_width / 2.0 + 40.0
	var half_z := turn_radius + track_width / 2.0 + 110.0
	var bounds := Rect2(-half_x, -half_z, half_x * 2.0, half_z * 2.0)
	_outline = rect_outline(bounds)
	_ceiling = 130.0
	ground(bounds.grow(10.0), _grass)
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		var reach := half_z if k % 2 == 0 else half_x
		var span := half_x if k % 2 == 0 else half_z
		box(out * (reach + 2.0) + Vector3.UP * 30.0, Vector3(span * 2.0 + 8.0, 60.0, 4.0), _stand, yaw)
	_straights()
	for side: float in [1.0, -1.0]:
		_turn(side)
	_grandstands()
	# Spawns down both straights.
	for i in 8:
		var x := lerpf(-straight * 0.4, straight * 0.4, (i / 2) / 3.0)
		var z := turn_radius * (1.0 if i % 2 == 0 else -1.0)
		_spawns.append(Vector3(x, 1.5, z))
	_decorate()


func _straights() -> void:
	for side: float in [1.0, -1.0]:
		var z := side * turn_radius
		var p := Vector2(0.0, z)
		var outer_y := bank_box(p, Vector2(0.0, side), track_width, straight + 2.0, straight_bank, 0.0, _asphalt)
		# Retaining wall along the outside.
		var edge := z + side * (track_width / 2.0 * cos(straight_bank) + 0.7)
		box(Vector3(0.0, (outer_y + wall_height) / 2.0, edge), Vector3(straight + 2.0, outer_y + wall_height, 1.4), _wall)
		# Inside apron, a little lower, and the white line between.
		var apron_z := z - side * (track_width / 2.0 + 5.0)
		box(Vector3(0.0, -0.1, apron_z), Vector3(straight, 0.4, 10.0), _apron)
		deco(Vector3(0.0, 0.12, z - side * (track_width / 2.0 - 0.4)), Vector3(straight, 0.1, 0.5), _stripe)


## The turn at the +x end (side 1) or -x end (side -1): a half circle of banked slabs.
func _turn(side: float) -> void:
	var center := Vector2(side * straight / 2.0, 0.0)
	var step := PI / segments
	var outer_r := turn_radius + track_width / 2.0
	for i in segments:
		var a := -PI / 2.0 + step * (i + 0.5)
		var t := (i + 0.5) / segments
		var ease_in := clampf(t / bank_ease, 0.0, 1.0)
		var ease_out := clampf((1.0 - t) / bank_ease, 0.0, 1.0)
		var bank := lerpf(straight_bank, turn_bank, smoothstep(0.0, 1.0, minf(ease_in, ease_out)))
		var dir := Vector2(cos(a) * side, sin(a))
		var p := center + dir * turn_radius
		var length := 2.0 * outer_r * sin(step / 2.0) + 1.2
		var outer_y := bank_box(p, dir, track_width, length, bank, 0.0, _asphalt)
		# Retaining wall from the ground up past the outside edge.
		var edge := center + dir * (turn_radius + track_width / 2.0 * cos(bank) + 0.7)
		var u := Vector3(dir.x, 0.0, dir.y)
		var h := outer_y + wall_height
		box_basis(Basis(u, Vector3.UP, u.cross(Vector3.UP).normalized()), Vector3(edge.x, h / 2.0, edge.y), Vector3(1.4, h, length + 0.4), _wall)
		# The apron inside the turn.
		var inner := center + dir * (turn_radius - track_width / 2.0 - 5.0)
		box_basis(Basis(u, Vector3.UP, u.cross(Vector3.UP).normalized()), Vector3(inner.x, -0.1, inner.y), Vector3(10.0, 0.4, 2.0 * (turn_radius - track_width / 2.0) * sin(step / 2.0) + 1.0), _apron)


## Tiered stands behind the front straight's wall, with a roof on columns and a press box.
func _grandstands() -> void:
	var z0 := turn_radius + track_width / 2.0 + 8.0
	var length := straight * 0.9
	for t in stand_tiers:
		var h := 6.0 + t * 3.2
		box(Vector3(0.0, h / 2.0, z0 + t * 6.0 + 3.0), Vector3(length, h, 6.0), _stand)
	var back := z0 + stand_tiers * 6.0
	var top := 6.0 + stand_tiers * 3.2
	box(Vector3(0.0, top + 14.0, back - 12.0), Vector3(length, 1.0, 34.0), _wall, 0.0, 0.0, false)
	for i in 9:
		var x := lerpf(-length / 2.0 + 4.0, length / 2.0 - 4.0, i / 8.0)
		pillar(Vector2(x, back - 2.0), top, 1.6, 14.0, _stand)
	# Press box: a glass-fronted block on top.
	box(Vector3(0.0, top + 20.0, back - 14.0), Vector3(90.0, 10.0, 14.0), panel(Color(0.18, 0.2, 0.26), Color(0.4, 0.6, 1.0), 3.0, 0.6, 0.5), 0.0, 0.0, false)


## A stock car: body and cabin in a racing colour. Solid, so it's cover.
func car(p: Vector2, yaw: float, color: Color, y := 0.0, roll := 0.0) -> void:
	var body := solid(color, 0.35, 0.4)
	var basis := Basis.from_euler(Vector3(0.0, yaw, roll))
	box_basis(basis, Vector3(p.x, y + 1.0, p.y), Vector3(4.2, 2.0, 10.0), body)
	box_basis(basis, Vector3(p.x, y + 2.6, p.y) + basis.z * 0.6, Vector3(3.6, 1.4, 4.6), solid(Color(0.08, 0.1, 0.14), 0.2, 0.3))


## A light tower: a tall mast with a glowing head and a real light.
func light_tower(p: Vector2, height := 40.0) -> void:
	pillar(p, 0.0, 2.0, height, _stand)
	deco(Vector3(p.x, height + 1.5, p.y), Vector3(8.0, 3.0, 1.5), glow(Color(1.0, 0.95, 0.85), 6.0))
	var light := OmniLight3D.new()
	light.position = Vector3(p.x, height - 2.0, p.y)
	light.omni_range = 120.0
	light.light_energy = 1.2
	light.light_color = Color(1.0, 0.95, 0.85)
	add_child(light)
