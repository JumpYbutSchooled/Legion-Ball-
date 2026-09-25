extends Node
## Moderation service (/root/Mod, created by scripts/services.gd).
## Staff type their code into Settings. When they join an online server the game sends
## it, and the server compares it with its OWNER_CODE, MOD_CODE and TESTER_CODE
## environment variables (set on Render, never in the game files):
##   owner  - moderator powers, the owner weapons (slots 7-8, also in offline practice
##            once a server has confirmed the code: STAFF_FILE) and a gold OWNER title
##   mod    - kick, ban and end the match, and a MOD title
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
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## A roster entry's title as [text, colour], or [] for none. Older servers only send
## the "mod" flag.
static func title_of(entry: Dictionary) -> Array:
	var r: String = entry.get("role", "mod" if entry.get("mod", false) else "")
	return TITLES.get(r, [])


## Online: what the server confirmed. Offline (practice): the role a server confirmed
## before, as long as the same code is still in Settings.
func is_owner() -> bool:
	if _net != null and _net.get("online"):
		return role == "owner"
	return _saved_role == "owner" and _saved_hash != "" and _saved_hash == _code_hash()


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
		role = ""
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
