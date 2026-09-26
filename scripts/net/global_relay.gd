extends Node
## Global chat relay (/root/GlobalChat, created by scripts/services.gd). Only does
## anything on the online servers:
## - Server 1 is the hub. The other servers connect to it and send it their players'
##   global messages; it passes each one to every linked server and its own players.
## - Servers 2-4 each keep a link to the hub while they have players, dropping it a
##   minute after the last one leaves so server 1 can go back to sleep.
## Links connect to the hub's normal port but never finish Godot's multiplayer
## authentication step, so the hub sends them none of the game's traffic. Everything
## between hub and link goes through that step's own messages (send_auth). Players'
## games say "player" in that step and are let straight in (Net._use_client_auth).
## Links prove they're one of our servers with a hash of MOD_CODE (the same on every
## server), so nobody else can post into global chat.
## The hub also answers "who's online?" for the multiplayer menu (ServerStatus in
## scripts/ui/lobby_panel.gd): links keep it up to date with their player lists, and a
## server with no link is empty (and asleep). The question and answer also go through
## the authentication step, then the asker hangs up.
## Players sitting in the main menu can use global chat too (scripts/net/menu_chat.gd):
## their game connects to the hub and says "listen" in the same step, stays pending like
## a link, gets recent history and every new global message ("down"), and can post with
## "say". The hub stamps those with the name they gave and server "MENU" (they have no
## verified identity or staff title), and rate-limits them.
## For local testing: GLOBAL_HUB=1 makes a server the hub; GLOBAL_HUB_URL points a server
## at a hub.

const ModScript := preload("res://scripts/net/moderation.gd")
const KEY_SALT := "leigon-global-chat"
## Seconds the hub waits for a new connection to say "player" or prove it's a link.
const AUTH_WAIT := 3.0
## Seconds with no players before a server drops its link.
const IDLE_DROP := 60.0
## Seconds between reconnect attempts (the hub may be asleep: it takes up to a minute).
const RETRY := 10.0
## Seconds between "still here" messages, which also keep the hub awake while linked.
const PING := 30.0
const QUEUE_MAX := 10
## Pending (never-authenticated) connections should never time out.
const FOREVER := 1.0e7

# Hub: linked servers, peer id -> label ("S2"), and what each last reported:
# peer id -> {"players": [names], "map": "SPRAWL"}.
var _links := {}
var _link_status := {}
# Hub: menu players listening to global chat, peer id -> {"name", "sent": [times]}; and
# the last few global messages, for anyone who starts listening.
var _listeners := {}
var _history: Array = []
const HISTORY_MAX := 25
const MENU_MAX_LISTENERS := 200
## Menu players' rate limit: MENU_BURST messages per MENU_WINDOW seconds.
const MENU_BURST := 3
const MENU_WINDOW := 6.0
const MENU_COLOR := Color(0.7, 0.78, 0.85)
# Link servers: this server's own connection to the hub, while linked.
var _link_api: SceneMultiplayer
var _link_holder: Node
var _connected := false
var _retry := -1.0
var _ping := 0.0
var _idle := 0.0
var _queue: Array = []


func _ready() -> void:
	var net := _net()
	if net:
		# Links tell the hub whenever their players change (for the server list).
		net.connect("roster_changed", func() -> void:
			if _link_api and _connected:
				_hello())


## True on the online servers: global chat goes through the relay.
func is_active() -> bool:
	return _is_hub() or _hub_url() != ""


## This server's players and map, for the server list.
func _own_status() -> Dictionary:
	var net := _net()
	var names: Array = []
	for id in net.get("players"):
		var p: Dictionary = net.get("players")[id]
		if p.get("bot", false):
			continue  # Only real people count as "online".
		var title := ModScript.title_of(p)
		names.append(("[%s] " % title[0] if not title.is_empty() else "") + String(p["name"]))
	return {"players": names, "map": net.MAP_NAMES.get(net.get("map_scene"), "")}


## Called by Net once a dedicated server is listening: the hub starts screening new
## connections for links.
func on_server_started() -> void:
	if not _is_hub():
		return
	var api := multiplayer as SceneMultiplayer
	api.auth_callback = _on_hub_auth
	api.auth_timeout = FOREVER
	api.peer_authenticating.connect(_on_hub_peer_authenticating)
	print("[relay] hub ready")


## A global message from one of this server's players.
func send(entry: Dictionary) -> void:
	if _is_hub():
		_relay(entry)
	elif _hub_url() != "":
		_ensure_link()
		if _connected:
			_send_up(entry)
		elif _queue.size() < QUEUE_MAX:
			_queue.append(entry)


func _process(delta: float) -> void:
	if _is_hub():
		# Forget links whose connection has gone.
		var pending := (multiplayer as SceneMultiplayer).get_authenticating_peers()
		for id in _links.keys():
			if not pending.has(id):
				_links.erase(id)
				_link_status.erase(id)
		for id in _listeners.keys():
			if not pending.has(id):
				_listeners.erase(id)
		return
	if _hub_url() == "":
		return
	if not _net().get("players").is_empty():
		_idle = 0.0
		_ensure_link()
	elif _link_api:
		_idle += delta
		if _idle > IDLE_DROP:
			_drop_link()
			return
	if _link_api:
		_process_link(delta)


func _net() -> Node:
	return get_tree().root.get_node_or_null("Net")


func _is_hub() -> bool:
	var net := _net()
	if not net or not net.get("dedicated"):
		return false
	if OS.get_environment("GLOBAL_HUB") == "1":
		return true
	return OS.get_environment("GLOBAL_HUB_URL") == "" and net.call("server_index") == 0


## Where this server's link goes ("" if it doesn't link: the hub, LAN games, clients).
func _hub_url() -> String:
	var net := _net()
	if not net or not net.get("dedicated") or _is_hub() or _key() == "":
		return ""
	var env := OS.get_environment("GLOBAL_HUB_URL").strip_edges()
	if env != "":
		return env
	return net.SERVER_URLS[0] if net.call("server_index") > 0 else ""


func _key() -> String:
	var code := OS.get_environment("MOD_CODE").strip_edges()
	return (code + KEY_SALT).sha256_text() if code != "" else ""


static func _pack(msg: Dictionary) -> PackedByteArray:
	return var_to_bytes(msg)


## Dictionaries only (var_to_bytes/bytes_to_var never build objects).
static func _unpack(data: PackedByteArray) -> Dictionary:
	var msg = bytes_to_var(data)
	return msg if typeof(msg) == TYPE_DICTIONARY else {}


# --- Hub ------------------------------------------------------------------------------

## Anything that hasn't said "player" or proved it's a link by now is a game from before
## the hub existed (it doesn't know this step, so it can't be sent a message either) or
## a stranger: drop it. Older games see "Lost connection"; on the other servers they get
## the usual "out of date" message.
func _on_hub_peer_authenticating(id: int) -> void:
	await get_tree().create_timer(AUTH_WAIT).timeout
	var api := multiplayer as SceneMultiplayer
	if not _links.has(id) and not _listeners.has(id) and api.get_authenticating_peers().has(id) and api.multiplayer_peer:
		api.multiplayer_peer.disconnect_peer(id)


func _on_hub_auth(id: int, data: PackedByteArray) -> void:
	var msg := _unpack(data)
	match msg.get("t", ""):
		"player":
			(multiplayer as SceneMultiplayer).complete_auth(id)
		"status?":
			(multiplayer as SceneMultiplayer).send_auth(id, _pack(_status_snapshot()))
		"hello":
			var k := _key()
			if k != "" and msg.get("key", "") == k:
				if not _links.has(id):
					print("[relay] %s linked" % msg.get("label", "?"))
				_links[id] = String(msg.get("label", "?"))
				var players = msg.get("players", [])
				_link_status[id] = {
					"players": players if typeof(players) == TYPE_ARRAY else [],
					"map": String(msg.get("map", "")),
				}
		"up":
			if _links.has(id) and typeof(msg.get("entry")) == TYPE_DICTIONARY:
				_relay(msg["entry"])
		"listen":
			# A main-menu player. Same version only (entries change between versions).
			if String(msg.get("version", "")) != String(_net().get("version")) or _listeners.size() >= MENU_MAX_LISTENERS:
				var api := multiplayer as SceneMultiplayer
				api.send_auth(id, _pack({"t": "refused", "version": _net().get("version")}))
				return
			_listeners[id] = {"name": _menu_name(msg.get("name", "")), "sent": []}
			(multiplayer as SceneMultiplayer).send_auth(id, _pack({"t": "history", "entries": _history}))
		"say":
			if _listeners.has(id):
				_menu_say(id, String(msg.get("text", "")))


## A name for a menu player: their own, cleaned, capped, never blank.
func _menu_name(raw) -> String:
	var n := String(raw).replace("\n", " ").replace("[", "(").replace("]", ")").strip_edges().substr(0, 16)
	return n if n != "" else "PILOT"


func _menu_say(id: int, text: String) -> void:
	var listener: Dictionary = _listeners[id]
	var now := Time.get_ticks_msec() / 1000.0
	var times: Array = listener["sent"].filter(func(t: float) -> bool: return now - t < MENU_WINDOW)
	if times.size() >= MENU_BURST:
		return
	times.append(now)
	listener["sent"] = times
	text = text.replace("\n", " ").replace("\r", " ").strip_edges().substr(0, 120)
	if text == "":
		return
	print("[chat GLOBAL MENU] %s: %s" % [listener["name"], text])
	_relay({
		"name": listener["name"], "color": MENU_COLOR, "title": "", "title_color": Color.WHITE,
		"text": text, "global": true, "server": "MENU",
	})


## Who's on every server right now: the hub's own players plus what each link reported.
## Servers missing from it have no players (and are asleep).
func _status_snapshot() -> Dictionary:
	var net := _net()
	var servers := {String(net.call("server_label")): _own_status()}
	for id in _links:
		servers[_links[id]] = _link_status.get(id, {"players": [], "map": ""})
	return {"t": "status", "version": net.get("version"), "servers": servers}


func _relay(entry: Dictionary) -> void:
	entry["text"] = String(entry.get("text", "")).substr(0, 120)
	var api := multiplayer as SceneMultiplayer
	for id in _links:
		api.send_auth(id, _pack({"t": "down", "entry": entry}))
	for id in _listeners:
		api.send_auth(id, _pack({"t": "down", "entry": entry}))
	_history.append(entry)
	while _history.size() > HISTORY_MAX:
		_history.pop_front()
	var chat := get_tree().root.get_node_or_null("Chat")
	if chat:
		chat.call("deliver_global", entry)


# --- Link (servers 2-4) ---------------------------------------------------------------

func _ensure_link() -> void:
	if _link_api:
		return
	# Its own SceneMultiplayer (on an empty branch), so the game's connection is untouched.
	_link_holder = Node.new()
	_link_holder.name = "RelayLink"
	get_tree().root.add_child(_link_holder)
	_link_api = SceneMultiplayer.new()
	_link_api.auth_callback = _on_link_auth
	_link_api.auth_timeout = FOREVER
	_link_api.peer_authenticating.connect(_on_link_up)
	get_tree().set_multiplayer(_link_api, _link_holder.get_path())
	_open()


func _drop_link() -> void:
	if _link_api.multiplayer_peer:
		_link_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, _link_holder.get_path())
	_link_holder.queue_free()
	_link_api = null
	_connected = false
	_retry = -1.0
	print("[relay] link dropped (no players)")


func _open() -> void:
	var url := _hub_url()
	var peer := WebSocketMultiplayerPeer.new()
	var tls := TLSOptions.client() if url.begins_with("wss") else null
	if peer.create_client(url, tls) != OK:
		_retry = RETRY
		return
	_link_api.multiplayer_peer = peer
	_retry = -1.0


## The connection to the hub is open: say who we are, then send anything waiting.
func _on_link_up(_id: int) -> void:
	_connected = true
	_ping = PING
	print("[relay] linked to hub as %s" % _net().call("server_label"))
	_hello()
	for entry in _queue:
		_send_up(entry)
	_queue.clear()


func _hello() -> void:
	var status := _own_status()
	_link_api.send_auth(1, _pack({
		"t": "hello", "key": _key(), "label": _net().call("server_label"),
		"players": status["players"], "map": status["map"],
	}))


func _send_up(entry: Dictionary) -> void:
	_link_api.send_auth(1, _pack({"t": "up", "entry": entry}))


func _on_link_auth(_id: int, data: PackedByteArray) -> void:
	var msg := _unpack(data)
	if msg.get("t", "") == "down" and typeof(msg.get("entry")) == TYPE_DICTIONARY:
		var chat := get_tree().root.get_node_or_null("Chat")
		if chat:
			chat.call("deliver_global", msg["entry"])


func _process_link(delta: float) -> void:
	var peer := _link_api.multiplayer_peer
	var status := peer.get_connection_status() if peer else MultiplayerPeer.CONNECTION_DISCONNECTED
	if _retry < 0.0 and status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		# Dropped, or never got through (the hub asleep): try again shortly.
		_connected = false
		_retry = RETRY
	if _retry >= 0.0:
		_retry -= delta
		if _retry < 0.0:
			_open()
	elif _connected:
		_ping -= delta
		if _ping <= 0.0:
			_ping = PING
			_hello()
