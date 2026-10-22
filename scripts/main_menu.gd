extends Control

const UiSounds := preload("res://scripts/ui_sounds.gd")

@onready var main_buttons: VBoxContainer = %MainButtons
@onready var settings_panel: VBoxContainer = %SettingsPanel
@onready var play_button: Button = %PlayButton
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var sensitivity_slider: HSlider = %SensitivitySlider
@onready var brightness_slider: HSlider = %BrightnessSlider
@onready var fullscreen_toggle: CheckButton = %FullscreenToggle
@onready var quality_button: Button = %QualityButton
var _scale_button: Button
@onready var title_label: Label = $Center/Content/Title
@onready var subtitle_label: Label = $Center/Content/Subtitle
@onready var keybind_list: VBoxContainer = %KeybindList
@onready var keybind_hint: Label = %KeybindHint

var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _key_buttons := {}          # action -> Button
var _waiting_action := ""
var _flicker_timer := 1.0
var _starting := false


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	play_button.pressed.connect(_play_game)
	%SettingsButton.pressed.connect(_show_settings)
	%QuitButton.pressed.connect(get_tree().quit)
	%BackButton.pressed.connect(_hide_settings)

	_tabs = [%AudioTab, %DisplayTab, %ControlsTab]
	_pages = [%AudioPage, %DisplayPage, %ControlsPage]
	for index in _tabs.size():
		_tabs[index].pressed.connect(_select_tab.bind(index))
	_select_tab(0)

	_setup_slider(master_slider, "Master")
	_setup_slider(music_slider, "Music")
	_setup_slider(sfx_slider, "SFX")
	sensitivity_slider.value = Settings.mouse_sensitivity * 100.0
	brightness_slider.value = Settings.brightness * 100.0
	fullscreen_toggle.button_pressed = Settings.fullscreen
	sensitivity_slider.value_changed.connect(
		func(value: float) -> void: Settings.set_mouse_sensitivity(value / 100.0)
	)
	brightness_slider.value_changed.connect(
		func(value: float) -> void: Settings.set_brightness(value / 100.0)
	)
	fullscreen_toggle.toggled.connect(Settings.set_fullscreen)
	%SkipIntroToggle.button_pressed = Settings.skip_intro
	%SkipIntroToggle.toggled.connect(Settings.set_skip_intro)
	_refresh_quality_text()
	quality_button.pressed.connect(
		func() -> void:
			Settings.cycle_quality()
			_refresh_quality_text()
	)
	# The render scale button is a copy of the graphics button, placed right under it.
	_scale_button = quality_button.duplicate() as Button
	_scale_button.name = "RenderScaleButton"
	_scale_button.unique_name_in_owner = false
	quality_button.get_parent().add_child(_scale_button)
	quality_button.get_parent().move_child(_scale_button, quality_button.get_index() + 1)
	_refresh_scale_text()
	_scale_button.pressed.connect(
		func() -> void:
			Settings.cycle_render_scale()
			_refresh_scale_text()
	)
	_build_keybind_rows()
	%ResetKeysButton.pressed.connect(
		func() -> void:
			_cancel_rebind()
			Settings.reset_bindings()
	)
	Settings.bindings_changed.connect(_refresh_key_texts)
	_show_best_run()
	UiSounds.attach(self)
	play_button.grab_focus()


func _process(delta: float) -> void:
	# The title buzzes like a failing neon tube.
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(0.04, 0.12) if randf() < 0.4 else randf_range(1.5, 5.0)
		title_label.modulate.a = randf_range(0.25, 1.0) if _flicker_timer < 0.2 else 1.0


func _input(event: InputEvent) -> void:
	# While waiting for a key, take the next key press before anything else.
	if _waiting_action == "" or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_ESCAPE:
		_cancel_rebind()
		return
	var action := _waiting_action
	_waiting_action = ""
	Settings.rebind(action, code)
	keybind_hint.text = "%s  >  %s" % [_label_for(action), Settings.key_text(action)]
	keybind_hint.modulate = Color(0.45, 1.0, 0.55)
	_refresh_key_texts()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		settings_panel.visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		_hide_settings()


func _build_keybind_rows() -> void:
	for entry in Settings.REBINDABLE:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.text = entry[1]
		label.custom_minimum_size = Vector2(205.0, 0.0)
		label.theme_type_variation = &"SubtleLabel"
		label.add_theme_font_size_override("font_size", 15)
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(185.0, 38.0)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_begin_rebind.bind(entry[0]))
		row.add_child(button)
		keybind_list.add_child(row)
		_key_buttons[entry[0]] = button
	var extra := Label.new()
	extra.text = "LEFT CLICK: USE / THROW     ESC: PAUSE"
	extra.theme_type_variation = &"SubtleLabel"
	extra.add_theme_font_size_override("font_size", 13)
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keybind_list.add_child(extra)
	_refresh_key_texts()


func _refresh_key_texts() -> void:
	for action in _key_buttons:
		var button: Button = _key_buttons[action]
		button.text = "PRESS A KEY..." if action == _waiting_action else Settings.key_text(action)


func _label_for(action: String) -> String:
	for entry in Settings.REBINDABLE:
		if entry[0] == action:
			return entry[1]
	return action


func _begin_rebind(action: String) -> void:
	_waiting_action = action
	keybind_hint.text = "PRESS A NEW KEY FOR  %s" % _label_for(action)
	keybind_hint.modulate = Color(1.0, 0.8, 0.35)
	_refresh_key_texts()


func _cancel_rebind() -> void:
	_waiting_action = ""
	keybind_hint.text = "CLICK A KEY, THEN PRESS A NEW ONE  (ESC CANCELS)"
	keybind_hint.modulate = Color.WHITE
	_refresh_key_texts()


func _select_tab(index: int) -> void:
	_cancel_rebind()
	for tab_index in _tabs.size():
		_tabs[tab_index].set_pressed_no_signal(tab_index == index)
		_pages[tab_index].visible = tab_index == index


func _refresh_quality_text() -> void:
	quality_button.text = "GRAPHICS:  %s" % Settings.QUALITY_NAMES[Settings.quality]


func _refresh_scale_text() -> void:
	_scale_button.text = "RENDER SCALE:  %d%%" % roundi(Settings.RENDER_SCALES[Settings.render_scale_index] * 100.0)


func _show_best_run() -> void:
	if Settings.best_time <= 0:
		return
	subtitle_label.text += "\nBEST ESCAPE %02d:%02d   NOTES %d/8" % [
		floori(Settings.best_time / 60.0), Settings.best_time % 60, Settings.best_notes
	]


func _setup_slider(slider: HSlider, bus_name: String) -> void:
	slider.value = Settings.get_volume(bus_name) * 100.0
	slider.value_changed.connect(
		func(value: float) -> void: Settings.set_volume(bus_name, value / 100.0)
	)


func _play_game() -> void:
	if _starting:
		return
	_starting = true
	# The start sting plays while the screen sinks to black, then the game loads.
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.9)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _show_settings() -> void:
	main_buttons.visible = false
	title_label.visible = false
	subtitle_label.visible = false
	settings_panel.visible = true
	_select_tab(0)
	%AudioTab.grab_focus()


func _hide_settings() -> void:
	_cancel_rebind()
	settings_panel.visible = false
	title_label.visible = true
	subtitle_label.visible = true
	main_buttons.visible = true
	%SettingsButton.grab_focus()
