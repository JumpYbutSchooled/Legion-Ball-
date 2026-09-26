extends Node3D
## Shared toolkit for maps built in code when they load (Coliseum, The Box, Thunder Dome,
## Tunnels, City; Sprawl predates it and has its own copy). Everything solid is a box with
## a matching box collider, because the spark particle colliders (spark_colliders.gd) and
## the minimap (minimap.gd) only understand boxes.
## A map extends this, fills in _build(), and sets:
##   _spawns   where players (re)spawn          -> spawn_points()
##   _turrets  where AI turrets stand           -> turret_points()
##   _outline  the boundary, for the minimap    -> outline()
##   _ceiling  height where rising bleeds off   -> ceiling()   (ball.gd max_height)
##   _fall     height below which you've fallen off -> fall_height() (ball.gd fall_reset_height)
## Randomness must come from a fixed seed (_rng) so every computer builds the same map.
## Builds in _ready, which runs before the parent Map's, so Map's particle colliders
## cover all of it.

const CheckerShader := preload("res://shaders/checker.gdshader")
const PanelShader := preload("res://shaders/panel.gdshader")

var _spawns: Array[Vector3] = []
var _turrets: Array[Vector3] = []
var _outline := PackedVector2Array()
var _ceiling := 120.0
var _fall := -20.0
var _rng := RandomNumberGenerator.new()
var _phys := PhysicsMaterial.new()


func _ready() -> void:
	_phys.friction = 1.0
	_build()


## Overridden by each map.
func _build() -> void:
	pass


func spawn_points() -> Array[Vector3]:
	return _spawns


func turret_points() -> Array[Vector3]:
	return _turrets


func outline() -> PackedVector2Array:
	return _outline


func ceiling() -> float:
	return _ceiling


func fall_height() -> float:
	return _fall


# --- Pieces ---------------------------------------------------------------------------

## A solid box: turned `yaw` about Y, then tipped `pitch` (its +z end goes down).
## `minimap` false keeps it off the minimap (roofs, ceilings).
func box(center: Vector3, size: Vector3, mat: Material, yaw := 0.0, pitch := 0.0, minimap := true) -> StaticBody3D:
	return box_basis(Basis.from_euler(Vector3(pitch, yaw, 0.0)), center, size, mat, minimap)


func box_basis(basis: Basis, center: Vector3, size: Vector3, mat: Material, minimap := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = Transform3D(basis, center)
	body.physics_material_override = _phys
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	if not minimap:
		shape.set_meta("no_minimap", true)
	body.add_child(shape)
	add_child(body)
	return body


## Looks only, no collision (glow strips, trim).
func deco(center: Vector3, size: Vector3, mat: Material, yaw := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), center)
	add_child(mesh)
	return mesh


## A wall from a to b (x, z) standing on `y0`.
func wall(a: Vector2, b: Vector2, y0: float, height: float, thick: float, mat: Material, minimap := true) -> StaticBody3D:
	var d := b - a
	var mid := (a + b) / 2.0
	return box(Vector3(mid.x, y0 + height / 2.0, mid.y), Vector3(d.length() + thick, height, thick), mat, -d.angle(), 0.0, minimap)


## A plank ramp whose top surface runs from `low` up to `high` (centre-line points).
func ramp(low: Vector3, high: Vector3, width: float, mat: Material) -> StaticBody3D:
	var flat := Vector2(high.x - low.x, high.z - low.z)
	var run := flat.length()
	var rise := high.y - low.y
	var out := -flat / run  # Downhill, which the box's +z end points along.
	var yaw := atan2(out.x, out.y)
	var pitch := atan2(rise, run)
	var center := (low + high) / 2.0 + Vector3.DOWN * 0.25 / cos(pitch)
	return box(center, Vector3(width, 0.5, sqrt(run * run + rise * rise) + 0.3), mat, yaw, pitch)


## A ring of wall segments round `center`. Segments whose index is in `gaps` are left out.
func ring(center: Vector2, radius: float, sides: int, y0: float, height: float, thick: float, mat: Material, gaps := []) -> void:
	for i in sides:
		if gaps.has(i):
			continue
		var a := center + Vector2.from_angle(TAU * i / sides) * radius
		var b := center + Vector2.from_angle(TAU * (i + 1) / sides) * radius
		wall(a, b, y0, height, thick, mat)


## The ground: one big slab under everything, top at y = 0.
func ground(rect: Rect2, mat: Material) -> void:
	var c := rect.get_center()
	box(Vector3(c.x, -0.5, c.y), Vector3(rect.size.x, 1.0, rect.size.y), mat)


## A flat round slab (top at `top`): rings of blocks, like the Coliseum's tiers.
func disc(center: Vector3, radius: float, thick: float, mat: Material, rings := 4, minimap := true) -> void:
	var inner := radius / rings
	box(Vector3(center.x, center.y - thick / 2.0, center.z), Vector3(inner * 1.42, thick, inner * 1.42), mat, 0.0, 0.0, minimap)
	for i in range(1, rings):
		var r0 := radius * i / rings
		var r1 := radius * (i + 1) / rings
		var sides := maxi(12, int(TAU * r1 / 14.0))
		var step := TAU / sides
		for s in sides:
			var mid := step * (s + 0.5)
			var c := Vector2.from_angle(mid) * (r0 + r1) / 2.0
			box(Vector3(center.x + c.x, center.y - thick / 2.0, center.z + c.y), Vector3(r1 - r0 + 0.6, thick, 2.0 * r1 * sin(step / 2.0) + 0.4), mat, -mid, 0.0, minimap)


## A square column from the ground (y0) up `height`.
func pillar(p: Vector2, y0: float, width: float, height: float, mat: Material, yaw := 0.0) -> StaticBody3D:
	return box(Vector3(p.x, y0 + height / 2.0, p.y), Vector3(width, height, width), mat, yaw)


## Steps from `low` (x, z at y) climbing `count` steps of `rise` each toward `dir`.
func stairs(low: Vector3, dir: Vector2, count: int, rise: float, tread: float, width: float, mat: Material) -> void:
	var d := dir.normalized()
	for i in count:
		var p := Vector2(low.x, low.z) + d * tread * (i + 0.5)
		var h := rise * (i + 1)
		box(Vector3(p.x, low.y + h / 2.0, p.y), Vector3(width, h, tread), mat, atan2(d.x, d.y))


## One piece of banked track: a slab `width` across and `length` along, centred on the
## track's centre line at `p` (x, z), with `outward` pointing to the outside of the
## turn. It's tilted `bank` radians so the outside edge is raised; the inside edge sits
## at `base_y`. Returns the height of the outside edge (for the wall on top of it).
func bank_box(p: Vector2, outward: Vector2, width: float, length: float, bank: float, base_y: float, mat: Material, thick := 1.2) -> float:
	var u := Vector3(outward.x, 0.0, outward.y).normalized()
	# Local X across (towards the outside), Y up, Z along the track; then tipped about Z.
	var basis := Basis(u, Vector3.UP, u.cross(Vector3.UP).normalized()) * Basis(Vector3(0, 0, 1), bank)
	var top_mid := base_y + width / 2.0 * sin(bank)
	box_basis(basis, Vector3(p.x, top_mid, p.y) - basis.y * thick / 2.0, Vector3(width, thick, length), mat)
	return base_y + width * sin(bank)

## A regular polygon outline (for round maps).
static func circle_outline(radius: float, sides: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in sides:
		out.append(Vector2.from_angle(TAU * i / sides) * radius)
	return out


static func rect_outline(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


# --- Materials --------------------------------------------------------------------------

static func solid(color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r * 0.2, color.g * 0.2, color.b * 0.2)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func checker(a: Color, b: Color, cell_size := 4.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CheckerShader
	mat.set_shader_parameter("color_a", a)
	mat.set_shader_parameter("color_b", b)
	mat.set_shader_parameter("cell_size", cell_size)
	return mat


static func panel(base: Color, line: Color, cell := 4.0, line_glow := 0.0, windows := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PanelShader
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("line_color", line)
	mat.set_shader_parameter("cell", cell)
	mat.set_shader_parameter("line_glow", line_glow)
	mat.set_shader_parameter("windows", windows)
	return mat
