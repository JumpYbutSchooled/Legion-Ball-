extends RefCounted
## Game-wide services, created at runtime instead of as project autoloads.
## Autoloads are loaded before the boot scene can mount an update, so they could never
## be updated; these are created after it, so they always come from the latest update.
## ensure() is safe to call from anywhere, any number of times.

const SERVICES := {
	"Settings": "res://scripts/settings.gd",
	"Net": "res://scripts/net/net.gd",
	"Sfx": "res://scripts/sfx.gd",
	"Music": "res://scripts/music.gd",
	"Mod": "res://scripts/net/moderation.gd",
	"Chat": "res://scripts/net/chat.gd",
	"GlobalChat": "res://scripts/net/global_relay.gd",
}


static func ensure(tree: SceneTree) -> void:
	for service in SERVICES:
		if tree.root.get_node_or_null(service) == null:
			var node: Node = load(SERVICES[service]).new()
			node.name = service
			tree.root.add_child(node)
	load("res://scripts/input_setup.gd").apply()
