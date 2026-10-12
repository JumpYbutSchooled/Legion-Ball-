extends Node
## Works out every weapon's pentagons (weapons/pentagon_skin.gd) on a background thread as soon
## as the game starts, so building a weapon later (the Armory's pictures, your loadout when a
## match starts, another player's weapons when they join) never stalls a frame doing it.
## Also starts decoding the Armory's saved weapon pictures (ui/weapon_icons.gd).
## A service (services.gd). Nothing to do on a headless server (no pentagons drawn there).

const WeaponInfo := preload("res://scripts/weapon_info.gd")
const PentagonSkin := preload("res://scripts/weapons/pentagon_skin.gd")

var _ids: Array = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_ids = WeaponInfo.WEAPONS.keys()
	# The Armory's saved weapon pictures too, decoded long before the menu needs them.
	load("res://scripts/ui/weapon_icons.gd").preload_disk(WeaponInfo.pool())


## A little every frame: each is only made in memory (never added to the scene) to read
## its blades' shapes, which go off to the background thread.
func _process(_delta: float) -> void:
	# At most ~1.5 ms a frame of reading weapons (the maths itself runs on the other thread).
	var until := Time.get_ticks_usec() + 1500
	while Time.get_ticks_usec() < until and not _ids.is_empty():
		var info: Dictionary = WeaponInfo.WEAPONS[_ids.pop_back()]
		if not info.has("script"):
			continue
		var weapon: Node = load(info["script"]).new()
		weapon.call("_build")
		for blade in weapon.get("_blades"):
			var job: Array = blade.call("pentagon_job")
			PentagonSkin.warm(job[0], job[1], job[2])
		weapon.free()
	if PentagonSkin.reap() and _ids.is_empty():
		set_process(false)


func _exit_tree() -> void:
	PentagonSkin.shutdown()
