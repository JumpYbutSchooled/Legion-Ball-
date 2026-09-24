extends Node
## Keeps one player's ball and weapons in step across the network.
## The owning computer simulates its own ball and sends its state SEND_RATE times a
## second. Everyone else holds that ball frozen (kinematic) and glides it toward the
## latest state, predicted forward by its velocity so it doesn't trail behind.
## Also places the floating name tag over other players' balls.

const SEND_RATE := 30.0
## How quickly remote balls catch up to the received state.
const SMOOTHING := 18.0
## Farther off than this, snap instead of gliding (respawns, teleports).
const SNAP_DISTANCE := 8.0
## Never predict further ahead than this, in seconds.
const MAX_PREDICT := 0.25

@onready var _ball: RigidBody3D = get_parent()
@onready var _weapon: Node = get_parent().get_node("Weapon")
@onready var _tag: Label3D = get_parent().get_node("NameTag")

var _send_timer := 0.0
var _has_state := false
var _pos := Vector3.ZERO
var _rot := Quaternion.IDENTITY
var _vel := Vector3.ZERO
var _age := 0.0


func _ready() -> void:
	if not is_multiplayer_authority():
		_ball.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_ball.freeze = true
		# Other players can be locked, painted and hit like targets (see ball.gd, PvP).
		_ball.add_to_group("lock_targets")
		var id := get_multiplayer_authority()
		var net := get_tree().root.get_node_or_null("Net")
		if net:
			_tag.text = net.call("player_name", id)
			_tag.modulate = net.call("player_color", id)
		_tag.visible = true


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var net := get_tree().root.get_node_or_null("Net")
		if not net or not net.get("online"):
			return
		_send_timer += delta
		if _send_timer >= 1.0 / SEND_RATE:
			_send_timer = 0.0
			var w: Array = _weapon.call("get_net_state")
			_state.rpc(_ball.global_position, _ball.global_basis.get_rotation_quaternion(),
				_ball.linear_velocity, w[0], w[1], w[2])
	elif _has_state:
		_age += delta
		var predicted := _pos + _vel * minf(_age, MAX_PREDICT)
		var t := 1.0 - exp(-SMOOTHING * delta)
		var pos := _ball.global_position.lerp(predicted, t)
		if _ball.global_position.distance_to(predicted) > SNAP_DISTANCE:
			pos = predicted
		var rot := _ball.global_basis.get_rotation_quaternion().slerp(_rot, t)
		_ball.global_transform = Transform3D(Basis(rot), pos)


func _process(_delta: float) -> void:
	if _tag.visible:
		_tag.global_position = _ball.get_global_transform_interpolated().origin + Vector3.UP * 1.4


@rpc("authority", "unreliable_ordered")
func _state(pos: Vector3, rot: Quaternion, vel: Vector3, aim: Vector3, slot: int, armed: bool) -> void:
	_pos = pos
	_rot = rot
	_vel = vel
	_age = 0.0
	if not _has_state:
		_has_state = true
		_ball.global_transform = Transform3D(Basis(rot), pos)
	_weapon.call("apply_net_state", aim, slot, armed)
