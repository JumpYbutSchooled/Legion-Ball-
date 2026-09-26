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
## The online servers (Render web services running this repo), SERVER 1-4 in the lobby.
## Each is a separate arena of up to MAX_PLAYERS.
const SERVER_URLS := [
	"wss://legion-ball-server.onrender.com",
	"wss://legion-ball-server-1i3q.onrender.com",
	"wss://legion-ball-server-vbgx.onrender.com",
	"wss://legion-ball-server-4v2m.onrender.com",
]
## Port a dedicated server listens on when not told otherwise (Render sets $PORT).
const SERVER_PORT := 7778
const MAX_PLAYERS := 8
## Online matches use the big walled map by default; offline practice keeps
## scenes/arena.tscn (online, its cubes and targets are left out).
const ARENA_SCENE := "res://scenes/arena_sprawl.tscn"
const TRAINING_SCENE := "res://scenes/arena.tscn"
const MAP_NAMES := {
	"res://scenes/arena_sprawl.tscn": "SPRAWL",
	"res://scenes/arena.tscn": "TRAINING",
	"res://scenes/arena_coliseum.tscn": "COLISEUM",
	"res://scenes/arena_box.tscn": "THE BOX",
	"res://scenes/arena_thunderdome.tscn": "THUNDER DOME",
	"res://scenes/arena_tunnels.tscn": "TUNNELS",
	"res://scenes/arena_city.tscn": "CITY",
}
## The combat maps: what end-of-match votes, moderators and hosts choose between.
const COMBAT_MAPS := [
	"res://scenes/arena_sprawl.tscn",
	"res://scenes/arena_coliseum.tscn",
	"res://scenes/arena_box.tscn",
	"res://scenes/arena_thunderdome.tscn",
	"res://scenes/arena_tunnels.tscn",
	"res://scenes/arena_city.tscn",
]
## The map each online server runs, in the same order as SERVER_URLS. A server finds its
## own entry from Render's RENDER_EXTERNAL_HOSTNAME; a MAP env var ("sprawl" or
## "training") overrides it.
const SERVER_MAPS := [ARENA_SCENE, ARENA_SCENE, TRAINING_SCENE, TRAINING_SCENE]
const MENU_SCENE := "res://scenes/menu.tscn"
const WeaponInfo := preload("res://scripts/weapon_info.gd")
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
## The map matches load. Set by the server (_use_map) before it loads anyone in.
var map_scene := ARENA_SCENE
## AI turrets on (scripts/turrets.gd). Off by default. The host's copy is the real one
## (staff switch it with Mod.toggle_turrets); offline it's the practice setting.
var turrets_on := false
## This game's version (res://version.txt, updated with every patch). Players must match
## the server's exactly to join.
var version := ""
# Server: the version each connected peer reported before registering.
var _peer_versions := {}
# Server: the loadout each peer sent before registering (weapon_info.gd ids).
var _peer_loadouts := {}

var _connecting := false
var _connect_timer := 0.0
# Online-server joining: keep retrying until the deadline while it wakes up.
var _server_url := ""
var _server_deadline := 0.0
var _retry_timer := -1.0
## Why the server turned us away (e.g. full), shown instead of "Lost connection".
var _rejected_reason := ""

func _ready() -> void:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	version = f.get_as_text().strip_edges() if f else "0.0.0"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


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
	if id < 0:
		return "TURRET"  # AI turrets (scripts/turrets.gd) deal damage as id -1.
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
	players[1]["loadout"] = WeaponInfo.local_loadout(get_tree())
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


## Join an online server. If it's asleep (free hosting), keeps retrying while it wakes.
func join_server(url: String = SERVER_URLS[0]) -> void:
	leave()
	# Only server 1 (the global chat hub) uses the authentication step; with any other
	# server the connection must not wait for it.
	if url == SERVER_URLS[0] or OS.get_environment("GLOBAL_HUB_TEST") == "1":
		_use_client_auth()
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
	map_scene = _dedicated_map()
	print("[server] listening on port %d, map %s" % [port, MAP_NAMES.get(map_scene, map_scene)])
	# Server 1 relays global chat between the servers (scripts/net/global_relay.gd).
	var relay := get_tree().root.get_node_or_null("GlobalChat")
	if relay:
		relay.call("on_server_started")
	get_tree().change_scene_to_file(map_scene)
	return OK


## Which map this dedicated server runs: the MAP env var, else its own entry in
## SERVER_MAPS, else the default.
func _dedicated_map() -> String:
	var env := OS.get_environment("MAP").strip_edges().to_lower()
	for path in MAP_NAMES:
		if MAP_NAMES[path].to_lower() == env:
			return path
	var index := server_index()
	return SERVER_MAPS[index] if index >= 0 else ARENA_SCENE


## Which of SERVER_URLS this dedicated server is (0-3), from the address Render gives
## it (or a SERVER_INDEX env var, for testing); -1 if unknown (e.g. a LAN host).
func server_index() -> int:
	var env := OS.get_environment("SERVER_INDEX").strip_edges()
	if env.is_valid_int():
		return int(env)
	var hostname := OS.get_environment("RENDER_EXTERNAL_HOSTNAME").strip_edges()
	if hostname != "":
		for i in SERVER_URLS.size():
			if SERVER_URLS[i].ends_with("//" + hostname):
				return i
	return -1


## "S1".."S4" for the online servers (shown on global chat), "LAN" otherwise.
func server_label() -> String:
	var index := server_index() if dedicated else -1
	return "S%d" % (index + 1) if index >= 0 else "LAN"


## Joining server 1 (the global chat hub) takes part in Godot's authentication step, so
## it can tell players from the other servers' relay links: we say "player" and finish
## straight away. See scripts/net/global_relay.gd.
func _use_client_auth() -> void:
	var api := multiplayer as SceneMultiplayer
	api.auth_callback = func(_id: int, _data: PackedByteArray) -> void: pass
	api.auth_timeout = 15.0
	if not api.peer_authenticating.is_connected(_on_client_authenticating):
		api.peer_authenticating.connect(_on_client_authenticating)


func _on_client_authenticating(id: int) -> void:
	var api := multiplayer as SceneMultiplayer
	api.send_auth(id, var_to_bytes({"t": "player"}))
	api.complete_auth(id)


## Disconnects (if connected) and goes back to offline.
func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	(multiplayer as SceneMultiplayer).auth_callback = Callable()
	online = false
	in_match = false
	dedicated = false
	_connecting = false
	_server_url = ""
	_retry_timer = -1.0
	_rejected_reason = ""
	map_scene = ARENA_SCENE
	players.clear()
	input_blocked = false
	roster_changed.emit()


## Host only: everyone loads the arena.
func start_match() -> void:
	if not is_host():
		return
	in_match = true
	_use_map.rpc(map_scene)
	_load_arena.rpc()


## Host only: everyone moves to map `path` now, scores reset (a moderator's switch).
func change_map(path: String) -> void:
	if not is_host() or not MAP_NAMES.has(path):
		return
	map_scene = path
	for id in players:
		players[id]["kills"] = 0
		players[id]["deaths"] = 0
	_sync_roster.rpc(players)
	in_match = true
	_use_map.rpc(map_scene)
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
		_use_map.rpc(map_scene)
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
	# Version first: the server turns mismatched games away before they register.
	_version_is.rpc_id(1, version)
	# Our loadout too, so we spawn with our own weapons even when joining mid-match.
	_zset_loadout.rpc_id(1, WeaponInfo.local_loadout(get_tree()))
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


func _on_server_disconnected() -> void:
	var reason := _rejected_reason if _rejected_reason != "" else "Lost connection to the host/server."
	_fail(reason)


func _on_peer_connected(id: int) -> void:
	if dedicated:
		print("[server] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	_peer_versions.erase(id)
	_peer_loadouts.erase(id)
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
	# Different versions don't work together (maps, weapons and messages change), so
	# only exact matches get in. Games from before this check send no version at all.
	var theirs: String = _peer_versions.get(id, "")
	if theirs != version:
		var reason := "Your game is out of date (v%s, server v%s). Restart the game to update." % [theirs if theirs != "" else "old", version]
		if theirs != "" and _is_newer(theirs, version):
			reason = "This server is still updating (server v%s, you v%s). Try again in a few minutes." % [version, theirs]
		if dedicated:
			print("[server] turned away %s: version %s" % [player_name_in, theirs if theirs != "" else "old"])
		_turned_away.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(_drop_peer.bind(id))
		return
	if players.size() >= MAX_PLAYERS:
		# Tell them why, then drop them once the message has had time to arrive.
		_turned_away.rpc_id(id, "Server is full (%d/%d). Try another server." % [MAX_PLAYERS, MAX_PLAYERS])
		get_tree().create_timer(0.5).timeout.connect(_drop_peer.bind(id))
		return
	players[id] = _new_player(player_name_in.strip_edges().substr(0, 16), _free_color())
	players[id]["loadout"] = WeaponInfo.valid_loadout(_peer_loadouts.get(id, []))
	if dedicated:
		print("[server] %s joined (%d online)" % [players[id]["name"], players.size()])
	_sync_roster.rpc(players)
	if in_match:
		_use_map.rpc_id(id, map_scene)
		_load_arena.rpc_id(id)


## A player's game version, sent right before _register. (Named to sort after the other
## RPCs, so their numbering is unchanged for older versions.)
@rpc("any_peer", "reliable")
func _version_is(their_version: String) -> void:
	if multiplayer.is_server():
		_peer_versions[multiplayer.get_remote_sender_id()] = their_version.substr(0, 20)


## True if version a is newer than b ("1.2.10" > "1.2.9").
func _is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false


## Which map to load next (sent just before _load_arena). Named to sort after the other
## RPCs, so their numbering is unchanged for older versions.
@rpc("authority", "reliable")
func _use_map(path: String) -> void:
	if MAP_NAMES.has(path):
		map_scene = path


## The server turned us away; the disconnect that follows shows this reason.
## Named to sort after the other RPCs: Godot numbers RPCs alphabetically, so a new name
## sorting earlier would shift theirs and break players and servers on older versions.
@rpc("authority", "reliable")
func _turned_away(reason: String) -> void:
	_rejected_reason = reason


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
	get_tree().change_scene_to_file(map_scene)


@rpc("authority", "call_local", "reliable")
func _back_to_lobby() -> void:
	in_match = false
	input_blocked = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Helpers ------------------------------------------------------------------------

func _new_player(n: String, color: int) -> Dictionary:
	return {"name": n if n != "" else "PLAYER", "color": color, "kills": 0, "deaths": 0,
		"loadout": WeaponInfo.DEFAULT_LOADOUT.duplicate()}


## Tell the server our loadout changed (the Armory). It takes effect on our next respawn.
func send_loadout() -> void:
	if not online:
		return
	var mine := WeaponInfo.local_loadout(get_tree())
	if multiplayer.is_server():
		_zset_loadout(mine)
	else:
		_zset_loadout.rpc_id(1, mine)


## A player's loadout: before they register (kept for _register), or a change later
## (roster updated; every computer swaps their weapons on their next respawn). The server
## only accepts built pool weapons, six of them, no repeats. (Named to sort last.)
@rpc("any_peer", "reliable")
func _zset_loadout(ids: Array) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var clean := WeaponInfo.valid_loadout(ids)
	if players.has(id):
		players[id]["loadout"] = clean
		_sync_roster.rpc(players)
	else:
		_peer_loadouts[id] = clean


func _drop_peer(id: int) -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.disconnect_peer(id)


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
