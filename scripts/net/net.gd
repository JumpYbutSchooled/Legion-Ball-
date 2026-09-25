extends Node
## Networking service (/root/Net, created by scripts/services.gd).
## Two ways to play:
## - Online server: a dedicated server (scenes/server.tscn, hosted on Render) keeps one
##   arena running; players join it over WebSockets (wss://, the normal web port, so it
##   works on school networks and needs no firewall changes). It has no player of its own.
## - Local: one player hosts (ENet on PORT) and others on the same network join by IP.
## The server/host owns the roster {peer_id: {name, color, kills, deaths}} and sends it
## to everyone whenever it changes. Late joiners go straight into a running match.
## Offline (no host/join) the game runs as single-player practice.

signal roster_changed
## Human-readable connection status for the lobby screen.
signal status_changed(text: String)
## The connection dropped (host left, kicked, or failed to connect).
signal disconnected(reason: String)

const PORT := 7777
## The online server's address (see render.yaml).
const SERVER_URL := "wss://legion-ball-server.onrender.com"
## Port a dedicated server listens on when not told otherwise (Render sets $PORT).
const SERVER_PORT := 7778
const MAX_PLAYERS := 8
## Online matches use the big walled map; offline practice keeps scenes/arena.tscn.
const ARENA_SCENE := "res://scenes/arena_sprawl.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const CONNECT_TIMEOUT := 8.0
## A sleeping free-tier server takes up to about a minute to wake; keep retrying this long.
const SERVER_WAKE_TIMEOUT := 100.0
const SERVER_RETRY_DELAY := 3.0

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
## True on the dedicated server itself (no local player).
var dedicated := false

var _connecting := false
var _connect_timer := 0.0
# Online-server joining: keep retrying until the deadline while it wakes up.
var _server_url := ""
var _server_deadline := 0.0
var _retry_timer := -1.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(func() -> void: _fail("Lost connection to the host/server."))


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


## This PC's IPv4 address(es) on the local network, to tell friends - best guess first.
## Skips loopback and link-local, plus virtual adapters (VirtualBox, VMware, Hyper-V,
## WSL...), which show up as extra networks nobody else can reach. Those host-only
## adapters almost always sit at x.x.x.1, so .1 addresses are dropped when there's
## anything better.
func lan_addresses() -> PackedStringArray:
	var virtual_words := ["virtual", "vmware", "vbox", "hyper-v", "vethernet", "wsl", "loopback", "bluetooth", "tailscale"]
	var good := PackedStringArray()
	var fallback := PackedStringArray()
	for iface in IP.get_local_interfaces():
		var label := (String(iface.get("friendly", "")) + " " + String(iface.get("name", ""))).to_lower()
		var is_virtual := false
		for w in virtual_words:
			if label.contains(w):
				is_virtual = true
		for a in iface.get("addresses", []):
			var addr := String(a)
			if addr.count(".") != 3 or addr.begins_with("127.") or addr.begins_with("169.254."):
				continue
			if is_virtual or addr.ends_with(".1"):
				fallback.append(addr)
			else:
				good.append(addr)
	return good if not good.is_empty() else fallback


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


## Join the online server. If it's asleep (free hosting), keeps retrying while it wakes.
func join_server(url := SERVER_URL) -> void:
	leave()
	_server_url = url
	_server_deadline = _now() + SERVER_WAKE_TIMEOUT
	_try_server()


func _try_server() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var tls := TLSOptions.client() if _server_url.begins_with("wss") else null
	var err := peer.create_client(_server_url, tls)
	if err != OK:
		_give_up("Could not start a connection to the online server.")
		return
	multiplayer.multiplayer_peer = peer
	online = true
	_connecting = true
	_connect_timer = 20.0
	_set_status("Connecting to the online server...")


## Run as the dedicated online server: no local player, one arena that never stops.
func host_dedicated(port := SERVER_PORT) -> Error:
	leave()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		print("[server] could not listen on port %d (error %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	dedicated = true
	in_match = true
	players = {}
	print("[server] listening on port %d" % port)
	get_tree().change_scene_to_file(ARENA_SCENE)
	return OK


## Disconnects (if connected) and goes back to offline.
func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	in_match = false
	dedicated = false
	_connecting = false
	_server_url = ""
	_retry_timer = -1.0
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


## Host only: the match is over; scores reset. A dedicated server starts a fresh round
## straight away; a player-hosted game goes back to the lobby.
func end_match() -> void:
	if not is_host():
		return
	for id in players:
		players[id]["kills"] = 0
		players[id]["deaths"] = 0
	_sync_roster.rpc(players)
	if dedicated:
		_load_arena.rpc()
	else:
		_back_to_lobby.rpc()


## Leave the match and return to the main menu.
func quit_to_menu() -> void:
	leave()
	get_tree().change_scene_to_file(MENU_SCENE)


func _process(delta: float) -> void:
	if _retry_timer >= 0.0:
		_retry_timer -= delta
		if _retry_timer < 0.0:
			_try_server()
	if _connecting:
		_connect_timer -= delta
		if _connect_timer <= 0.0:
			_on_connect_failed()


# --- Connection events ------------------------------------------------------------

func _on_connected() -> void:
	_connecting = false
	_server_url = ""
	_set_status("Connected. Waiting for the host...")
	_register.rpc_id(1, local_name())


func _on_connect_failed() -> void:
	_connecting = false
	if _server_url != "":
		# Online server: probably still waking up. Try again until the deadline.
		if _now() < _server_deadline:
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			_retry_timer = SERVER_RETRY_DELAY
			var left := int(_server_deadline - _now())
			_set_status("Waking the online server up (free hosting sleeps when idle)... %ds" % left)
			return
		_give_up("The online server didn't answer. It may be down; try again in a minute.")
		return
	_give_up("Connection timed out. Check the address, then on the HOST PC allow LeigonBall through Windows Firewall (UDP %d). On school Wi-Fi use the ONLINE SERVER instead." % PORT)


func _give_up(reason: String) -> void:
	_fail(reason)


func _on_peer_connected(id: int) -> void:
	if dedicated:
		print("[server] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not players.has(id):
		return
	if dedicated:
		print("[server] %s left" % players[id]["name"])
	players.erase(id)
	_sync_roster.rpc(players)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


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
	if dedicated:
		print("[server] %s joined (%d online)" % [players[id]["name"], players.size()])
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
