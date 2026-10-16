extends Node
# Run: Godot --path . res://tests/behavior_test.tscn -- <mode>
# Modes: warning | light | hide_seen | hide_unseen | patrol | noise
# Exercises the enemy behaviour rules inside the real level and prints results.

var main: Node
var enemy: Enemy
var player: Player
var mode := "warning"
var frame := 0
var caught := false
var stage := 0
var _shot_frame := -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	enemy = main.get_node_or_null("Enemy") as Enemy
	player = main.get_node_or_null("player") as Player
	if enemy == null or player == null or frame < 60:
		return
	if frame == 60:
		enemy.reached_player.connect(func() -> void: caught = true)
		# Keep the main controller from ending the run on a catch during the test.
		main.enemy.reached_player.disconnect(main._on_enemy_reached_player)
		player.controls_locked = true
		call("_setup_" + mode)
	if frame == _shot_frame:
		get_viewport().get_texture().get_image().save_png("user://hide_view.png")
	call("_step_" + mode)
	if frame > 900:
		print("[Behave] %s TIMEOUT stage=%d state=%d" % [mode, stage, enemy._state])
		get_tree().quit()


func _stage_enemy(offset: Vector3, state: int) -> void:
	enemy.global_position = player.global_position + offset
	enemy._enter_state(state)
	# DORMANT hides the enemy; bring it back so a chase can start.
	enemy.visible = true
	enemy._collision_shape.set_deferred("disabled", false)


# warning: a chase starts with a frozen warning beat
func _setup_warning() -> void:
	player.global_position = Vector3(0, 0.1, 52)
	_stage_enemy(Vector3(0, 1.45, -9), Enemy.State.DORMANT)
	enemy._start_chase("test hint")


func _step_warning() -> void:
	if frame == 62:
		print("[Behave] warning timer=%.2f vel=%s hint='%s' (want >0, zero, test hint)" % [enemy._warning_timer, enemy.velocity, enemy.last_catch_hint])
	if frame == 62 + 90:
		print("[Behave] after warning timer=%.2f speed=%.2f (want 0, >0)" % [enemy._warning_timer, enemy.velocity.length()])
		get_tree().quit()


# light: a lit flashlight aimed at a chasing enemy staggers it
func _setup_light() -> void:
	player.global_position = Vector3(0, 0.1, 52)
	player.rotation.y = 0.0
	player.is_flashlight_on = true
	player.light.visible = true
	_stage_enemy(Vector3(0, 1.45, -9), Enemy.State.DORMANT)
	enemy._start_chase("light test")
	enemy._warning_timer = 0.0


func _step_light() -> void:
	if frame % 20 == 0 and stage == 0:
		var to_enemy := enemy._eye.global_position - player.camera.global_position
		print("[Behave] light dbg: state=%d lit=%.2f dist=%.1f aimed=%.2f los_broken=%s" % [enemy._state, enemy._lit_time, to_enemy.length(), -player.camera.global_basis.z.dot(to_enemy.normalized()), enemy.is_line_of_sight_broken()])
	if enemy._stagger_timer > 0.0 and stage == 0:
		stage = 1
		print("[Behave] light: STAGGERED at frame %d (want yes)" % frame)
		get_tree().quit()


# hide_seen / hide_unseen: hiding while watched gets the locker opened
func _setup_hide_seen() -> void:
	_hide_setup(true)


func _setup_hide_unseen() -> void:
	_hide_setup(false)


func _hide_setup(seen: bool) -> void:
	var spot := get_tree().get_nodes_in_group("hide_spot")[0] as Node3D
	player.global_position = spot.exit_position()
	player.controls_locked = false
	if seen:
		_stage_enemy(Vector3(0, 1.45, 0) + spot.global_basis.z * 7.0, Enemy.State.DORMANT)
		enemy._start_chase("hide test")
		enemy._warning_timer = 0.0
		enemy.look_at(player.global_position * Vector3(1, 0, 1) + Vector3(0, enemy.global_position.y, 0), Vector3.UP)
	else:
		enemy.visible = false
	enemy.hide_open_chance_unseen = 0.0
	player.hide_in(spot)
	if not seen:
		_stage_enemy(Vector3(0, 1.45, 0) + spot.global_basis.z * 14.0, Enemy.State.DORMANT)
		enemy._start_chase("hide test")
		enemy._warning_timer = 0.0
		enemy._player_last_seen_position = spot.global_position + spot.global_basis.z * 4.0
	print("[Behave] %s: hidden=%s known=%s" % [mode, player.is_hidden, enemy._hidden_known])
	_shot_frame = frame + 4


func _step_hide_seen() -> void:
	if caught:
		print("[Behave] hide_seen: locker OPENED hint='%s' (want opened)" % enemy.last_catch_hint)
		get_tree().quit()


func _step_hide_unseen() -> void:
	if caught:
		print("[Behave] hide_unseen: OPENED (unexpected)")
		get_tree().quit()
	if enemy._state == Enemy.State.SEARCHING and stage == 0:
		stage = 1
		print("[Behave] hide_unseen: gave up and searched (want yes), hidden=%s" % player.is_hidden)
		get_tree().quit()


# patrol: phase 2 makes it walk the plant in the open
func _setup_patrol() -> void:
	player.global_position = Vector3(0, 0.1, 52)
	enemy.set_phase(2)
	enemy._start_patrol()


func _step_patrol() -> void:
	if frame == 64:
		print("[Behave] patrol: state=%d visible=%s timer=%.1f pos=%s (want ROAMING=2, true)" % [enemy._state, enemy.visible, enemy._patrol_timer, enemy.global_position])
	if frame in [70, 100]:
		print("[Behave] patrol dbg: vel=%s target=%s finished=%s next=%s speed=%.2f state=%d" % [enemy.velocity, enemy.navigation_agent.target_position, enemy.navigation_agent.is_navigation_finished(), enemy.navigation_agent.get_next_path_position(), enemy._current_speed, enemy._state])
	if frame == 64 + 120:
		print("[Behave] patrol: moved to %s" % enemy.global_position)
		get_tree().quit()


# noise: footsteps shorten the dormant cooldown
func _setup_noise() -> void:
	enemy._enter_state(Enemy.State.DORMANT)
	enemy._stalking_cooldown = 60.0
	for i in 10:
		enemy.hear_noise(player.global_position, 14.0)
	print("[Behave] noise: cooldown 60 -> %.1f after ten sprint steps (want ~54.4)" % enemy._stalking_cooldown)
	get_tree().quit()


func _step_noise() -> void:
	pass
