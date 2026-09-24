extends Node3D
## GPU particles don't collide with physics bodies, only with GPUParticlesCollision nodes.
## On load, this adds an exact particle collision box to every box in the map
## (CSG boxes and box collision shapes), so sparks bounce off walls, floors and ramps.


func _ready() -> void:
	_add_colliders(self)


func _add_colliders(node: Node) -> void:
	for child in node.get_children():
		_add_colliders(child)

	var size := Vector3.ZERO
	if node is CSGBox3D and (node as CSGBox3D).use_collision:
		size = (node as CSGBox3D).size
	elif node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:
		size = ((node as CollisionShape3D).shape as BoxShape3D).size
	if size == Vector3.ZERO:
		return

	var box := GPUParticlesCollisionBox3D.new()
	box.size = size
	node.add_child.call_deferred(box)
