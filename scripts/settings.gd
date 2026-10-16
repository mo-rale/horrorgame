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
## 0 = low, 1 = medium, 2 = high. Controls fog, glow and shadow cost.
var quality := 2
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]

# Best run, kept between sessions (seconds, 0 = none yet) and notes found.
var best_time := 0
var best_notes := 0


func _ready() -> void:
	_ensure_audio_buses()
	_load_settings()
	_apply_all_volumes()
	_apply_window_mode()
	_apply_viewport_quality.call_deferred()


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


func set_quality(value: int) -> void:
	quality = clampi(value, 0, 2)
	_apply_viewport_quality()
	_save_settings()


func cycle_quality() -> int:
	set_quality((quality + 1) % 3)
	return quality


func apply_quality(environment: Environment) -> void:
	if not environment:
		return
	environment.volumetric_fog_enabled = quality >= 2 and environment.volumetric_fog_enabled
	environment.glow_enabled = quality >= 1 and environment.glow_enabled
	environment.ssao_enabled = false


func record_run(seconds: int, notes: int) -> bool:
	# Returns true when this run beat the saved best (faster, or more notes on a tie).
	var better := best_time == 0 or seconds < best_time
	if better:
		best_time = seconds
	best_notes = maxi(best_notes, notes)
	_save_settings()
	return better


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
	quality = clampi(int(config.get_value("video", "quality", quality)), 0, 2)
	best_time = int(config.get_value("progress", "best_time", best_time))
	best_notes = int(config.get_value("progress", "best_notes", best_notes))


func _save_settings() -> void:
	var config := ConfigFile.new()
	for bus_name in BUS_NAMES:
		config.set_value("audio", bus_name.to_lower(), volumes[bus_name])
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("video", "brightness", brightness)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "quality", quality)
	config.set_value("progress", "best_time", best_time)
	config.set_value("progress", "best_notes", best_notes)
	config.save(SETTINGS_PATH)


func _apply_window_mode() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _apply_viewport_quality() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	# MSAA and shadow filtering are the cheap, visible wins.
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality]
	)
	RenderingServer.positional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality]
	)
