extends Node3D
## One rift of the RIFT GUN's pair (practice only for now). Its +Z points out of the
## surface it's on. It shows the view through its partner (a camera behind the partner,
## where yours would be if the two rifts were one hole, rendering into a texture drawn
## lined up with the screen), bends the air round its rim, and sends the ball through:
## roll into it and you come out of the partner at the same speed, turned to match.

const ViewShader := preload("res://shaders/rift_view.gdshader")
const SteamScript := preload("res://scripts/steam.gd")
const WarpShader := preload("res://shaders/rift_warp.gdshader")
## Half width and half height of the oval (an upright rift, sized for the ball).
const RX := 2.2
const RY := 3.4
## How much of the quad the oval fills (rift_view.gdshader `fill`; the rest is halo).
const FILL := 0.78
## Render layer the rift surfaces are on, left out of the rift cameras (no recursion).
const RIFT_LAYER := 1 << 19
## Pass through: centre this close to the surface, this near its middle.
const TRIGGER := 1.25
## Turn a point in front of one rift round to face out of the other: 180 degrees
## about the rift's own up.
const FLIP := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))

var color := Color(0.2, 0.55, 1.0)
var partner: Node3D = null
var ball: RigidBody3D = null

var _surface: MeshInstance3D
var _surface_mat: ShaderMaterial
var _warp_mat: ShaderMaterial
var _viewport: SubViewport
var _cam: Camera3D
var _t := 0.0
var _cooldown := 0.0
var _open := 0.0


func _ready() -> void:
	_surface_mat = ShaderMaterial.new()
	_surface_mat.shader = ViewShader
	_surface_mat.set_shader_parameter("rim_color", Vector3(color.r, color.g, color.b))
	_surface = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(RX * 2.0, RY * 2.0) / FILL
	_surface_mat.set_shader_parameter("fill", FILL)
	_surface.mesh = quad
	_surface.material_override = _surface_mat
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.layers = RIFT_LAYER
	add_child(_surface)
	# The warped air: a bigger ring just in front.
	_warp_mat = ShaderMaterial.new()
	_warp_mat.shader = WarpShader
	# Under the rift (its halo draws over the bent air, not the other way round).
	_warp_mat.render_priority = -1
	_surface_mat.render_priority = 5
	var ring := MeshInstance3D.new()
	var big := QuadMesh.new()
	big.size = Vector2(RX, RY) * 3.4
	ring.mesh = big
	ring.material_override = _warp_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.z = 0.03
	ring.layers = RIFT_LAYER
	_warp_mat.set_shader_parameter("inner", 1.0 / 1.7)
	add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = RY * 3.0
	light.position.z = 1.0
	add_child(light)
	# The view through the partner: a camera over there drawing into this texture.
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_cam = Camera3D.new()
	_cam.cull_mask = 0xFFFFF & ~RIFT_LAYER
	_viewport.add_child(_cam)
	_surface_mat.set_shader_parameter("view", _viewport.get_texture())
	scale = Vector3.ONE * 0.05


## Where a rift shot at `pos` on a surface facing `normal` goes (`look` = where the
## shooter looks, to stand floor and ceiling rifts the right way round). Wall rifts
## drop to sit on the floor if there is one just below, like a door you can roll into.
static func frame_for(pos: Vector3, normal: Vector3, look: Vector3, space: PhysicsDirectSpaceState3D) -> Transform3D:
	var z := normal.normalized()
	var up := Vector3.UP if absf(z.y) < 0.9 else -Vector3(look.x, 0.0, look.z)
	if up.length() < 0.01:
		up = Vector3.FORWARD
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	var at := pos + z * 0.06
	if absf(z.y) < 0.3:
		var from := at + z * 0.6
		var floor := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RY * 2.0))
		if not floor.is_empty():
			at.y = floor["position"].y + RY - 0.15
	return Transform3D(Basis(x, y, z), at)


## The transform taking things at this rift to its partner (a point just in front of
## this one ends up just behind that one: add the push out separately).
func to_partner() -> Transform3D:
	return _frame(partner) * Transform3D(FLIP, Vector3.ZERO) * _frame(self).affine_inverse()


## A rift's place, without the grow-in scale.
static func _frame(p: Node3D) -> Transform3D:
	return Transform3D(p.global_basis.orthonormalized(), p.global_position)


func _process(delta: float) -> void:
	_t += delta
	_open = minf(_open + delta * 4.0, 1.0)
	scale = Vector3.ONE * ease(_open, 0.4) if _open < 1.0 else Vector3.ONE
	_surface_mat.set_shader_parameter("time", _t)
	_warp_mat.set_shader_parameter("time", _t)
	var linked := partner != null and is_instance_valid(partner)
	_surface_mat.set_shader_parameter("linked", linked)
	var main := get_viewport().get_camera_3d()
	if not linked or not main or not _surface.is_visible_in_tree():
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# Only worth drawing if you might see it.
	var to_me := global_position - main.global_position
	var facing := to_me.dot(global_basis.z) < 0.0
	if not facing or to_me.length() > 250.0 or main.is_position_behind(global_position):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var size := get_viewport().get_visible_rect().size
	_viewport.size = Vector2i(maxi(int(size.x * 0.6), 64), maxi(int(size.y * 0.6), 64))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cam.fov = main.fov
	_cam.global_transform = to_partner() * main.global_transform
	# Nothing between that camera and the partner's surface may show (the wall the
	# partner is on is right there): start drawing at the surface.
	var d := absf((_cam.global_position - partner.global_position).dot(partner.global_basis.z))
	_cam.near = clampf(d - RX * 0.3, 0.05, 50.0)
	_cam.far = main.far


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0 or not ball or not is_instance_valid(ball) or not partner or not is_instance_valid(partner):
		return
	if ball.get("dead") or ball.call("is_rushing"):
		return
	var frame := _frame(self)
	var local := frame.affine_inverse() * ball.global_position
	var oval := Vector2(local.x / (RX - 0.1), local.y / (RY - 0.1))
	if local.z > TRIGGER or local.z < -1.5 or oval.length() > 1.0:
		return
	# Only while moving into it: never for a ball sitting still in front of it.
	if (frame.basis.inverse() * ball.linear_velocity).z > -0.5:
		return
	var move := to_partner()
	# Out just past the partner's trigger zone, so it can't send you straight back.
	var out := _frame(partner) * (FLIP * Vector3(local.x, local.y, 0.0)) + _frame(partner).basis.z * (TRIGGER + 0.35)
	# The speed it went in with (by the next physics step it might have touched the wall).
	ball.call("rift_to", move.basis, out, ball.linear_velocity, ball.angular_velocity)
	_cooldown = 0.25
	partner.set("_cooldown", 0.25)
	SteamScript.achieve(get_tree(), "RIFT_WALKER")
	if ball.get_node_or_null("Weapon"):
		ball.get_node("Weapon").call("play_sound", "zap", out, -8.0)
