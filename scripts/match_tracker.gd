extends Node
## Watches a match for the player at this computer and turns what happens into their
## career (scripts/profile.gd): experience for kills and for finishing, medals for doing
## it with style (multi-kills, streaks, long shots, revenge...), lifetime stats. Added by
## the arena beside the HUD, in real matches only (online or a skirmish against bots, not
## solo practice). It only listens: the host still decides every hit and kill.
## It also keeps this match's tally (`earned`, `kills`, `deaths`, `medals`) for the summary
## the HUD shows when the match ends.

const Profile := preload("res://scripts/profile.gd")
const NetScript := preload("res://scripts/net/net.gd")
## Kills this close together (seconds) chain into a multi-kill.
const MULTI_WINDOW := 4.0
const LONG_SHOT := 150.0
const POINT_BLANK := 6.0
## Speedometer units (m/s x 5).
const SPEED_DEMON := 300.0

var arena: Node
var ball: RigidBody3D

## This match: experience by reason, in the order it came; kills, deaths, medal ids.
var earned := {}
var kills := 0
var deaths := 0
var medals: Array[String] = []
var best_streak := 0
var finished := false

var _profile: Node
var _me := 0
var _streak := 0
var _streaks := {}
var _multi := 0
var _multi_until := 0.0
var _last_killer := 0
var _deaths_in_row := 0
var _any_kill := false
var _second := 0.0


func _ready() -> void:
	_profile = Profile.of(get_tree())
	if not _profile or not arena:
		set_process(false)
		return
	_me = multiplayer.get_unique_id()
	arena.connect("player_killed", _on_killed)
	arena.connect("match_over", _on_match_over)
	_profile.connect("xp_gained", _on_xp)
	_profile.connect("medal_earned", func(id: String) -> void: medals.append(id))
	if ball and ball.has_signal("parried"):
		ball.connect("parried", _on_parried)
	_profile.call("roll_challenges")


func _exit_tree() -> void:
	# Leaving (or the next round loading): what was earned is kept.
	if _profile:
		_profile.call("save")


func _process(delta: float) -> void:
	_second += delta
	if _second >= 1.0:
		_profile.call("add_stat", "playtime", _second)
		_second = 0.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_xp(amount: int, reason: String) -> void:
	if finished and reason == "":
		return
	var key := reason if reason != "" else "OTHER"
	earned[key] = int(earned.get(key, 0)) + amount


func total_earned() -> int:
	var sum := 0
	for key in earned:
		sum += int(earned[key])
	return sum


func _on_parried() -> void:
	_profile.call("add_stat", "parries")
	_profile.call("earn_medal", "parry")


func _on_killed(victim: int, attacker: int) -> void:
	if finished:
		return
	var solo := attacker == victim
	if attacker == _me and not solo:
		_my_kill(victim)
	if victim == _me:
		deaths += 1
		_profile.call("add_stat", "deaths")
		_streak = 0
		_multi = 0
		_deaths_in_row += 1
		_last_killer = 0 if solo else attacker
	if not solo:
		_streaks[attacker] = int(_streaks.get(attacker, 0)) + 1
		_any_kill = true
	_streaks[victim] = 0


func _my_kill(victim: int) -> void:
	kills += 1
	_profile.call("add_stat", "kills")
	var weapon := String(arena.get("last_kill_weapon"))
	if weapon != "":
		_profile.call("add_stat", "kills_with_" + weapon)
	_profile.call("award", Profile.XP_KILL, "KILLS")
	var earned_now: Array[String] = []
	if not _any_kill:
		earned_now.append("first_blood")
	# Multi-kills: each kill within MULTI_WINDOW of the last adds to the chain.
	var now := _now()
	_multi = _multi + 1 if now <= _multi_until else 1
	_multi_until = now + MULTI_WINDOW
	if _multi >= 2:
		earned_now.append(["double", "triple", "quad", "rampage"][mini(_multi, 5) - 2])
		_profile.call("add_stat", "multi_kills")
	# Streaks.
	_streak += 1
	best_streak = maxi(best_streak, _streak)
	_profile.call("best_stat", "best_streak", float(_streak))
	_profile.call("best_stat", "day_best_streak", float(_streak))
	match _streak:
		5:
			earned_now.append("spree")
		10:
			earned_now.append("unstoppable")
		15:
			earned_now.append("godlike")
	# How it was done.
	var theirs: Node3D = arena.call("player_ball", victim)
	if ball and theirs:
		var dist := ball.global_position.distance_to(theirs.global_position)
		if dist >= LONG_SHOT:
			earned_now.append("long_shot")
			_profile.call("add_stat", "long_shots")
		elif dist <= POINT_BLANK:
			earned_now.append("point_blank")
		_profile.call("best_stat", "longest_kill", dist)
	if ball:
		if not bool(ball.get("_grounded")):
			earned_now.append("airborne")
			_profile.call("add_stat", "air_kills")
		if ball.linear_velocity.length() * 5.0 >= SPEED_DEMON:
			earned_now.append("speed_demon")
	if victim == _last_killer and victim != 0:
		earned_now.append("revenge")
		_last_killer = 0
	if int(_streaks.get(victim, 0)) >= 5:
		earned_now.append("shutdown")
	if _deaths_in_row >= 3:
		earned_now.append("comeback")
	_deaths_in_row = 0
	var hp: float = (arena.get("health") as Dictionary).get(_me, 100.0)
	if hp > 0.0 and hp < 15.0:
		earned_now.append("last_gasp")
	if arena.has_method("is_juggernaut") and arena.call("is_juggernaut", victim):
		earned_now.append("giant_slayer")
	# Biggest first, so the one that matters most leads the pop-ups.
	earned_now.sort_custom(func(a: String, b: String) -> bool: return int(Profile.MEDALS[a]["tier"]) > int(Profile.MEDALS[b]["tier"]))
	for id in earned_now:
		_profile.call("earn_medal", id)


func _on_match_over(winner: int) -> void:
	if finished:
		return
	var won := winner == _me
	if winner == -1 or winner == -2:
		var net := get_tree().root.get_node_or_null("Net")
		won = net != null and int(net.call("team_of", _me)) == -1 - winner
	_profile.call("add_stat", "matches")
	_profile.call("award", Profile.XP_MATCH, "MATCH COMPLETE")
	if won:
		_profile.call("add_stat", "wins")
		var mode: String = arena.call("base_mode") if arena.has_method("base_mode") else "ffa"
		_profile.call("add_stat", "wins_" + mode)
		_profile.call("earn_medal", "victory")
		if deaths == 0 and kills > 0:
			_profile.call("earn_medal", "flawless")
	finished = true
	_profile.call("save")
