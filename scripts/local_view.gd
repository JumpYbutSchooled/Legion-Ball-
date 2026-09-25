extends Node
## Everything that belongs only to the player at this computer: the orbit camera, screen
## warp, crosshair, weapon selector, impact frames and pause menu.
## The arena spawns one of these for the local player and calls setup() with that
## player's ball BEFORE adding it, so every piece is wired up by the time it's ready.

const Speedometer := preload("res://scripts/ui/speedometer.gd")
const Minimap := preload("res://scripts/ui/minimap.gd")
const LockWarning := preload("res://scripts/ui/lock_warning.gd")


func setup(ball: RigidBody3D) -> void:
	var speedo := Speedometer.new()
	speedo.ball = ball
	add_child(speedo)
	var minimap := Minimap.new()
	minimap.ball = ball
	add_child(minimap)
	add_child(LockWarning.new())
	var rig := $CameraRig
	var camera := $CameraRig/Pitch/SpringArm3D/Camera3D
	var weapon := ball.get_node("Weapon")
	rig.set("target", ball)
	rig.set("warp_rect", $WarpLayer/Warp)
	ball.set("camera_rig", rig)
	weapon.set("camera", camera)
	weapon.set("camera_rig", rig)
	$CameraRig/Pitch/SpringArm3D/Camera3D/MotionBlur.set("ball", ball)
	$HUD/Crosshair.set("weapon", weapon)
	$WeaponSelector.set("weapon", weapon)
	$ImpactFrames.set("camera_rig", rig)
	$ImpactFrames.set("weapon", weapon)
