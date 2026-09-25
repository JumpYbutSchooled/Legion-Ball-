extends Node
## Asks server 1 (the hub, scripts/net/global_relay.gd) who's online on every server,
## for the multiplayer menu. Uses its own short connection (a separate SceneMultiplayer
## rooted at this node, so the game's connection is untouched): the question and the
## answer travel in Godot's authentication step, then it hangs up.
## Emits `finished` with {"version", "servers": {"S1": {"players", "map"}, ...}}, or {}
## if server 1 couldn't be reached. Frees itself afterwards.

signal finished(status: Dictionary)

## Server 1 may be asleep: keep trying this long (it takes up to a minute to wake).
const GIVE_UP := 90.0
const RETRY := 4.0

var url := ""

var _api: SceneMultiplayer
var _elapsed := 0.0
var _retry := -1.0
var _done := false


func _ready() -> void:
	_api = SceneMultiplayer.new()
	_api.auth_callback = _on_auth
	_api.auth_timeout = GIVE_UP
	_api.peer_authenticating.connect(func(id: int) -> void:
		_api.send_auth(id, var_to_bytes({"t": "status?"})))
	get_tree().set_multiplayer(_api, get_path())
	_open()


func _open() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var tls := TLSOptions.client() if url.begins_with("wss") else null
	if peer.create_client(url, tls) != OK:
		_retry = RETRY
		return
	_api.multiplayer_peer = peer
	_retry = -1.0


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > GIVE_UP:
		_finish({})
		return
	var peer := _api.multiplayer_peer
	if _retry < 0.0 and (not peer or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED):
		_retry = RETRY
	if _retry >= 0.0:
		_retry -= delta
		if _retry < 0.0:
			_open()


func _on_auth(_id: int, data: PackedByteArray) -> void:
	var msg = bytes_to_var(data)
	if typeof(msg) == TYPE_DICTIONARY and msg.get("t", "") == "status":
		# Deferred: this runs inside the connection's own polling, which must finish
		# before the connection can be closed and removed.
		_finish.call_deferred(msg)


func _finish(status: Dictionary) -> void:
	if _done:
		return
	_done = true
	if _api.multiplayer_peer:
		_api.multiplayer_peer.close()
	get_tree().set_multiplayer(null, get_path())
	finished.emit(status)
	queue_free()


func _exit_tree() -> void:
	# Leaving the menu mid-question: hang up.
	if not _done:
		_done = true
		if _api and _api.multiplayer_peer:
			_api.multiplayer_peer.close()
		get_tree().set_multiplayer(null, get_path())
