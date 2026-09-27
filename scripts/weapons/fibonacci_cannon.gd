extends "res://scripts/weapons/simple_weapon.gd"
## FIBONACCI CANNON (Marksman / Long Range): a long spiral of blades, each longer than the
## last. 10 rounds a magazine; each shot's damage is the next Fibonacci number (0, 1, 1,
## 2, 3, 5, 8, 13, 21, 34 health), with infinite range. The fuller the magazine, the
## longer between shots: it speeds up as it runs dry. Empty: a 5 s reload (only while
## it's out).

const SEQUENCE := [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
## Seconds between shots with a full magazine, and with one round left.
const SLOW_GAP := 1.1
const FAST_GAP := 0.15
const RELOAD := 5.0

var _shot := 0


func _build() -> void:
	cooldown = SLOW_GAP
	lock_on = true
	lock_radius_px = 12.0
	crosshair_shape = "cross"
	crosshair_radius = 8.0
	# A golden spiral of blades, growing like the sequence.
	var lengths := [1.0, 1.0, 1.6, 2.3, 3.0]
	for i in lengths.size():
		var a := i * 72.0
		add_blade(1.0, a, {"arc_radius": 0.4, "tip": Vector3(0.3, 0.3, -lengths[i]), "max_width": 0.12, "max_thickness": 0.1, "segments": 6})


func _crosshair_extra(info: Dictionary) -> void:
	info["count"] = "%d/10  NEXT %d" % [SEQUENCE.size() - _shot, SEQUENCE[_shot]]
	info["meter"] = float(_shot) / float(SEQUENCE.size() - 1)


func _fire(_pressed: bool, just: bool, _released: bool, _hit: Dictionary, _delta: float) -> void:
	if not just and not _pressed:
		return
	if not can_fire():
		return
	var health: int = SEQUENCE[_shot]
	var k := float(_shot) / float(SEQUENCE.size() - 1)
	var from := tip(4)
	var dir: Vector3 = (target_point() - from).normalized()
	# Health on players is x4 the practice-scale damage (ball.gd PVP_DAMAGE_SCALE).
	var shot := hitscan(from, dir, 100000.0, health / 4.0, lerpf(2.0, 60.0, k))
	tracer(from, shot["end"], lerpf(0.05, 0.5, k), lerpf(4.0, 26.0, k))
	flash_at(from, dir, 0.5 + k * 1.5)
	for i in _blades.size():
		kick(i)
	if k > 0.5:
		for hit in shot["hits"]:
			manager.spawn_explosion({"position": hit["position"], "color": color, "radius": lerpf(1.5, 5.0, k),
				"damage": 0.0, "force": 0.0, "spark_count": int(lerpf(40, 220, k)), "light_energy": lerpf(40, 200, k)})
	manager.play_sound("rail" if k > 0.6 else "zap", from, lerpf(-10.0, 3.0, k))
	manager.shake(0.1 + k * 0.7)
	_shot += 1
	if _shot >= SEQUENCE.size():
		_shot = 0
		cooldown = RELOAD
		start_cooldown()
		manager.play_sound("equip", from, -6.0)
	else:
		# The emptier the magazine, the quicker the next shot.
		cooldown = lerpf(SLOW_GAP, FAST_GAP, float(_shot) / float(SEQUENCE.size() - 1))
		start_cooldown()
