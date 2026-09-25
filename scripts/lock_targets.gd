extends Node3D
## Spawns the lock-on targets near the start and resets them all when the ball resets.

const LockTarget := preload("res://scripts/lock_target.gd")

## Each entry: [kind, position, ground path end (ignored for other kinds)].
const TARGETS := [
	[LockTarget.Kind.DRONE, Vector3(-14, 4, 48), Vector3.ZERO],
	[LockTarget.Kind.DRONE, Vector3(14, 5.5, 52), Vector3.ZERO],
	[LockTarget.Kind.GROUND, Vector3(-7, 0.7, 52), Vector3(7, 0.7, 52)],
	[LockTarget.Kind.GROUND, Vector3(-27, 0.7, 42), Vector3(-27, 0.7, 60)],
]

@export var ball: Node


func _ready() -> void:
	for entry in TARGETS:
		var target := LockTarget.new()
		target.kind = entry[0]
		target.path_end = entry[2]
		target.position = entry[1]
		add_child(target)
	if ball and ball.has_signal("respawned"):
		ball.connect("respawned", reset_all)


func reset_all() -> void:
	for target in get_children():
		if target.has_method("reset"):
			target.call("reset")
