extends "res://scripts/weapons/simple_weapon.gd"
## JET CRYSTALS (Skyborne / Mobility): four short fins pointing backwards in a ring.
## Hold to thrust wherever you're looking. Fuel runs out in about 2.5s and refills on
## the ground.

@export var thrust := 55.0
@export var burn := 0.4
@export var refill_rate := 0.5

var fuel := 1.0
var _burning := false


func _build() -> void:
	cooldown = 0.0
	crosshair_shape = "dot"
	var shape := {"arc_radius": 0.35, "tip": Vector3(0.5, 0.0, 1.7), "max_width": 0.2, "max_thickness": 0.14, "segments": 5}
	for roll in [45.0, -45.0]:
		for side in [1.0, -1.0]:
			add_blade(side, roll, shape)


func _crosshair_extra(info: Dictionary) -> void:
	info["meter"] = fuel
	info["ready"] = fuel > 0.05


func _fire(pressed: bool, _just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	var b := ball()
	var grounded: bool = not manager.raycast(b.global_position, b.global_position + Vector3.DOWN * 0.8).is_empty()
	_burning = pressed and fuel > 0.0
	if _burning:
		fuel = maxf(fuel - burn * delta, 0.0)
		b.apply_central_force(look_dir() * thrust * b.mass)
		# Cancel some gravity so it can actually fly.
		b.apply_central_force(Vector3.UP * 7.0 * b.mass)
		if fmod(Time.get_ticks_msec() / 1000.0, 0.06) < delta:
			for i in _blades.size():
				manager.spawn_beam(tip(i), -look_dir(), 1.6, 0.3, 0.08, 10.0, color)
	elif grounded:
		fuel = minf(fuel + refill_rate * delta, 1.0)
	charge = fuel


func _update(_delta: float) -> void:
	_set_param("charge_glow", 1.5 if _burning else 0.0)


func refill() -> void:
	super.refill()
	fuel = 1.0
