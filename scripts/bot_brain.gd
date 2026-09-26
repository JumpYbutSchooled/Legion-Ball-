extends Node
## An AI pilot, added to a bot's ball on the host only (arena.gd _spawn). It picks the
## nearest enemy it can see, rolls to a comfortable range for its style and circles
## there, jumps and dashes when stuck or out-ranged, raises its shield when it's taking
## fire, and shoots with one of three styles, drawn with the real weapon's blades:
##   GUNNER   (Gatling)  short bursts of quick, light shots
##   SNIPER   (Railgun)  a charged heavy shot from long range
##   BRAWLER  (Scatter)  pellet blasts up close
## Its hits go to the host directly (arena.bot_hit), credited to the bot. It avoids
## driving off edges and turns away from walls.

enum Style { GUNNER, SNIPER, BRAWLER }

const THINK := 0.2
## [weapon id, preferred range, shot interval, damage per hit (HP), reach]
const STYLES := {
	Style.GUNNER: ["gatling", 30.0, 0.13, 3.0, 140.0],
	Style.SNIPER: ["railgun", 75.0, 2.6, 40.0, 400.0],
	Style.BRAWLER: ["scatter", 9.0, 0.85, 4.0, 28.0],
}

var arena: Node
var bot_id := 0

var _ball: RigidBody3D
var _weapon: Node
var _style: int = Style.GUNNER
var _target: Node3D
var _target_id := 0
var _can_see := false
var _think := 0.0
var _cooldown := 1.5
var _burst := 0.0
var _charge := 0.0
var _strafe := 1.0
var _strafe_time := 2.0
var _wander := Vector3.ZERO
var _wander_time := 0.0
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO
var _last_health := 100.0
var _hurt := 0.0
var _move := Vector3.ZERO
var _blade := 0


func _ready() -> void:
	_ball = get_parent() as RigidBody3D
	_weapon = _ball.get_node_or_null("Weapon")
	_style = [Style.GUNNER, Style.SNIPER, Style.BRAWLER][bot_id % 3]
	_last_pos = _ball.global_position
	# Hold the style's weapon, drawn.
	var slot: int = (_weapon.get("slot_ids") as Array).find(STYLES[_style][0]) if _weapon else -1
	if slot >= 0:
		_weapon.call("select", slot)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not _ball or not is_instance_valid(arena):
		return
	if _ball.get("dead") or arena.get("match_done"):
		_ball.set("bot_move", Vector3.ZERO)
		_charge = 0.0
		return
	_track_health(delta)
	_think -= delta
	if _think <= 0.0:
		_think = THINK
		_choose_target()
		_plan_move()
	_ball.set("bot_move", _move)
	_aim_and_fire(delta)


## Taking damage: remember it for a moment (dodging, shielding).
func _track_health(delta: float) -> void:
	var hp: float = arena.get("health").get(bot_id, 100.0)
	if hp < _last_health - 0.5:
		_hurt = 1.5
	_last_health = hp
	_hurt = maxf(_hurt - delta, 0.0)


## The nearest living enemy, preferring ones in sight.
func _choose_target() -> void:
	var players: Dictionary = arena.get("_players")
	var alive: Dictionary = arena.get("alive")
	var best: Node3D = null
	var best_id := 0
	var best_score := INF
	var best_seen := false
	var here := _ball.global_position
	for id in players:
		if id == bot_id or not alive.get(id, false) or arena.call("_same_team", bot_id, id):
			continue
		var other: Node3D = players[id]
		var d := here.distance_to(other.global_position)
		var seen := _sees(other)
		# Anyone in sight beats anyone behind a wall, then nearest first.
		var score := d + (0.0 if seen else 1000.0)
		if score < best_score:
			best_score = score
			best = other
			best_id = id
			best_seen = seen
	_target = best
	_target_id = best_id
	_can_see = best_seen


func _sees(other: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(_ball.global_position + Vector3.UP * 0.4, other.global_position)
	query.exclude = [_ball.get_rid()]
	var hit := _ball.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == other


## Where to roll: to the style's range from the target and round it, or wander toward
## the spawn points; never off an edge, round walls, and out of corners when stuck.
func _plan_move() -> void:
	var here := _ball.global_position
	var want := Vector3.ZERO
	_strafe_time -= THINK
	if _strafe_time <= 0.0:
		_strafe = -_strafe
		_strafe_time = randf_range(1.2, 3.0)
	if _target:
		var to := _target.global_position - here
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		var dir := flat / dist if dist > 0.1 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP) * _strafe
		var pref: float = STYLES[_style][1]
		if not _can_see or dist > pref * 1.3:
			want = dir + side * 0.35
		elif dist < pref * 0.7:
			want = -dir + side * 0.6
		else:
			want = side + dir * 0.15
		# Out-ranged by a lot, on the ground: dash in.
		if dist > pref * 2.5 and randf() < 0.08:
			_ball.call("bot_press", "dash")
		# The target's well above us: jump.
		if _target.global_position.y - here.y > 3.0 and randf() < 0.15:
			_ball.call("bot_press", "jump")
	else:
		_wander_time -= THINK
		if _wander_time <= 0.0 or here.distance_to(_wander) < 8.0:
			var spots: Array = arena.call("_map_spawns")
			_wander = spots[randi() % spots.size()] if not spots.is_empty() else Vector3.ZERO
			_wander_time = 6.0
		var to := _wander - here
		want = Vector3(to.x, 0.0, to.z).normalized()
	want = want.normalized() if want.length() > 0.01 else Vector3.ZERO
	want = _avoid(want)
	# Under fire: sometimes shield, sometimes dash sideways.
	if _hurt > 0.0 and randf() < 0.12:
		_ball.call("bot_press", "block" if randf() < 0.5 else "dash")
	# Stuck (wanting to move but not moving): jump and dash out.
	if want != Vector3.ZERO and here.distance_to(_last_pos) < 0.6:
		_stuck_time += THINK
		if _stuck_time > 1.2:
			_stuck_time = 0.0
			_ball.call("bot_press", "jump")
			_ball.call("bot_press", "dash")
			want = want.rotated(Vector3.UP, PI / 2.0 * _strafe)
	else:
		_stuck_time = 0.0
	_last_pos = here
	_move = want


## Steers `dir` away from drops and walls.
func _avoid(dir: Vector3) -> Vector3:
	if dir == Vector3.ZERO:
		return dir
	var space := _ball.get_world_3d().direct_space_state
	var here := _ball.global_position
	# A drop ahead (no floor within 14 m below a point 7 m ahead): turn back.
	var ahead := here + dir * 7.0
	var down := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 2.0, ahead + Vector3.DOWN * 14.0)
	down.exclude = [_ball.get_rid()]
	if space.intersect_ray(down).is_empty():
		var spots: Array = arena.call("_map_spawns")
		var home: Vector3 = spots[0] if not spots.is_empty() else Vector3.ZERO
		var back := Vector3(home.x - here.x, 0.0, home.z - here.z)
		return back.normalized() if back.length() > 0.1 else -dir
	# A wall right ahead: slide along it.
	var front := PhysicsRayQueryParameters3D.create(here, here + dir * 4.0)
	front.exclude = [_ball.get_rid()]
	var wall := space.intersect_ray(front)
	if not wall.is_empty() and not (wall["collider"] as Object).has_method("take_hit"):
		var n: Vector3 = wall["normal"]
		var slide := (dir - n * dir.dot(n))
		slide.y = 0.0
		return slide.normalized() if slide.length() > 0.1 else dir.rotated(Vector3.UP, PI / 2.0 * _strafe)
	return dir


## Point the weapon at the target (leading it a little) and fire in the style's rhythm.
func _aim_and_fire(delta: float) -> void:
	var look := _move if _move != Vector3.ZERO else -_ball.global_basis.z
	if not _target or not is_instance_valid(_target):
		_ball.set("bot_look", look)
		if _weapon:
			_weapon.set("aim_point", _ball.global_position + look * 20.0)
		return
	var sync := _target.get_node_or_null("Sync")
	var vel: Vector3 = sync.call("net_velocity") if sync else Vector3.ZERO
	var dist := _ball.global_position.distance_to(_target.global_position)
	var aim := _target.global_position + vel * minf(dist / 300.0, 0.3)
	_ball.set("bot_look", (aim - _ball.global_position).normalized())
	if _weapon:
		_weapon.set("aim_point", aim)
	_cooldown -= delta
	var reach: float = STYLES[_style][4]
	if not _can_see or dist > reach or _ball.call("is_staggered") or _ball.call("is_blocking"):
		_charge = 0.0
		_set_charge(0.0)
		return
	match _style:
		Style.GUNNER:
			# Bursts: 1.4 s of fire, then a breather.
			_burst += delta
			if _burst > 2.4:
				_burst = 0.0
			if _burst < 1.4 and _cooldown <= 0.0:
				_cooldown = STYLES[_style][2]
				_shoot(aim, dist, STYLES[_style][3], clampf(1.0 - dist / 140.0, 0.25, 0.8), 0.07, 6.0, "zap")
		Style.SNIPER:
			if _cooldown > 0.0:
				return
			_charge += delta / 1.3
			_set_charge(_charge)
			if _charge >= 1.0:
				_charge = 0.0
				_set_charge(0.0)
				_cooldown = STYLES[_style][2]
				_shoot(aim, dist, STYLES[_style][3], clampf(0.9 - dist / 500.0, 0.45, 0.85), 0.35, 16.0, "rail")
		Style.BRAWLER:
			if _cooldown <= 0.0:
				_cooldown = STYLES[_style][2]
				var chance := clampf(1.0 - dist / 28.0, 0.1, 0.85)
				for i in 8:
					_shoot(aim, dist, STYLES[_style][3], chance, 0.06, 4.0, "shotgun" if i == 0 else "")


## One shot: a tracer from the weapon (to the target, or past it on a miss) and, if it
## lands, the damage.
func _shoot(aim: Vector3, dist: float, damage: float, chance: float, width: float, glow: float, sound: String) -> void:
	if not _weapon:
		return
	var from := _ball.global_position
	var hit := randf() < chance
	var end := aim
	if not hit:
		var off := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 1.0), randf_range(-1.0, 1.0)).normalized()
		end = aim + off * randf_range(2.0, 4.0 + dist * 0.05)
	var dir := (end - from).normalized()
	var w = _weapon.call("current_weapon")
	var color: Color = w.get("color") if w else Color(0.35, 0.9, 1.0)
	_weapon.call("spawn_beam", from + dir * 1.5, dir, from.distance_to(end), width, 0.1, glow, color)
	var blades: int = (w.get("_blades") as Array).size() if w else 0
	if blades > 0:
		_blade = (_blade + 1) % blades
		w.call("kick", _blade)
	if sound != "":
		_weapon.call("play_sound", sound, from, -6.0)
	if hit:
		arena.call("bot_hit", bot_id, _target_id, damage)
		_weapon.call("spawn_light", aim, 12.0, 4.0, 0.08, color)


## The railgun's charge glow, so players see the sniper winding up (it's synced).
func _set_charge(k: float) -> void:
	var w = _weapon.call("current_weapon") if _weapon else null
	if w and "charge" in w:
		w.set("charge", clampf(k, 0.0, 1.0))
