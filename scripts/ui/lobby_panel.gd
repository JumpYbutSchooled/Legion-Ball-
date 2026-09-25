extends VBoxContainer
## Multiplayer lobby page: pick a callsign, then join an online server (SERVER 1-4),
## HOST a game or JOIN one by IP.
## Once connected it shows the address to give friends (host), the live roster and
## START MATCH (host) / LEAVE. Rebuilds itself whenever the Net roster or status changes.

const UIStyle := preload("res://scripts/ui/ui_style.gd")
const NetScript := preload("res://scripts/net/net.gd")

var _net: Node
var _settings: Node
var _body: VBoxContainer
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_net = get_tree().root.get_node_or_null("Net")
	_settings = get_tree().root.get_node_or_null("Settings")
	if not _net or not _settings:
		add_child(UIStyle.label("Network service offline.", 15, UIStyle.TEXT_DIM))
		return

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 14)
	add_child(name_row)
	var name_label := UIStyle.label("CALLSIGN", 15, UIStyle.TEXT)
	name_label.custom_minimum_size = Vector2(120, 0)
	name_row.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.text = _settings.call("get_value", "player_name")
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(240, 0)
	name_edit.text_changed.connect(func(t: String) -> void: _settings.call("set_value", "player_name", t))
	name_row.add_child(name_edit)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	add_child(_body)
	_status = UIStyle.label("", 14, UIStyle.ACCENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_net.connect("roster_changed", _rebuild)
	_net.connect("status_changed", _on_status)
	_rebuild()
	_on_status(_net.get("status"))


func _on_status(text: String) -> void:
	if _status:
		_status.text = "> " + text if text != "" else ""


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	if _net.get("online"):
		_build_lobby()
	else:
		_build_connect()


func _build_connect() -> void:
	_body.add_child(UIStyle.label("ONLINE", 13, UIStyle.TEXT_DIM))
	var servers := HBoxContainer.new()
	servers.add_theme_constant_override("separation", 10)
	_body.add_child(servers)
	var last: int = _settings.call("get_value", "last_server")
	for i in NetScript.SERVER_URLS.size():
		var map_name: String = NetScript.MAP_NAMES.get(NetScript.SERVER_MAPS[i], "")
		var b := _button("SERVER %d · %s" % [i + 1, map_name], _join_server.bind(i))
		if i == last:
			b.add_theme_color_override("font_color", UIStyle.ACCENT)
		servers.add_child(b)
	_body.add_child(UIStyle.label(
		"%d always-running arenas, %d players each. If one is full, try another.\n" % [NetScript.SERVER_URLS.size(), NetScript.MAX_PLAYERS]
		+ "Works anywhere, including school Wi-Fi. A server nobody's used for a while\n"
		+ "takes up to a minute to wake up.", 12, UIStyle.TEXT_DIM))

	var line := ColorRect.new()
	line.color = UIStyle.ACCENT_DIM
	line.custom_minimum_size = Vector2(0, 1)
	_body.add_child(line)
	_body.add_child(UIStyle.label("LOCAL NETWORK (host needs firewall access)", 13, UIStyle.TEXT_DIM))
	var host := _button("HOST GAME", _host)
	_body.add_child(host)
	_body.add_child(UIStyle.label("Friends join you by IP on port %d." % NetScript.PORT, 13, UIStyle.TEXT_DIM))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 14)
	_body.add_child(join_row)
	var ip := LineEdit.new()
	ip.text = _settings.call("get_value", "last_join_ip")
	ip.placeholder_text = "host IP, e.g. 192.168.1.20"
	ip.custom_minimum_size = Vector2(260, 0)
	join_row.add_child(ip)
	join_row.add_child(_button("JOIN", func() -> void: _join(ip.text)))
	ip.text_submitted.connect(func(t: String) -> void: _join(t))
	_body.add_child(UIStyle.label(
		"Same Wi-Fi: use the host's address shown on their screen.\n"
		+ "Over the internet: the host forwards UDP port %d, or everyone uses Tailscale." % NetScript.PORT,
		12, UIStyle.TEXT_DIM))


func _build_lobby() -> void:
	var is_host: bool = _net.call("is_host")
	if is_host:
		var addrs: PackedStringArray = _net.call("lan_addresses")
		var text := "YOUR ADDRESS  " + (",  ".join(addrs) if not addrs.is_empty() else "(no network found)")
		_body.add_child(UIStyle.label(text + "   PORT %d" % NetScript.PORT, 15, Color.WHITE, true))

	_body.add_child(UIStyle.label("SQUAD  %d / %d" % [_net.get("players").size(), NetScript.MAX_PLAYERS], 13, UIStyle.TEXT_DIM))
	var players: Dictionary = _net.get("players")
	var ids := players.keys()
	ids.sort()
	for id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = _net.call("player_color", id)
		swatch.custom_minimum_size = Vector2(10, 18)
		row.add_child(swatch)
		var tags := ""
		if id == 1:
			tags += "  [HOST]"
		if id == _net.call("local_id"):
			tags += "  [YOU]"
		row.add_child(UIStyle.label(String(players[id]["name"]) + tags, 16, UIStyle.TEXT))
		_body.add_child(row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	_body.add_child(buttons)
	if is_host:
		buttons.add_child(_button("START MATCH", func() -> void: _net.call("start_match")))
	else:
		buttons.add_child(UIStyle.label("Waiting for the host to start...", 14, UIStyle.TEXT_DIM))
	buttons.add_child(_button("LEAVE", func() -> void: _net.call("leave")))


func _host() -> void:
	_net.call("host")


func _join_server(index: int) -> void:
	_settings.call("set_value", "last_server", index)
	_net.call("join_server", NetScript.SERVER_URLS[index])


func _join(ip: String) -> void:
	if ip.strip_edges() == "":
		return
	_settings.call("set_value", "last_join_ip", ip.strip_edges())
	_net.call("join", ip)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = "[ " + text + " ]"
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(action)
	return b
