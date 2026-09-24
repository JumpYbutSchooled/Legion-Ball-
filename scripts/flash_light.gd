extends OmniLight3D
## One-shot light flash that fades out and frees itself.

@export var lifetime := 0.08

var _start_energy := 1.0
var _t := 0.0


func _ready() -> void:
	_start_energy = light_energy
	shadow_enabled = false


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	light_energy = _start_energy * (1.0 - _t / lifetime)
