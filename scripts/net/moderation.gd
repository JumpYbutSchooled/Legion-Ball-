extends Node
## Moderation service (/root/Mod, created by scripts/services.gd).
## Staff type their code into Settings. When they join an online server the game sends
## it, and the server compares it with its OWNER_CODE, MOD_CODE and TESTER_CODE
## environment variables (set on Render, never in the game files):
##   owner  - moderator powers, both staff weapons (slots 7-8), the gold invincibility
##            shield (G) and a gold OWNER title
##   mod    - kick, ban and end the match, Rain of God (slot 7) and a MOD title
## Staff weapons also work in offline practice once a server has confirmed the code
## (STAFF_FILE), and key 0 hides or shows them (weapon.gd).
##   tester - a green TESTER title
## The server checks every request, so a modified game can't fake being a mod.
## On a player-hosted game the host can moderate without a code.
## Bans live in the server's memory: they last until that server restarts or sleeps.
## Every player sends a random device id (user://device_id), so a ban survives a name
## change or a reconnect.
## These RPCs live on their own node rather than Net: Godot numbers a node's RPCs
## alphabetically, and adding them to Net would renumber its RPCs and break players and
## servers on other versions.

signal mod_changed

const DEVICE_FILE := "user://device_id"
## The last role a server confirmed, and a hash of the code that earned it, so the owner
## weapons also work in offline practice (no server to ask). Only this PC trusts it, and
## only for solo play: online, the server checks the code every time.
const STAFF_FILE := "user://staff.cfg"
## Wrong codes allowed per connection before the server stops listening.
const MAX_ATTEMPTS := 5
## The same code box takes any staff code; the server checks each against its own
## environment variable. Owners are also moderators, and get the owner weapons.
const ROLE_CODES := [["owner", "OWNER_CODE"], ["mod", "MOD_CODE"], ["tester", "TESTER_CODE"]]
## Title shown by each role's name: [text, colour].
const TITLES := {
	"owner": ["OWNER", Color(1.0, 0.78, 0.2)],
	"mod": ["MOD", Color(0.35, 0.9, 1.0)],
	"tester": ["TESTER", Color(0.35, 1.0, 0.35)],
}

## True once the server has accepted this player's moderator (or owner) code.
var is_mod := false
## "owner", "mod", "tester" or "", as confirmed by the server.
var role := ""
## The gold shield in offline practice (online it's in the server's roster: "god").
var offline_god := false
## Staff state the server shares with every peer (_zstate), so each game enforces it on
## its own player:
##   allowed_weapons  bitmask of the weapon slots players may use (owner exempt); 0 = none
##   low_gravity      everyone floats (owner toggle)
##   frozen / muted   peer ids held in place / kept out of chat (moderators)
const ALL_WEAPONS := 0xFF
const LOW_GRAVITY_SCALE := 0.3
var allowed_weapons := ALL_WEAPONS
var low_gravity := false
var frozen: Array = []
var muted: Array = []

## A staff announcement for everyone (HUD banner).
signal announced(text: String, by: String)

var _net: Node
var _device_id := ""
var _saved_role := ""
var _saved_hash := ""
var _greeted := false
# Server only, all keyed by peer id except the ban lists.
var _mods := {}
var _attempts := {}
var _devices := {}
var _banned_devices := {}
var _banned_names := {}


func _ready() -> void:
	_device_id = _load_device_id()
	var staff := ConfigFile.new()
	if staff.load(STAFF_FILE) == OK:
		_saved_role = staff.get_value("staff", "role", "")
		_saved_hash = staff.get_value("staff", "code_hash", "")
	_net = get_tree().root.get_node_or_null("Net")
	if _net:
		_net.connect("roster_changed", _on_roster_changed)
		# Server: whoever joins learns the staff state (weapon locks, freezes...).
		_net.connect("roster_changed", func() -> void:
			if _net.get("online") and multiplayer.is_server():
				_send_state())
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## A roster entry's title as [text, colour], or [] for none. Older servers only send
## the "mod" flag.
static func title_of(entry: Dictionary) -> Array:
	var r: String = entry.get("role", "mod" if entry.get("mod", false) else "")
	return TITLES.get(r, [])


## Online: the role the server confirmed. Offline (practice): the role a server
## confirmed before, as long as the same code is still in Settings.
func staff_role() -> String:
	if _net != null and _net.get("online"):
		return role
	if _saved_hash != "" and _saved_hash == _code_hash():
		return _saved_role
	return ""


func is_owner() -> bool:
	return staff_role() == "owner"


## True if this player can use the moderation tools right now.
func can_moderate() -> bool:
	if not _net or not _net.get("online"):
		return false
	return is_mod or (_net.call("is_host") and not _net.get("dedicated"))


func kick(id: int) -> void:
	if multiplayer.is_server():
		_kick(id)
	else:
		_kick.rpc_id(1, id)


func ban(id: int) -> void:
	if multiplayer.is_server():
		_ban(id)
	else:
		_ban.rpc_id(1, id)


## G: the owner's gold shield. Online the server checks you're the owner and makes you
## invincible (arena.gd _is_god); everyone sees the shield. In offline practice it's
## just the look (nothing hurts you there anyway).
func toggle_god_shield() -> void:
	if not is_owner():
		return
	if _net.get("online"):
		var mine: Dictionary = _net.get("players").get(multiplayer.get_unique_id(), {})
		var on: bool = not mine.get("god", false)
		if multiplayer.is_server():
			_set_god(on)
		else:
			_set_god.rpc_id(1, on)
	else:
		offline_god = not offline_god
		_refresh_god_shields()


## Ends the round for everyone on the server (scores reset).
func end_match() -> void:
	if multiplayer.is_server():
		_end_match()
	else:
		_end_match.rpc_id(1)


## Moderators and the owner: teleport player `id` to you (0 = everyone).
func bring(id: int) -> void:
	_to_server("_zbring", [id])


## Owner: kill every other player (scores unchanged).
func kill_all() -> void:
	_to_server("_zkill_all", [])


## Owner: which weapon slots everyone else may use (bitmask, bit n = slot n).
func set_weapons(mask: int) -> void:
	_to_server("_zweapons", [mask])


## Testers and up: jump to player `id`.
func goto(id: int) -> void:
	_to_server("_zgoto", [id])


## Moderators: kill one player (scores unchanged).
func slay(id: int) -> void:
	_to_server("_zslay", [id])


## Moderators: hold a player in place (0 = everyone, owner only).
func set_frozen(id: int, on: bool) -> void:
	_to_server("_zfreeze", [id, on])


## Moderators: keep a player out of chat.
func set_muted(id: int, on: bool) -> void:
	_to_server("_zmute", [id, on])


## Moderators: a banner on everyone's screen.
func announce(text: String) -> void:
	text = text.replace("\n", " ").strip_edges().substr(0, 100)
	if text != "":
		_to_server("_zannounce", [text])


## Owner: everyone back to full health.
func heal_all() -> void:
	_to_server("_zheal_all", [])


## Owner: fling a player high into the air.
func launch(id: int) -> void:
	_to_server("_zlaunch", [id])


## Owner: low gravity for everyone, on or off.
func toggle_low_gravity() -> void:
	_to_server("_zgravity", [])


func _to_server(method: StringName, args: Array) -> void:
	if not _net or not _net.get("online"):
		return
	if multiplayer.is_server():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


## Staff levels: 3 owner, 2 mod, 1 tester, 0 nobody.
static func level_of(staff: String) -> int:
	return {"owner": 3, "mod": 2, "tester": 1}.get(staff, 0)


## This player's staff level online (a player-hosted game's host counts as a mod).
func my_level() -> int:
	if not _net or not _net.get("online"):
		return 0
	var lvl := level_of(role)
	if _net.call("is_host") and not _net.get("dedicated"):
		lvl = maxi(lvl, 2)
	return lvl


## May our own player use weapon `slot` right now? The owner always may.
func weapon_allowed(slot: int) -> bool:
	return staff_role() == "owner" or (allowed_weapons & (1 << slot)) != 0


## Every weapon locked for our player.
func my_guns_locked() -> bool:
	return staff_role() != "owner" and (allowed_weapons & ALL_WEAPONS) == 0


func is_frozen(id: int) -> bool:
	return frozen.has(id)


func is_muted(id: int) -> bool:
	return muted.has(id)


## Who may switch the AI turrets on and off: anyone in practice; online, staff (owner,
## mod or tester) or the host of a player-hosted game.
func can_toggle_turrets() -> bool:
	if not _net or not _net.get("online"):
		return true
	return staff_role() != "" or (_net.call("is_host") and not _net.get("dedicated"))


## Switches the AI turrets on or off (for the whole server when online).
func toggle_turrets() -> void:
	if not _net.get("online"):
		_apply_turrets(not _net.get("turrets_on"))
	elif multiplayer.is_server():
		_toggle_turrets()
	else:
		_toggle_turrets.rpc_id(1)


## Whether turrets are on right now, as far as this game knows (the arena's turrets, or
## the practice setting).
func turrets_enabled() -> bool:
	var scene := get_tree().current_scene
	var turrets := scene.get_node_or_null("Turrets") if scene else null
	if turrets:
		return turrets.get("enabled")
	return _net.get("turrets_on")


func _apply_turrets(on: bool) -> void:
	_net.set("turrets_on", on)
	var scene := get_tree().current_scene
	var turrets := scene.get_node_or_null("Turrets") if scene else null
	if turrets:
		turrets.call("set_enabled", on)


## Moves everyone on the server to map `path` straight away (scores reset).
func switch_map(path: String) -> void:
	if multiplayer.is_server():
		_switch_map(path)
	else:
		_switch_map.rpc_id(1, path)


# --- Client ---------------------------------------------------------------------------

## Once we're on a server's roster: say hello (device id for bans), then try the code.
func _on_roster_changed() -> void:
	if not _net.get("online"):
		_greeted = false
		role = ""
		offline_god = false
		# Leaving a server lifts everything it imposed.
		if allowed_weapons != ALL_WEAPONS or low_gravity or not frozen.is_empty() or not muted.is_empty():
			_zstate({"weapons": ALL_WEAPONS, "gravity": false, "frozen": [], "muted": []})
		_set_mod(false)
		return
	if multiplayer.is_server() or _greeted:
		return
	var players: Dictionary = _net.get("players")
	if not players.has(multiplayer.get_unique_id()):
		return
	_greeted = true
	_hello.rpc_id(1, _device_id)
	var settings := get_tree().root.get_node_or_null("Settings")
	var code := String(settings.call("get_value", "mod_code")).strip_edges() if settings else ""
	if code != "":
		_login.rpc_id(1, code)


@rpc("authority", "reliable")
func _login_result(ok: bool) -> void:
	_set_mod(ok)
	_net.call("_set_status", "Moderator tools unlocked." if ok else "Wrong moderator code.")


## Newer servers follow _login_result with the role itself. (Named to sort after the
## existing RPCs, so their numbering is unchanged for older versions.)
@rpc("authority", "reliable")
func _role_result(new_role: String) -> void:
	role = new_role
	_remember_role(new_role)
	var status := {
		"owner": "Owner mode unlocked.",
		"mod": "Moderator tools unlocked.",
		"tester": "Tester title unlocked.",
	}
	_net.call("_set_status", status.get(new_role, "Wrong code."))
	mod_changed.emit()


## Saves (or, on a wrong code, forgets) the confirmed role for offline practice.
func _remember_role(new_role: String) -> void:
	_saved_role = new_role
	_saved_hash = _code_hash() if new_role != "" else ""
	var staff := ConfigFile.new()
	staff.set_value("staff", "role", _saved_role)
	staff.set_value("staff", "code_hash", _saved_hash)
	staff.save(STAFF_FILE)


func _code_hash() -> String:
	var settings := get_tree().root.get_node_or_null("Settings") if is_inside_tree() else null
	var code := String(settings.call("get_value", "mod_code")).strip_edges() if settings else ""
	return code.sha256_text() if code != "" else ""


func _set_mod(value: bool) -> void:
	if value != is_mod:
		is_mod = value
		mod_changed.emit()


func _load_device_id() -> String:
	var f := FileAccess.open(DEVICE_FILE, FileAccess.READ)
	if f:
		var saved := f.get_as_text().strip_edges()
		if saved != "":
			return saved
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var w := FileAccess.open(DEVICE_FILE, FileAccess.WRITE)
	if w:
		w.store_string(id)
	return id


# --- Server ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _hello(device_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	_devices[peer] = device_id.substr(0, 64)
	if _banned_devices.has(_devices[peer]) or _banned_names.has(_player_name(peer).to_lower()):
		_remove(peer, "You are banned from this server.")


@rpc("any_peer", "reliable")
func _login(code: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var tries: int = _attempts.get(peer, 0)
	if tries >= MAX_ATTEMPTS:
		return
	_attempts[peer] = tries + 1
	# Compared as hashes so the check takes the same time whatever was typed.
	var typed := code.strip_edges().sha256_text()
	var new_role := ""
	for entry in ROLE_CODES:
		var real := OS.get_environment(entry[1]).strip_edges()
		if real != "" and typed == real.sha256_text():
			new_role = entry[0]
			break
	var moderates := new_role == "owner" or new_role == "mod"
	if new_role != "":
		if moderates:
			_mods[peer] = true
		var players: Dictionary = _net.get("players")
		if players.has(peer):
			players[peer]["role"] = new_role
			players[peer]["mod"] = moderates
			_net.call("push_roster")
		print("[server] %s is %s" % [_player_name(peer), new_role])
	# Testers aren't moderators: skip the older "moderator yes/no" reply for them.
	if new_role != "tester":
		_login_result.rpc_id(peer, moderates)
	_role_result.rpc_id(peer, new_role)


@rpc("any_peer", "reliable")
func _kick(target: int) -> void:
	if _may_act_on(target):
		print("[server] %s kicked %s" % [_player_name(_sender()), _player_name(target)])
		_remove(target, "Kicked by a moderator.")


@rpc("any_peer", "reliable")
func _ban(target: int) -> void:
	if not _may_act_on(target):
		return
	print("[server] %s banned %s" % [_player_name(_sender()), _player_name(target)])
	if _devices.has(target):
		_banned_devices[_devices[target]] = true
	_banned_names[_player_name(target).to_lower()] = true
	_remove(target, "Banned by a moderator.")


@rpc("any_peer", "reliable")
func _end_match() -> void:
	if multiplayer.is_server() and _is_moderator(_sender()):
		print("[server] %s ended the match" % _player_name(_sender()))
		_net.call("end_match")


## Owner only: turn the gold shield (invincibility) on or off. (Named to sort after the
## existing RPCs so their numbering is unchanged for older versions.)
@rpc("any_peer", "reliable")
func _set_god(on: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var players: Dictionary = _net.get("players")
	if not players.has(peer) or players[peer].get("role", "") != "owner":
		return
	players[peer]["god"] = on
	_net.call("push_roster")
	print("[server] %s gold shield %s" % [_player_name(peer), "ON" if on else "OFF"])


## Moderators: change the map now. (Named to sort after the other RPCs.)
@rpc("any_peer", "reliable")
func _switch_map(path: String) -> void:
	if multiplayer.is_server() and _is_moderator(_sender()) and _net.MAP_NAMES.has(path):
		print("[server] %s switched the map to %s" % [_player_name(_sender()), _net.MAP_NAMES[path]])
		_net.call("change_map", path)


## Staff (owner, mod or tester) or a player-hosted game's host: turrets on/off for
## everyone. (Named to sort after the other RPCs.)
@rpc("any_peer", "reliable")
func _toggle_turrets() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var staff: String = _net.get("players").get(peer, {}).get("role", "")
	if staff == "" and not (peer == 1 and not _net.get("dedicated")):
		return
	var on: bool = not _net.get("turrets_on")
	_apply_turrets(on)
	print("[server] %s turned the turrets %s" % [_player_name(peer), "ON" if on else "OFF"])


## Owner and moderator powers on players in the match. (All named to sort after the other
## RPCs: Godot numbers RPCs alphabetically.)
@rpc("any_peer", "reliable")
func _zbring(target: int) -> void:
	var peer := _sender()
	if not multiplayer.is_server() or not _is_moderator(peer):
		return
	var arena := _arena()
	var me: Node3D = arena.call("player_ball", peer) if arena else null
	if not me:
		return
	var ids: Array = [target] if target != 0 else _net.get("players").keys()
	ids.erase(peer)
	for i in ids.size():
		# In a ring round you, so they don't land on top of each other.
		var spot := Vector2.from_angle(TAU * i / maxf(ids.size(), 1.0)) * 4.0
		arena.call("teleport_player", ids[i], me.global_position + Vector3(spot.x, 1.5, spot.y))
	print("[server] %s brought %s" % [_player_name(peer), "everyone" if target == 0 else _player_name(target)])


@rpc("any_peer", "reliable")
func _zkill_all() -> void:
	var peer := _sender()
	if not multiplayer.is_server() or not _is_owner(peer):
		return
	var arena := _arena()
	if not arena:
		return
	for id in _net.get("players").keys():
		if id != peer:
			arena.call("staff_kill", id, peer)
	print("[server] %s killed everyone" % _player_name(peer))


@rpc("any_peer", "reliable")
func _zweapons(mask: int) -> void:
	var peer := _sender()
	if not multiplayer.is_server() or not _is_owner(peer):
		return
	allowed_weapons = mask & ALL_WEAPONS
	_send_state()
	print("[server] %s set allowed weapons to %s" % [_player_name(peer), String.num_int64(allowed_weapons, 2)])


@rpc("any_peer", "reliable")
func _zgoto(target: int) -> void:
	var peer := _sender()
	if not multiplayer.is_server() or _level(peer) < 1 or target == peer:
		return
	var arena := _arena()
	var there: Node3D = arena.call("player_ball", target) if arena else null
	if there:
		arena.call("teleport_player", peer, there.global_position + Vector3(0, 2.0, 4.0))


@rpc("any_peer", "reliable")
func _zslay(target: int) -> void:
	var peer := _sender()
	if not multiplayer.is_server() or not _may_act_on(target):
		return
	var arena := _arena()
	if arena:
		arena.call("staff_kill", target, peer)
		print("[server] %s slew %s" % [_player_name(peer), _player_name(target)])


@rpc("any_peer", "reliable")
func _zfreeze(target: int, on: bool) -> void:
	var peer := _sender()
	if not multiplayer.is_server():
		return
	var ids: Array = []
	if target == 0:
		if not _is_owner(peer):
			return
		ids = _net.get("players").keys()
		ids.erase(peer)
	elif _may_act_on(target):
		ids = [target]
	for id in ids:
		if on and not frozen.has(id):
			frozen.append(id)
		elif not on:
			frozen.erase(id)
	_send_state()
	print("[server] %s %s %s" % [_player_name(peer), "froze" if on else "unfroze", "everyone" if target == 0 else _player_name(target)])


@rpc("any_peer", "reliable")
func _zmute(target: int, on: bool) -> void:
	var peer := _sender()
	if not multiplayer.is_server() or not _may_act_on(target):
		return
	if on and not muted.has(target):
		muted.append(target)
	elif not on:
		muted.erase(target)
	_send_state()
	print("[server] %s %s %s" % [_player_name(peer), "muted" if on else "unmuted", _player_name(target)])


@rpc("any_peer", "reliable")
func _zannounce(text: String) -> void:
	var peer := _sender()
	if not multiplayer.is_server() or _level(peer) < 2:
		return
	text = text.replace("\n", " ").strip_edges().substr(0, 100)
	if text != "":
		print("[server] %s announced: %s" % [_player_name(peer), text])
		_zannounced.rpc(text, _player_name(peer))


@rpc("any_peer", "reliable")
func _zheal_all() -> void:
	var peer := _sender()
	var arena := _arena()
	if multiplayer.is_server() and _is_owner(peer) and arena:
		for id in _net.get("players"):
			arena.call("staff_heal", id)


@rpc("any_peer", "reliable")
func _zlaunch(target: int) -> void:
	var peer := _sender()
	var arena := _arena()
	if multiplayer.is_server() and _is_owner(peer) and arena and target != peer:
		arena.call("staff_launch", target)


@rpc("any_peer", "reliable")
func _zgravity() -> void:
	var peer := _sender()
	if not multiplayer.is_server() or not _is_owner(peer):
		return
	low_gravity = not low_gravity
	_send_state()
	print("[server] %s turned low gravity %s" % [_player_name(peer), "ON" if low_gravity else "OFF"])


## Server: the staff state, to everyone.
func _send_state() -> void:
	if multiplayer.is_server() and _net.get("online"):
		_zstate.rpc({"weapons": allowed_weapons, "gravity": low_gravity, "frozen": frozen, "muted": muted})


@rpc("authority", "call_local", "reliable")
func _zstate(state: Dictionary) -> void:
	allowed_weapons = int(state.get("weapons", ALL_WEAPONS))
	low_gravity = bool(state.get("gravity", false))
	frozen = state.get("frozen", []).duplicate()
	muted = state.get("muted", []).duplicate()
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	PhysicsServer3D.area_set_param(get_viewport().world_3d.space, PhysicsServer3D.AREA_PARAM_GRAVITY,
		g * (LOW_GRAVITY_SCALE if low_gravity else 1.0))
	mod_changed.emit()


@rpc("authority", "call_local", "reliable")
func _zannounced(text: String, by: String) -> void:
	announced.emit(text, by)


func _is_owner(peer: int) -> bool:
	return _net.get("players").get(peer, {}).get("role", "") == "owner"


## A peer's staff level on this server (a player-hosted game's host counts as a mod).
func _level(peer: int) -> int:
	var lvl := level_of(_net.get("players").get(peer, {}).get("role", ""))
	if peer == 1 and not _net.get("dedicated"):
		lvl = maxi(lvl, 2)
	return lvl


func _arena() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.has_method("teleport_player") else null


func _refresh_god_shields() -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("refresh_god_shields"):
		scene.call("refresh_god_shields")


## Sender is a moderator, and allowed to act on the target: anyone can be kicked or
## banned except the owner; moderators only by the owner (testers by any moderator).
func _may_act_on(target: int) -> bool:
	var sender := _sender()
	if not multiplayer.is_server() or not _is_moderator(sender):
		return false
	var players: Dictionary = _net.get("players")
	if not players.has(target) or target == sender or target == 1:
		return false
	if players[target].get("role", "") == "owner":
		return false
	if _mods.has(target):
		return players.get(sender, {}).get("role", "") == "owner"
	return true


## What this player may kick or ban, by the target's roster entry (for the UI; the
## server checks for itself in _may_act_on).
func can_act_on(entry: Dictionary) -> bool:
	var target_role: String = entry.get("role", "mod" if entry.get("mod", false) else "")
	if target_role == "owner":
		return false
	if target_role == "mod":
		return role == "owner"
	return true


func _is_moderator(peer: int) -> bool:
	return _mods.has(peer) or (peer == 1 and not _net.get("dedicated"))


## Tells `peer` why (Net's existing message), then drops them once it's had time to arrive.
func _remove(peer: int, reason: String) -> void:
	_net.rpc_id(peer, "_turned_away", reason)
	get_tree().create_timer(0.5).timeout.connect(Callable(_net, "_drop_peer").bind(peer))


func _on_peer_disconnected(id: int) -> void:
	_mods.erase(id)
	_attempts.erase(id)
	_devices.erase(id)
	frozen.erase(id)
	muted.erase(id)


## Who sent the RPC being handled (the host's own direct calls count as peer 1).
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else 1


func _player_name(peer: int) -> String:
	return String(_net.get("players").get(peer, {}).get("name", ""))
