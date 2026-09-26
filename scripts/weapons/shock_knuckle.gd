extends "res://scripts/weapons/simple_weapon.gd"
## SHOCK KNUCKLE (Brawler / Close Quarters): two fists of stubby blades tight to the
## front. Press to charge them (3s); your next dash becomes a punch: anyone you hit in
## the moment after dashing is killed outright and knocked flying.

## 25 x 4 (PvP damage scale) = 100: a landed punch kills.
@export var damage := 25.0
@export var launch := 60.0

var _primed := 0.0
var _punching := 0.0
var _struck: Array = []
var _hooked := false


func _build() -> void:
	cooldown = 1.0
	crosshair_shape = "cross"
	var shape := {"arc_radius": 0.3, "tip": Vector3(0.35, 0.0, -1.2), "max_width": 0.3, "max_thickness": 0.3, "segments": 4}
	for roll in [15.0, -15.0]:
		for side in [1.0, -1.0]:
			add_blade(side, roll, shape)


func _crosshair_extra(info: Dictionary) -> void:
	info["meter"] = _primed / 3.0


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, delta: float) -> void:
	if not _hooked:
		_hooked = true
		ball().connect("dashed", _on_dashed)
	_primed = maxf(_primed - delta, 0.0)
	if just and can_fire() and _primed == 0.0:
		start_cooldown()
		_primed = 3.0
		manager.play_sound("zap", ball().global_position, -4.0)
	if _punching > 0.0:
		_punching -= delta
		var b := ball()
		var v := b.linear_velocity
		for t in targets_near(b.global_position, 4.5):
			if _struck.has(t):
				continue
			_struck.append(t)
			var p: Vector3 = t.call("get_aim_point")
			manager.hit_object(t, damage, p, v.normalized(), launch)
			manager.spawn_explosion({"position": p, "color": color, "radius": 2.5, "damage": 0.0,
				"force": 0.0, "spark_count": 120, "light_energy": 120.0, "warp_strength": 0.3, "sound": "impact_boom"})
			manager.shake(0.7)


func _on_dashed() -> void:
	if _primed > 0.0 and is_ready():
		_primed = 0.0
		_punching = 0.4
		_struck.clear()
		for i in _blades.size():
			kick(i)


func _update(_delta: float) -> void:
	_set_param("charge_glow", 2.0 if _primed > 0.0 else 0.0)
