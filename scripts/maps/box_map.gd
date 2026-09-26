extends "res://scripts/maps/map_builder.gd"
## "The Box": literally just a big box. A 220 m cube, floor, four walls and a roof, all
## panelled with a glowing grid so you can judge distance and height, and nothing else.
## Pure movement and aim.

const SIZE := 220.0
const HEIGHT := 220.0
const THICK := 6.0


func _build() -> void:
	var half := SIZE / 2.0
	_ceiling = HEIGHT - 12.0
	_outline = rect_outline(Rect2(-half, -half, SIZE, SIZE))
	var floor_mat := panel(Color(0.16, 0.18, 0.22), Color(0.35, 0.9, 1.0), 10.0, 1.2)
	var wall_mat := panel(Color(0.2, 0.22, 0.27), Color(0.35, 0.9, 1.0), 10.0, 0.7)
	var roof_mat := panel(Color(0.12, 0.13, 0.16), Color(0.35, 0.9, 1.0), 10.0, 0.5)
	box(Vector3(0, -THICK / 2.0, 0), Vector3(SIZE + THICK * 2.0, THICK, SIZE + THICK * 2.0), floor_mat)
	box(Vector3(0, HEIGHT + THICK / 2.0, 0), Vector3(SIZE + THICK * 2.0, THICK, SIZE + THICK * 2.0), roof_mat, 0.0, 0.0, false)
	for k in 4:
		var yaw := TAU * k / 4.0
		var out := Vector3(sin(yaw), 0.0, cos(yaw))
		box(out * (half + THICK / 2.0) + Vector3.UP * HEIGHT / 2.0, Vector3(SIZE + THICK * 2.0, HEIGHT, THICK), wall_mat, yaw)
	# Spawns round the middle, turrets in the corners.
	for i in 8:
		var p := Vector2.from_angle(TAU * i / 8.0) * 60.0
		_spawns.append(Vector3(p.x, 1.0, p.y))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_turrets.append(Vector3(sx * (half - 18.0), 0.0, sz * (half - 18.0)))
	# Light from the roof: the sun can't get in.
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [-1.0, 0.0, 1.0]:
			var light := OmniLight3D.new()
			light.position = Vector3(sx * half * 0.6, HEIGHT - 20.0, sz * half * 0.6)
			light.omni_range = 170.0
			light.light_energy = 1.4
			light.light_color = Color(0.8, 0.92, 1.0)
			light.omni_attenuation = 0.6
			add_child(light)
