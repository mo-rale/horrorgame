extends Node3D

signal lightning_struck

@export_range(1.0, 30.0, 0.1) var lightning_delay_min: float = 5.0
@export_range(1.0, 30.0, 0.1) var lightning_delay_max: float = 11.0

@onready var lightning_light: DirectionalLight3D = $LightningLight

var _lightning_timer: float = 0.0
var _flash_timer: float = 0.0
var _second_flash_timer: float = -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# The first strike comes soon so the menu does not sit in silence.
	_lightning_timer = _rng.randf_range(1.5, 3.0)
	lightning_light.light_energy = 0.0


func _process(delta: float) -> void:
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_start_lightning()

	if _second_flash_timer >= 0.0:
		_second_flash_timer -= delta
		if _second_flash_timer <= 0.0:
			_second_flash_timer = -1.0
			_flash_timer = _rng.randf_range(0.07, 0.13)

	if _flash_timer > 0.0:
		_flash_timer -= delta
		lightning_light.light_energy = 3.8
	else:
		lightning_light.light_energy = move_toward(
			lightning_light.light_energy,
			0.0,
			delta * 18.0
		)


func _start_lightning() -> void:
	_flash_timer = _rng.randf_range(0.06, 0.11)
	_second_flash_timer = _rng.randf_range(0.11, 0.22)
	lightning_light.rotation_degrees.y = _rng.randf_range(-160.0, 160.0)
	lightning_struck.emit()
	_schedule_lightning()


func _schedule_lightning() -> void:
	_lightning_timer = _rng.randf_range(lightning_delay_min, lightning_delay_max)
