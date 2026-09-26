extends StaticBody3D
## One AI turret (managed by scripts/turrets.gd): an armoured base with a head that turns
## to track its target, a barrel and a red eye. It's a lock target like any other, so
## every weapon can lock, hit, stagger and destroy it; hits are sent to the host, which
## owns its health. Destroyed, the head is gone and the base smoulders until it rebuilds.

const MapBuilder := preload("res://scripts/maps/map_builder.gd")
const TURN_RATE := 6.0

var index := 0
var manager: Node
## Where the head is looking (world space); the head eases toward it.
var aim_at := Vector3.ZERO
var alive := true
## Turrets are off unless staff (or anyone, in practice) switch them on: then hidden,
## solid to nothing and not a target.
var enabled := false
## Seconds left stunned (Nova, or a parried shot): the head droops and the eye flickers gold.
var stunned := 0.0

var _head: Node3D
var _eye: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group("lock_targets")
	var armour := MapBuilder.solid(Color(0.22, 0.23, 0.26), 0.45, 0.7)
	var trim := MapBuilder.glow(Color(1.0, 0.25, 0.15), 2.0)
	_mesh(self, Vector3(0, 1.0, 0), Vector3(3.2, 2.0, 3.2), armour)
	_mesh(self, Vector3(0, 2.05, 0), Vector3(3.4, 0.15, 3.4), trim)
	_head = Node3D.new()
	_head.position = Vector3(0, 3.1, 0)
	add_child(_head)
	_mesh(_head, Vector3.ZERO, Vector3(2.4, 1.6, 2.4), armour)
	_mesh(_head, Vector3(0, 0.1, -2.0), Vector3(0.5, 0.5, 2.4), armour)
	_eye_mat = MapBuilder.glow(Color(1.0, 0.15, 0.1), 5.0)
	_eye = _mesh(_head, Vector3(0, 0.25, -1.22), Vector3(1.4, 0.3, 0.1), _eye_mat)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 4.0, 3.2)
	_shape.shape = box
	_shape.position = Vector3(0, 2.0, 0)
	add_child(_shape)
	aim_at = global_position + Vector3(0, 3.1, -10)
	_refresh()


func set_enabled(on: bool) -> void:
	enabled = on
	_refresh()


func set_alive(on: bool) -> void:
	alive = on
	_refresh()


func stun(duration: float) -> void:
	stunned = maxf(stunned, duration)


## Visible, solid and lockable only while switched on; the head only while alive.
func _refresh() -> void:
	if not _head:
		return
	visible = enabled
	_shape.set_deferred("disabled", not enabled)
	_head.visible = alive
	if enabled and alive:
		add_to_group("lock_targets")
	else:
		remove_from_group("lock_targets")


func _mesh(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


func _process(delta: float) -> void:
	stunned = maxf(stunned - delta, 0.0)
	if not alive or not enabled:
		return
	var from := _head.global_position
	var goal: Basis
	if stunned > 0.0:
		# Knocked out: the head sags toward the floor and the eye sputters gold.
		var flat := -_head.global_basis.z
		flat.y = 0.0
		if flat.length() < 0.1:
			flat = Vector3.FORWARD
		goal = Basis.looking_at((flat.normalized() + Vector3.DOWN * 0.8).normalized(), Vector3.UP)
		_eye_mat.emission = Color(1.0, 0.8, 0.2)
		_eye_mat.emission_energy_multiplier = 1.0 + 4.0 * float(randf() < 0.5)
	else:
		var to := aim_at - from
		if to.length() < 0.5:
			return
		goal = Basis.looking_at(to.normalized(), Vector3.UP)
		_eye_mat.emission = Color(1.0, 0.15, 0.1)
		# The eye pulses while it's hunting.
		_eye_mat.emission_energy_multiplier = 4.0 + 2.0 * sin(Time.get_ticks_msec() / 80.0)
	_head.global_basis = _head.global_basis.slerp(goal, 1.0 - exp(-TURN_RATE * delta)).orthonormalized()


## Where shots leave from.
func muzzle() -> Vector3:
	return _head.to_global(Vector3(0, 0.1, -3.3))


func head_position() -> Vector3:
	return _head.global_position


# --- Lock target interface (see ball.gd PvP) ------------------------------------------

func is_alive() -> bool:
	return alive and enabled


func get_aim_point() -> Vector3:
	return _head.global_position if _head else global_position + Vector3.UP * 3.0


## Damage in the same units as players (practice-tuned weapon damage x PVP_DAMAGE_SCALE).
func take_hit(amount: float, _pos: Vector3, _dir: Vector3) -> void:
	if alive and enabled and manager:
		manager.call("request_hit", index, amount * 4.0)


func take_unblockable_hit(amount: float, pos: Vector3, dir: Vector3) -> void:
	take_hit(amount, pos, dir)


## Nova's stagger shuts it down for a moment.
func stagger(duration: float) -> void:
	if alive and enabled and manager:
		manager.call("request_stagger", index, duration)


## Freezes, cages and pins knock it out like a stagger; so does a Time Dilator (time stops
## for it while it's inside).
func take_status(kind: String, duration: float, _data := Vector3.ZERO) -> void:
	if kind in ["freeze", "cage", "pin", "dilate"]:
		stagger(duration)


func mark(_duration: float) -> void:
	pass
