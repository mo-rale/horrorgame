extends Node

const SETTINGS_PATH := "user://settings.cfg"
const BUS_NAMES := ["Master", "Music", "SFX"]

var volumes := {
	"Master": 0.8,
	"Music": 0.7,
	"SFX": 0.8,
}
var mouse_sensitivity := 1.0
var brightness := 1.0
var fullscreen := false


func _ready() -> void:
	_ensure_audio_buses()
	_load_settings()
	_apply_all_volumes()
	_apply_window_mode()


func set_volume(bus_name: String, linear_value: float) -> void:
	if not volumes.has(bus_name):
		return

	volumes[bus_name] = clampf(linear_value, 0.0, 1.0)
	_apply_volume(bus_name)
	_save_settings()


func get_volume(bus_name: String) -> float:
	return float(volumes.get(bus_name, 1.0))


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.25, 2.5)
	_save_settings()


func set_brightness(value: float) -> void:
	brightness = clampf(value, 0.5, 1.5)
	_save_settings()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_window_mode()
	_save_settings()


func apply_brightness(environment: Environment) -> void:
	if not environment:
		return
	environment.adjustment_enabled = true
	environment.adjustment_brightness = brightness


func _ensure_audio_buses() -> void:
	for bus_name in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _apply_all_volumes() -> void:
	for bus_name in BUS_NAMES:
		_apply_volume(bus_name)


func _apply_volume(bus_name: String) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return

	var value: float = volumes[bus_name]
	AudioServer.set_bus_mute(bus_index, value <= 0.001)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value, 0.001)))


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	for bus_name in BUS_NAMES:
		volumes[bus_name] = clampf(
			float(config.get_value("audio", bus_name.to_lower(), volumes[bus_name])),
			0.0,
			1.0
		)

	mouse_sensitivity = clampf(
		float(config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)),
		0.25,
		2.5
	)
	brightness = clampf(
		float(config.get_value("video", "brightness", brightness)),
		0.5,
		1.5
	)
	fullscreen = bool(config.get_value("video", "fullscreen", fullscreen))


func _save_settings() -> void:
	var config := ConfigFile.new()
	for bus_name in BUS_NAMES:
		config.set_value("audio", bus_name.to_lower(), volumes[bus_name])
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("video", "brightness", brightness)
	config.set_value("video", "fullscreen", fullscreen)
	config.save(SETTINGS_PATH)


func _apply_window_mode() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
