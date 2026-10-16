extends OmniLight3D
# Emergency lighting that sputters now and then.

@export var flicker_chance := 0.35
@export var dropout_chance := 0.1

var _base_energy := 1.0
var _timer := 0.0
var _off_time := 0.0


func _ready() -> void:
	_base_energy = light_energy
	_timer = randf_range(0.5, 4.0)
	# Only some fixtures misbehave, so the plant feels uneven rather than disco.
	if randf() > flicker_chance:
		set_process(false)


func _process(delta: float) -> void:
	_timer -= delta
	_off_time -= delta
	if _off_time > 0.0:
		light_energy = _base_energy * randf_range(0.0, 0.25)
		return
	light_energy = _base_energy
	if _timer <= 0.0:
		_timer = randf_range(1.5, 7.0)
		if randf() < dropout_chance * 4.0:
			_off_time = randf_range(0.08, 0.5)
