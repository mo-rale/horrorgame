extends Node3D

@onready var screeching: AudioStreamPlayer = $Screeching
@onready var enemy: Enemy = $Enemy
@onready var generator: Node3D = $Generator
@onready var game_over_screen: CanvasLayer = $GameOverScreen
@onready var restart_button: Button = %RestartButton
@onready var victory_screen: CanvasLayer = $VictoryScreen
@onready var play_again_button: Button = %PlayAgainButton
@onready var pause_screen: CanvasLayer = $PauseScreen
@onready var resume_button: Button = %ResumeButton
@onready var pause_master_slider: HSlider = %PauseMasterSlider
@onready var pause_music_slider: HSlider = %PauseMusicSlider
@onready var pause_sfx_slider: HSlider = %PauseSFXSlider
@onready var objective_label: Label = %ObjectiveLabel
@onready var fuel_label: Label = %FuelLabel
@onready var controls_label: Label = %ControlsLabel
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var game_ended := false
var player_paused := false

@export_group("Ending")
@export var victory_screen_delay := 4.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The controller must keep receiving R while paused, but gameplay children
	# must not inherit ALWAYS and continue moving behind an ending screen.
	for child in get_children():
		if child != game_over_screen and child != victory_screen and child != pause_screen:
			child.process_mode = Node.PROCESS_MODE_PAUSABLE

	randomize()
	Settings.apply_brightness(world_environment.environment)
	enemy.reached_player.connect(_on_enemy_reached_player)
	generator.generator_started.connect(_on_generator_started)
	generator.fuel_changed.connect(_on_fuel_changed)
	restart_button.pressed.connect(_restart_game)
	play_again_button.pressed.connect(_restart_game)
	resume_button.pressed.connect(_resume_game)
	%MainMenuButton.pressed.connect(_return_to_main_menu)
	%QuitButton.pressed.connect(get_tree().quit)
	%GameOverMenuButton.pressed.connect(_return_to_main_menu)
	%VictoryMenuButton.pressed.connect(_return_to_main_menu)
	_setup_volume_slider(pause_master_slider, "Master")
	_setup_volume_slider(pause_music_slider, "Music")
	_setup_volume_slider(pause_sfx_slider, "SFX")
	_on_fuel_changed(generator.get_current_fuel(), generator.get_required_fuel())
	_fade_controls_after_delay()
	start_random_screeches()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		not game_ended
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		_set_player_paused(not player_paused)
		return

	if (
		game_ended
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_R
	):
		_restart_game()


func _on_enemy_reached_player() -> void:
	if game_ended:
		return

	_finish_game(game_over_screen, restart_button)


func _on_generator_started() -> void:
	objective_label.text = "OBJECTIVE: GENERATOR STARTED"
	objective_label.modulate = Color(0.35, 1.0, 0.55)

	# Give the player time to see and hear the running generator before ending.
	await get_tree().create_timer(victory_screen_delay, false).timeout
	if game_ended:
		return

	_finish_game(victory_screen, play_again_button)


func _on_fuel_changed(current_fuel: int, required_fuel: int) -> void:
	fuel_label.text = "FUEL: %d / %d" % [current_fuel, required_fuel]

	if current_fuel <= 0:
		objective_label.text = "OBJECTIVE: FIND GAS CANS"
		fuel_label.modulate = Color(1.0, 0.3, 0.25)
	elif current_fuel < required_fuel:
		objective_label.text = "OBJECTIVE: BRING FUEL TO THE GENERATOR"
		fuel_label.modulate = Color(1.0, 0.8, 0.25)
	else:
		objective_label.text = "OBJECTIVE: START THE GENERATOR"
		fuel_label.modulate = Color(0.35, 1.0, 0.55)


func _fade_controls_after_delay() -> void:
	await get_tree().create_timer(10.0, false).timeout
	if game_ended:
		return

	var tween := controls_label.create_tween()
	tween.tween_property(controls_label, "modulate:a", 0.0, 2.0)


func _finish_game(screen: CanvasLayer, focus_button: Button) -> void:
	game_ended = true
	player_paused = false
	pause_screen.visible = false
	screeching.stop()
	screen.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	focus_button.grab_focus()


func _set_player_paused(paused: bool) -> void:
	player_paused = paused
	pause_screen.visible = paused
	get_tree().paused = paused
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	)

	if paused:
		resume_button.grab_focus()


func _resume_game() -> void:
	if player_paused and not game_ended:
		_set_player_paused(false)


func _setup_volume_slider(slider: HSlider, bus_name: String) -> void:
	slider.value = Settings.get_volume(bus_name) * 100.0
	slider.value_changed.connect(
		func(value: float) -> void: Settings.set_volume(bus_name, value / 100.0)
	)


func _return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _restart_game() -> void:
	if not game_ended:
		return

	get_tree().paused = false
	get_tree().reload_current_scene()

func start_random_screeches() -> void:
	while true:
		
		# Wait a random amount of time
		await get_tree().create_timer(randf_range(20.0, 90.0), false).timeout

		if game_ended:
			return

		if !screeching.playing:
			print("ABOUT TO PLAY: ",screeching)
			screeching.play()
