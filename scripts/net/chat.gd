extends Node
## Chat service (/root/Chat, created by scripts/services.gd). Two channels
## (scripts/ui/chat_box.gd): SERVER chat (/) reaches everyone on this server; GLOBAL chat
## (right Shift) reaches every online server, passed between them by server 1
## (scripts/net/global_relay.gd).
## Messages go to your server, which stamps them with your real name and staff title (so
## nobody can post as someone else), trims them and rate-limits each player.
## Its RPCs live on their own node, not Net, so adding them didn't renumber Net's RPCs.

signal message_received(entry: Dictionary)

const ModScript := preload("res://scripts/net/moderation.gd")
const MAX_LENGTH := 120
## Rate limit (both channels together): at most BURST messages in WINDOW seconds.
const BURST := 4
const WINDOW := 5.0
const HISTORY := 40

## Recent messages, oldest first:
## {name, color, title, title_color, text, global, server ("S1".."S4" for global)}.
var history: Array = []

var _net: Node
# Server: recent send times per peer.
var _sent := {}


func _ready() -> void:
	_net = get_tree().root.get_node_or_null("Net")
	if _net:
		_net.connect("roster_changed", _on_roster_changed)


## Send a message (from the chat box) to this server, or to every server if `global`.
func send(text: String, global := false) -> void:
	text = _clean(text)
	if text == "" or not _net or not _net.get("online"):
		return
	if multiplayer.is_server():
		_post(text, global)
	else:
		_post.rpc_id(1, text, global)


## Server: a global message from another server (via the relay) for our players.
func deliver_global(entry: Dictionary) -> void:
	if multiplayer.is_server():
		_show.rpc(entry)


func _clean(text: String) -> String:
	return text.replace("\n", " ").replace("\r", " ").strip_edges().substr(0, MAX_LENGTH)


func _on_roster_changed() -> void:
	# Leaving a server clears the chat.
	if not _net.get("online"):
		history.clear()


@rpc("any_peer", "reliable")
func _post(text: String, global: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = 1
	var players: Dictionary = _net.get("players")
	if not players.has(peer):
		return
	# Rate limit: drop anything past BURST messages in WINDOW seconds.
	var now := Time.get_ticks_msec() / 1000.0
	var times: Array = _sent.get(peer, []).filter(func(t: float) -> bool: return now - t < WINDOW)
	if times.size() >= BURST:
		return
	times.append(now)
	_sent[peer] = times
	text = _clean(text)
	if text == "":
		return
	var p: Dictionary = players[peer]
	var title := ModScript.title_of(p)
	var entry := {
		"name": String(p["name"]),
		"color": _net.call("player_color", peer),
		"title": title[0] if not title.is_empty() else "",
		"title_color": title[1] if not title.is_empty() else Color.WHITE,
		"text": text,
		"global": global,
		"server": _net.call("server_label"),
	}
	if _net.get("dedicated"):
		print("[chat%s] %s: %s" % [" GLOBAL" if global else "", entry["name"], text])
	var relay := get_tree().root.get_node_or_null("GlobalChat")
	if global and relay and relay.call("is_active"):
		# Every server, this one included, gets it back from the relay.
		relay.call("send", entry)
	else:
		# Server chat, or global chat on a server with no relay (LAN games).
		_show.rpc(entry)


@rpc("authority", "call_local", "reliable")
func _show(entry: Dictionary) -> void:
	history.append(entry)
	while history.size() > HISTORY:
		history.pop_front()
	message_received.emit(entry)
