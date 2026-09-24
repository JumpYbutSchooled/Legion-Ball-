extends Node
## Networking service (/root/Net, created by scripts/services.gd).
## One player hosts (ENet server on PORT) and up to MAX_PLAYERS - 1 others join by IP.
## The host owns the roster {peer_id: {name, color, kills, deaths}} and sends it to
## everyone whenever it changes. The host starts the match; late joiners are sent
## straight into it. Offline (no host/join) the game runs as single-player practice.

signal roster_changed
## Human-readable connection status for the lobby screen.
signal status_changed(text: String)
## The connection dropped (host left, kicked, or failed to connect).
signal disconnected(reason: String)

const PORT := 7777
const MAX_PLAYERS := 8
const ARENA_SCENE := "res://scenes/arena.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const CONNECT_TIMEOUT := 8.0

## Trim colours handed out to players in join order.
const COLORS := [
	Color(0.35, 0.9, 1.0), Color(1.0, 0.5, 0.1), Color(1.0, 0.25, 0.75), Color(0.55, 1.0, 0.2),
	Color(1.0, 0.82, 0.2), Color(0.6, 0.35, 1.0), Color(1.0, 0.3, 0.3), Color(0.9, 0.9, 0.95),
]

var players := {}
## True while hosting or connected to a host.
var online := false
var in_match := false
## Set by menus that should stop the local player moving and firing (the pause menu).
var input_blocked := false
var status := ""

var _connecting := false
var _connect_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Could not reach the host."))
	multiplayer.server_disconnected.connect(func() -> void: _fail("The host left the match."))


func is_host() -> bool:
	return online and multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id()


func local_name() -> String:
	var settings := get_tree().root.get_node_or_null("Settings")
	var n: String = settings.call("get_value", "player_name") if settings else "PLAYER"
	n = n.strip_edges().substr(0, 16)
	return n if n != "" else "PLAYER"


func player_color(id: int) -> Color:
	var info: Dictionary = players.get(id, {})
	return COLORS[int(info.get("color", 0)) % COLORS.size()]


func player_name(id: int) -> String:
	return players.get(id, {}).get("name", "PLAYER %d" % id)


## This PC's IPv4 addresses on the local network, to tell friends.
func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


func host(port := PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_set_status("Could not host on port %d (already in use?)" % port)
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	players = {1: _new_player(local_name(), 0)}
	_set_status("Hosting on port %d" % port)
	roster_changed.emit()
	return OK


func join(ip: String, port := PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port)
	if err != OK:
		_set_status("Bad address: " + ip)
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	_connecting = true
	_connect_timer = CONNECT_TIMEOUT
	_set_status("Connecting to %s:%d ..." % [ip, port])
	return OK


## Disconnects (if connected) and goes back to offline.
func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	in_match = false
	_connecting = false
	players.clear()
	input_blocked = false
	roster_changed.emit()


## Host only: everyone loads the arena.
func start_match() -> void:
	if not is_host():
		return
	in_match = true
	_load_arena.rpc()


## Host only: send the current roster (scores included) to everyone.
func push_roster() -> void:
	if is_host():
		_sync_roster.rpc(players)


## Host only: the match is over; everyone goes back to the lobby with scores reset.
func end_match() -> void:
	if not is_host():
		return
	for id in players:
		players[id]["kills"] = 0
		players[id]["deaths"] = 0
	_sync_roster.rpc(players)
	_back_to_lobby.rpc()


## Leave the match and return to the main menu.
func quit_to_menu() -> void:
	leave()
	get_tree().change_scene_to_file(MENU_SCENE)


func _process(delta: float) -> void:
	if _connecting:
		_connect_timer -= delta
		if _connect_timer <= 0.0:
			_fail("Connection timed out. Check the IP, the port (%d) and the host's firewall." % PORT)


# --- Connection events ------------------------------------------------------------

func _on_connected() -> void:
	_connecting = false
	_set_status("Connected. Waiting for the host...")
	_register.rpc_id(1, local_name())


func _on_peer_connected(_id: int) -> void:
	pass  # The new peer registers itself once it's connected.


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not players.has(id):
		return
	players.erase(id)
	_sync_roster.rpc(players)


func _fail(reason: String) -> void:
	var was_in_match := in_match
	leave()
	_set_status(reason)
	disconnected.emit(reason)
	if was_in_match:
		get_tree().change_scene_to_file(MENU_SCENE)


# --- RPCs ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _register(player_name_in: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = _new_player(player_name_in.strip_edges().substr(0, 16), _free_color())
	_sync_roster.rpc(players)
	if in_match:
		_load_arena.rpc_id(id)


@rpc("authority", "call_local", "reliable")
func _sync_roster(roster: Dictionary) -> void:
	players = roster
	if not multiplayer.is_server():
		_set_status("In lobby: %d player%s" % [players.size(), "" if players.size() == 1 else "s"])
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _load_arena() -> void:
	in_match = true
	input_blocked = false
	get_tree().change_scene_to_file(ARENA_SCENE)


@rpc("authority", "call_local", "reliable")
func _back_to_lobby() -> void:
	in_match = false
	input_blocked = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Helpers ------------------------------------------------------------------------

func _new_player(n: String, color: int) -> Dictionary:
	return {"name": n if n != "" else "PLAYER", "color": color, "kills": 0, "deaths": 0}


func _free_color() -> int:
	var used := {}
	for id in players:
		used[int(players[id]["color"])] = true
	for i in COLORS.size():
		if not used.has(i):
			return i
	return 0


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)
