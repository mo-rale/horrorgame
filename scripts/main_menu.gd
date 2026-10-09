extends Control

@onready var main_buttons: VBoxContainer = %MainButtons
@onready var settings_panel: VBoxContainer = %SettingsPanel
@onready var play_button: Button = %PlayButton
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	play_button.pressed.connect(_play_game)
	%SettingsButton.pressed.connect(_show_settings)
	%QuitButton.pressed.connect(get_tree().quit)
	%BackButton.pressed.connect(_hide_settings)

	_setup_slider(master_slider, "Master")
	_setup_slider(music_slider, "Music")
	_setup_slider(sfx_slider, "SFX")
	play_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		settings_panel.visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		_hide_settings()


func _setup_slider(slider: HSlider, bus_name: String) -> void:
	slider.value = Settings.get_volume(bus_name) * 100.0
	slider.value_changed.connect(
		func(value: float) -> void: Settings.set_volume(bus_name, value / 100.0)
	)


func _play_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _show_settings() -> void:
	main_buttons.visible = false
	settings_panel.visible = true
	master_slider.grab_focus()


func _hide_settings() -> void:
	settings_panel.visible = false
	main_buttons.visible = true
	%SettingsButton.grab_focus()
