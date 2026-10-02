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
## Weapon id of the kill player_killed is about to report ("" = none: the void, staff).
var last_kill_weapon := ""
signal player_respawned(id: int)
signal match_over(winner: int)
## End-of-match vote: the map choices (scene paths, plus "random") opened, and who has
## voted for what: {peer: map index} and {peer: mode index} (Net.MODES).
signal vote_opened(options: Array)
signal vote_state(map_votes: Dictionary, mode_votes: Dictionary)
## Our own player was hit from pos (the direction arrows: ui/combat_feedback.gd).
signal hurt_from(pos: Vector3)
## Team game: the two teams' kill totals changed.
signal team_scores_changed(scores: Array)
## Juggernaut: player `id` is the juggernaut now (0 = nobody).
signal juggernaut_changed(id: int)
## A fresh online server's first round: everyone votes on the map and mode before playing.
signal first_vote_opened

const Services := preload("res://scripts/services.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const LocalViewScene := preload("res://scenes/local_view.tscn")
const HudScript := preload("res://scripts/ui/hud.gd")
const ShardBurst := preload("res://scripts/shard_burst.gd")
const MapIntro := preload("res://scripts/map_intro.gd")
const HillScript := preload("res://scripts/koth_hill.gd")
const TutorialScript := preload("res://scripts/ui/tutorial.gd")
const Turrets := preload("res://scripts/turrets.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const WeaponInfo := preload("res://scripts/weapon_info.gd")
const NetScript := preload("res://scripts/net/net.gd")
const Graphics := preload("res://scripts/graphics.gd")
const BotBrain := preload("res://scripts/bot_brain.gd")
const SpeedTrail := preload("res://scripts/speed_trail.gd")
const MapMerge := preload("res://scripts/map_merge.gd")

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
## Juggernaut: one player at a time is the juggernaut - this much health, JUGGERNAUT_SIZE
## times bigger, JUGGERNAUT_SPEED times as fast, and no healing. Whoever kills them takes
## over; after JUGGERNAUT_ROUNDS juggernauts the match ends and the most kills wins.
const JUGGERNAUT_HEALTH := 1000.0
const JUGGERNAUT_SIZE := 2.0
const JUGGERNAUT_SPEED := 0.5
const JUGGERNAUT_ROUNDS := 5
## King of the Hill: seconds a round lasts; most seconds on the hill wins.
const KOTH_TIME := 300.0
## Team game: the first team to this many kills wins.
const TEAM_KILLS_TO_WIN := 30
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
var _mode_votes := {}
## Team game: kills per team (red, blue). The host counts; everyone gets a copy.
var team_scores := [0, 0]
## When this round started (msec), for the match clock on the scoreboard.
var _match_start := 0
## This arena was loaded for an online match (so losing the connection means we're
## leaving: never fall back to spawning a practice player).
var _started_online := false
## Host: players whose map has finished loading (they said hello). Only they get the
## turrets' updates (turrets.gd), which would be lost on anyone still loading.
var ready_peers := {}
## Gun Game (host): players already handed their first weapon this round.
var _gun_given := {}
## King of the Hill: the hill (everyone gets it from the host; radius 0 = no hill), each
## player's seconds on it (host), and the next time the scores go out.
var hill_pos := Vector3.ZERO
var hill_radius := 0.0
var _hill_time := {}
var _hill_push := 0.0
var _hill_node: Node3D
## Team King of the Hill (host): each team's seconds holding the hill (red, blue).
var _team_hill := [0.0, 0.0]
## Juggernaut: who it is (everyone gets it from the host; 0 = nobody yet) and how many
## juggernauts have fallen this match.
var juggernaut_id := 0
var juggernaut_rounds := 0


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
	_match_start = Time.get_ticks_msec()
	_started_online = net.get("online")
	# This map's sun and environment, in the player's graphics settings.
	(func() -> void:
		if is_inside_tree():
			Graphics.apply_scene(get_tree())).call_deferred()
	# Joining a match that's already going: ask the host for its clock and team scores.
	if net.get("online") and not multiplayer.is_server():
		_zzhello.rpc_id(1)
	if net.get("online"):
		# Cubes and practice targets only exist offline for now (not network-synced).
		for practice in ["Targets", "LockTargets"]:
			if has_node(practice):
				get_node(practice).queue_free()
		net.connect("roster_changed", _sync_players)
	_sync_players()
	if net.get("online") and multiplayer.is_server() and base_mode() == "koth":
		_place_hill.call_deferred()
	# AI turrets wherever the map wants them (Map/Layout.turret_points()).
	var layout := get_node_or_null("Map/Layout")
	if layout and layout.has_method("turret_points") and not (layout.call("turret_points") as Array).is_empty():
		var turrets := Turrets.new()
		turrets.name = "Turrets"
		turrets.set("points", layout.call("turret_points"))
		add_child(turrets)
	# The map builds itself in as a wireframe (not on the server: nobody's watching).
	# Combine the map's thousands of boxes into a few meshes (same look, far fewer draw
	# calls) - after the build-in if it plays, since that animates the boxes one by one.
	var intro_on: bool = DisplayServer.get_name() != "headless" and has_node("Map") and SettingsScript.read(get_tree(), "map_intro")
	if DisplayServer.get_name() != "headless" and has_node("Map") and not intro_on:
		_merge_map.call_deferred()
	if intro_on:
		var intro := MapIntro.new()
		intro.map = $Map
		intro.done.connect(_merge_map)
		intro.hidden.append(_players_root)
		if has_node("Turrets"):
			intro.hidden.append($Turrets)
		add_child(intro)


## Leaving practice: practice admin powers (speed, low gravity, gold shield) end with it.
func _exit_tree() -> void:
	if not _started_online:
		var mod := get_tree().root.get_node_or_null("Mod")
		if mod:
			mod.call("practice_reset")


## Combine the map's static boxes (map_merge.gd). Once only.
func _merge_map() -> void:
	if not is_inside_tree() or has_meta("merged") or not has_node("Map"):
		return
	set_meta("merged", true)
	MapMerge.merge($Map)
	# Looping maps: now draw copies of the merged map all round it.
	var layout := get_node_or_null("Map/Layout")
	if layout and layout.has_method("make_wrap_visuals"):
		layout.call("make_wrap_visuals", $Map)


func _net() -> Node:
	return get_tree().root.get_node_or_null("Net")


func _roster() -> Dictionary:
	var net := _net()
	if net and net.get("online"):
		return net.get("players")
	var mod := get_tree().root.get_node_or_null("Mod")
	var speed: float = mod.get("practice_speed") if mod else 1.0
	return {1: {"name": "YOU", "color": 0, "loadout": WeaponInfo.local_loadout(get_tree()), "speed": speed}}


func _sync_players() -> void:
	# Leaving an online match: the connection closes (and the roster empties) a moment
	# before this scene is swapped for the menu. Don't spawn a practice player into a map
	# that's being torn down.
	if _started_online and not is_online():
		return
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
	# Stats the owner changed (speed) take effect straight away.
	for id in _players:
		_apply_set_perks(id)


## A player's loadout (weapon ids for keys 1-6) from the roster.
func loadout_of(id: int) -> Array:
	match base_mode():
		"juggernaut":
			# Everything that works online (the rift gun's practice only).
			return WeaponInfo.built_pool().filter(func(w: String) -> bool: return not WeaponInfo.by_id(w).get("practice_only", false))
		"gungame":
			var pool := WeaponInfo.damaging_pool()
			return [String(_roster().get(id, {}).get("gun", pool[0]))]
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
	var ids := loadout_of(id)
	ball.get_node("Weapon").call("set_loadout", ids, ids.size())
	_apply_set_perks(id)


## The set bonuses that change how a ball moves (on its owner's computer).
func _apply_set_perks(id: int) -> void:
	var ball: Node = _players.get(id)
	if not ball:
		return
	if not ball.has_meta("base_air_control"):
		for stat in ["air_control", "top_speed", "max_speed", "push_force", "roll_torque", "dash_speed"]:
			ball.set_meta("base_" + stat, ball.get(stat))
	var perks := perks_of(id)
	# The owner can speed anyone up or slow them down (moderation.gd set_stats): rolling
	# speed, top speed, acceleration and dash all scale together.
	var speed := float(_roster().get(id, {}).get("speed", 1.0))
	# The juggernaut: twice the size (on every computer, so everyone sees it) at half speed.
	ball.call("set_size", JUGGERNAUT_SIZE if is_juggernaut(id) else 1.0)
	if is_juggernaut(id):
		speed *= JUGGERNAUT_SPEED
	ball.set("air_control", float(ball.get_meta("base_air_control")) * (1.2 if perks.has("skyborne") else 1.0))
	ball.set("top_speed", float(ball.get_meta("base_top_speed")) * (1.1 if perks.has("momentum") else 1.0) * speed)
	for stat in ["max_speed", "push_force", "roll_torque", "dash_speed"]:
		ball.set(stat, float(ball.get_meta("base_" + stat)) * speed)


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
## Full health for id: MAX_HEALTH, unless the owner has set theirs (moderation.gd set_stats).
func max_health_of(id: int) -> float:
	var custom := float(_roster().get(id, {}).get("max_hp", 0.0))
	if custom > 0.0:
		return custom
	return JUGGERNAUT_HEALTH if is_juggernaut(id) else MAX_HEALTH


## True if player `id` is the juggernaut (Juggernaut mode only).
func is_juggernaut(id: int) -> bool:
	return id != 0 and id == juggernaut_id and base_mode() == "juggernaut"


func _is_god(id: int) -> bool:
	var net := _net()
	return net != null and net.get("players").get(id, {}).get("god", false)


func _spawn(id: int, index: int) -> void:
	var ball: RigidBody3D = PlayerScene.instantiate()
	ball.name = "P%d" % id
	# AI pilots are simulated by the host (bot_brain.gd): it owns their balls.
	var bot := is_online() and NetScript.is_bot(id)
	ball.set_meta("player_id", id)
	ball.set("bot", bot)
	ball.set_multiplayer_authority(1 if bot else id)
	ball.position = spawn_point(index)
	# Maps can set their own height ceiling (Map/Layout.ceiling()).
	var layout := get_node_or_null("Map/Layout")
	if layout and layout.has_method("ceiling"):
		ball.set("max_height", layout.call("ceiling"))
	# ...and how far down counts as falling off (deep maps like the Station Trench go lower).
	if layout and layout.has_method("fall_height"):
		ball.set("fall_reset_height", layout.call("fall_height"))
	# Their own weapons (the roster's loadout), built when the ball is added.
	var ids := loadout_of(id)
	ball.get_node("Weapon").set("loadout", ids)
	ball.get_node("Weapon").set("loadout_size", ids.size())
	_players_root.add_child(ball)
	_apply_set_perks(id)
	# A glowing trail behind the ball when it's going fast, in its player's colour.
	if DisplayServer.get_name() != "headless":
		var trail := SpeedTrail.new()
		trail.ball = ball
		var net := _net()
		trail.color = net.call("player_color", id) if net and is_online() else Color(0.35, 0.9, 1.0)
		add_child(trail)
		ball.tree_exiting.connect(trail.queue_free)
	if bot and multiplayer.is_server():
		var brain := BotBrain.new()
		brain.arena = self
		brain.bot_id = id
		ball.add_child(brain)
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
		# The tutorial (practice only): the menu flags it just before loading the map.
		if not is_online() and Engine.has_meta("tutorial"):
			Engine.remove_meta("tutorial")
			var tutorial := TutorialScript.new()
			tutorial.set("ball", ball)
			view.add_child(tutorial)
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
	return {"respawn_time": RESPAWN_TIME, "kills_to_win": _win_target(),
		"max_health": MAX_HEALTH, "end_delay": END_DELAY, "mode": game_mode(),
		"koth_time": KOTH_TIME, "juggernaut_rounds": JUGGERNAUT_ROUNDS}


## Kills to win: KILLS_TO_WIN (TEAM_KILLS_TO_WIN in a team game), or a server's
## SCORE_LIMIT environment variable (a quicker match, or for testing).
func _win_target() -> int:
	var env := OS.get_environment("SCORE_LIMIT")
	if env.is_valid_int() and int(env) > 0:
		return int(env)
	# Team Deathmatch counts the team's kills; Team Gun Game is still one player's run.
	return TEAM_KILLS_TO_WIN if game_mode() == "teams" else KILLS_TO_WIN


func is_team_game() -> bool:
	var net := _net()
	return net != null and net.get("online") and NetScript.TEAM_MODES.has(net.get("game_mode"))


## Seconds since this round started.
func match_time() -> float:
	return (Time.get_ticks_msec() - _match_start) / 1000.0


## True if a and b are different players on the same team (no friendly fire).
func _same_team(a: int, b: int) -> bool:
	if a == b or not is_team_game():
		return false
	var net := _net()
	var ta: int = net.call("team_of", a)
	return ta >= 0 and ta == int(net.call("team_of", b))


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


## Medical/Support weapons (Vampire, Healing Beam, Miasma, Borrowed Life): adds HP to
## `target` (capped at their max health), self or ally - unlike request_hit, this isn't
## blocked between teammates.
func request_heal(target: int, amount: float) -> void:
	_to_host("_host_heal", [target, amount])


## Antidote: clears a stun on `target` (self or a stunned ally).
func request_cure(target: int) -> void:
	_to_host("_host_cure", [target])


## Like request_hit, from a Tears of an Angel missile: parrying it kills the shooter.
func request_tears_hit(victim: int, amount: float) -> void:
	_to_host("_zztears_hit", [victim, amount])


## An Arc Pylon at `from` zapped player `victim`: see _zzzpylon_zap.
func request_pylon_zap(victim: int, amount: float, from: Vector3) -> void:
	_to_host("_zzzpylon_zap", [victim, amount, from])


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
	if multiplayer.is_server():
		_resolve_hit(_sender(), victim, amount)


## Host: an AI pilot's shot landed (bot_brain.gd), like a player's hit report.
func bot_hit(bot: int, victim: int, amount: float) -> void:
	if multiplayer.is_server():
		_resolve_hit(bot, victim, amount)


@rpc("any_peer", "reliable")
func _host_heal(target: int, amount: float) -> void:
	if not multiplayer.is_server() or match_done or not alive.get(target, false):
		return
	var cap := max_health_of(target)
	# Never lethal (amount can be negative: Healing Beam's self-cost) - a floor of 1, so
	# using a support weapon can weaken you but never kill you outright.
	var hp: float = clampf(health.get(target, cap) + amount, 1.0, cap)
	_set_health.rpc(target, hp)


@rpc("any_peer", "reliable")
func _host_cure(target: int) -> void:
	if multiplayer.is_server() and not match_done and alive.get(target, false):
		_to_peer(target, "_apply_cure", [])


## Host: ttacker's hit on ictim: a shield parries it, otherwise it's damage.
func _resolve_hit(attacker: int, victim: int, amount: float) -> void:
	if match_done:
		return
	if attacker == victim or _is_god(victim) or _same_team(attacker, victim):
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
	if attacker != victim and not _same_team(attacker, victim):
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
	_deal(victim, -1, amount, from)
	return false


## The sender fell off the map: a death, credited to whoever hit them in the last
## FALL_CREDIT_TIME seconds (or nobody). (Named to sort last, like _unblockable_hit.)
@rpc("any_peer", "reliable")
func _zfell() -> void:
	if multiplayer.is_server():
		_fell(_sender())


## Host: a bot fell off the map (its ball runs here).
func bot_fell(id: int) -> void:
	if multiplayer.is_server():
		_fell(id)


## Host: a bot raised its shield.
func bot_block(id: int, duration: float) -> void:
	if multiplayer.is_server() and alive.get(id, false):
		_blocks[id] = duration + 0.15
		_parried.erase(id)


func _fell(victim: int) -> void:
	if match_done:
		return
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
func _deal(victim: int, attacker: int, amount: float, from := Vector3.INF) -> void:
	if not alive.get(victim, false) or _protect.get(victim, 0.0) > 0.0 or _is_god(victim):
		return
	# Tell the victim where it came from (their screen shows an arrow that way).
	var source := from
	if source == Vector3.INF and attacker != victim and _players.has(attacker):
		source = _players[attacker].global_position
	if source != Vector3.INF and not NetScript.is_bot(victim):
		_to_peer(victim, "_zzhurt", [source])
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
	if multiplayer.is_server() and alive.get(victim, false) and not _same_team(_sender(), victim) and not _blocks.has(victim) and not _is_god(victim):
		_to_peer(victim, "_apply_push", [impulse])


@rpc("any_peer", "reliable")
func _host_mark(victim: int, duration: float) -> void:
	if multiplayer.is_server() and alive.get(victim, false) and not _same_team(_sender(), victim) and not _blocks.has(victim) and not _is_god(victim):
		# HUNTER set bonus: your marks last 50% longer.
		if perks_of(_sender()).has("hunter"):
			duration *= 1.5
		_marks[victim] = maxf(_marks.get(victim, 0.0), duration)
		_show_status.rpc(victim, "mark", duration)


@rpc("any_peer", "reliable")
func _host_stagger(victim: int, duration: float) -> void:
	if multiplayer.is_server() and alive.get(victim, false) and not _same_team(_sender(), victim) and not _blocks.has(victim) and not _is_god(victim):
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
	# The juggernaut never heals; everyone else gets health back for a kill.
	if attacker != victim and alive.get(attacker, false) and not is_juggernaut(attacker):
		_set_health.rpc(attacker, minf(health.get(attacker, max_health_of(attacker)) + KILL_HEAL, max_health_of(attacker)))
	_on_killed.rpc(victim, attacker, _held_weapon(attacker) if attacker != victim else "")
	var base := base_mode()
	if credited and base == "gungame":
		_give_gun(attacker)
	if base == "koth":
		pass  # The hill decides (_koth_tick), in teams or not.
	elif base == "juggernaut":
		_juggernaut_killed(victim, attacker if credited else 0)
	else:
		# Team modes: the killer's team gets the kill on the team score.
		var team: int = net.call("team_of", attacker) if credited else -1
		if team >= 0:
			team_scores[team] += 1
			_zzteam_scores.rpc(team_scores)
		if game_mode() == "teams":
			# Team Deathmatch: first team to TEAM_KILLS_TO_WIN (winner -1 red, -2 blue).
			if team >= 0 and team_scores[team] >= _win_target():
				_match_won(-1 - team)
		elif credited and int(roster[attacker]["kills"]) >= _win_target():
			# Free for all and Gun Game; in Team Gun Game it wins for the killer's team.
			_match_won(-1 - team if team >= 0 else attacker)


## Host: the round is over, won by `winner` (a player, or -1 red / -2 blue): the banner,
## then the vote for the next round.
func _match_won(winner: int) -> void:
	_on_match_over.rpc(winner)
	_end_timer = END_DELAY
	_open_vote()


## Juggernaut (host): someone died. If it was the juggernaut, their round is over: the
## killer takes over (a fall or a staff kill hands it to someone at random), and after
## JUGGERNAUT_ROUNDS juggernauts the most kills wins.
func _juggernaut_killed(victim: int, killer: int) -> void:
	if victim != juggernaut_id:
		return
	juggernaut_rounds += 1
	if juggernaut_rounds >= JUGGERNAUT_ROUNDS:
		var winner := -1
		var best := -1
		var roster := _roster()
		for id in roster:
			if int(roster[id].get("kills", 0)) > best:
				best = int(roster[id].get("kills", 0))
				winner = id
		_zzzzjugg.rpc(0, juggernaut_rounds)
		_match_won(winner)
		return
	if killer == 0 or not alive.get(killer, false):
		killer = _random_alive(victim)
	_set_juggernaut(killer)


## Host: a random living player other than `skip` (0 if there's nobody).
func _random_alive(skip: int) -> int:
	var ids := _players.keys().filter(func(id: int) -> bool: return id != skip and alive.get(id, false))
	return ids[randi() % ids.size()] if not ids.is_empty() else 0


## Host: make `id` the juggernaut (everyone's told), at full juggernaut health.
func _set_juggernaut(id: int) -> void:
	_zzzzjugg.rpc(id, juggernaut_rounds)
	if id != 0 and alive.get(id, false):
		_set_health.rpc(id, max_health_of(id))
	print("[server] %s is the juggernaut (round %d/%d)" % [_net().call("player_name", id) if id != 0 else "nobody", juggernaut_rounds + 1, JUGGERNAUT_ROUNDS])


## Host, every physics step in Juggernaut: there's always a juggernaut while anyone's
## alive (the first round, or after the juggernaut left the server).
func _juggernaut_tick() -> void:
	if juggernaut_id != 0 and _players.has(juggernaut_id):
		return
	var id := _random_alive(0)
	if id != 0:
		_set_juggernaut(id)


## Everyone: player `id` is the juggernaut now, `rounds` juggernauts in. Their size and
## speed change on every computer. (Named to sort last: Godot numbers RPCs alphabetically.)
@rpc("authority", "call_local", "reliable")
func _zzzzjugg(id: int, rounds: int) -> void:
	var old := juggernaut_id
	juggernaut_id = id
	juggernaut_rounds = rounds
	for p in [old, id]:
		if _players.has(p):
			_apply_set_perks(p)
	juggernaut_changed.emit(id)


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
	var net := _net()
	# A fresh online server: before its first round gets going, everyone votes on the map
	# and mode (once someone has finished loading in, so the vote reaches them).
	if net.get("dedicated") and not net.get("first_vote_done") and not match_done and not ready_peers.is_empty():
		net.set("first_vote_done", true)
		_zzzzvote_first.rpc()
		_open_vote()
		_end_timer = END_DELAY
	if not match_done:
		_heal_holstered(delta)
		if base_mode() == "koth":
			_koth_tick(delta)
		elif base_mode() == "juggernaut":
			_juggernaut_tick()
		elif base_mode() == "gungame":
			# Anyone still unarmed (joined while their roster entry was on its way).
			_hill_push -= delta
			if _hill_push <= 0.0:
				_hill_push = 1.0
				for id in _players:
					if not _roster().get(id, {}).has("gun") or not _gun_given.has(id):
						_gun_given[id] = true
						_give_gun(id)
	if _end_timer > 0.0:
		_end_timer -= delta
		if _end_timer <= 0.0:
			_close_vote()
			_net().call("end_match")


## Host: open the vote for the next round: every combat map plus RANDOM, and the mode.
func _open_vote() -> void:
	var net := _net()
	var options: Array = net.COMBAT_MAPS.duplicate()
	options.append("random")
	_votes.clear()
	_mode_votes.clear()
	_zvote_open.rpc(options)


## Host: the most-voted map and mode win. A tie on maps is settled at random among the
## tied; RANDOM (or no votes at all) picks any map but this one. A tied or empty mode
## vote keeps the current mode.
func _close_vote() -> void:
	if vote_options.is_empty():
		return
	var net := _net()
	var counts := _count(_votes, vote_options.size())
	var best: int = counts.max()
	var tied: Array = []
	for i in counts.size():
		if counts[i] == best and best > 0:
			tied.append(i)
	var pick := "random"
	if not tied.is_empty():
		pick = vote_options[tied[randi() % tied.size()]]
	if pick == "random":
		var maps: Array = net.COMBAT_MAPS.duplicate()
		maps.erase(net.get("map_scene"))
		pick = maps[randi() % maps.size()]
	net.set("map_scene", pick)
	var modes := _count(_mode_votes, NetScript.MODES.size())
	var top: int = modes.max()
	if top > 0 and modes.count(top) == 1:
		net.set("game_mode", NetScript.MODES[modes.find(top)])


## How many (present) players voted for each of `size` choices.
func _count(votes: Dictionary, size: int) -> Array:
	var counts: Array = []
	counts.resize(size)
	counts.fill(0)
	for peer in votes:
		if _players.has(peer) and votes[peer] >= 0 and votes[peer] < size:
			counts[votes[peer]] += 1
	return counts


## Any peer: vote for map option `index` (0-based).
func cast_vote(index: int) -> void:
	if not is_online() or index < 0 or index >= vote_options.size():
		return
	if multiplayer.is_server():
		_zvote_cast(index)
	else:
		_zvote_cast.rpc_id(1, index)


## Any peer: vote for mode `index` (Net.MODES).
func cast_mode_vote(index: int) -> void:
	if not is_online() or index < 0 or index >= NetScript.MODES.size():
		return
	if multiplayer.is_server():
		_zzvote_mode(index)
	else:
		_zzvote_mode.rpc_id(1, index)

## Host: players with their weapon put away heal the faster they go (see HEAL_*).
func _heal_holstered(delta: float) -> void:
	for id in _players:
		if is_juggernaut(id):
			continue  # The juggernaut never heals.
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
	if NetScript.is_bot(peer):
		_bot_call(peer, method, args)
		return
	if peer == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer, method] + args)


## Host: what the host would have sent to a player's computer, done straight to a bot's
## ball (the host simulates bots).
func _bot_call(id: int, method: StringName, args: Array) -> void:
	var ball: Node = _players.get(id)
	if not ball or ball.get("dead"):
		return
	match String(method):
		"_apply_push":
			(ball as RigidBody3D).apply_central_impulse(args[0])
		"_apply_parry":
			var shooter: Node3D = _players.get(args[0])
			ball.call("on_parried", shooter.global_position if shooter else Vector3.INF)
		"_zzparry_at":
			ball.call("on_parried", args[0])
		"_zzzpylon_broken":
			_break_pylon(ball)
		"_apply_stagger":
			ball.call("stagger_controls", args[0])
		"_zzapply_status":
			ball.call("apply_status", args[0], args[1], args[2])
		"_zzteleport":
			ball.call("teleport", args[0])


# --- Results (run on every peer) -------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _set_health(id: int, hp: float) -> void:
	health[id] = hp
	health_changed.emit(id, hp)


@rpc("authority", "call_local", "reliable")
func _on_killed(victim: int, attacker: int, weapon: String) -> void:
	alive[victim] = false
	last_kill_weapon = weapon
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


## Host: the weapon id player `id` is holding ("" if unknown), for the kill feed.
func _held_weapon(id: int) -> String:
	var ball: Node = _players.get(id)
	var weapon := ball.get_node_or_null("Weapon") if ball else null
	return String(weapon.call("slot_id", weapon.get("current"))) if weapon else ""


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
		# Our own ball, or (on the host) a bot's: back to life at pos.
		if id == multiplayer.get_unique_id() or (NetScript.is_bot(id) and multiplayer.is_server()):
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
	_zzvote_state.rpc(_votes, _mode_votes)


@rpc("any_peer", "reliable")
func _zzvote_mode(index: int) -> void:
	if not multiplayer.is_server() or vote_options.is_empty() or index < 0 or index >= NetScript.MODES.size() \
			or not (_net().call("mode_pool") as Array).has(NetScript.MODES[index]):
		return
	_mode_votes[_sender()] = index
	_zzvote_state.rpc(_votes, _mode_votes)


## Everyone: who has voted for what (for the tokens on the vote screen).
@rpc("authority", "call_local", "reliable")
func _zzvote_state(map_votes: Dictionary, mode_votes: Dictionary) -> void:
	vote_state.emit(map_votes, mode_votes)


## A late joiner asks the host for the match clock and the team scores.
@rpc("any_peer", "reliable")
func _zzhello() -> void:
	if multiplayer.is_server():
		ready_peers[_sender()] = true
		if has_node("Turrets"):
			get_node("Turrets").call("send_state_to", _sender())
		_zzclock.rpc_id(_sender(), match_time(), team_scores)
		if hill_radius > 0.0:
			_zzzhill.rpc_id(_sender(), hill_pos, hill_radius)
		if juggernaut_id != 0:
			_zzzzjugg.rpc_id(_sender(), juggernaut_id, juggernaut_rounds)


@rpc("authority", "reliable")
func _zzclock(elapsed: float, scores: Array) -> void:
	_match_start = Time.get_ticks_msec() - int(elapsed * 1000.0)
	_zzteam_scores(scores)


## Everyone: the team totals (a team game).
@rpc("authority", "call_local", "reliable")
func _zzteam_scores(scores: Array) -> void:
	if scores.size() == 2:
		team_scores = scores
		team_scores_changed.emit(team_scores)


@rpc("authority", "call_local", "reliable")
func _zvote_open(options: Array) -> void:
	vote_options = options.filter(func(p) -> bool: return typeof(p) == TYPE_STRING)
	vote_opened.emit(vote_options)


## A Tears of an Angel hit. Unshielded: ordinary damage. On a shield: the usual parry for
## the blocker, and the shooter dies outright, credited to the blocker. (Named to sort
## after the other RPCs.)
@rpc("any_peer", "reliable")
func _zztears_hit(victim: int, amount: float) -> void:
	if not multiplayer.is_server() or match_done:
		return
	var attacker := _sender()
	if attacker == victim or _is_god(victim) or _same_team(attacker, victim):
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
	_on_killed.rpc(victim, by, "")
	# A staff kill on the juggernaut still ends their round (nobody's credited).
	if base_mode() == "juggernaut":
		_juggernaut_killed(victim, 0)


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
	if not multiplayer.is_server() or match_done or not kind in ["chill", "freeze", "cage", "pin", "pull", "dilate"]:
		return
	var attacker := _sender()
	if attacker == victim or not alive.get(victim, false) or _blocks.has(victim) or _is_god(victim) or _same_team(attacker, victim) \
			or _protect.get(victim, 0.0) > 0.0:
		return
	duration = clampf(duration, 0.0, 8.0)
	if kind != "pull" and perks_of(attacker).has("frost"):
		duration *= 1.3
	_to_peer(victim, "_zzapply_status", [kind, duration, data])
	_show_status.rpc(victim, kind, duration)


## We were hit from pos.
@rpc("authority", "unreliable")
func _zzhurt(pos: Vector3) -> void:
	hurt_from.emit(pos)


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


## Host: an Arc Pylon zap. On a raised shield the defender parries it (launched, like a
## turret's shot) and the pylon breaks; the planter is NOT stunned. Otherwise damage.
@rpc("any_peer", "reliable")
func _zzzpylon_zap(victim: int, amount: float, from: Vector3) -> void:
	if not multiplayer.is_server() or match_done:
		return
	var attacker := _sender()
	if attacker == victim or not alive.get(victim, false) or _is_god(victim) or _same_team(attacker, victim):
		return
	if _blocks.has(victim):
		if not _parried.has(victim):
			_parried[victim] = true
			_to_peer(victim, "_zzparry_at", [from])
		_to_peer(attacker, "_zzzpylon_broken", [])
		return
	_deal(victim, attacker, amount, from)


## Our Arc Pylon was parried: it breaks. (Named to sort last.)
@rpc("authority", "reliable")
func _zzzpylon_broken() -> void:
	_break_pylon(_players.get(multiplayer.get_unique_id()))


func _break_pylon(ball: Node) -> void:
	var manager: Node = ball.get_node_or_null("Weapon") if ball else null
	if not manager:
		return
	for w in manager.get_children():
		if w.has_method("break_pylon"):
			w.call("break_pylon")


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


## Antidote cured us: clear the stun so we can move and shoot again.
@rpc("authority", "reliable")
func _apply_cure() -> void:
	var ball: Node3D = _players.get(multiplayer.get_unique_id())
	if ball:
		ball.call("clear_stagger")


# --- Game modes (Net.MODES) --------------------------------------------------------

## The mode this round is played in ("ffa" offline).
func game_mode() -> String:
	var net := _net()
	return String(net.get("game_mode")) if net and net.get("online") else "ffa"


## The rules this round follows: Team King of the Hill plays like King of the Hill (and
## Team Gun Game like Gun Game), with teams on top.
func base_mode() -> String:
	return NetScript.base_mode(game_mode())


## Everyone: a fresh server's first round opens with the map and mode vote, before
## anyone plays (play stops while it's open). (Named to sort last.)
@rpc("authority", "call_local", "reliable")
func _zzzzvote_first() -> void:
	match_done = true
	first_vote_opened.emit()


## Gun Game (host): hand player `id` a new random weapon (never the one they hold). Bots
## only get the guns they know how to use.
func _give_gun(id: int) -> void:
	if not multiplayer.is_server() or not _roster().has(id):
		return
	var pool: Array = ["gatling", "railgun", "scatter"] if NetScript.is_bot(id) else WeaponInfo.damaging_pool()
	var held := String(_roster()[id].get("gun", ""))
	var choices := pool.filter(func(w: String) -> bool: return w != held)
	_zzzgun.rpc(id, choices[randi() % choices.size()])


## Everyone: player `id`'s Gun Game weapon is now `gun`. (Named to sort last.)
@rpc("authority", "call_local", "reliable")
func _zzzgun(id: int, gun: String) -> void:
	if not WeaponInfo.damaging_pool().has(gun):
		return
	var roster := _roster()
	if roster.has(id):
		roster[id]["gun"] = gun
	refresh_loadout(id)
	var ball: Node = _players.get(id)
	var weapon: Node = ball.get_node_or_null("Weapon") if ball else null
	if weapon and (id == multiplayer.get_unique_id() or (NetScript.is_bot(id) and multiplayer.is_server())):
		weapon.call("select", 0)


## King of the Hill (host): put the hill at the map's focus point: Map/Layout.hill_point()
## if the map says, else the ground in the middle of the spawn points (or, if that's a
## rooftop, the spawn nearest the middle).
func _place_hill() -> void:
	var spots := _map_spawns()
	var layout := get_node_or_null("Map/Layout")
	var pos := Vector3.ZERO
	var spread := 60.0
	if not spots.is_empty():
		var mid := Vector3.ZERO
		var low := INF
		for p in spots:
			mid += p
			low = minf(low, p.y)
		mid /= spots.size()
		spread = 0.0
		for p in spots:
			spread += Vector2(p.x - mid.x, p.z - mid.z).length()
		spread /= spots.size()
		var ray := PhysicsRayQueryParameters3D.create(Vector3(mid.x, low + 200.0, mid.z), Vector3(mid.x, low - 200.0, mid.z))
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit["position"].y < low + 20.0:
			pos = hit["position"]
		else:
			var best: Vector3 = spots[0]
			for p in spots:
				if Vector2(p.x - mid.x, p.z - mid.z).length() < Vector2(best.x - mid.x, best.z - mid.z).length():
					best = p
			pos = best - Vector3.UP * 0.5
	if layout and layout.has_method("hill_point"):
		pos = layout.call("hill_point")
	_zzzhill.rpc(pos, clampf(spread * 0.15, 7.0, 18.0))


## Everyone: where the hill is (drawn as a glowing gold ring and column). (Sorts last.)
@rpc("authority", "call_local", "reliable")
func _zzzhill(pos: Vector3, radius: float) -> void:
	hill_pos = pos
	hill_radius = radius
	if DisplayServer.get_name() == "headless":
		return
	if _hill_node:
		_hill_node.queue_free()
	_hill_node = HillScript.new()
	_hill_node.set("radius", radius)
	_hill_node.position = pos
	add_child(_hill_node)


## True if player `id` is standing in the hill.
func on_hill(id: int) -> bool:
	var ball: Node3D = _players.get(id)
	if hill_radius <= 0.0 or not ball or not alive.get(id, false):
		return false
	var d := ball.global_position - hill_pos
	return Vector2(d.x, d.z).length() <= hill_radius and d.y > -3.0 and d.y < 10.0


## Seconds left in a King of the Hill round.
func koth_time_left() -> float:
	return maxf(KOTH_TIME - match_time(), 0.0)


## Host, every physics step in King of the Hill: everyone on the hill scores time; scores
## go out once a second as the roster's "score"; at KOTH_TIME the most time wins.
## Team King of the Hill: a team scores while any of its players hold the hill (nobody
## does while both teams are on it), and at KOTH_TIME the team with more time wins.
func _koth_tick(delta: float) -> void:
	var teams_on := {}
	for id in _players:
		if on_hill(id):
			_hill_time[id] = float(_hill_time.get(id, 0.0)) + delta
			var team: int = _net().call("team_of", id)
			if team >= 0:
				teams_on[team] = true
	if is_team_game() and teams_on.size() == 1:
		var holder: int = teams_on.keys()[0]
		_team_hill[holder] += delta
	_hill_push -= delta
	var over := match_time() >= KOTH_TIME
	if _hill_push <= 0.0 or over:
		_hill_push = 1.0
		var roster := _roster()
		for id in roster:
			roster[id]["score"] = int(_hill_time.get(id, 0.0))
		_net().call("push_roster")
		if is_team_game():
			team_scores = [int(_team_hill[0]), int(_team_hill[1])]
			_zzteam_scores.rpc(team_scores)
	if over:
		if is_team_game():
			_match_won(-1 if _team_hill[0] >= _team_hill[1] else -2)
			return
		var winner := -1
		var best := -1.0
		for id in _roster():
			var t := float(_hill_time.get(id, 0.0))
			if t > best:
				best = t
				winner = id
		_match_won(winner)
