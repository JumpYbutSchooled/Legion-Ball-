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
## End-of-match map vote: the choices (scene paths) opened, and the running counts.
signal vote_opened(options: Array)
signal vote_counts(counts: Array)

const Services := preload("res://scripts/services.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const LocalViewScene := preload("res://scenes/local_view.tscn")
const HudScript := preload("res://scripts/ui/hud.gd")
const ShardBurst := preload("res://scripts/shard_burst.gd")
const MapIntro := preload("res://scripts/map_intro.gd")
const Turrets := preload("res://scripts/turrets.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")

## Spawn points spread round the middle of the map, facing inward.
const SPAWN_RADIUS := 55.0
const SPAWN_COUNT := 8

const MAX_HEALTH := 100.0
## The owner's max health (max_health_of).
const OWNER_HEALTH := 1000.0
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
## Seconds the winner banner (and the vote for the next map) shows before the next round.
const END_DELAY := 12.0
## Maps offered in the end-of-match vote.
const VOTE_OPTIONS := 3
## Falling off the map within this many seconds of being hit gives the hitter the kill.
const FALL_CREDIT_TIME := 10.0
## Holstered healing: HEAL_PER_SPEED HP a second for every 100 on the speedometer, up to
## HEAL_MAX_RATE a second, and never past HEAL_CAP.
const HEAL_PER_SPEED := 1.0
const HEAL_MAX_RATE := 5.0
const HEAL_CAP := 70.0
## m/s to speedometer units (scripts/ui/speedometer.gd SCALE).
const SPEEDO_SCALE := 5.0

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
## Host: who last damaged each player, and when: {victim: [attacker, msec]}.
var _last_hit := {}
## Host: when each player last respawned (msec), to ignore stale fall reports.
var _respawned_msec := {}
## Host: healing built up but not yet sent (health goes out in whole points).
var _heal_pending := {}
## The map vote: its choices (every peer) and each voter's pick (host).
var vote_options: Array = []
var _votes := {}


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
		for practice in ["Targets", "LockTargets"]:
			if has_node(practice):
				get_node(practice).queue_free()
		net.connect("roster_changed", _sync_players)
	_sync_players()
	# AI turrets wherever the map wants them (Map/Layout.turret_points()).
	var layout := get_node_or_null("Map/Layout")
	if layout and layout.has_method("turret_points") and not (layout.call("turret_points") as Array).is_empty():
		var turrets := Turrets.new()
		turrets.name = "Turrets"
		turrets.set("points", layout.call("turret_points"))
		add_child(turrets)
	# The map builds itself in as a wireframe (not on the server: nobody's watching).
	if DisplayServer.get_name() != "headless" and has_node("Map") and SettingsScript.read(get_tree(), "map_intro"):
		var intro := MapIntro.new()
		intro.map = $Map
		intro.hidden.append(_players_root)
		if has_node("Turrets"):
			intro.hidden.append($Turrets)
		add_child(intro)


func _net() -> Node:
	return get_tree().root.get_node_or_null("Net")


func _roster() -> Dictionary:
	var net := _net()
	if net and net.get("online"):
		return net.get("players")
	return {1: {"name": "YOU", "color": 0, "loadout": WeaponInfo.local_loadout(get_tree())}}


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
	refresh_god_shields()


## A player's loadout (weapon ids for keys 1-6) from the roster.
func loadout_of(id: int) -> Array:
	return WeaponInfo.valid_loadout(_roster().get(id, {}).get("loadout", []))


## The combo groups whose set bonus a player has (weapon_info.gd set_bonuses).
func perks_of(id: int) -> Array:
	return WeaponInfo.set_bonuses(loadout_of(id))


## Swap a player's weapons to their roster loadout (on respawn; right away in practice)
## and refresh their set bonuses.
func refresh_loadout(id: int) -> void:
	var ball: Node = _players.get(id)
	if not ball:
		return
	ball.get_node("Weapon").call("set_loadout", loadout_of(id))
	_apply_set_perks(id)


## The set bonuses that change how a ball moves (on its owner's computer).
func _apply_set_perks(id: int) -> void:
	var ball: Node = _players.get(id)
	if not ball:
		return
	if not ball.has_meta("base_air_control"):
		ball.set_meta("base_air_control", ball.get("air_control"))
		ball.set_meta("base_top_speed", ball.get("top_speed"))
	var perks := perks_of(id)
	ball.set("air_control", float(ball.get_meta("base_air_control")) * (1.2 if perks.has("skyborne") else 1.0))
	ball.set("top_speed", float(ball.get_meta("base_top_speed")) * (1.1 if perks.has("momentum") else 1.0))


## Shows the owner's gold shield on whoever has it on (the roster's "god" flag online,
## Mod.offline_god in practice).
func refresh_god_shields() -> void:
	var roster := _roster()
	var mod := get_tree().root.get_node_or_null("Mod")
	for id in _players:
		var on: bool = roster.get(id, {}).get("god", false)
		if not is_online() and mod:
			on = mod.get("offline_god")
		_players[id].call("set_god_shield", on)


## Host: the owner's gold shield is up, so nothing touches them.
## Full health for id: OWNER_HEALTH for the owner, MAX_HEALTH for everyone else.
func max_health_of(id: int) -> float:
	var role: String = _roster().get(id, {}).get("role", "")
	if not is_online() and id == multiplayer.get_unique_id():
		var mod := get_tree().root.get_node_or_null("Mod")
		if mod:
			role = mod.call("staff_role")
	return OWNER_HEALTH if role == "owner" else MAX_HEALTH


func _is_god(id: int) -> bool:
	var net := _net()
	return net != null and net.get("players").get(id, {}).get("god", false)


func _spawn(id: int, index: int) -> void:
	var ball: RigidBody3D = PlayerScene.instantiate()
	ball.name = "P%d" % id
	ball.set_multiplayer_authority(id)
	ball.position = spawn_point(index)
	# Maps can set their own height ceiling (Map/Layout.ceiling()).
	var layout := get_node_or_null("Map/Layout")
	if layout and layout.has_method("ceiling"):
		ball.set("max_height", layout.call("ceiling"))
	# Their own weapons (the roster's loadout), built when the ball is added.
	ball.get_node("Weapon").set("loadout", loadout_of(id))
	_players_root.add_child(ball)
	_apply_set_perks(id)
	_players[id] = ball
	health[id] = max_health_of(id)
	alive[id] = true
	# Nobody can be hit while their map is still building in (map_intro.gd), and a
	# moment after.
	if is_online() and multiplayer.is_server():
		_protect[id] = MapIntro.LENGTH + SPAWN_PROTECT
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
	var spots := _map_spawns()
	if not is_online():
		# Practice: the map's first spawn, or the training arena's old start by the cubes.
		return spots[0] if not spots.is_empty() else Vector3(0, 1, 60)
	if not spots.is_empty():
		return spots[index % spots.size()]
	var a := TAU * float(index % SPAWN_COUNT) / SPAWN_COUNT
	return Vector3(sin(a), 0.0, cos(a)) * SPAWN_RADIUS + Vector3.UP


## The map's own spawn points (Map/Layout.spawn_points()), if it has any.
func _map_spawns() -> Array[Vector3]:
	var layout := get_node_or_null("Map/Layout")
	if layout and layout.has_method("spawn_points"):
		return layout.call("spawn_points")
	return []


func _spawn_count() -> int:
	var spots := _map_spawns()
	return spots.size() if not spots.is_empty() else SPAWN_COUNT


func is_online() -> bool:
	var net := _net()
	return net != null and net.get("online")


func get_rules() -> Dictionary:
	return {"respawn_time": RESPAWN_TIME, "kills_to_win": KILLS_TO_WIN, "max_health": MAX_HEALTH, "end_delay": END_DELAY}


func player_ball(id: int) -> Node3D:
	return _players.get(id)


# --- Reporting (any peer; forwarded to the host) --------------------------------------

## The local shooter hit player `victim` for `amount` damage.
func request_hit(victim: int, amount: float) -> void:
	_to_host("_host_hit", [victim, amount])


## Like request_hit, but shields don't stop it and it can't be parried (staff weapons).
func request_unblockable_hit(victim: int, amount: float) -> void:
	_to_host("_unblockable_hit", [victim, amount])


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


## Like request_hit, from a Tears of an Angel missile: parrying it kills the shooter.
func request_tears_hit(victim: int, amount: float) -> void:
	_to_host("_zztears_hit", [victim, amount])


## A weapon put a status on player `victim` (chill, freeze, cage, pin, pull; weapon.gd
## apply_status). The host decides; `data` is the chill strength or the pull point.
func request_status(victim: int, kind: String, duration: float, data := Vector3.ZERO) -> void:
	_to_host("_zzstatus", [victim, kind, duration, data])


## The local player fell off the map.
func request_fall() -> void:
	_to_host("_zfell", [])


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
	if attacker == victim or _is_god(victim):
		return
	if _blocks.has(victim) and alive.get(victim, false):
		# Shielded: no damage. The first hit on this shield sets off the parry, which
		# strikes back at the shooter wherever they are: damage and a long stun.
		if not _parried.has(victim):
			_parried[victim] = true
			_to_peer(victim, "_apply_parry", [attacker])
			if alive.get(attacker, false) and not _blocks.has(attacker) and not _is_god(attacker):
				_to_peer(attacker, "_apply_stagger", [PARRY_STUN])
				_show_status.rpc(attacker, "stagger", PARRY_STUN)
				_deal(attacker, victim, PARRY_DAMAGE)
		return
	_deal(victim, attacker, amount)


## A hit that ignores shields and parries. (Named to sort after this node's other RPCs:
## Godot numbers RPCs alphabetically, and renumbering them breaks other versions.)
@rpc("any_peer", "reliable")
func _unblockable_hit(victim: int, amount: float) -> void:
	if not multiplayer.is_server() or match_done:
		return
	var attacker := _sender()
	if attacker != victim:
		_deal(victim, attacker, amount)


## Host: an AI turret (scripts/turrets.gd) at `from` hit `victim`. On a raised shield it's
## parried like a player's shot (the victim is launched and strikes back at the turret):
## returns true so the turret takes the strike. Otherwise it's damage, and a kill is
## nobody's (attacker -1). God mode ignores it.
func turret_shot(victim: int, amount: float, from: Vector3) -> bool:
	if not multiplayer.is_server() or match_done or not alive.get(victim, false) or _is_god(victim):
		return false
	if _blocks.has(victim):
		if _parried.has(victim):
			return false
		_parried[victim] = true
		_to_peer(victim, "_zzparry_at", [from])
		return true
	_deal(victim, -1, amount)
	return false


## The sender fell off the map: a death, credited to whoever hit them in the last
## FALL_CREDIT_TIME seconds (or nobody). (Named to sort last, like _unblockable_hit.)
@rpc("any_peer", "reliable")
func _zfell() -> void:
	if not multiplayer.is_server() or match_done:
		return
	var victim := _sender()
	if not alive.get(victim, false):
		return
	# A report sent from where they died, arriving just after they respawned: not a new fall.
	if Time.get_ticks_msec() - int(_respawned_msec.get(victim, -100000)) < 1000:
		return
	var attacker := victim
	var last: Array = _last_hit.get(victim, [])
	if not last.is_empty() and Time.get_ticks_msec() - int(last[1]) <= FALL_CREDIT_TIME * 1000.0 \
			and _players.has(last[0]):
		attacker = last[0]
	_set_health.rpc(victim, 0.0)
	_kill(victim, attacker)


## Host: the attacker's set bonuses on a hit (weapon_info.gd GROUPS): HUNTER +10% on
## marked targets, BRAWLER +15% within 10 m, MARKSMAN +15% beyond 60 m.
func _perk_damage(victim: int, attacker: int) -> float:
	if not _players.has(attacker) or not _players.has(victim) or attacker == victim:
		return 1.0
	var perks := perks_of(attacker)
	if perks.is_empty():
		return 1.0
	var k := 1.0
	if perks.has("hunter") and _marks.get(victim, 0.0) > 0.0:
		k *= 1.1
	var dist: float = _players[attacker].global_position.distance_to(_players[victim].global_position)
	if perks.has("brawler") and dist <= 10.0:
		k *= 1.15
	if perks.has("marksman") and dist >= 60.0:
		k *= 1.15
	return k


## Host only: take `amount` off `victim`, credited to `attacker` if it kills.
func _deal(victim: int, attacker: int, amount: float) -> void:
	if not alive.get(victim, false) or _protect.get(victim, 0.0) > 0.0 or _is_god(victim):
		return
	if _marks.get(victim, 0.0) > 0.0:
		amount *= MARK_MULTIPLIER
	amount *= _perk_damage(victim, attacker)
	if attacker != victim:
		_last_hit[victim] = [attacker, Time.get_ticks_msec()]
	var hp: float = health.get(victim, max_health_of(victim)) - amount
	_set_health.rpc(victim, hp)
	if hp <= 0.0:
		_kill(victim, attacker)


@rpc("any_peer", "reliable")
func _host_push(victim: int, impulse: Vector3) -> void:
	if multiplayer.is_server() and alive.get(victim, false) and not _blocks.has(victim) and not _is_god(victim):
		_to_peer(victim, "_apply_push", [impulse])


@rpc("any_peer", "reliable")
func _host_mark(victim: int, duration: float) -> void:
	if multiplayer.is_server() and alive.get(victim, false) and not _blocks.has(victim) and not _is_god(victim):
		# HUNTER set bonus: your marks last 50% longer.
		if perks_of(_sender()).has("hunter"):
			duration *= 1.5
		_marks[victim] = maxf(_marks.get(victim, 0.0), duration)
		_show_status.rpc(victim, "mark", duration)


@rpc("any_peer", "reliable")
func _host_stagger(victim: int, duration: float) -> void:
	if multiplayer.is_server() and alive.get(victim, false) and not _blocks.has(victim) and not _is_god(victim):
		# FROST set bonus: your staggers (and later slows and freezes) last 30% longer.
		if perks_of(_sender()).has("frost"):
			duration *= 1.3
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
	# Dying on your own (falling off with nobody to blame) is a death, not a kill.
	var credited := attacker != victim and roster.has(attacker)
	if credited:
		roster[attacker]["kills"] = int(roster[attacker]["kills"]) + 1
	if roster.has(victim):
		roster[victim]["deaths"] = int(roster[victim]["deaths"]) + 1
	net.call("push_roster")
	_marks.erase(victim)
	_last_hit.erase(victim)
	_respawn_timers[victim] = RESPAWN_TIME
	if attacker != victim and alive.get(attacker, false):
		_set_health.rpc(attacker, minf(health.get(attacker, max_health_of(attacker)) + KILL_HEAL, max_health_of(attacker)))
	_on_killed.rpc(victim, attacker)
	if credited and int(roster[attacker]["kills"]) >= KILLS_TO_WIN:
		_on_match_over.rpc(attacker)
		_end_timer = END_DELAY
		_open_vote()


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
				_respawned_msec[id] = Time.get_ticks_msec()
				_set_health.rpc(id, max_health_of(id))
				_on_respawn.rpc(id, _safest_spawn())
	if not match_done:
		_heal_holstered(delta)
	if _end_timer > 0.0:
		_end_timer -= delta
		if _end_timer <= 0.0:
			_close_vote()
			_net().call("end_match")


## Host: offer this map and a couple of others to vote on for the next round.
func _open_vote() -> void:
	var net := _net()
	var maps: Array = net.COMBAT_MAPS.duplicate()
	var here: String = net.get("map_scene")
	maps.erase(here)
	maps.shuffle()
	var options: Array = []
	if net.COMBAT_MAPS.has(here):
		options.append(here)
	for path in maps:
		if options.size() >= VOTE_OPTIONS:
			break
		options.append(path)
	_votes.clear()
	_zvote_open.rpc(options)


## Host: the most-voted map becomes the next one (ties: the earliest listed, so staying
## put wins a tie). No votes at all: stay.
func _close_vote() -> void:
	if vote_options.is_empty():
		return
	var counts := _count_votes()
	var best := 0
	for i in counts.size():
		if counts[i] > counts[best]:
			best = i
	_net().set("map_scene", vote_options[best])


func _count_votes() -> Array:
	var counts: Array = []
	counts.resize(vote_options.size())
	counts.fill(0)
	for peer in _votes:
		if _players.has(peer):
			counts[_votes[peer]] += 1
	return counts


## Any peer: vote for option `index` (0-based).
func cast_vote(index: int) -> void:
	if not is_online() or index < 0 or index >= vote_options.size():
		return
	if multiplayer.is_server():
		_zvote_cast(index)
	else:
		_zvote_cast.rpc_id(1, index)


## Host: players with their weapon put away heal the faster they go (see HEAL_*).
func _heal_holstered(delta: float) -> void:
	for id in _players:
		var ball: Node = _players[id]
		var weapon := ball.get_node_or_null("Weapon")
		var sync := ball.get_node_or_null("Sync")
		var hp: float = health.get(id, max_health_of(id))
		var cap := HEAL_CAP / MAX_HEALTH * max_health_of(id)
		if not alive.get(id, false) or hp >= cap or not weapon or not sync or weapon.call("is_drawn"):
			_heal_pending.erase(id)
			continue
		var speed: float = (sync.call("net_velocity") as Vector3).length() * SPEEDO_SCALE
		var rate := minf(speed / 100.0 * HEAL_PER_SPEED, HEAL_MAX_RATE)
		var pending: float = _heal_pending.get(id, 0.0) + rate * delta
		if pending >= 1.0:
			var whole := floorf(pending)
			pending -= whole
			_set_health.rpc(id, minf(hp + whole, cap))
		_heal_pending[id] = pending


## The spawn point furthest from every living player.
func _safest_spawn() -> Vector3:
	var best := spawn_point(0)
	var best_score := -1.0
	for i in _spawn_count():
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
		# Everyone sees every kill's impact frames, styled by the killer's weapon. Only the
		# killer and the victim get the hitstop: it slows your own ball, and freezing
		# everyone on every kill would stall the whole match.
		var me := multiplayer.get_unique_id()
		get_tree().call_group("impact_frames", "trigger", ball.global_position, burst.color,
			_kill_weapon(attacker), attacker == me or victim == me)
	player_killed.emit(victim, attacker)


## Weapon id whose impact frames a kill plays: our own last hit if it was ours (""),
## otherwise whatever the killer is holding.
func _kill_weapon(attacker: int) -> String:
	if attacker == multiplayer.get_unique_id():
		return ""
	var killer: Node = _players.get(attacker)
	var weapon := killer.get_node_or_null("Weapon") if killer else null
	return weapon.call("slot_id", weapon.get("current")) if weapon else "railgun"


@rpc("authority", "call_local", "reliable")
func _on_respawn(id: int, pos: Vector3) -> void:
	alive[id] = true
	# A loadout changed in the Armory mid-match takes effect now.
	refresh_loadout(id)
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


## Map vote RPCs. (Named to sort after the others: Godot numbers RPCs alphabetically.)
@rpc("any_peer", "reliable")
func _zvote_cast(index: int) -> void:
	if not multiplayer.is_server() or vote_options.is_empty() or index < 0 or index >= vote_options.size():
		return
	_votes[_sender()] = index
	_zvote_tally.rpc(_count_votes())


@rpc("authority", "call_local", "reliable")
func _zvote_open(options: Array) -> void:
	vote_options = options.filter(func(p) -> bool: return typeof(p) == TYPE_STRING)
	vote_opened.emit(vote_options)


@rpc("authority", "call_local", "reliable")
func _zvote_tally(counts: Array) -> void:
	vote_counts.emit(counts)


## A Tears of an Angel hit. Unshielded: ordinary damage. On a shield: the usual parry for
## the blocker, and the shooter dies outright, credited to the blocker. (Named to sort
## after the other RPCs.)
@rpc("any_peer", "reliable")
func _zztears_hit(victim: int, amount: float) -> void:
	if not multiplayer.is_server() or match_done:
		return
	var attacker := _sender()
	if attacker == victim or _is_god(victim):
		return
	if _blocks.has(victim) and alive.get(victim, false):
		if not _parried.has(victim):
			_parried[victim] = true
			_to_peer(victim, "_apply_parry", [attacker])
			if alive.get(attacker, false) and not _is_god(attacker):
				_set_health.rpc(attacker, 0.0)
				_kill(attacker, victim)
		return
	_deal(victim, attacker, amount)


## Host: staff moved player `id` to `pos` (moderation.gd bring).
func teleport_player(id: int, pos: Vector3) -> void:
	if multiplayer.is_server() and alive.get(id, false):
		_to_peer(id, "_zzteleport", [pos])


## Host: the owner struck `victim` down (kill all). Ignores shields and spawn protection;
## nobody's score changes.
func staff_kill(victim: int, by: int) -> void:
	if not multiplayer.is_server() or match_done or not alive.get(victim, false):
		return
	_set_health.rpc(victim, 0.0)
	_marks.erase(victim)
	_last_hit.erase(victim)
	_respawn_timers[victim] = RESPAWN_TIME
	_on_killed.rpc(victim, by)


## Host: the owner healed `id` to full.
func staff_heal(id: int) -> void:
	if multiplayer.is_server() and alive.get(id, false):
		_set_health.rpc(id, max_health_of(id))


## Host: the owner flung `id` into the sky.
func staff_launch(id: int) -> void:
	if multiplayer.is_server() and alive.get(id, false):
		_to_peer(id, "_apply_push", [Vector3.UP * 75.0])


## Host: a status from a weapon. Shields and god mode stop it; FROST set bonus makes it
## last 30% longer. (Named to sort after the other RPCs.)
@rpc("any_peer", "reliable")
func _zzstatus(victim: int, kind: String, duration: float, data: Vector3) -> void:
	if not multiplayer.is_server() or match_done or not kind in ["chill", "freeze", "cage", "pin", "pull"]:
		return
	var attacker := _sender()
	if attacker == victim or not alive.get(victim, false) or _blocks.has(victim) or _is_god(victim) \
			or _protect.get(victim, 0.0) > 0.0:
		return
	duration = clampf(duration, 0.0, 8.0)
	if kind != "pull" and perks_of(attacker).has("frost"):
		duration *= 1.3
	_to_peer(victim, "_zzapply_status", [kind, duration, data])
	_show_status.rpc(victim, kind, duration)


## Our own ball got a status the host approved.
@rpc("authority", "reliable")
func _zzapply_status(kind: String, duration: float, data: Vector3) -> void:
	var ball: Node3D = _players.get(multiplayer.get_unique_id())
	if ball and not ball.get("dead"):
		ball.call("apply_status", kind, duration, data)


## Staff brought us to `pos`.
@rpc("authority", "reliable")
func _zzteleport(pos: Vector3) -> void:
	var ball: Node3D = _players.get(multiplayer.get_unique_id())
	if ball and not ball.get("dead"):
		ball.call("teleport", pos)


## Our shield parried a turret's shot from `from`. (Named to sort last.)
@rpc("authority", "reliable")
func _zzparry_at(from: Vector3) -> void:
	var ball: Node3D = _players.get(multiplayer.get_unique_id())
	if ball and not ball.get("dead"):
		ball.call("on_parried", from)


@rpc("authority", "reliable")
func _apply_stagger(duration: float) -> void:
	var ball: Node3D = _players.get(multiplayer.get_unique_id())
	if ball:
		ball.call("stagger_controls", duration)
