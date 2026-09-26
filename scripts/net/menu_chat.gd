extends Node
## Global chat from the main menu. Keeps its own connection to server 1 (the hub,
## scripts/net/global_relay.gd) on a separate SceneMultiplayer rooted at this node, so the
## game's connection is untouched. Like ServerStatus, everything travels in Godot's
## authentication step: it says "listen" (with the player's name and game version), gets
## the recent history, then every new global message; send() posts one ("say").
## Reconnects on its own (the hub may be asleep: it takes up to a minute to wake).
## Hangs up when it leaves the tree (leaving the main menu).

signal message_received(entry: Dictionary)
signal status_changed(text: String)

const NetScript := preload("res://scripts/net/net.gd")
const RETRY := 5.0
const HISTORY := 40

var history: Array = []
## "CONNECTING", "LINKED", "OUT OF DATE" or "OFFLINE".
var status := "CONNECTING"

var _api: SceneMultiplayer
var _retry := -1.0
var _linked := false
var _refused := false


func _ready() -> void:
	_api = SceneMultiplayer.new()
	_api.auth_callback = _on_auth
	_api.auth_timeout = 1.0e7
	_api.peer_authenticating.connect(_on_up)
	get_tree().set_multiplayer(_api, get_path())
	_open()


func _exit_tree() -> void:
	if _api and _api.multiplayer_peer:
		_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, get_path())


func is_linked() -> bool:
	return _linked


## Posts to global chat (as your player name, tagged MENU). Dropped if not linked.
func send(text: String) -> void:
	text = text.replace("\n", " ").strip_edges().substr(0, 120)
	if text == "" or not _linked:
		return
	_api.send_auth(1, var_to_bytes({"t": "say", "text": text}))


func _open() -> void:
	var url: String = NetScript.SERVER_URLS[0]
	var peer := WebSocketMultiplayerPeer.new()
	var tls := TLSOptions.client() if url.begins_with("wss") else null
	if peer.create_client(url, tls) != OK:
		_retry = RETRY
		return
	_api.multiplayer_peer = peer
	_retry = -1.0


func _on_up(id: int) -> void:
	var net := get_tree().root.get_node_or_null("Net")
	var settings := get_tree().root.get_node_or_null("Settings")
	_api.send_auth(id, var_to_bytes({
		"t": "listen",
		"version": net.get("version") if net else "",
		"name": settings.call("get_value", "player_name") if settings else "PILOT",
	}))


func _on_auth(_id: int, data: PackedByteArray) -> void:
	var msg = bytes_to_var(data)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match msg.get("t", ""):
		"history":
			_linked = true
			_set_status("LINKED")
			history.clear()
			var entries = msg.get("entries", [])
			if typeof(entries) == TYPE_ARRAY:
				for entry in entries:
					if typeof(entry) == TYPE_DICTIONARY:
						_add(entry)
		"down":
			if typeof(msg.get("entry")) == TYPE_DICTIONARY:
				_add(msg["entry"])
		"refused":
			# Different version (or the hub is full): stop trying until the menu reopens.
			_refused = true
			_linked = false
			_set_status("OUT OF DATE")
			_close.call_deferred()


func _add(entry: Dictionary) -> void:
	history.append(entry)
	while history.size() > HISTORY:
		history.pop_front()
	message_received.emit(entry)


func _close() -> void:
	if _api.multiplayer_peer:
		_api.multiplayer_peer.close()


func _set_status(text: String) -> void:
	if text != status:
		status = text
		status_changed.emit(text)


func _process(delta: float) -> void:
	if _refused:
		return
	var peer := _api.multiplayer_peer
	if _retry < 0.0 and (not peer or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED):
		# Dropped, or never got through (the hub asleep): try again shortly.
		if _linked:
			_linked = false
		_set_status("CONNECTING")
		_retry = RETRY
	if _retry >= 0.0:
		_retry -= delta
		if _retry < 0.0:
			_open()
