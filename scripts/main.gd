extends Node3D

const LIGHT_SWITCH_SFX := preload("res://assets/sfx/effects/light_switch.mp3")
const GATE_OPEN_SFX := preload("res://assets/sfx/effects/gate_open.mp3")
const UiSounds := preload("res://scripts/ui_sounds.gd")
const INTRO_RAIN_SFX := preload("res://assets/sfx/menu/rain_loop.ogg")
const RADIO_STATIC_SFX := preload("res://assets/sfx/intro/radio_static.wav")
const RADIO_OPEN_SFX := preload("res://assets/sfx/intro/radio_open.wav")
const RADIO_LOST_SFX := preload("res://assets/sfx/intro/radio_lost.wav")
const DOOR_SLAM_SFX := preload("res://assets/sfx/ending/gate_close.ogg")
const DISTANT_CLANG_SFX := preload("res://assets/sfx/valve/metal_slam.ogg")
const JUMPSCARE_FACE_DISTANCE := 0.72
## When the punch lands, in seconds after the catch (matches the jumpscare clip in
## tools/build_enemy_animations.gd), and when the screen is gone after it.
const JUMPSCARE_HIT_TIME := 0.89
const JUMPSCARE_END_TIME := 1.55
const JUMPSCARE_SFX := preload("res://assets/sfx/ambience/freesound_community-jumpscare-68730.mp3")

var _jumpscare_running := false
var _run_started_msec := 0
var _ui_sounds: Node

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
var _intro_speaker: Label
var _intro_audio := {}
var _intro_start_yaw := 0.0
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
	play_intro = play_intro and not Settings.skip_intro
	_run_started_msec = Time.get_ticks_msec()
	load("res://scripts/story_note.gd").notes_read.clear()
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
	Settings.apply_quality(world_environment.environment)
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
	_ui_sounds = UiSounds.attach(self)
	_refresh_controls_hint()
	Settings.bindings_changed.connect(_refresh_controls_hint)
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
	# The level ships with a pre-baked mesh (tools/bake_navmesh.gd). Only bake at
	# runtime if it is missing, since runtime baking logs a performance warning.
	if navigation_mesh.get_polygon_count() == 0:
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
		_lock_entrance_door()
		enemy.set_physics_process(true)
	print(
		"[Map] Navigation ready with %d polygons after %d frames"
		% [navigation_mesh.get_polygon_count(), wait_frames]
	)
	print("[Map] Gas cans and fuses randomized across safe spawn points")


func _build_intro_overlay() -> void:
	player.controls_locked = true
	$ObjectiveHUD.visible = false
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 50
	_intro_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_intro_layer)

	_intro_black = ColorRect.new()
	_intro_black.color = Color.BLACK
	_intro_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(_intro_black)

	# Letterbox bars slide away when the scene begins.
	for index in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.name = "Bar%d" % index
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if index == 0:
			bar.anchor_bottom = 0.0
			bar.offset_bottom = 70.0
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -70.0
		_intro_layer.add_child(bar)

	# A permanent skip prompt, so nobody has to guess the key.
	var skip_hint := Label.new()
	skip_hint.text = "[SPACE]  SKIP"
	skip_hint.anchor_left = 1.0
	skip_hint.anchor_right = 1.0
	skip_hint.anchor_top = 1.0
	skip_hint.anchor_bottom = 1.0
	skip_hint.offset_left = -240.0
	skip_hint.offset_right = -28.0
	skip_hint.offset_top = -52.0
	skip_hint.offset_bottom = -22.0
	skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skip_hint.add_theme_font_size_override("font_size", 15)
	skip_hint.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6, 0.85))
	skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(skip_hint)

	_intro_speaker = Label.new()
	_intro_speaker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_speaker.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_intro_speaker.offset_bottom = -170.0
	_intro_speaker.add_theme_font_size_override("font_size", 14)
	_intro_speaker.add_theme_color_override("font_color", Color(0.78, 0.2, 0.16))
	_intro_speaker.modulate.a = 0.0
	_intro_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(_intro_speaker)

	_intro_label = Label.new()
	_intro_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_intro_label.offset_bottom = -110.0
	_intro_label.offset_left = 120.0
	_intro_label.offset_right = -120.0
	_intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_label.add_theme_font_size_override("font_size", 26)
	_intro_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.78))
	_intro_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_intro_label.add_theme_constant_override("outline_size", 4)
	_intro_label.modulate.a = 0.0
	_intro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(_intro_label)

	# The audio for the scene: rain on the roof and the radio.
	_intro_audio["rain"] = _make_intro_player(INTRO_RAIN_SFX, -20.0)
	_intro_audio["static"] = _make_intro_player(RADIO_STATIC_SFX, -8.0)
	_intro_audio["open"] = _make_intro_player(RADIO_OPEN_SFX, -6.0)
	_intro_audio["lost"] = _make_intro_player(RADIO_LOST_SFX, -6.0)
	_intro_audio["slam"] = _make_intro_player(DOOR_SLAM_SFX, 2.0)
	_intro_audio["clang"] = _make_intro_player(DISTANT_CLANG_SFX, -9.0)


func _make_intro_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = stream == INTRO_RAIN_SFX
	audio.stream = stream
	audio.bus = &"SFX"
	audio.volume_db = volume_db
	audio.process_mode = Node.PROCESS_MODE_PAUSABLE
	_intro_layer.add_child(audio)
	return audio


func _intro_sound(sound_name: String) -> void:
	if not _intro_skipped and _intro_audio.has(sound_name):
		(_intro_audio[sound_name] as AudioStreamPlayer).play()


func _intro_wait(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0 and not _intro_skipped:
		await get_tree().process_frame
		remaining -= get_process_delta_time()


## One subtitle: fades in, holds, fades out. A speaker (e.g. DISPATCH) is shown
## above the line in red and is accompanied by the radio keying sound.
func _intro_line(text: String, hold: float, speaker := "") -> void:
	if _intro_skipped:
		return
	_intro_label.text = text
	_intro_speaker.text = speaker
	if speaker != "":
		_intro_sound("open")
		_intro_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.78))
	else:
		_intro_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.78))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_intro_label, "modulate:a", 1.0, 0.7)
	tween.tween_property(_intro_speaker, "modulate:a", 1.0 if speaker != "" else 0.0, 0.7)
	await tween.finished
	await _intro_wait(hold)
	if _intro_skipped:
		return
	tween = create_tween().set_parallel(true)
	tween.tween_property(_intro_label, "modulate:a", 0.0, 0.6)
	tween.tween_property(_intro_speaker, "modulate:a", 0.0, 0.6)
	await tween.finished


## Lightning outside the staff-entrance window: the room jumps in and out of
## the dark in a couple of white flashes.
func _intro_lightning(flashes := 2) -> void:
	var window := _level_map.get_node_or_null("Props/EntranceWindow")
	var material: StandardMaterial3D = null
	if window and window.get("material_override") is StandardMaterial3D:
		material = window.get("material_override") as StandardMaterial3D
	for _flash in flashes:
		if _intro_skipped:
			break
		if material:
			material.emission_energy_multiplier = 7.0
		await _intro_wait(0.07)
		if material:
			material.emission_energy_multiplier = 0.25
		await _intro_wait(0.12)


## The staff-entrance lamp turns red and stays red: the seal is engaged.
func _lock_entrance_door() -> void:
	var lamp := _level_map.get_node_or_null("Props/EntranceLamp")
	if lamp and lamp.get("material_override") is StandardMaterial3D:
		(lamp.get("material_override") as StandardMaterial3D).emission_energy_multiplier = 4.0
	var glow := _level_map.get_node_or_null("Props/EntranceLight") as OmniLight3D
	if glow:
		glow.light_energy = 1.4


func _play_intro() -> void:
	var camera := player.camera
	_intro_start_yaw = player.rotation.y
	var door := Vector3(7.0, 0.0, 57.5)
	var to_door := door - player.global_position
	var door_yaw := atan2(-to_door.x, -to_door.z)
	# Start looking down at your hands, a little unsteady.
	camera.rotation = Vector3(deg_to_rad(-28.0), 0.0, deg_to_rad(4.0))
	(_intro_audio["rain"] as AudioStreamPlayer).play()

	# 1. Black screen, the dispatcher on the radio: why you are here.
	await _intro_wait(1.2)
	_intro_sound("static")
	await _intro_wait(0.9)
	await _intro_line("Halverson Works has not answered the radio since 02:07 this morning.", 3.0, "DISPATCH")
	await _intro_line("Fourteen on the night shift. Boiler pressure alarms, then silence.", 3.0, "DISPATCH")
	await _intro_line("You are the nearest safety inspector. Go in, find out what happened.", 3.2, "DISPATCH")
	await _intro_line("Check in when you are through the main floor. Dispatch out.", 2.4, "DISPATCH")
	_intro_sound("static")
	await _intro_wait(0.7)

	# 2. Fade up on the lobby: you have just stepped in out of the storm.
	if not _intro_skipped:
		var open_up := create_tween().set_parallel(true)
		open_up.tween_property(_intro_black, "modulate:a", 0.0, 2.2)
		open_up.tween_property(camera, "rotation:x", 0.0, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		open_up.tween_property(camera, "rotation:z", 0.0, 2.6)
		for index in 2:
			var bar := _intro_layer.get_node("Bar%d" % index) as Control
			if index == 0:
				open_up.tween_property(bar, "offset_bottom", 0.0, 2.6)
			else:
				open_up.tween_property(bar, "offset_top", 0.0, 2.6)
		await _intro_wait(1.2)
	await _intro_line("04:52 AM. The staff entrance was unlocked.", 2.6)

	# 3. Look around, then a distant clang from deep inside the plant.
	if not _intro_skipped:
		var scan := create_tween()
		scan.tween_property(player, "rotation:y", _intro_start_yaw + 0.5, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		scan.tween_property(player, "rotation:y", _intro_start_yaw - 0.5, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await _intro_wait(2.3)
	_intro_sound("clang")
	await _intro_wait(1.0)
	await _intro_line("Something metal, far inside. Then nothing.", 2.4)

	# 4. The door slams and locks behind you; the lights flicker in the lightning.
	_intro_sound("slam")
	_lock_entrance_door()
	if not _intro_skipped:
		var whip := create_tween()
		whip.tween_property(player, "rotation:y", door_yaw, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		whip.parallel().tween_property(camera, "rotation:x", deg_to_rad(4.0), 0.55)
	await _intro_lightning(3)
	await _intro_wait(0.8)
	await _intro_line("The door sealed behind you. No handle on this side.", 3.0)

	# 5. The radio dies. You are on your own.
	_intro_sound("open")
	await _intro_line("Dispatch? Dispatch, I am inside. Do you copy?", 2.2, "YOU")
	_intro_sound("lost")
	await _intro_wait(1.6)
	await _intro_line("Only static. The power is out, so the seal engaged on its own.", 3.0)
	await _intro_line("Find out why the power failed. Find a way out.", 2.6)

	# 6. Turn back toward the plant and take control.
	if not _intro_skipped:
		var turn_back := create_tween()
		turn_back.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		turn_back.tween_property(player, "rotation:y", _intro_start_yaw, 1.6)
		turn_back.parallel().tween_property(camera, "rotation:x", 0.0, 1.6)
		await _intro_wait(1.6)
	_finish_intro()


func _finish_intro() -> void:
	if not is_instance_valid(_intro_layer):
		return
	player.camera.rotation = Vector3.ZERO
	player.rotation.y = _intro_start_yaw
	player.pitch = 0.0
	player.controls_locked = false
	$ObjectiveHUD.visible = true
	_lock_entrance_door()
	var window := _level_map.get_node_or_null("Props/EntranceWindow")
	if window and window.get("material_override") is StandardMaterial3D:
		(window.get("material_override") as StandardMaterial3D).emission_energy_multiplier = 0.25
	_intro_layer.queue_free()
	_intro_layer = null
	if not game_ended:
		enemy.set_physics_process(true)


func _skip_intro() -> void:
	if _intro_skipped or _intro_layer == null:
		return
	_intro_skipped = true
	for key in _intro_audio:
		(_intro_audio[key] as AudioStreamPlayer).stop()
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
	var hint_label := game_over_screen.get_node_or_null("CenterContainer/Content/Hint") as Label
	if hint_label and enemy.last_catch_hint != "":
		hint_label.text = enemy.last_catch_hint
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_label.custom_minimum_size = Vector2(560.0, 0.0)
	player.controls_locked = true
	player.velocity = Vector3.ZERO
	player.stop_stalking_heartbeat()
	screeching.stop()
	enemy.set_physics_process(false)
	enemy.visible = true
	enemy.stop_all_sounds()
	var model := enemy.get_node_or_null("Model")
	if model and model.has_method("play_jumpscare"):
		model.play_jumpscare()

	# Turn the player to face the enemy, then slam its face into the camera.
	var to_enemy := enemy.global_position - player.global_position
	to_enemy.y = 0.0
	if to_enemy.length() < 0.01:
		to_enemy = -player.global_basis.z
	var direction := to_enemy.normalized()
	player.rotation.y = atan2(-direction.x, -direction.z)
	var camera := player.camera
	camera.rotation = Vector3.ZERO
	var head := enemy.get_node_or_null("Model/Torso/Head") as Node3D

	# The face must end up level with the lens, so lower or raise the whole body
	# by the head's height above the enemy's origin (the model hovers a little).
	var head_height := 0.95
	if head:
		head_height = head.global_position.y - enemy.global_position.y
	var face_level_y := player.camera.global_position.y - head_height
	var start_position := player.global_position + direction * 2.4
	start_position.y = face_level_y
	enemy.global_position = start_position
	enemy.look_at(
		Vector3(player.global_position.x, enemy.global_position.y, player.global_position.z),
		Vector3.UP
	)
	# The head leans toward the player, so stop the body far enough back that the
	# face ends up about half a metre from the lens, filling the screen.
	var head_forward := 0.2
	if head:
		var offset := head.global_position - enemy.global_position
		offset.y = 0.0
		head_forward = maxf(offset.dot(-direction), 0.0)
	var end_position := player.global_position + direction * (JUMPSCARE_FACE_DISTANCE + head_forward)
	end_position.y = face_level_y
	_aim_camera_at_face(head)

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

	var lunge := create_tween().set_parallel(true)
	lunge.tween_method(
		func(progress: float) -> void:
			enemy.global_position = start_position.lerp(end_position, progress)
			_aim_camera_at_face(head),
		0.0, 1.0, 0.14
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	lunge.tween_property(camera, "fov", 82.0, 0.14)
	var fade := flash.create_tween()
	fade.tween_property(flash, "color:a", 0.0, 0.45)

	# Hold on the face, shaking and screaming, for a beat before game over.
	var elapsed := 0.0
	var next_shake := 0.0
	var hit := false
	var jolt := 0.0
	while elapsed < JUMPSCARE_END_TIME:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		_aim_camera_at_face(head)
		if not hit and elapsed >= JUMPSCARE_HIT_TIME:
			# The punch lands: the head snaps round, the screen flares and goes dark.
			hit = true
			jolt = 0.5
			player.add_trauma(1.0)
			var thud := AudioStreamPlayer.new()
			thud.stream = DISTANT_CLANG_SFX
			thud.bus = &"SFX"
			thud.volume_db = 3.0
			thud.pitch_scale = 0.6
			add_child(thud)
			thud.play()
			thud.finished.connect(thud.queue_free)
			flash.color = Color(0.9, 0.04, 0.03, 0.9)
			var knockout := flash.create_tween()
			knockout.tween_property(flash, "color", Color(0.0, 0.0, 0.0, 1.0), 0.5).set_ease(Tween.EASE_IN)
		if jolt > 0.0:
			# A sharp kick to the camera that dies away fast.
			player.camera.rotation += Vector3(-jolt * 0.5, jolt * 0.9, jolt * 0.6)
			jolt = maxf(0.0, jolt - delta * 2.4)
		if not hit and elapsed >= next_shake:
			player.add_trauma(0.5)
			next_shake += 0.2
	flash_layer.queue_free()
	scream.queue_free()
	_finish_game(game_over_screen, restart_button)


func _aim_camera_at_face(head: Node3D) -> void:
	# Keep the lens locked on the enemy's face (it sways and twitches).
	if head != null and is_instance_valid(head) and player.camera.is_inside_tree():
		player.camera.look_at(head.global_position, Vector3.UP)


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
	_start_ending()


func _start_ending() -> void:
	game_ended = true
	player.controls_locked = true
	var note_script: Script = load("res://scripts/story_note.gd")
	Engine.set_meta("run_stats", {
		"time": floori((Time.get_ticks_msec() - _run_started_msec) / 1000.0),
		"notes": note_script.notes_read.size(),
		"notes_total": $LevelMap/Notes.get_child_count(),
	})
	# Sink to black, then cut to the ending at the factory gate.
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 0)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	var layer := CanvasLayer.new()
	layer.layer = 200
	layer.add_child(cover)
	add_child(layer)
	var tween := cover.create_tween()
	tween.tween_property(cover, "color:a", 1.0, 1.4)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/ending.tscn")


func _on_fuel_changed(current_fuel: int, required_fuel: int) -> void:
	fuel_label.text = "FUEL: %d / %d" % [current_fuel, required_fuel]
	if current_fuel <= 0:
		fuel_label.modulate = Color(1.0, 0.3, 0.25)
	elif current_fuel < required_fuel:
		fuel_label.modulate = Color(1.0, 0.8, 0.25)
	else:
		fuel_label.modulate = Color(0.35, 1.0, 0.55)
	_refresh_objective()


func _refresh_objective() -> void:
	# Valves and fuses can be done in either order; fuel needs both.
	if generator_powered:
		return
	var valves_left: int = generator.get_required_pressure_valves() - generator.get_current_pressure_valves()
	var fuses_left: int = generator.get_required_fuses() - generator.get_current_fuses()
	if valves_left > 0 and fuses_left > 0:
		objective_label.text = "OBJECTIVE: CLOSE THE LEAKING VALVES AND POWER THE FUSE BOX"
	elif valves_left > 0:
		objective_label.text = "OBJECTIVE: CLOSE THE LEAKING PRESSURE VALVES"
	elif fuses_left > 0:
		objective_label.text = "OBJECTIVE: FIND THE FUSES AND PUT THEM IN THE FUSE BOX"
	else:
		var fuel: int = generator.get_current_fuel()
		if fuel <= 0:
			objective_label.text = "OBJECTIVE: FIND GAS CANS"
		elif fuel < generator.get_required_fuel():
			objective_label.text = "OBJECTIVE: BRING FUEL TO THE GENERATOR"
		else:
			objective_label.text = "OBJECTIVE: START THE GENERATOR"


func _update_enemy_progress() -> void:
	# The first valve or the first fuse wakes him; each finished task raises his phase.
	if generator.get_current_pressure_valves() >= 1 or generator.get_current_fuses() >= 1:
		enemy.awaken()
	var done := 0
	if generator.get_current_pressure_valves() >= generator.get_required_pressure_valves():
		done += 1
	if generator.get_current_fuses() >= generator.get_required_fuses():
		done += 1
	enemy.set_phase(1 + done)


func _on_fuse_changed(current_fuses: int, required_fuses: int) -> void:
	fuse_label.text = "FUSES: %d / %d" % [current_fuses, required_fuses]
	if current_fuses < required_fuses:
		fuse_label.modulate = Color(1.0, 0.3, 0.25) if current_fuses == 0 else Color(1.0, 0.8, 0.25)
	else:
		fuse_label.modulate = Color(0.35, 1.0, 0.55)
	_update_enemy_progress()
	_refresh_objective()


func _on_pressure_changed(current_valves: int, required_valves: int) -> void:
	pressure_label.text = "PRESSURE VALVES: %d / %d" % [current_valves, required_valves]
	if current_valves < required_valves:
		pressure_label.modulate = Color(1.0, 0.3, 0.25) if current_valves == 0 else Color(1.0, 0.8, 0.25)
	else:
		pressure_label.modulate = Color(0.35, 1.0, 0.55)
	_update_enemy_progress()
	_refresh_objective()


func _refresh_controls_hint() -> void:
	controls_label.text = (
		"%s%s%s%s Move   %s Sprint (uses stamina)   %s Crouch   %s Flashlight (battery drains, recharges when off)
"
		+ "%s Interact / Pick Up   LEFT CLICK Use / Throw   ESC Pause"
	) % [
		Settings.key_text("Forward"), Settings.key_text("Left"), Settings.key_text("Backward"),
		Settings.key_text("Right"), Settings.key_text("Sprint"), Settings.key_text("Crouch"),
		Settings.key_text("Flashlight"), Settings.key_text("Interact"),
	]


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
	if paused != player_paused and _ui_sounds:
		_ui_sounds.play("pause_open" if paused else "pause_close")
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
			screeching.play()
