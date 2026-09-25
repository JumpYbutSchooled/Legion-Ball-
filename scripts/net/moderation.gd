extends Node
## Moderation service (/root/Mod, created by scripts/services.gd).
## Moderators type the moderator code into Settings. When they join an online server the
## game sends it, and the server compares it with its MOD_CODE environment variable (set
## on Render, never in the game files). If it matches, they can kick, ban and end the
## match. The server checks every request, so a modified game can't fake being a mod.
## On a player-hosted game the host can moderate without a code.
## Bans live in the server's memory: they last until that server restarts or sleeps.
## Every player sends a random device id (user://device_id), so a ban survives a name
## change or a reconnect.
## These RPCs live on their own node rather than Net: Godot numbers a node's RPCs
## alphabetically, and adding them to Net would renumber its RPCs and break players and
## servers on other versions.

signal mod_changed

const DEVICE_FILE := "user://device_id"
## Wrong codes allowed per connection before the server stops listening.
const MAX_ATTEMPTS := 5

## True once the server has accepted this player's moderator code.
var is_mod := false

var _net: Node
var _device_id := ""
var _greeted := false
# Server only, all keyed by peer id except the ban lists.
var _mods := {}
var _attempts := {}
var _devices := {}
var _banned_devices := {}
var _banned_names := {}


func _ready() -> void:
	_device_id = _load_device_id()
	_net = get_tree().root.get_node_or_null("Net")
	if _net:
		_net.connect("roster_changed", _on_roster_changed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


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


## Ends the round for everyone on the server (scores reset).
func end_match() -> void:
	if multiplayer.is_server():
		_end_match()
	else:
		_end_match.rpc_id(1)


# --- Client ---------------------------------------------------------------------------

## Once we're on a server's roster: say hello (device id for bans), then try the code.
func _on_roster_changed() -> void:
	if not _net.get("online"):
		_greeted = false
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
	var real := OS.get_environment("MOD_CODE").strip_edges()
	# Compared as hashes so the check takes the same time whatever was typed.
	var ok := real != "" and code.strip_edges().sha256_text() == real.sha256_text()
	if ok:
		_mods[peer] = true
		var players: Dictionary = _net.get("players")
		if players.has(peer):
			players[peer]["mod"] = true
			_net.call("push_roster")
		print("[server] %s is a moderator" % _player_name(peer))
	_login_result.rpc_id(peer, ok)


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


## Sender is a moderator, and the target is a real player who isn't one.
func _may_act_on(target: int) -> bool:
	if not multiplayer.is_server() or not _is_moderator(_sender()):
		return false
	var players: Dictionary = _net.get("players")
	return players.has(target) and target != _sender() and target != 1 and not _mods.has(target)


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


## Who sent the RPC being handled (the host's own direct calls count as peer 1).
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else 1


func _player_name(peer: int) -> String:
	return String(_net.get("players").get(peer, {}).get("name", ""))
