extends Node3D

const LIGHT_SWITCH_SFX := preload("res://assets/sfx/effects/light_switch.mp3")
const GATE_OPEN_SFX := preload("res://assets/sfx/effects/gate_open.mp3")
const JUMPSCARE_SFX := preload("res://assets/sfx/ambience/freesound_community-jumpscare-68730.mp3")

var _jumpscare_running := false

@onready var screeching: AudioStreamPlayer = $Screeching
@onready var enemy: Enemy = $Enemy
@onready var player: Player = $player
@onready var generator: Node3D = $Generator
@onready var navigation_region: NavigationRegion3D = $LevelMap/NavigationRegion3D
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
@onready var pressure_label: Label = %PressureLabel
@onready var fuse_label: Label = %FuseLabel
@onready var fuel_label: Label = %FuelLabel
@onready var controls_label: Label = %ControlsLabel
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var factory_gate: CSGBox3D = $LevelMap/factorygate
@onready var factory_lights: Node3D = $LevelMap/lights
@onready var victory_area: Area3D = $LevelMap/VictoryArea

var game_ended := false
var player_paused := false
var generator_powered := false
@onready var _level_map: Node3D = $LevelMap

@export_group("Intro")
@export var play_intro := true

var _intro_layer: CanvasLayer
var _intro_black: ColorRect
var _intro_label: Label
var _intro_skipped := false

@export_group("Ending")
@export var factory_power_start_delay := 1.0
@export var light_activation_interval_min := 1.0
@export var light_activation_interval_max := 2.0
@export var factory_gate_open_delay := 2.0
@export var factory_gate_open_height := 6.0
@export var factory_gate_open_duration := 7.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The controller must keep receiving R while paused, but gameplay children
	# must not inherit ALWAYS and continue moving behind an ending screen.
	for child in get_children():
		if child != game_over_screen and child != victory_screen and child != pause_screen:
			child.process_mode = Node.PROCESS_MODE_PAUSABLE

	randomize()
	var post_fx := CanvasLayer.new()
	post_fx.set_script(preload("res://scripts/post_fx.gd"))
	post_fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(post_fx)
	if play_intro:
		_build_intro_overlay()
	factory_lights.visible = true
	for child in factory_lights.get_children():
		if child is Light3D:
			child.visible = false
	victory_area.monitoring = false
	_rebuild_level_and_randomize_pickups()
	Settings.apply_brightness(world_environment.environment)
	enemy.reached_player.connect(_on_enemy_reached_player)
	generator.generator_started.connect(_on_generator_started)
	generator.fuel_changed.connect(_on_fuel_changed)
	generator.fuse_changed.connect(_on_fuse_changed)
	generator.pressure_changed.connect(_on_pressure_changed)
	victory_area.body_entered.connect(_on_victory_area_body_entered)
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
	_on_pressure_changed(
		generator.get_current_pressure_valves(),
		generator.get_required_pressure_valves()
	)
	_fade_controls_after_delay()
	start_random_screeches()


func _rebuild_level_and_randomize_pickups() -> void:
	enemy.set_physics_process(false)
	player.set_physics_process(false)

	var navigation_map := navigation_region.get_navigation_map()
	var previous_iteration := NavigationServer3D.map_get_iteration_id(navigation_map)
	var legacy_map := get_node_or_null("NavigationRegion3D")
	if legacy_map:
		legacy_map.queue_free()
	var pickup_spawn_points: Array[Marker3D] = _level_map.rebuild(navigation_region)

	player.global_position = _level_map.player_spawn
	player.velocity = Vector3.ZERO
	enemy.global_position = _level_map.enemy_spawn
	enemy.velocity = Vector3.ZERO
	generator.global_position = _level_map.generator_spawn
	_freeze_pickups()

	# NavigationServer applies a freshly baked map on the following sync.
	# Gameplay begins after that update so the enemy never uses the old map.
	_enable_level_after_navigation_sync(pickup_spawn_points, previous_iteration)


func _enable_level_after_navigation_sync(
	pickup_spawn_points: Array[Marker3D],
	previous_iteration: int
) -> void:
	var navigation_map := navigation_region.get_navigation_map()
	var navigation_mesh := navigation_region.navigation_mesh
	# CSG geometry finishes its collision/mesh update after entering the tree.
	# Baking before this frame can produce an empty navigation mesh.
	# On some launches the CSG meshes are not ready on the very first physics
	# frame and the bake returns an empty mesh, so give them a few frames and
	# re-bake below if the result is still empty.
	for _warmup in 3:
		await get_tree().physics_frame
	await get_tree().process_frame
	navigation_region.set_navigation_map(get_world_3d().get_navigation_map())
	navigation_map = navigation_region.get_navigation_map()
	navigation_region.bake_navigation_mesh(false)
	var wait_frames := 0
	var closest_owner := RID()
	while wait_frames < 120:
		await get_tree().physics_frame
		wait_frames += 1
		if navigation_mesh.get_polygon_count() == 0 and wait_frames % 10 == 0:
			navigation_region.bake_navigation_mesh(false)
		var current_iteration := NavigationServer3D.map_get_iteration_id(
			navigation_map
		)
		if (
			navigation_mesh.get_polygon_count() == 0
			or current_iteration == 0
			or current_iteration <= previous_iteration
		):
			continue
		closest_owner = NavigationServer3D.map_get_closest_point_owner(
			navigation_map,
			enemy.global_position
		)
		if closest_owner.is_valid():
			break

	# A region can finish baking before its RID update reaches the map. Force
	# one clean re-registration, then wait for a real queryable point.
	if not closest_owner.is_valid() and navigation_mesh.get_polygon_count() > 0:
		var refresh_iteration := NavigationServer3D.map_get_iteration_id(
			navigation_map
		)
		navigation_region.enabled = false
		await get_tree().physics_frame
		navigation_region.enabled = true
		for _retry in 30:
			await get_tree().physics_frame
			wait_frames += 1
			var current_iteration := NavigationServer3D.map_get_iteration_id(
				navigation_map
			)
			if current_iteration == 0 or current_iteration <= refresh_iteration:
				continue
			closest_owner = NavigationServer3D.map_get_closest_point_owner(
				navigation_map,
				enemy.global_position
			)
			if closest_owner.is_valid():
				break

	if game_ended:
		return
	if navigation_mesh.get_polygon_count() == 0:
		push_error("Level navigation bake produced no polygons; enemy cannot move")
	elif not closest_owner.is_valid():
		push_error("Level navigation region did not register on the world map")
	else:
		enemy.reset_after_navigation_rebuild()
	_randomize_pickup_spawns(pickup_spawn_points)
	player.set_physics_process(true)
	if play_intro:
		# The enemy stays frozen until the intro hands control to the player.
		_play_intro()
	else:
		enemy.set_physics_process(true)
	print(
		"[Map] Navigation ready with %d polygons after %d frames"
		% [navigation_mesh.get_polygon_count(), wait_frames]
	)
	print("[Map] Gas cans and fuses randomized across safe spawn points")


func _build_intro_overlay() -> void:
	player.controls_locked = true
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 50
	_intro_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_intro_layer)

	_intro_black = ColorRect.new()
	_intro_black.color = Color.BLACK
	_intro_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(_intro_black)

	_intro_label = Label.new()
	_intro_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_label.add_theme_font_size_override("font_size", 28)
	_intro_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_intro_label.modulate.a = 0.0
	_intro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(_intro_label)


func _intro_wait(seconds: float) -> void:
	if _intro_skipped:
		return
	await get_tree().create_timer(seconds, false).timeout


func _intro_line(text: String, hold: float) -> void:
	if _intro_skipped:
		return
	_intro_label.text = text
	var tween := _intro_label.create_tween()
	tween.tween_property(_intro_label, "modulate:a", 1.0, 1.0)
	await tween.finished
	await _intro_wait(hold)
	if _intro_skipped:
		return
	tween = _intro_label.create_tween()
	tween.tween_property(_intro_label, "modulate:a", 0.0, 1.0)
	await tween.finished


func _play_intro() -> void:
	var camera := player.camera
	# Wake up on the floor: looking at the ceiling, tilted, then rise.
	camera.rotation = Vector3(deg_to_rad(75.0), 0.0, deg_to_rad(18.0))

	await _intro_wait(0.8)
	await _intro_line("Halverson Works went dark at 2:07 AM.", 1.8)
	await _intro_line("Fourteen night-shift workers. Nobody answers the radio.", 2.0)
	await _intro_line("Restore power. Release the gate seal. Get out.", 1.8)

	if not _intro_skipped:
		var rise := camera.create_tween().set_parallel(true)
		rise.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		rise.tween_property(camera, "rotation:x", 0.0, 3.0)
		rise.tween_property(camera, "rotation:z", 0.0, 3.0)
		var fade := _intro_black.create_tween()
		fade.tween_property(_intro_black, "modulate:a", 0.0, 2.5)
		await rise.finished
	_finish_intro()


func _finish_intro() -> void:
	if not is_instance_valid(_intro_layer):
		return
	player.camera.rotation = Vector3.ZERO
	player.pitch = 0.0
	player.controls_locked = false
	_intro_layer.queue_free()
	_intro_layer = null
	if not game_ended:
		enemy.set_physics_process(true)


func _skip_intro() -> void:
	if _intro_skipped or _intro_layer == null:
		return
	_intro_skipped = true
	_intro_black.modulate.a = 0.0
	_intro_label.modulate.a = 0.0
	_finish_intro()


func _freeze_pickups() -> void:
	for group_name in ["gas_can", "fuse"]:
		for node in get_tree().get_nodes_in_group(group_name):
			var pickup := node as RigidBody3D
			pickup.freeze = true
			pickup.linear_velocity = Vector3.ZERO
			pickup.angular_velocity = Vector3.ZERO


func _randomize_pickup_spawns(spawn_points: Array[Marker3D]) -> void:
	var pickups := get_tree().get_nodes_in_group("gas_can")
	pickups.append_array(get_tree().get_nodes_in_group("fuse"))
	var available_spawns: Array[Marker3D] = []
	var navigation_map := navigation_region.get_navigation_map()
	for spawn_point in spawn_points:
		var path := NavigationServer3D.map_get_path(
			navigation_map,
			generator.global_position,
			spawn_point.global_position,
			true
		)
		if not path.is_empty():
			available_spawns.append(spawn_point)

	if available_spawns.size() < pickups.size():
		push_warning(
			"Only %d connected pickup spawns were found; using the authored safe list"
			% available_spawns.size()
		)
		available_spawns = spawn_points.duplicate()
	available_spawns.shuffle()

	# Fuses were hidden by the electrician in fuse spawns; fuel is kept in the
	# plant's gas spawns. Any shortfall falls back to whatever spawn is left.
	var assigned: Array[Marker3D] = []
	var used := {}
	for pickup in pickups:
		var wanted_group := &"fuse_spawn" if pickup.is_in_group("fuse") else &"gas_spawn"
		var chosen: Marker3D = null
		for spawn_point in available_spawns:
			if not used.has(spawn_point) and spawn_point.is_in_group(wanted_group):
				chosen = spawn_point
				break
		if chosen == null:
			for spawn_point in available_spawns:
				if not used.has(spawn_point):
					chosen = spawn_point
					break
		if chosen != null:
			used[chosen] = true
		assigned.append(chosen)

	for index in pickups.size():
		var pickup := pickups[index] as RigidBody3D
		var spawn_point := assigned[index]
		if spawn_point == null:
			continue
		pickup.freeze = true
		pickup.linear_velocity = Vector3.ZERO
		pickup.angular_velocity = Vector3.ZERO
		pickup.global_position = spawn_point.global_position
		pickup.rotation = Vector3(0.0, randf_range(0.0, TAU), 0.0)
		pickup.freeze = false
		print("[Map] %s spawned at %s" % [pickup.name, pickup.global_position])


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		_intro_layer != null
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)
	):
		_skip_intro()
		return

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
	if game_ended or _jumpscare_running:
		return

	_play_jumpscare()


func _play_jumpscare() -> void:
	_jumpscare_running = true
	player.controls_locked = true
	player.velocity = Vector3.ZERO
	player.stop_stalking_heartbeat()
	screeching.stop()
	enemy.set_physics_process(false)
	enemy.visible = true
	enemy.stop_all_sounds()

	# Snap the view onto the enemy's face and slam it into the camera.
	var to_enemy := enemy.global_position - player.global_position
	to_enemy.y = 0.0
	if to_enemy.length() < 0.01:
		to_enemy = -player.global_basis.z
	var direction := to_enemy.normalized()
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.camera.rotation = Vector3(deg_to_rad(18.0), 0.0, 0.0)
	var start_position := player.global_position + direction * 2.4
	start_position.y = enemy.global_position.y
	var end_position := player.global_position + direction * 0.85
	end_position.y = enemy.global_position.y
	enemy.global_position = start_position
	enemy.look_at(
		Vector3(player.global_position.x, enemy.global_position.y, player.global_position.z),
		Vector3.UP
	)

	var scream := AudioStreamPlayer.new()
	scream.stream = JUMPSCARE_SFX
	scream.bus = &"SFX"
	scream.volume_db = 4.0
	add_child(scream)
	scream.play()

	var flash := ColorRect.new()
	flash.color = Color(0.8, 0.0, 0.0, 0.85)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 60
	flash_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	flash_layer.add_child(flash)
	add_child(flash_layer)

	player.add_trauma(1.0)
	get_tree().call_group("post_fx", "set_anxiety", 1.0)

	var lunge := enemy.create_tween().set_parallel(true)
	lunge.tween_property(enemy, "global_position", end_position, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	lunge.tween_property(player.camera, "fov", 105.0, 0.12)
	var fade := flash.create_tween()
	fade.tween_property(flash, "color:a", 0.0, 0.45)

	# Keep shaking and screaming for a beat before the game over screen.
	for _i in 6:
		player.add_trauma(0.5)
		await get_tree().create_timer(0.2, false).timeout
	flash_layer.queue_free()
	scream.queue_free()
	_finish_game(game_over_screen, restart_button)


func _on_generator_started() -> void:
	if generator_powered or game_ended:
		return

	generator_powered = true
	objective_label.text = "OBJECTIVE: FACTORY POWER STARTING..."
	objective_label.modulate = Color(0.35, 1.0, 0.55)
	fuel_label.text = "POWER RESTORED"
	fuel_label.modulate = Color(0.35, 1.0, 0.55)
	fuse_label.text = "FUSES ONLINE"
	fuse_label.modulate = Color(0.35, 1.0, 0.55)
	pressure_label.text = "PRESSURE ONLINE"
	pressure_label.modulate = Color(0.35, 1.0, 0.55)
	_run_factory_power_sequence()


func _run_factory_power_sequence() -> void:
	await get_tree().create_timer(factory_power_start_delay, false).timeout
	if game_ended:
		return

	# The enemy is gone before the first powered light becomes visible.
	enemy.disable_permanently()
	var lights: Array[Light3D] = []
	for child in factory_lights.get_children():
		if child is Light3D:
			lights.append(child)

	for index in lights.size():
		var factory_light := lights[index]
		factory_light.visible = true
		_play_factory_sfx(LIGHT_SWITCH_SFX, factory_light.global_position)
		print("[Factory] Light %d/%d switched on" % [index + 1, lights.size()])
		if index < lights.size() - 1:
			await get_tree().create_timer(
				randf_range(
					light_activation_interval_min,
					maxf(light_activation_interval_max, light_activation_interval_min)
				),
				false
			).timeout
			if game_ended:
				return

	await get_tree().create_timer(factory_gate_open_delay, false).timeout
	if game_ended:
		return

	_play_factory_sfx(GATE_OPEN_SFX, factory_gate.global_position)
	objective_label.text = "OBJECTIVE: ESCAPE THROUGH THE FACTORY GATE"

	var gate_tween := factory_gate.create_tween()
	gate_tween.set_trans(Tween.TRANS_LINEAR)
	gate_tween.set_ease(Tween.EASE_IN_OUT)
	gate_tween.tween_property(
		factory_gate,
		"position:y",
		factory_gate.position.y + factory_gate_open_height,
		factory_gate_open_duration
	)
	print("[Factory] All lights on — gate opening")
	await gate_tween.finished
	if game_ended:
		return
	victory_area.set_deferred("monitoring", true)
	print("[Factory] Gate open — victory area enabled")


func _play_factory_sfx(stream: AudioStream, world_position: Vector3) -> void:
	var audio_player := AudioStreamPlayer3D.new()
	audio_player.stream = stream
	audio_player.bus = &"SFX"
	audio_player.max_distance = 45.0
	add_child(audio_player)
	audio_player.global_position = world_position
	audio_player.finished.connect(audio_player.queue_free)
	audio_player.play()


func _on_victory_area_body_entered(body: Node3D) -> void:
	if game_ended or not generator_powered or body != player:
		return

	print("[Factory] Player reached the powered exit")
	_finish_game(victory_screen, play_again_button)


func _on_fuel_changed(current_fuel: int, required_fuel: int) -> void:
	fuel_label.text = "FUEL: %d / %d" % [current_fuel, required_fuel]
	if generator.get_current_pressure_valves() < generator.get_required_pressure_valves():
		return
	if generator.get_current_fuses() < generator.get_required_fuses():
		return

	if current_fuel <= 0:
		objective_label.text = "OBJECTIVE: FIND GAS CANS"
		fuel_label.modulate = Color(1.0, 0.3, 0.25)
	elif current_fuel < required_fuel:
		objective_label.text = "OBJECTIVE: BRING FUEL TO THE GENERATOR"
		fuel_label.modulate = Color(1.0, 0.8, 0.25)
	else:
		objective_label.text = "OBJECTIVE: START THE GENERATOR"
		fuel_label.modulate = Color(0.35, 1.0, 0.55)


func _on_fuse_changed(current_fuses: int, required_fuses: int) -> void:
	fuse_label.text = "FUSES: %d / %d" % [current_fuses, required_fuses]
	if generator.get_current_pressure_valves() < generator.get_required_pressure_valves():
		return
	if current_fuses < required_fuses:
		objective_label.text = "OBJECTIVE: FIND THE FUSES AND PUT THEM IN THE FUSE BOX"
		fuse_label.modulate = Color(1.0, 0.3, 0.25) if current_fuses == 0 else Color(1.0, 0.8, 0.25)
	else:
		fuse_label.modulate = Color(0.35, 1.0, 0.55)
		_on_fuel_changed(generator.get_current_fuel(), generator.get_required_fuel())


func _on_pressure_changed(current_valves: int, required_valves: int) -> void:
	pressure_label.text = "PRESSURE VALVES: %d / %d" % [current_valves, required_valves]
	if current_valves < required_valves:
		objective_label.text = "OBJECTIVE: CLOSE THE LEAKING PRESSURE VALVES"
		pressure_label.modulate = Color(1.0, 0.3, 0.25) if current_valves == 0 else Color(1.0, 0.8, 0.25)
	else:
		pressure_label.modulate = Color(0.35, 1.0, 0.55)
		_on_fuse_changed(generator.get_current_fuses(), generator.get_required_fuses())


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
