extends Node3D
## Base for a weapon built from crystal blades wrapped round the ball.
## Owns the enter/exit animation: a glowing wave runs from each blade's back point to its
## tip, pulling the facets together (enter) or breaking them apart (exit). The blades are
## grey while this runs and flash in the weapon's colour once fully equipped.
## Subclasses add blades in _build(), animate in _update(), fire in handle_fire(),
## and describe their crosshair in get_crosshair().

signal equipped
signal unequipped

enum State { HOLSTERED, ENTERING, READY, EXITING }

const BladeMesh := preload("res://scripts/energy_blade_mesh.gd")
const BladeFlare := preload("res://scripts/weapons/blade_flare.gd")
const FlashLight := preload("res://scripts/flash_light.gd")
const Sfx := preload("res://scripts/sfx.gd")
const WAVE_END := 1.4  # Wave position where every facet has fully broken/joined.

@export var color := Color(0.3, 0.8, 1.0)
## Seconds for the enter/exit wave to run the length of the blades.
@export var toggle_time := 0.55
@export var equip_flash_time := 0.35
@export var equip_light_energy := 40.0
## How far a blade jolts back when it fires, and how fast it settles.
@export var kick_distance := 0.3
@export var kick_recover := 14.0
## How far a blade's tip opens when it kicks (0 = not at all). Settles with the kick.
@export var kick_open := 0.0

## The weapon manager (scripts/weapon.gd). Set before this is added to the tree.
var manager: Node
var state := State.HOLSTERED
## How open every blade's tip is right now (subclasses animate this, e.g. the grapple).
var tip_open := 0.0

var _blades: Array[MeshInstance3D] = []
var _bases: Array[Basis] = []
var _kicks := PackedFloat32Array()
var _wave := -1.0
var _flash := 0.0
var _flash_color := Color.WHITE


func _ready() -> void:
	_build()
	_kicks.resize(_blades.size())
	_kicks.fill(0.0)
	_set_param("color", color)
	visible = false


## Adds a blade on `side` (1 right, -1 left), rolled `roll_deg` round the forward axis.
## `props` overrides energy_blade_mesh.gd settings (tip, max_width, ...).
func add_blade(side: float, roll_deg: float, props := {}) -> MeshInstance3D:
	var blade := BladeMesh.new()
	blade.side = side
	blade.jag_seed = _blades.size() + 1
	for key in props:
		blade.set(key, props[key])
	var roll := Basis(Vector3.BACK, deg_to_rad(roll_deg * side))
	blade.transform = Transform3D(roll, Vector3.ZERO)
	add_child(blade)
	_blades.append(blade)
	_bases.append(roll)
	return blade


func enter() -> void:
	if state == State.READY or state == State.ENTERING:
		return
	state = State.ENTERING
	_wave = 0.0
	visible = true
	_sound("equip", -10.0)


func exit() -> void:
	if state == State.HOLSTERED or state == State.EXITING:
		return
	state = State.EXITING
	_wave = 0.0
	_on_exit()
	_sound("unequip", -12.0)


## A sound at the weapon. Not broadcast: every computer runs enter/exit itself.
func _sound(sound: String, volume_db := 0.0) -> void:
	if is_inside_tree():
		Sfx.play_at(get_tree(), sound, global_position, volume_db)


func is_ready() -> bool:
	return state == State.READY


## 1 fully out, 0 fully away, in between while the wave runs.
func get_arm_amount() -> float:
	match state:
		State.READY:
			return 1.0
		State.ENTERING:
			return clampf(_wave / WAVE_END, 0.0, 1.0)
		State.EXITING:
			return 1.0 - clampf(_wave / WAVE_END, 0.0, 1.0)
	return 0.0


## Jolts blade `index` backward (it settles on its own). Other players see it too.
func kick(index: int) -> void:
	_kicks[index] = 1.0
	if manager and manager.is_multiplayer_authority():
		manager.call("broadcast_kick", self, index)


## Flash in `c`: every blade glows, gets its own blade-shaped flare, and a light rides
## along with the weapon. All of it is parented to the weapon, so it follows it.
func flash(c: Color) -> void:
	_flash = 1.0
	_flash_color = c
	_set_param("flash_color", c)
	for blade in _blades:
		var flare := BladeFlare.new()
		flare.mesh = blade.mesh
		flare.color = c
		blade.add_child(flare)
	var light := FlashLight.new()
	light.light_color = c
	light.light_energy = equip_light_energy
	light.omni_range = 10.0
	light.lifetime = 0.3
	# Out in front of the ball, among the blades.
	light.position = Vector3(0, 0, -1.5)
	add_child(light)


func _process(delta: float) -> void:
	var settle := 1.0 - exp(-kick_recover * delta)
	for i in _blades.size():
		_kicks[i] = lerpf(_kicks[i], 0.0, settle)
		_blades[i].transform = Transform3D(_bases[i], Vector3(0, 0, _kicks[i] * kick_distance))
		# Per blade: its own shot kick can open its tip on top of the weapon-wide opening.
		var mat := _blades[i].material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("tip_open", maxf(tip_open, _kicks[i] * kick_open))

	var animating := state == State.ENTERING or state == State.EXITING
	if animating:
		_wave += delta / toggle_time * WAVE_END
		if _wave >= WAVE_END:
			_finish_wave()
			animating = false

	_flash = move_toward(_flash, 0.0, delta / equip_flash_time)
	_set_param("wave_pos", _wave if animating else -1.0)
	_set_param("wave_assembling", state == State.ENTERING)
	_set_param("grey", 1.0 if animating else 0.0)
	_set_param("flash_amount", _flash)
	_update(delta)


func _finish_wave() -> void:
	_wave = -1.0
	if state == State.ENTERING:
		state = State.READY
		flash(_equip_flash_color())
		equipped.emit()
	else:
		state = State.HOLSTERED
		visible = false
		unequipped.emit()


func _set_param(param: StringName, value: Variant) -> void:
	for blade in _blades:
		var mat := blade.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter(param, value)


# --- For subclasses -----------------------------------------------------------

## Create the blades with add_blade().
func _build() -> void:
	pass


## Per-frame visuals, after the base has updated.
func _update(_delta: float) -> void:
	pass


## Called by the manager every physics step while this is the equipped weapon.
## `pressed` is true while fire is held (mouse captured); `hit` is the crosshair raycast.
func handle_fire(_pressed: bool, _hit: Dictionary, _delta: float) -> void:
	pass


## Called when the weapon starts leaving (e.g. to cancel a charge).
func _on_exit() -> void:
	pass


## What the crosshair should draw. Must include "kind".
func get_crosshair() -> Dictionary:
	return {"kind": "none"}


## Colour of the flash when the weapon finishes coming out (a reloading weapon flashes
## its reload colour instead).
func _equip_flash_color() -> Color:
	return color


## 0..1 build-up other players should see (railgun / nova charge). Sent over the network.
func get_net_charge() -> float:
	return 0.0


## Another player's charge, from the network.
func apply_net_charge(_charge: float) -> void:
	pass
