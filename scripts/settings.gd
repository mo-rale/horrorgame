extends Node

const SETTINGS_PATH := "user://settings.cfg"
const BUS_NAMES := ["Master", "Music", "SFX"]

var volumes := {
	"Master": 0.8,
	"Music": 0.7,
	"SFX": 0.8,
}


func _ready() -> void:
	_ensure_audio_buses()
	_load_settings()
	_apply_all_volumes()


func set_volume(bus_name: String, linear_value: float) -> void:
	if not volumes.has(bus_name):
		return

	volumes[bus_name] = clampf(linear_value, 0.0, 1.0)
	_apply_volume(bus_name)
	_save_settings()


func get_volume(bus_name: String) -> float:
	return float(volumes.get(bus_name, 1.0))


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


func _save_settings() -> void:
	var config := ConfigFile.new()
	for bus_name in BUS_NAMES:
		config.set_value("audio", bus_name.to_lower(), volumes[bus_name])
	config.save(SETTINGS_PATH)
