extends SceneTree
## WebSocket test client. Run with user arg "A" (the shooter) or "B" (the target).

func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await physics_frame
		t += 1.0 / 60.0

func _initialize() -> void:
	var role: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "A"
	load("res://scripts/services.gd").ensure(self)
	await process_frame
	var net: Node = root.get_node("Net")
	root.get_node("Settings").call("set_value", "player_name", "PLAYER_" + role)
	await _secs(1.5 if role == "A" else 3.0)
	net.join_server("ws://127.0.0.1:7778")
	var waited := 0.0
	while (current_scene == null or current_scene.name != "Arena") and waited < 20.0:
		await _secs(0.25)
		waited += 0.25
	print(role, ": in arena=", current_scene != null and current_scene.name == "Arena", " status=", net.get("status"))
	await _secs(2.5)
	var arena := current_scene
	print(role, ": players in arena=", arena.get_node("Players").get_child_count(), " roster=", net.get("players").size())
	if role == "A":
		var other := 0
		for id in net.get("players"):
			if id != net.local_id():
				other = id
		var target: Node = arena.get_node("Players/P%d" % other)
		for i in 25:
			target.take_hit(1.0, Vector3.ZERO, Vector3.ZERO)
			await physics_frame
		await _secs(1.0)
		print("A: target alive=", arena.alive.get(other), " my kills=", net.get("players")[net.local_id()]["kills"])
	else:
		await _secs(1.5)
		print("B: my hp=", arena.health.get(net.local_id()), " alive=", arena.alive.get(net.local_id()))
	await _secs(4.0)
	if role == "B":
		print("B: after respawn alive=", arena.alive.get(net.local_id()), " hp=", arena.health.get(net.local_id()))
	quit()
