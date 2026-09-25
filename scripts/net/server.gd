extends Node
## Entry point for the dedicated online server:
##   godot --headless --path <project> res://scenes/server.tscn
## Listens for players over WebSockets on $PORT (set by the host, e.g. Render) or
## Net.SERVER_PORT, then keeps one arena running for whoever joins.

const Services := preload("res://scripts/services.gd")
const NetScript := preload("res://scripts/net/net.gd")


func _ready() -> void:
	# Deferred: the root is still busy adding this scene.
	_start.call_deferred()


func _start() -> void:
	Services.ensure(get_tree())
	var net := get_tree().root.get_node("Net")
	var env_port := OS.get_environment("PORT")
	var port := int(env_port) if env_port.is_valid_int() else NetScript.SERVER_PORT
	var err: int = net.call("host_dedicated", port)
	if err != OK:
		get_tree().quit(1)
