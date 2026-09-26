extends Node3D
## Where a wall-piercing shot passes through a wall (Tears of an Angel missiles, Rain of
## God bolts): a white ripple spreads over the wall's surface and the wall warps round
## the hole, on the face it went in and the face it came out.
## crossings() finds those faces along a path; spawn() makes one ripple. Purely visual.

const RippleShader := preload("res://shaders/ripple.gdshader")
const MuzzleWarp := preload("res://scripts/muzzle_warp.gd")

@export var radius := 2.6
@export var lifetime := 0.55
@export var warp_strength := 0.16

var _quad: MeshInstance3D
var _t := 0.0

static var _mat: ShaderMaterial
static var _mesh: QuadMesh


## A ripple at `pos` on a wall facing `normal`, added under `parent`.
static func spawn(parent: Node, pos: Vector3, normal: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or not parent or not parent.is_inside_tree():
		return
	var ripple: Node3D = load("res://scripts/wall_ripple.gd").new()
	parent.add_child(ripple)
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
	# The quad faces +Z: point that out of the wall, just off its surface.
	ripple.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.04)


## Ripples on every wall face crossed between `from` and `to`.
static func pierce(parent: Node, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> void:
	for c in crossings(space, from, to, exclude):
		spawn(parent, c[0], c[1])


## Every wall face crossed going from `from` to `to`: [position, outward normal] for
## each entry and each exit (players and targets don't count, only solid level).
## Casts a few rays each way, so it's cheap enough for every shot.
static func crossings(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Array:
	var out: Array = []
	for pass_i in 2:
		var a := from if pass_i == 0 else to
		var b := to if pass_i == 0 else from
		var skip: Array[RID] = exclude.duplicate()
		for i in 6:
			var query := PhysicsRayQueryParameters3D.create(a, b)
			query.exclude = skip
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			var collider: Object = hit["collider"]
			skip.append(hit["rid"])
			if collider.has_method("take_hit"):
				continue  # A player or target, not a wall.
			out.append([hit["position"], hit["normal"]])
	return out


func _ready() -> void:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = RippleShader
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(2, 2)
	_quad = MeshInstance3D.new()
	_quad.mesh = _mesh
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.scale = Vector3.ONE * radius
	add_child(_quad)
	# The wall itself warps round the hole.
	var warp := MuzzleWarp.new()
	warp.strength = warp_strength
	warp.start_radius = 0.3
	warp.end_radius = radius * 0.9
	warp.lifetime = lifetime * 0.7
	add_child(warp)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	_update()


func _update() -> void:
	_quad.set_instance_shader_parameter("progress", ease(_t / lifetime, 0.6))
