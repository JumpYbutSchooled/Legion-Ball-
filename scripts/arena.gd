extends Node3D
## The playable level. Spawns a ball for every player in the Net roster (just one for
## offline practice), keeps that in step as people join and leave, and gives the local
## player their camera, HUD and menus (scenes/local_view.tscn).
## Every computer spawns the same players under the same names (P<peer id>), so their
## network messages line up without a spawner.
##
## PvP (online): the shooter's computer decides what it hit and reports it; the host
## owns everyone's health, marks, kills and respawns, and tells everyone the results.

signal health_changed(id: int, hp: float)
signal player_killed(victim: int, attacker: int)
signal player_respawned(id: int)
signal match_over(winner: int)

const Services := preload("res://scripts/services.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const LocalViewScene := preload("res://scenes/local_view.tscn")
const HudScript := preload("res://scripts/ui/hud.gd")
const ShardBurst := preload("res://scripts/shard_burst.gd")

## Spawn points spread round the middle of the map, facing inward.
const SPAWN_RADIUS := 55.0
const SPAWN_COUNT := 8

const MAX_HEALTH := 100.0
const RESPAWN_TIME := 3.0
## After respawning, hits are ignored for this long.
const SPAWN_PROTECT := 2.0
## Damage multiplier on a Swarm-marked player (2x made any mark + hit a kill).
const MARK_MULTIPLIER := 1.5
## A parried shot strikes back at whoever fired it: this much damage, and a stun.
const PARRY_DAMAGE := 20.0
const PARRY_STUN := 5.0
## Health the killer gets back for each kill (capped at MAX_HEALTH).
const KILL_HEAL := 30.0
const KILLS_TO_WIN := 15
## Seconds the winner banner shows before everyone returns to the lobby.
const END_DELAY := 6.0

@onready var _players_root: Node3D = $Players

var _players := {}
## Synced to every peer by the host.
var health := {}
var alive := {}
var match_done := false
# Host-only timers, in seconds: {peer_id: time left}.
var _respawn_timers := {}
var _protect := {}
var _marks := {}
## Shields up: {peer_id: time left}; and who has already parried with this shield.
var _blocks := {}
var _parried := {}
var _end_timer := -1.0


func _ready() -> void:
	var net := _net()
	if not net:
		# Launched directly (editor / tests): the boot scene didn't create services.
		# Deferred because the root is busy while this scene is being added.
		_ensure_then_spawn.call_deferred()
		return
	_start(net)


func _ensure_then_spawn() -> void:
	Services.ensure(get_tree())
	_start(_net())


func _start(net: Node) -> void:
	if net.get("online"):
		# Cubes and practice targets only exist offline for now (not network-synced).
		$Targets.queue_free()
		$LockTargets.queue_free()
		net.connect("roster_changed", _sync_players)
	_sync_players()


func _net() -> Node:
	return get_tree().root.get_node_or_null("Net")


func _roster() -> Dictionary:
	var net := _net()
	if net and net.get("online"):
		return net.get("players")
	return {1: {"name": "YOU", "color": 0}}


func _sync_players() -> void:
	var roster := _roster()
	var ids := roster.keys()
	ids.sort()
	for id in ids:
		if not _players.has(id):
			_spawn(id, ids.find(id))
	for id in _players.keys():
		if not roster.has(id):
			_players[id].queue_free()
			_players.erase(id)


func _spawn(id: int, index: int) -> void:
	var ball: RigidBody3D = PlayerScene.instantiate()
	ball.name = "P%d" % id
	ball.set_multiplayer_authority(id)
	ball.position = spawn_point(index)
	_players_root.add_child(ball)
	_players[id] = ball
	health[id] = MAX_HEALTH
	alive[id] = true
	if id == multiplayer.get_unique_id():
		var view := LocalViewScene.instantiate()
		view.call("setup", ball)
		add_child(view)
		if is_online():
			var hud := HudScript.new()
			hud.arena = self
			view.add_child(hud)
		# Practice extras follow the local player's resets.
		if has_node("Targets"):
			ball.connect("respawned", $Targets.respawn)
		if has_node("LockTargets"):
			ball.connect("respawned", $LockTargets.reset_all)


func spawn_point(index: int) -> Vector3:
	if not is_online():
		return Vector3(0, 1, 60)  # Practice: the old start, facing the cubes.
	var a := TAU * float(index % SPAWN_COUNT) / SPAWN_COUNT
	return Vector3(sin(a), 0.0, cos(a)) * SPAWN_RADIUS + Vector3.UP


func is_online() -> bool:
	var net := _net()
	return net != null and net.get("online")


func get_rules() -> Dictionary:
	return {"respawn_time": RESPAWN_TIME, "kills_to_win": KILLS_TO_WIN, "max_health": MAX_HEALTH}


func player_ball(id: int) -> Node3D:
	return _players.get(id)


# --- Reporting (any peer; forwarded to the host) --------------------------------------

## The local shooter hit player `victim` for `amount` damage.
func request_hit(victim: int, amount: float) -> void:
	_to_host("_host_hit", [victim, amount])


## Push player `victim`'s ball by `impulse` (applied on their own computer).
func request_push(victim: int, impulse: Vector3) -> void:
	_to_host("_host_push", [victim, impulse])


func request_mark(victim: int, duration: float) -> void:
	_to_host("_host_mark", [victim, duration])


func request_stagger(victim: int, duration: float) -> void:
	_to_host("_host_stagger", [victim, duration])


## The local player raised their shield for `duration` seconds.
func request_block(duration: float) -> void:
	_to_host("_host_block", [duration])


func _to_host(method: StringName, args: Array) -> void:
	if not is_online() or match_done:
		return
	if multiplayer.is_server():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


## Who sent the RPC being handled (the host's own direct calls count as peer 1).
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else 1


# --- Host-side rules ------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _host_hit(victim: int, amount: float) -> void:
	if not multiplayer.is_server() or match_done:
		return
	var attacker := _sender()
	if attacker == victim:
		return
	if _blocks.has(victim) and alive.get(victim, false):
		# Shielded: no damage. The first hit on this shield sets off the parry, which
		# strikes back at the shooter wherever they are: damage and a long stun.
		if not _parried.has(victim):
			_parried[victim] = true
			_to_peer(victim, "_apply_parry", [attacker])
			if alive.get(attacker, false) and not _blocks.has(attacker):
				_to_peer(attacker, "_apply_stagger", [PARRY_STUN])
				_show_status.rpc(attacker, "stagger", PARRY_STUN)
				_deal(attacker, victim, PARRY_DAMAGE)
		return
	_deal(victim, attacker, amount)


## Host only: take `amount` off `victim`, credited to `attacker` if it kills.
func _deal(victim: int, attacker: int, amount: float) -> void:
	if not alive.get(victim, false) or _protect.get(victim, 0.0) > 0.0:
		return
	if _marks.get(victim, 0.0) > 0.0:
		amount *= MARK_MULTIPLIER
	var hp: float = health.get(victim, MAX_HEALTH) - amount
	_set_health.rpc(victim, hp)
	if hp <= 0.0:
		_kill(victim, attacker)


@rpc("any_peer", "reliable")
func _host_push(victim: int, impulse: Vector3) -> void:
	if multiplayer.is_server() and alive.get(victim, false) and not _blocks.has(victim):
		_to_peer(victim, "_apply_push", [impulse])


@rpc("any_peer", "reliable")
func _host_mark(victim: int, duration: float) -> void:
	if multiplayer.is_server() and alive.get(victim, false) and not _blocks.has(victim):
		_marks[victim] = maxf(_marks.get(victim, 0.0), duration)
		_show_status.rpc(victim, "mark", duration)


@rpc("any_peer", "reliable")
func _host_stagger(victim: int, duration: float) -> void:
	if multiplayer.is_server() and alive.get(victim, false) and not _blocks.has(victim):
		_to_peer(victim, "_apply_stagger", [duration])
		_show_status.rpc(victim, "stagger", duration)


@rpc("any_peer", "reliable")
func _host_block(duration: float) -> void:
	var id := _sender()
	if multiplayer.is_server() and alive.get(id, false):
		# A little extra so shots already in flight when it drops still count.
		_blocks[id] = duration + 0.15
		_parried.erase(id)


func _kill(victim: int, attacker: int) -> void:
	var net := _net()
	var roster: Dictionary = net.get("players")
	if roster.has(attacker):
		roster[attacker]["kills"] = int(roster[attacker]["kills"]) + 1
	if roster.has(victim):
		roster[victim]["deaths"] = int(roster[victim]["deaths"]) + 1
	net.call("push_roster")
	_marks.erase(victim)
	_respawn_timers[victim] = RESPAWN_TIME
	if attacker != victim and alive.get(attacker, false):
		_set_health.rpc(attacker, minf(health.get(attacker, MAX_HEALTH) + KILL_HEAL, MAX_HEALTH))
	_on_killed.rpc(victim, attacker)
	if roster.has(attacker) and int(roster[attacker]["kills"]) >= KILLS_TO_WIN:
		_on_match_over.rpc(attacker)
		_end_timer = END_DELAY


func _physics_process(delta: float) -> void:
	if not is_online() or not multiplayer.is_server():
		return
	for table in [_protect, _marks, _blocks]:
		for id in table.keys():
			table[id] -= delta
			if table[id] <= 0.0:
				table.erase(id)
	for id in _parried.keys():
		if not _blocks.has(id):
			_parried.erase(id)
	for id in _respawn_timers.keys():
		_respawn_timers[id] -= delta
		if _respawn_timers[id] <= 0.0:
			_respawn_timers.erase(id)
			if _players.has(id) and not match_done:
				_protect[id] = SPAWN_PROTECT
				_set_health.rpc(id, MAX_HEALTH)
				_on_respawn.rpc(id, _safest_spawn())
	if _end_timer > 0.0:
		_end_timer -= delta
		if _end_timer <= 0.0:
			_net().call("end_match")


## The spawn point furthest from every living player.
func _safest_spawn() -> Vector3:
	var best := spawn_point(0)
	var best_score := -1.0
	for i in SPAWN_COUNT:
		var p := spawn_point(i)
		var nearest := INF
		for id in _players:
			if alive.get(id, false):
				nearest = minf(nearest, p.distance_to(_players[id].global_position))
		if nearest > best_score:
			best_score = nearest
			best = p
	return best


func _to_peer(peer: int, method: StringName, args: Array) -> void:
	if peer == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer, method] + args)


# --- Results (run on every peer) -------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _set_health(id: int, hp: float) -> void:
	health[id] = hp
	health_changed.emit(id, hp)


@rpc("authority", "call_local", "reliable")
func _on_killed(victim: int, attacker: int) -> void:
	alive[victim] = false
	var ball: Node3D = _players.get(victim)
	if ball:
		var burst := ShardBurst.new()
		burst.color = _net().call("player_color", victim)
		burst.count = 28
		burst.speed = 11.0
		add_child(burst)
		burst.global_position = ball.global_position
		ball.call("set_dead", true)
		if attacker == multiplayer.get_unique_id():
			get_tree().call_group("impact_frames", "trigger", ball.global_position, burst.color)
	player_killed.emit(victim, attacker)


@rpc("authority", "call_local", "reliable")
func _on_respawn(id: int, pos: Vector3) -> void:
	alive[id] = true
	var ball: Node3D = _players.get(id)
	if ball:
		ball.call("set_dead", false)
		if id == multiplayer.get_unique_id():
			ball.call("respawn_at", pos)
	player_respawned.emit(id)


@rpc("authority", "call_local", "reliable")
func _show_status(id: int, kind: String, duration: float) -> void:
	var ball: Node3D = _players.get(id)
	if ball:
		ball.call("show_status", kind, duration)


@rpc("authority", "call_local", "reliable")
func _on_match_over(winner: int) -> void:
	match_done = true
	match_over.emit(winner)


@rpc("authority", "reliable")
func _apply_push(impulse: Vector3) -> void:
	var ball: RigidBody3D = _players.get(multiplayer.get_unique_id())
	if ball and not ball.get("dead"):
		ball.apply_central_impulse(impulse)


@rpc("authority", "reliable")
func _apply_parry(attacker: int) -> void:
	var ball: Node3D = _players.get(multiplayer.get_unique_id())
	if ball and not ball.get("dead"):
		var shooter: Node3D = _players.get(attacker)
		ball.call("on_parried", shooter.global_position if shooter else Vector3.INF)


@rpc("authority", "reliable")
func _apply_stagger(duration: float) -> void:
	var ball: Node3D = _players.get(multiplayer.get_unique_id())
	if ball:
		ball.call("stagger_controls", duration)
