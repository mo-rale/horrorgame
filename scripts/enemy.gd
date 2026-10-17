extends CharacterBody3D
class_name Enemy

# ── Signals ──────────────────────────────────────────────────────────────
signal reached_player

# ── States ───────────────────────────────────────────────────────────────
enum State { DORMANT, ROAMING, INVESTIGATING, STALKING, VANISHING, CHASING, SEARCHING }

var _state: State = State.DORMANT

# How a stalking encounter plays out. BEHIND hugs the player's back, FLANK
# paces beside them at the edge of vision, STATUE stands in plain sight far
# ahead and only creeps closer while nobody is looking at it.
enum StalkStyle { BEHIND, FLANK, STATUE }

var _stalk_style: StalkStyle = StalkStyle.BEHIND
var _flank_side := 1.0
var _statue_watch_time := 0.0
var _statue_frozen := false

# ── Tunables ─────────────────────────────────────────────────────────────
@export_group("Detection")
@export var max_spotting_distance := 50.0
@export var close_detection_distance := 3.0

@export_group("Roaming")
@export var roaming_speed := 2.0
@export var roam_radius := 15.0

@export_group("Investigating")
@export var investigating_speed := 3.5
@export var investigation_time := 6.0
@export var investigation_turn_speed := 0.8
@export var hearing_position_uncertainty := 2.0

@export_group("Stalking")
@export var stalking_speed := 5.5
@export var stalking_teleport_distance := 7.0
@export var stalking_min_teleport_distance := 5.0
@export var stalking_max_nav_snap_distance := 2.5
@export var stalking_blocked_retry_delay := 3.0
@export var stalking_path_update_delay := 0.5
@export var stalking_follow_distance := 3.5
@export var stalking_follow_max_nav_snap_distance := 3.0
@export var stalking_cooldown_time := 18.0
@export var initial_stalking_delay_min := 6.0
@export var initial_stalking_delay_max := 10.0
@export_range(-1.0, 1.0) var player_look_dot_threshold := 0.82
@export var stalking_footstep_volume_db := -12.0
@export var anxiety_rise_per_second := 8.0
@export_range(1.0, 99.0, 1.0) var anxiety_heartbeat_threshold := 55.0
@export var anxiety_rise_bonus_per_threat := 1.25
@export var seen_vanish_delay := 0.75
@export var vanish_hidden_time := 3.0
@export var vanish_reappear_distance_min := 30.0
@export var vanish_reappear_distance_max := 45.0
@export var vanish_max_nav_snap_distance := 4.0
@export var vanish_relocation_retry_delay := 1.0
@export var post_vanish_detection_grace := 5.0

@export_group("Chasing")
@export var chasing_speed := 8.2
@export var chase_max_time := 10.0
@export var catching_distance := 1.6
@export var update_path_delay := 0.2

@export_group("Threat Escalation")
@export_range(0, 8, 1) var max_threat_level := 4
@export var cooldown_reduction_per_level := 2.0
@export var minimum_stalking_cooldown := 9.0
@export var stalking_speed_bonus_per_level := 0.35
@export var stalking_distance_reduction_per_level := 0.3
@export var minimum_stalking_follow_distance := 2.0
@export var chase_speed_bonus_per_level := 0.4
@export var chase_time_bonus_per_level := 1.5

@export_group("Searching")
@export var searching_speed := 6.0
@export var search_time := 10.0
@export var search_radius := 10.0

@export_group("Wall Navigation")
@export var wall_steer_duration := 0.4
@export var wall_steer_strength := 1.25

@export_group("Footsteps")
@export var footstep_distance := 2.0  # meters between steps
@export var footstep_pitch_min := 0.9
@export var footstep_pitch_max := 1.1

# ── Movement state ───────────────────────────────────────────────────────
var _current_speed := 0.0
var _wall_steer_direction := Vector3.ZERO
var _wall_steer_timer := 0.0

# ── Footstep state ───────────────────────────────────────────────────────
var _distance_since_last_step := 0.0

# ── Investigation state ─────────────────────────────────────────────────
var _investigation_timer := 0.0
var _heard_position := Vector3.ZERO

# ── Stalking state ──────────────────────────────────────────────────────
var _stalking_path_timer := 0.0
var _stalking_cooldown := 0.0
var _stalking_follow_target := Vector3.ZERO
var _direct_path := PackedVector3Array()
var _direct_path_index := 0
var _anxiety_level := 0.0
var _heartbeat_active := false
var _stalking_encounters := 0
var _footstep_base_volume_db := 0.0
var _stalking_clearance_shape := CapsuleShape3D.new()
var _detection_grace_timer := 0.0
var _vanish_sequence_id := 0

# ── Dread behaviours ────────────────────────────────────────────────────
@export_group("Dread")
@export var anxiety_follow_distance_shrink := 0.45
@export var stalk_pause_interval_min := 3.0
@export var stalk_pause_interval_max := 7.0
@export var stalk_pause_duration_min := 1.2
@export var stalk_pause_duration_max := 2.6
@export var ambient_cue_interval_min := 14.0
@export var ambient_cue_interval_max := 32.0
@export var ambient_cue_distance_min := 14.0
@export var ambient_cue_distance_max := 24.0
@export var chase_lunge_distance := 6.0
@export var chase_lunge_multiplier := 1.25
@export var searching_whisper_interval := 4.0

@export_group("Stalk Styles")
@export var flank_distance := 6.5
@export var statue_spawn_distance := 14.0
@export var statue_creep_speed := 3.4
@export var statue_catch_distance := 2.2
@export var statue_max_watch_time := 9.0
## -1 picks randomly; 0 = behind, 1 = flank, 2 = statue (for testing).
@export_range(-1, 2) var forced_stalk_style := -1

@export_group("Behaviour Rules")
@export var chase_warning_time := 1.1
@export var hide_search_time := 2.6
@export var hide_open_chance_unseen := 0.2
@export var flashlight_stagger_time := 1.6
@export var flashlight_stagger_cooldown := 7.0
@export var patrol_duration_phase2 := 26.0
@export var patrol_duration_phase3 := 40.0

## It stays dormant until awaken() is called (the first pressure valve).
@export var wake_on_first_valve := true
@export var wake_delay_min := 10.0
@export var wake_delay_max := 16.0
var awakened := false

## Escalation: 1 = stalking only, 2 = valves closed (adds patrols),
## 3 = fuse box powered (shorter cooldowns, faster, more patrols).
var phase := 1
## Shown on the game over screen to explain what went wrong.
var last_catch_hint := ""

var _pending_hint := ""
var _warning_timer := 0.0
var _lit_time := 0.0
var _stagger_timer := 0.0
var _stagger_cooldown := 0.0
var _hidden_known := false
var _hide_wait := 0.0
var _waiting_at_hide := false
var _patrol_timer := 0.0
var _stalk_pause_timer := 0.0
var _next_stalk_pause := 0.0
var _ambient_cue_timer := 0.0
var _ambient_cue_running := false
var _search_whisper_timer := 0.0

# ── Chasing state ────────────────────────────────────────────────────────
var _chase_timer := 0.0
var _update_path_timer := 0.0
var _chase_path_failure_reported := false
var _catch_emitted := false
var _active_chasing_speed := 0.0

# ── Searching state ──────────────────────────────────────────────────────
var _search_timer := 0.0
var _player_last_seen_position: Vector3

# ── Navigation map sync ──────────────────────────────────────────────────
var _nav_map: RID
var _map_synchronized := false

# ── Node references ──────────────────────────────────────────────────────
@onready var navigation_agent: NavigationAgent3D = %NavigationAgent3D
@onready var player: Player = get_tree().get_first_node_in_group("player")
@onready var _eye: Node3D = %Eye
@onready var _eye_ray_cast: RayCast3D = %EyeRayCast
@onready var _footsteps: AudioStreamPlayer3D = $footsteps
@onready var _chasing: AudioStreamPlayer3D = $chasing
@onready var _stalking: AudioStreamPlayer3D = $stalking
@onready var _seen: AudioStreamPlayer3D = $seen
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var ray_cast_3d: RayCast3D = %EyeRayCast
@onready var generator: Node3D = get_tree().get_first_node_in_group("generator")

func _ready() -> void:
	randomize()
	add_to_group("enemy")
	visible = false
	_collision_shape.set_deferred("disabled", true)
	_footstep_base_volume_db = _footsteps.volume_db
	var enemy_capsule := _collision_shape.shape as CapsuleShape3D
	if enemy_capsule:
		_stalking_clearance_shape.radius = maxf(enemy_capsule.radius - 0.03, 0.1)
		_stalking_clearance_shape.height = maxf(enemy_capsule.height - 0.1, 0.2)
	awakened = not wake_on_first_valve
	_stalking_cooldown = randf_range(
		initial_stalking_delay_min,
		maxf(initial_stalking_delay_max, initial_stalking_delay_min)
	)
	if is_instance_valid(player):
		player.calm_pressed.connect(_on_player_calm_pressed)
		player.anxiety_calmed.connect(_on_player_anxiety_calmed)
	print("[Enemy] First stalking event scheduled in %.1f seconds" % _stalking_cooldown)
	_nav_map = get_world_3d().get_navigation_map()
	# The body origin floats above the navmesh; offset the agent's path so its
	# waypoints are reachable (otherwise it never advances past the first one).
	navigation_agent.path_height_offset = -_root_position_from_nav_point(Vector3.ZERO).y
	_sync_map_then_start_dormant()


func _sync_map_then_start_dormant() -> void:
	# Wait until the NavigationServer has actually finished building this
	# map at least once. A fixed frame-count wait is not reliable here;
	# map_get_iteration_id() is the engine's own ground truth for "ready".
	while NavigationServer3D.map_get_iteration_id(_nav_map) == 0:
		await get_tree().process_frame
	
	_map_synchronized = true
	_enter_state(State.DORMANT)


func reset_after_navigation_rebuild() -> void:
	# The level replaces its navigation region during startup. Clear any path
	# calculated from the old map, snap onto the rebuilt mesh, and create a
	# fresh dormant state so the next stalking event starts from clean data.
	_nav_map = get_world_3d().get_navigation_map()
	_map_synchronized = false
	velocity = Vector3.ZERO
	_wall_steer_timer = 0.0
	_wall_steer_direction = Vector3.ZERO

	var closest_owner := NavigationServer3D.map_get_closest_point_owner(
		_nav_map,
		global_position
	)
	if not closest_owner.is_valid():
		push_error("[Enemy] Rebuilt navigation map has no point near the enemy")
		return

	var nav_point := NavigationServer3D.map_get_closest_point(
		_nav_map,
		global_position
	)
	global_position = _root_position_from_nav_point(nav_point)
	navigation_agent.target_position = global_position
	_map_synchronized = true
	_enter_state(State.DORMANT)
	print("[Enemy] Navigation reset after level rebuild at ", global_position)


func disable_permanently() -> void:
	# Powering the factory ends all enemy activity, including any pending
	# stalking disappearance coroutine and the player's heartbeat warning.
	_vanish_sequence_id += 1
	_enter_state(State.DORMANT)
	_map_synchronized = false
	set_physics_process(false)
	if is_instance_valid(player):
		player.end_stalking_anxiety()
	print("[Enemy] DISABLED — factory power is on")


func _physics_process(delta: float) -> void:
	if not _map_synchronized:
		return
	# Until the first valve is turned the plant is quiet: no stalking, no cues.
	if not awakened:
		velocity = Vector3.ZERO
		return
	_stalking_cooldown = maxf(_stalking_cooldown - delta, 0.0)
	_detection_grace_timer = maxf(_detection_grace_timer - delta, 0.0)
	_stagger_cooldown = maxf(_stagger_cooldown - delta, 0.0)
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	_update_flashlight_reaction(delta)
	if (
		_stalking_cooldown <= 0.0
		and _state == State.DORMANT
	):
		_try_start_stalking()
	
	match _state:
		State.DORMANT:
			velocity = Vector3.ZERO
			_update_ambient_cues(delta)
			return
		State.ROAMING:
			_update_roaming(delta)
		State.INVESTIGATING:
			_update_investigating(delta)
		State.STALKING:
			_update_stalking(delta)
			if _state == State.STALKING and _update_stalk_pause(delta):
				return
			if _state == State.STALKING:
				var creep_speed := (
					stalking_speed + _threat_level() * stalking_speed_bonus_per_level
				)
				if _stalk_style == StalkStyle.STATUE:
					creep_speed = (
						statue_creep_speed
						+ _threat_level() * stalking_speed_bonus_per_level
					)
				_move_direct_path(delta, creep_speed, true)
			return
		State.VANISHING:
			velocity = Vector3.ZERO
			return
		State.CHASING:
			_update_chasing(delta)
			if _warning_timer > 0.0 or _waiting_at_hide:
				velocity = Vector3.ZERO
				return
			if _state == State.CHASING and not _catch_emitted:
				var lunge := 1.0
				if (
					is_instance_valid(player)
					and global_position.distance_to(player.global_position) < chase_lunge_distance
				):
					lunge = chase_lunge_multiplier
				var stagger := 0.12 if _stagger_timer > 0.0 else 1.0
				_move_direct_path(delta, _active_chasing_speed * lunge * stagger, false)
			return
		State.SEARCHING:
			_update_searching(delta)
	if _state == State.DORMANT:
		return
	
	_move_along_path(delta)


# ── State transition ─────────────────────────────────────────────────────

func _enter_state(new_state: State, data := {}) -> void:
	# VANISHING owns its complete hide/relocate/restore lifecycle. Ignore all
	# external transitions until that sequence safely returns to dormancy.
	if _state == State.VANISHING and new_state != State.DORMANT:
		print("[Enemy] State transition suppressed — stalker is vanishing")
		return

	# A chase must never begin while the stalker is still hidden or in the
	# middle of its disappearance sequence.
	if new_state == State.CHASING and (_state == State.VANISHING or not visible):
		print("[Enemy] CHASING suppressed — stalker is still vanishing")
		return

	# One-shot behavior sounds do not stop automatically when the state
	# changes. Clean them up so an old chase scream cannot leak into a
	# stalking disappearance.
	if _state == State.CHASING and new_state != State.CHASING:
		_end_chase_effects(new_state == State.SEARCHING)
	if new_state != State.CHASING:
		_chasing.stop()
	if new_state == State.VANISHING:
		_footsteps.stop()
		_stalking.stop()

	if _state == State.STALKING and new_state != State.STALKING:
		_stalking.stop()
		_direct_path.clear()
		_direct_path_index = 0
		_stalking_encounters += 1
		_stalking_cooldown = maxf(
			minimum_stalking_cooldown,
			stalking_cooldown_time - _threat_level() * cooldown_reduction_per_level
		) * [1.0, 0.75, 0.5][phase - 1]
		if is_instance_valid(player):
			player.end_stalking_anxiety()
	_state = new_state
	
	match _state:
		State.DORMANT:
			_stop_moving()
			_direct_path.clear()
			_direct_path_index = 0
			visible = false
			_collision_shape.set_deferred("disabled", true)
			_footsteps.stop()
			_stalking.stop()
			_chasing.stop()
			get_tree().call_group("post_fx", "set_anxiety", 0.0)
			if is_instance_valid(player):
				player.threat_proximity = 0.0
			print("[Enemy] DORMANT — hidden until the next stalking event")

		State.ROAMING:
			_travel_to_random_position()
			if _patrol_timer <= 0.0:
				_patrol_timer = 20.0

		State.INVESTIGATING:
			if not data.has("sound_position"):
				printerr(name + ": entered Investigating without sound_position.")
				_enter_state(State.DORMANT)
				return
			_heard_position = NavigationServer3D.map_get_closest_point(
				_nav_map,
				data["sound_position"]
			)
			_investigation_timer = investigation_time
			travel_to_position(_heard_position, investigating_speed)

		State.STALKING:
			if not data.has("teleport_position"):
				_stalking_cooldown = stalking_blocked_retry_delay
				_enter_state(State.DORMANT)
				return
			_stalking_path_timer = 0.0
			_statue_watch_time = 0.0
			_statue_frozen = false
			_stalk_pause_timer = 0.0
			_next_stalk_pause = randf_range(
				stalk_pause_interval_min,
				maxf(stalk_pause_interval_max, stalk_pause_interval_min)
			)
			_anxiety_level = 0.0
			_heartbeat_active = false
			player.start_stalking_anxiety()
			# Invalidate any older disappearance timer and always restore the
			# physical/visual state before beginning a new stalking cycle.
			_vanish_sequence_id += 1
			visible = true
			_collision_shape.set_deferred("disabled", false)
			_player_last_seen_position = player.global_position
			# Stalking starts as a supernatural appearance directly behind the
			# player. Following after this point still uses the navigation mesh.
			var stalking_teleport_position: Vector3 = data["teleport_position"]
			global_position = stalking_teleport_position
			_stalking_follow_target = stalking_teleport_position
			_update_stalking_follow_path()
			_face_player()
			print(
				"[Enemy] STALKING chosen (%s) — teleported to " % StalkStyle.keys()[_stalk_style],
				stalking_teleport_position
			)
			print("[Enemy] STALKING path waypoints: ", _direct_path.size())
			print("[Enemy] STALKER visibility restored: ", visible)
			print("[Enemy] THREAT LEVEL: ", _threat_level())
			velocity = Vector3.ZERO
			_play_stalking_sound()

		State.VANISHING:
			_stop_moving()
			_vanish_sequence_id += 1
			_delay_then_vanish(_vanish_sequence_id)
		
		State.CHASING:
			_active_chasing_speed = (
				chasing_speed
				+ _threat_level() * chase_speed_bonus_per_level
				+ (phase - 1) * 0.5
			)
			last_catch_hint = _pending_hint
			_warning_timer = chase_warning_time
			_waiting_at_hide = false
			_hide_wait = 0.0
			_stagger_timer = 0.0
			_chase_timer = (
				chase_max_time + _threat_level() * chase_time_bonus_per_level
			)
			_update_path_timer = update_path_delay
			_chase_path_failure_reported = false
			_catch_emitted = false
			_player_last_seen_position = player.global_position
			print(
				"[Enemy] CHASING started — player position: ",
				_player_last_seen_position
			)
			_update_chase_path()
			print("[Enemy] CHASING path waypoints: ", _direct_path.size())
			_play_scream_chase()
			if is_instance_valid(player):
				player.add_trauma(0.9)
			get_tree().call_group("post_fx", "set_anxiety", 1.0)
		
		State.SEARCHING:
			if data.has("player_last_seen_position"):
				_player_last_seen_position = data["player_last_seen_position"]
			else:
				printerr(name + ": entered Searching without player_last_seen_position.")
			_search_timer = search_time
			_go_to_position_around_last_seen()


# ── Per-state behavior ───────────────────────────────────────────────────

func _update_roaming(_delta: float) -> void:
	if navigation_agent.is_navigation_finished():
		_travel_to_random_position()

	_patrol_timer -= _delta
	if _patrol_timer <= 0.0:
		_enter_state(State.DORMANT)
		return

	if _detection_grace_timer <= 0.0 and is_player_in_view():
		_start_chase(
			"He was walking the plant and spotted you. Listen for his footsteps, "
			+ "and break line of sight or hide before he sees you."
		)


func _update_investigating(delta: float) -> void:
	if _detection_grace_timer <= 0.0 and is_player_in_view():
		_start_chase("You made noise and he came to look. Running and thrown things are loud.")
		return

	_investigation_timer -= delta
	if _investigation_timer <= 0.0:
		_enter_state(State.DORMANT)
		return

	# Stay near the source and look for the player until the investigation
	# timer expires. A newer sound can redirect us through hear_noise().
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		rotate_y(investigation_turn_speed * delta)


func _update_stalking(delta: float) -> void:
	_stalking_path_timer -= delta

	# A player hiding in a locker is invisible: it loses interest after a while.
	if is_instance_valid(player) and player.is_hidden:
		_hide_wait += delta
		if _hide_wait > 3.0 and not _hidden_known:
			print("[Enemy] STALKING player hidden - losing interest")
			_hide_wait = 0.0
			_enter_state(State.VANISHING)
		return
	_hide_wait = 0.0

	var distance_to_player := global_position.distance_to(player.global_position)
	var has_line_of_sight := (
		distance_to_player <= max_spotting_distance
		and not is_line_of_sight_broken()
	)

	var player_is_watching := has_line_of_sight and _is_player_looking_at_enemy()
	if _stalk_style == StalkStyle.STATUE:
		_update_statue(delta, player_is_watching, distance_to_player)
		if _state != State.STALKING:
			return
	elif player_is_watching:
		print(
			"[Enemy] STALKER SEEN — disappearing in %.2f seconds"
			% seen_vanish_delay
		)
		_enter_state(State.VANISHING)
		return

	_anxiety_level = minf(
		100.0,
		_anxiety_level + (
			anxiety_rise_per_second
			+ float(_threat_level()) * anxiety_rise_bonus_per_threat
		) * delta
	)
	player.update_stalking_anxiety(_anxiety_level, anxiety_heartbeat_threshold)
	if not _heartbeat_active and _anxiety_level >= anxiety_heartbeat_threshold:
		_heartbeat_active = true
		player.start_stalking_heartbeat()
		print("[Enemy] ANXIETY HIGH — heartbeat warning started")
	if _anxiety_level >= 100.0:
		print("[Enemy] ANXIETY MAXED — chase started")
		_start_chase("You let the dread build. When your heart pounds, calm yourself with the on-screen key.")
		return

	# The stalker continually follows the player's back. It can navigate
	# around obstacles, but being caught in view still makes it vanish.
	if _stalking_path_timer <= 0.0:
		_stalking_path_timer = stalking_path_update_delay
		_update_stalking_follow_path()


func _update_statue(delta: float, watched: bool, distance_to_player: float) -> void:
	_statue_frozen = watched
	if watched:
		# Meeting its stare only works for so long before it slips away.
		_statue_watch_time += delta
		if _statue_watch_time >= statue_max_watch_time:
			print("[Enemy] STATUE outstared — vanishing")
			_enter_state(State.VANISHING)
		return

	_statue_watch_time = maxf(_statue_watch_time - delta * 0.5, 0.0)
	if distance_to_player <= statue_catch_distance:
		print("[Enemy] STATUE reached the player — chase started")
		_start_chase("He only moves when you look away. Keep your eyes on him.")


func _update_stalk_pause(delta: float) -> bool:
	if _stalk_style == StalkStyle.STATUE:
		# Frozen solid while watched; no random pauses otherwise.
		if _statue_frozen:
			velocity = Vector3.ZERO
			move_and_slide()
			_face_player()
			return true
		return false

	# Now and then it stops dead and stares in total silence, then resumes.
	if _stalk_pause_timer > 0.0:
		_stalk_pause_timer -= delta
		velocity = Vector3.ZERO
		move_and_slide()
		_face_player()
		return true

	_next_stalk_pause -= delta
	if _next_stalk_pause <= 0.0:
		_next_stalk_pause = randf_range(
			stalk_pause_interval_min,
			maxf(stalk_pause_interval_max, stalk_pause_interval_min)
		)
		_stalk_pause_timer = randf_range(
			stalk_pause_duration_min,
			maxf(stalk_pause_duration_max, stalk_pause_duration_min)
		)
	return false


func _end_chase_effects(still_hunting: bool) -> void:
	get_tree().call_group("post_fx", "set_anxiety", 0.3 if still_hunting else 0.0)
	if is_instance_valid(player):
		player.threat_proximity = 0.0


func _update_ambient_cues(delta: float) -> void:
	# While hidden, the thing occasionally makes itself known from far away so
	# the player never feels alone: distant whispers or steps through the walls.
	if _ambient_cue_running or not is_instance_valid(player):
		return
	if _ambient_cue_timer <= 0.0:
		_ambient_cue_timer = randf_range(
			ambient_cue_interval_min,
			maxf(ambient_cue_interval_max, ambient_cue_interval_min)
		)
		return
	_ambient_cue_timer -= delta
	if _ambient_cue_timer > 0.0 or _stalking_cooldown < 4.0:
		return
	_play_ambient_cue()


func _play_ambient_cue() -> void:
	_ambient_cue_running = true
	var angle := randf() * TAU
	var distance := randf_range(
		ambient_cue_distance_min,
		maxf(ambient_cue_distance_max, ambient_cue_distance_min)
	)
	var requested := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	var nav_point := NavigationServer3D.map_get_closest_point(_nav_map, requested)
	global_position = _root_position_from_nav_point(nav_point)

	if randf() < 0.5:
		_play_stalking_sound()
	else:
		# A slow walk that never quite arrives.
		for step in 4:
			if _state != State.DORMANT or not is_inside_tree():
				break
			_footsteps.volume_db = _footstep_base_volume_db - 6.0
			_footsteps.pitch_scale = randf_range(0.85, 1.0)
			_footsteps.play()
			await get_tree().create_timer(randf_range(0.55, 0.8), false).timeout
			if _state != State.DORMANT:
				break
			var toward := (player.global_position - global_position)
			toward.y = 0.0
			global_position += toward.normalized() * 1.5
	_ambient_cue_running = false


func _on_player_calm_pressed(amount: float) -> void:
	if _state != State.STALKING:
		return
	_anxiety_level = maxf(_anxiety_level - amount, 0.0)
	player.update_stalking_anxiety(_anxiety_level, anxiety_heartbeat_threshold)
	print("[Enemy] CALM pressed — anxiety now %.0f%%" % _anxiety_level)


func _on_player_anxiety_calmed() -> void:
	if _state != State.STALKING:
		return
	print("[Enemy] ANXIETY SUPPRESSED — stalker withdrawing and restarting cooldown")
	_enter_state(State.DORMANT)


func _move_direct_path(delta: float, speed: float, face_player: bool) -> void:
	# Teleporting can leave NavigationAgent3D in a stale finished state. Both
	# stalking and chasing therefore follow fresh NavigationServer waypoints.
	_wall_steer_timer = maxf(_wall_steer_timer - delta, 0.0)
	while _direct_path_index < _direct_path.size():
		var waypoint := _direct_path[_direct_path_index]
		var waypoint_offset := waypoint - global_position
		waypoint_offset.y = 0.0
		if waypoint_offset.length() > 0.35:
			break
		_direct_path_index += 1

	if _direct_path_index >= _direct_path.size():
		velocity = Vector3.ZERO
		move_and_slide()
		if face_player:
			_face_player()
		return

	var next_waypoint := _direct_path[_direct_path_index]
	var to_next := next_waypoint - global_position
	to_next.y = 0.0
	var distance_to_next := to_next.length()
	if distance_to_next < 0.01:
		velocity = Vector3.ZERO
		move_and_slide()
		if face_player:
			_face_player()
		return

	var direction := to_next / distance_to_next
	if _wall_steer_timer > 0.0:
		direction = (
			direction + _wall_steer_direction * wall_steer_strength
		).normalized()

	var position_before_move := global_position
	velocity = direction * speed
	move_and_slide()
	if _state == State.CHASING and _try_catch_player():
		return
	_update_wall_steering(direction, to_next)
	var distance_moved := Vector2(
		global_position.x - position_before_move.x,
		global_position.z - position_before_move.z
	).length()
	_update_footsteps(distance_moved)
	if face_player:
		_face_player()
	else:
		var look_target := next_waypoint
		look_target.y = global_position.y
		if not look_target.is_equal_approx(global_position):
			look_at(look_target, Vector3.UP)


func _update_chasing(delta: float) -> void:
	# The warning beat: it roars and stares, frozen, before it gives chase.
	if _warning_timer > 0.0:
		_warning_timer -= delta
		velocity = Vector3.ZERO
		_face_player()
		return

	if is_instance_valid(player) and player.is_hidden:
		_update_hidden_search(delta)
		if _catch_emitted or _state != State.CHASING:
			return
	else:
		_waiting_at_hide = false
		_hide_wait = 0.0

	if _try_catch_player():
		return

	_update_path_timer -= delta
	if is_instance_valid(player):
		var chase_distance := global_position.distance_to(player.global_position)
		player.threat_proximity = clampf(1.0 - chase_distance / 14.0, 0.0, 1.0)

	var can_see_player := _can_see_player_during_chase()
	if can_see_player:
		_chase_timer = chase_max_time
		_player_last_seen_position = player.global_position

		if _update_path_timer <= 0.0:
			_update_path_timer = update_path_delay
			_update_chase_path()
	else:
		_chase_timer -= delta

		# Keep pursuing the last visible location. Never replace it with the
		# player's hidden position while a wall blocks sight.
		if _update_path_timer <= 0.0:
			_update_path_timer = update_path_delay
			_update_chase_path()

		if _chase_timer <= 0.0:
			# It does not give up: it hunts around where it lost the player.
			_enter_state(
				State.SEARCHING,
				{"player_last_seen_position": _player_last_seen_position}
			)
			return


func _try_catch_player() -> bool:
	if _catch_emitted or _state != State.CHASING or not is_instance_valid(player):
		return false

	# Physical contact is authoritative. It cannot be blocked by a held gas can
	# crossing the enemy's sight ray, and walls still prevent this collision.
	for collision_index in get_slide_collision_count():
		var collider := get_slide_collision(collision_index).get_collider() as Node
		if collider == player or (collider != null and player.is_ancestor_of(collider)):
			_catch_emitted = true
			print("[Enemy] PLAYER CAUGHT — physical contact")
			reached_player.emit()
			return true

	# Also catch at close horizontal range if the path ends just short of body
	# contact. A clear ray prevents this fallback from working through walls.
	var player_offset := player.global_position - global_position
	player_offset.y = 0.0
	if player_offset.length() <= catching_distance and not is_line_of_sight_broken():
		_catch_emitted = true
		print("[Enemy] PLAYER CAUGHT — close range")
		reached_player.emit()
		return true

	return false


func _update_searching(delta: float) -> void:
	_search_timer -= delta
	_search_whisper_timer -= delta
	if _search_whisper_timer <= 0.0:
		_search_whisper_timer = searching_whisper_interval * randf_range(0.8, 1.6)
		_play_stalking_sound()

	if _search_timer <= 0.0:
		_enter_state(State.DORMANT)
		return
	
	if navigation_agent.is_navigation_finished():
		_go_to_position_around_last_seen()
	
	if _detection_grace_timer <= 0.0 and is_player_in_view():
		_start_chase("He lost you but kept looking. Get far away and out of sight before he finds you again.")


# ── Movement (shared by all states) ─────────────────────────────────────

func _move_along_path(delta: float) -> void:
	_wall_steer_timer = maxf(_wall_steer_timer - delta, 0.0)

	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	var next_path_position := navigation_agent.get_next_path_position()
	
	var to_next := next_path_position - global_position
	to_next.y = 0.0
	var distance_to_next := to_next.length()
	
	# Avoid normalizing a near-zero vector, which amplifies floating point
	# noise into a full-speed direction and causes rapid back-and-forth
	# jitter right at the end of a path. If we're already within a tiny
	# distance of the next waypoint, stop cleanly instead of lurching
	# toward noise - but keep facing the movement direction so the eye
	# doesn't freeze looking the wrong way while idle.
	if distance_to_next < 0.05:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	var where_to_look := next_path_position
	where_to_look.y = global_position.y
	if not where_to_look.is_equal_approx(global_position):
		# If you want interpolation, look into quaternions and slerp().
		# Using look_at directly for simplicity.
		look_at(where_to_look)
	
	var direction := to_next / distance_to_next
	if _wall_steer_timer > 0.0:
		direction = (direction + _wall_steer_direction * wall_steer_strength).normalized()

	var position_before_move := global_position
	velocity = direction * _current_speed
	move_and_slide()
	_update_wall_steering(direction, to_next)
	
	var distance_moved := Vector2(
		global_position.x - position_before_move.x,
		global_position.z - position_before_move.z
	).length()
	_update_footsteps(distance_moved)


func _update_wall_steering(move_direction: Vector3, to_next: Vector3) -> void:
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var wall_normal := collision.get_normal()

		# Ignore the floor and slopes. Only near-horizontal normals represent walls.
		if absf(wall_normal.y) > 0.5:
			continue

		wall_normal.y = 0.0
		if wall_normal.length_squared() < 0.001:
			continue
		wall_normal = wall_normal.normalized()

		# Only steer when movement is actually pressing into this wall.
		if move_direction.dot(wall_normal) >= -0.05:
			continue

		var tangent_a := Vector3.UP.cross(wall_normal).normalized()
		var tangent_b := -tangent_a
		var target_direction := to_next.normalized()
		_wall_steer_direction = (
			tangent_a
			if tangent_a.dot(target_direction) >= tangent_b.dot(target_direction)
			else tangent_b
		)
		_wall_steer_timer = wall_steer_duration
		return


func _update_footsteps(distance_moved: float) -> void:
	if velocity.length() < 0.01:
		return
	
	_distance_since_last_step += distance_moved
	
	if _distance_since_last_step >= footstep_distance:
		_distance_since_last_step = 0.0
		_play_footstep()


func _play_footstep() -> void:
	if _footsteps == null:
		return
	_footsteps.pitch_scale = randf_range(footstep_pitch_min, footstep_pitch_max)
	_footsteps.volume_db = (
		stalking_footstep_volume_db
		if _state == State.STALKING
		else _footstep_base_volume_db
	)
	_footsteps.play()


func _play_scream_chase() -> void:
	if _chasing == null:
		return
	_chasing.play()


func _play_stalking_sound() -> void:
	if _stalking and not _stalking.playing:
		_stalking.pitch_scale = randf_range(0.95, 1.05)
		_stalking.play()


func _play_seen_sound() -> void:
	if _seen:
		_seen.pitch_scale = randf_range(0.97, 1.03)
		_seen.play()


func stop_all_sounds() -> void:
	_footsteps.stop()
	_chasing.stop()
	_stalking.stop()
	_seen.stop()


func hear_noise(sound_position: Vector3, hearing_distance: float) -> void:
	if not _map_synchronized or (is_instance_valid(player) and player.is_hidden):
		return
	var radius := hearing_distance * (1.0 + 0.25 * (phase - 1))
	match _state:
		State.DORMANT:
			# Loud play wakes it sooner: every footstep eats into its cooldown.
			_stalking_cooldown = maxf(_stalking_cooldown - radius * 0.02, 0.0)
		State.ROAMING, State.SEARCHING:
			if global_position.distance_to(sound_position) <= radius * 2.0:
				_enter_state(State.INVESTIGATING, {"sound_position": sound_position})


func awaken() -> void:
	# Turning the first valve is what draws it: a whisper from far off, then the
	# first stalking event after a tense pause.
	if awakened:
		return
	awakened = true
	_stalking_cooldown = randf_range(wake_delay_min, maxf(wake_delay_max, wake_delay_min))
	_ambient_cue_timer = 99.0
	print("[Enemy] AWAKENED - first stalking in %.1f s" % _stalking_cooldown)
	if is_instance_valid(player) and _map_synchronized:
		_play_ambient_cue()


func set_phase(new_phase: int) -> void:
	new_phase = clampi(new_phase, 1, 3)
	if new_phase <= phase:
		return
	phase = new_phase
	print("[Enemy] PHASE %d" % phase)


func player_hiding(spot_position: Vector3) -> void:
	# Judge, just before the player vanishes, whether it saw them duck in.
	_hidden_known = (
		visible
		and _state != State.DORMANT
		and global_position.distance_to(spot_position) < 18.0
		and not _is_blocked_to(spot_position)
	)
	_hide_wait = 0.0
	if _hidden_known:
		_player_last_seen_position = spot_position
		print("[Enemy] saw the player hide")


func player_left_hiding() -> void:
	_hidden_known = false
	_waiting_at_hide = false
	_hide_wait = 0.0


func _is_blocked_to(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		_eye.global_position, target + Vector3.UP, collision_mask, [get_rid()]
	)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit["collider"] as Node
	# Hitting the locker it is hiding in does not count as an obstruction.
	return not (collider != null and collider.is_in_group("hide_spot"))


func _update_hidden_search(delta: float) -> void:
	# The player is in a locker. If it saw where they went it camps outside and
	# opens it; otherwise it checks the spot it last saw them and gives up.
	if _hidden_known:
		_player_last_seen_position = player.global_position
		_chase_timer = chase_max_time
	var distance := Vector2(
		global_position.x - player.global_position.x,
		global_position.z - player.global_position.z
	).length()
	if distance > 1.9:
		_waiting_at_hide = false
		return
	_waiting_at_hide = true
	_face_player()
	velocity = Vector3.ZERO
	_hide_wait += delta
	if int(_hide_wait * 2.0) != int((_hide_wait - delta) * 2.0):
		player.add_trauma(0.25)   # knocking on the door
	if _hide_wait < hide_search_time:
		return
	_hide_wait = 0.0
	_waiting_at_hide = false
	if _hidden_known or randf() < hide_open_chance_unseen:
		last_catch_hint = "He saw you hide. Never hide where he can watch you go in."
		print("[Enemy] OPENED the locker")
		_catch_emitted = true
		reached_player.emit()
	else:
		print("[Enemy] hide spot checked - nothing found")
		_enter_state(
			State.SEARCHING,
			{"player_last_seen_position": _player_last_seen_position}
		)


func _update_flashlight_reaction(delta: float) -> void:
	if not visible or not is_instance_valid(player) or player.is_hidden:
		_lit_time = 0.0
		return
	var lit := false
	if player.is_flashlight_on and _state != State.DORMANT:
		var to_enemy := _eye.global_position - player.camera.global_position
		var distance := to_enemy.length()
		var aimed := -player.camera.global_basis.z.normalized().dot(to_enemy.normalized())
		lit = distance < 16.0 and aimed > 0.93 and not is_line_of_sight_broken()
	_lit_time = _lit_time + delta if lit else maxf(_lit_time - delta * 2.0, 0.0)
	if (
		_state == State.CHASING
		and _warning_timer <= 0.0
		and _lit_time > 0.5
		and _stagger_cooldown <= 0.0
	):
		_lit_time = 0.0
		_stagger_timer = flashlight_stagger_time
		_stagger_cooldown = flashlight_stagger_cooldown
		_play_seen_sound()
		player.add_trauma(0.35)
		print("[Enemy] STAGGERED by the flashlight")


func _start_chase(reason: String) -> void:
	_pending_hint = reason
	_enter_state(State.CHASING)


func _start_patrol() -> void:
	# From phase 2 it also walks the plant in the open, footsteps and all.
	var angle := randf() * TAU
	for distance in [32.0, 26.0, 40.0, 20.0]:
		var requested: Vector3 = player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * float(distance)
		var nav_point := NavigationServer3D.map_get_closest_point(_nav_map, requested)
		if Vector2(nav_point.x - requested.x, nav_point.z - requested.z).length() > 6.0:
			angle += 1.3
			continue
		var root_position := _root_position_from_nav_point(nav_point)
		if not _has_stalking_clearance(root_position):
			continue
		# Skip walled-off slivers of navmesh: the spot must connect to the player.
		var route := NavigationServer3D.map_get_path(_nav_map, nav_point, player.global_position, true)
		if route.is_empty() or route[route.size() - 1].distance_to(
			NavigationServer3D.map_get_closest_point(_nav_map, player.global_position)
		) > 2.0:
			angle += 0.9
			continue
		visible = true
		_collision_shape.set_deferred("disabled", false)
		global_position = root_position
		_patrol_timer = patrol_duration_phase2 if phase == 2 else patrol_duration_phase3
		_enter_state(State.ROAMING)
		_current_speed = roaming_speed * (1.0 if phase == 2 else 1.5)
		print("[Enemy] PATROL started at ", global_position)
		return
	_stalking_cooldown = stalking_blocked_retry_delay


func _threat_level() -> int:
	return mini(_stalking_encounters, max_threat_level)


func _choose_stalk_style() -> StalkStyle:
	if forced_stalk_style >= 0:
		return forced_stalk_style as StalkStyle
	# The first encounter is always the classic one so the player learns it.
	if _stalking_encounters == 0:
		return StalkStyle.BEHIND
	var roll := randf()
	if roll < 0.4:
		return StalkStyle.BEHIND
	if roll < 0.7:
		return StalkStyle.FLANK
	return StalkStyle.STATUE


func _stalk_direction() -> Vector3:
	# Horizontal direction, from the player, where this style wants the enemy.
	var forward := -player.global_basis.z
	match _stalk_style:
		StalkStyle.FLANK:
			return player.global_basis.x.normalized() * _flank_side
		StalkStyle.STATUE:
			return forward.normalized()
	return player.global_basis.z.normalized()


func _try_start_stalking() -> void:
	if phase >= 2 and randf() < (0.35 if phase == 2 else 0.5):
		_start_patrol()
		return
	_stalk_style = _choose_stalk_style()
	_flank_side = 1.0 if randf() < 0.5 else -1.0
	var placement := _find_safe_stalking_teleport()
	if not bool(placement["found"]) and _stalk_style != StalkStyle.BEHIND:
		# No room for the fancy placement: fall back to the classic ambush.
		_stalk_style = StalkStyle.BEHIND
		placement = _find_safe_stalking_teleport()
	if not bool(placement["found"]):
		_stalking_cooldown = stalking_blocked_retry_delay
		print(
			"[Enemy] STALKING postponed — no safe room behind player; retrying in %.1f seconds"
			% stalking_blocked_retry_delay
		)
		return

	_enter_state(State.STALKING, {"teleport_position": placement["position"]})


func _update_stalking_follow_path() -> void:
	if _stalk_style == StalkStyle.STATUE:
		# Head straight for the player; movement itself pauses while watched.
		var player_nav_point := NavigationServer3D.map_get_closest_point(
			_nav_map, player.global_position
		)
		var path := NavigationServer3D.map_get_path(
			_nav_map, global_position, player_nav_point, true
		)
		if not path.is_empty():
			_direct_path = path
			_direct_path_index = 0
		return

	var placement := _find_stalking_follow_target()
	if not bool(placement["found"]):
		return
	_stalking_follow_target = placement["position"]
	_direct_path = placement["path"]
	_direct_path_index = 0


func _update_chase_path() -> void:
	var player_nav_point := NavigationServer3D.map_get_closest_point(
		_nav_map,
		_player_last_seen_position
	)
	var chase_path := NavigationServer3D.map_get_path(
		_nav_map,
		global_position,
		player_nav_point,
		true
	)
	if chase_path.is_empty():
		_direct_path.clear()
		_direct_path_index = 0
		if not _chase_path_failure_reported:
			push_warning("[Enemy] CHASING could not build a path to the player")
			_chase_path_failure_reported = true
		return

	_chase_path_failure_reported = false
	_direct_path = chase_path
	_direct_path_index = 0


func _find_stalking_follow_target() -> Dictionary:
	# Following is intentionally less restrictive than the initial teleport.
	# The enemy is already in the world, so it only needs a reachable navmesh
	# point behind the player; walls are handled by the generated path.
	var behind_direction := _stalk_direction()
	var angle_offsets: Array[float] = [0.0, -0.35, 0.35, -0.7, 0.7, -1.05, 1.05]
	# The higher the player's anxiety, the closer the thing hugs their back.
	var anxiety_scale := 1.0 - anxiety_follow_distance_shrink * (_anxiety_level / 100.0)
	var base_follow_distance := stalking_follow_distance
	if _stalk_style == StalkStyle.FLANK:
		base_follow_distance = flank_distance
	var effective_follow_distance := maxf(
		minimum_stalking_follow_distance * 0.8,
		(
			base_follow_distance
			- _threat_level() * stalking_distance_reduction_per_level
		) * anxiety_scale
	)

	for angle in angle_offsets:
		var direction := behind_direction.rotated(Vector3.UP, angle)
		var requested_point := (
			player.global_position + direction * effective_follow_distance
		)
		var nav_point := NavigationServer3D.map_get_closest_point(
			_nav_map,
			requested_point
		)
		var horizontal_snap_error := Vector2(
			nav_point.x - requested_point.x,
			nav_point.z - requested_point.z
		).length()
		if horizontal_snap_error > stalking_follow_max_nav_snap_distance:
			continue

		var path := NavigationServer3D.map_get_path(
			_nav_map,
			global_position,
			nav_point,
			true
		)
		if path.is_empty():
			continue

		return {
			"found": true,
			"position": _root_position_from_nav_point(nav_point),
			"path": path,
		}

	# Narrow corridors may have no navmesh point at the preferred offset.
	# Continue following through the corridor instead of leaving the old
	# teleport position as the active target.
	var player_nav_point := NavigationServer3D.map_get_closest_point(
		_nav_map,
		player.global_position
	)
	var fallback_path := NavigationServer3D.map_get_path(
		_nav_map,
		global_position,
		player_nav_point,
		true
	)
	if not fallback_path.is_empty():
		return {
			"found": true,
			"position": _root_position_from_nav_point(player_nav_point),
			"path": fallback_path,
		}

	return {
		"found": false,
		"position": Vector3.ZERO,
		"path": PackedVector3Array(),
	}


func _find_safe_stalking_teleport() -> Dictionary:
	var behind_direction := _stalk_direction()
	var min_distance := stalking_min_teleport_distance
	var angle_offsets: Array[float] = [0.0, -0.35, 0.35, -0.7, 0.7, -1.05, 1.05]
	var distances: Array[float] = [
		stalking_min_teleport_distance,
		maxf(stalking_teleport_distance - 1.0, stalking_min_teleport_distance),
		maxf(stalking_teleport_distance, stalking_min_teleport_distance),
	]
	if _stalk_style == StalkStyle.STATUE:
		min_distance = statue_spawn_distance * 0.6
		distances = [
			statue_spawn_distance,
			statue_spawn_distance - 2.0,
			statue_spawn_distance + 2.0,
			statue_spawn_distance * 0.65,
		]
	elif _stalk_style == StalkStyle.FLANK:
		distances = [flank_distance, flank_distance + 1.5, flank_distance - 1.0]

	for distance in distances:
		for angle in angle_offsets:
			var direction := behind_direction.rotated(Vector3.UP, angle)
			var requested_point := player.global_position + direction * distance
			var nav_point := NavigationServer3D.map_get_closest_point(
				_nav_map,
				requested_point
			)
			var horizontal_snap_error := Vector2(
				nav_point.x - requested_point.x,
				nav_point.z - requested_point.z
			).length()
			if horizontal_snap_error > stalking_max_nav_snap_distance:
				continue

			var player_to_point := nav_point - player.global_position
			player_to_point.y = 0.0
			if player_to_point.length() < minf(min_distance, distances.min()) - 0.01:
				continue
			if player_to_point.normalized().dot(behind_direction) < 0.25:
				continue

			var root_position := _root_position_from_nav_point(nav_point)
			if (
				_has_stalking_clearance(root_position)
				and _has_clear_teleport_line(root_position)
			):
				return {"found": true, "position": root_position}

	return {"found": false, "position": Vector3.ZERO}


func _root_position_from_nav_point(nav_point: Vector3) -> Vector3:
	var capsule := _collision_shape.shape as CapsuleShape3D
	var body_half_height := 0.9
	if capsule:
		body_half_height = capsule.height * 0.5
	return nav_point + Vector3.UP * (
		body_half_height - _collision_shape.position.y + 0.05
	)


func _has_stalking_clearance(root_position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stalking_clearance_shape
	query.transform = Transform3D(global_basis, root_position) * _collision_shape.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _has_clear_teleport_line(root_position: Vector3) -> bool:
	# A destination can be physically empty while still sitting outside the
	# player's room on the other side of a wall. Reject any candidate when
	# solid geometry separates it from the player's body center.
	var ray_start := player.global_position + Vector3.UP
	var ray_end := root_position
	var query := PhysicsRayQueryParameters3D.create(
		ray_start,
		ray_end,
		collision_mask,
		[player.get_rid(), get_rid()]
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _is_player_looking_at_enemy() -> bool:
	if not is_instance_valid(player.camera):
		return false
	var camera_to_enemy: Vector3 = _eye.global_position - player.camera.global_position
	if camera_to_enemy.length_squared() < 0.001:
		return true
	var player_forward: Vector3 = -player.camera.global_basis.z.normalized()
	return player_forward.dot(camera_to_enemy.normalized()) >= player_look_dot_threshold


func _stop_moving() -> void:
	navigation_agent.target_position = global_position
	velocity = Vector3.ZERO


func _face_player() -> void:
	if not is_instance_valid(player):
		return
	var player_position := player.global_position
	player_position.y = global_position.y
	if not player_position.is_equal_approx(global_position):
		look_at(player_position, Vector3.UP)


func _delay_then_vanish(sequence_id: int) -> void:
	# Hold still for a brief, readable moment after the player notices the
	# stalker. The sound and disappearance happen together after the delay.
	await get_tree().create_timer(seen_vanish_delay, false).timeout
	if (
		not is_inside_tree()
		or _state != State.VANISHING
		or sequence_id != _vanish_sequence_id
	):
		return

	_play_seen_sound()
	visible = false
	_collision_shape.set_deferred("disabled", true)

	await get_tree().create_timer(vanish_hidden_time, false).timeout
	if (
		not is_inside_tree()
		or _state != State.VANISHING
		or sequence_id != _vanish_sequence_id
	):
		return

	_enter_state(State.DORMANT)


func _find_safe_vanish_destination() -> Dictionary:
	# Prefer a distant connected point hidden behind solid geometry. A clear
	# but otherwise safe point is retained only as a fallback.
	var behind_direction := player.global_basis.z.normalized()
	var angle_offsets: Array[float] = [0.0, -0.5, 0.5, -1.0, 1.0, -1.5, 1.5, PI]
	var distances: Array[float] = [
		randf_range(
			vanish_reappear_distance_min,
			maxf(vanish_reappear_distance_max, vanish_reappear_distance_min)
		),
		vanish_reappear_distance_min,
		maxf(vanish_reappear_distance_max, vanish_reappear_distance_min),
	]
	var visible_fallback := {"found": false, "position": Vector3.ZERO}

	for distance in distances:
		for angle in angle_offsets:
			var direction := behind_direction.rotated(Vector3.UP, angle)
			var requested_point := player.global_position + direction * distance
			var nav_point := NavigationServer3D.map_get_closest_point(
				_nav_map,
				requested_point
			)
			var horizontal_snap_error := Vector2(
				nav_point.x - requested_point.x,
				nav_point.z - requested_point.z
			).length()
			if horizontal_snap_error > vanish_max_nav_snap_distance:
				continue

			var actual_distance := Vector2(
				nav_point.x - player.global_position.x,
				nav_point.z - player.global_position.z
			).length()
			if actual_distance < vanish_reappear_distance_min * 0.8:
				continue

			var navigation_path := NavigationServer3D.map_get_path(
				_nav_map,
				player.global_position,
				nav_point,
				true
			)
			if navigation_path.is_empty():
				continue

			var root_position := _root_position_from_nav_point(nav_point)
			if not _has_stalking_clearance(root_position):
				continue

			var candidate := {"found": true, "position": root_position}
			if not _has_clear_teleport_line(root_position):
				return candidate
			if not bool(visible_fallback["found"]):
				visible_fallback = candidate

	return visible_fallback


func travel_to_position(wanted_position: Vector3, speed: float, _play_run_anim := false) -> void:
	navigation_agent.target_position = wanted_position
	_current_speed = speed


func _travel_to_random_position() -> void:
	var rand_pos := _pick_roam_target()
	travel_to_position(rand_pos, roaming_speed)


func _pick_roam_target() -> Vector3:
	# Only choose targets the enemy can actually walk to (not walled-off slivers).
	for _attempt in 12:
		var target := _pick_roam_target_unchecked()
		var route := NavigationServer3D.map_get_path(_nav_map, global_position, target, true)
		if route.size() > 1 and route[route.size() - 1].distance_to(target) < 1.0:
			return target
	return _pick_roam_target_unchecked()


func _pick_roam_target_unchecked() -> Vector3:
	# map_get_random_point has been unreliable in this project (returning
	# (0,0,0) regardless of layer/uniform settings). Instead, sample a
	# random point within roam_radius of the enemy's current position and
	# snap it onto the navmesh with map_get_closest_point, which we've
	# confirmed works correctly.
	var min_roam_distance := navigation_agent.target_desired_distance + 1.0
	var attempts := 0
	var candidate := _sample_and_snap_point(min_roam_distance)
	
	while global_position.distance_to(candidate) < min_roam_distance and attempts < 15:
		candidate = _sample_and_snap_point(min_roam_distance)
		attempts += 1
	
	# Safety net: if every attempt still landed too close (e.g. enemy is
	# cornered against the edge of the navmesh), force a point along an
	# arbitrary direction at exactly min_roam_distance and snap that
	# instead of returning a target the enemy is already standing on.
	if global_position.distance_to(candidate) < min_roam_distance:
		var forced_offset := Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU) * min_roam_distance
		candidate = NavigationServer3D.map_get_closest_point(_nav_map, global_position + forced_offset)
	
	return candidate


func _sample_and_snap_point(min_distance: float) -> Vector3:
	# Sample within an annulus (a ring) between min_distance and roam_radius,
	# rather than a full disc from 0, so we don't waste attempts on points
	# that are guaranteed to be too close before they're even snapped.
	var outer_radius := maxf(roam_radius, min_distance + 1.0)
	var theta := randf() * TAU
	var r := lerpf(min_distance, outer_radius, randf())
	var offset := Vector3(cos(theta), 0.0, sin(theta)) * r
	var raw_point := global_position + offset
	return NavigationServer3D.map_get_closest_point(_nav_map, raw_point)


func _go_to_position_around_last_seen() -> void:
	var random_offset := _random_point_in_circle(search_radius)
	var target := _player_last_seen_position + random_offset
	travel_to_position(target, searching_speed)


func _random_point_in_circle(radius: float) -> Vector3:
	var theta := randf() * TAU
	return Vector3(cos(theta), 0.0, sin(theta)) * sqrt(randf()) * radius


# ── Perception ───────────────────────────────────────────────────────────

func is_player_in_view() -> bool:
	if not is_instance_valid(player):
		return false
	if player.is_hidden:
		return false

	# A lit flashlight shows you from much farther; crouching in the dark shrinks it.
	var spotting := max_spotting_distance
	var cone := 0.3
	if player.is_flashlight_on:
		spotting *= 1.6
		cone = -0.1
	elif player.is_crouching:
		spotting *= 0.6

	var vec_to_player := player.global_position - global_position
	var distance_to_player := vec_to_player.length()
	
	if distance_to_player > spotting:
		return false
	if is_line_of_sight_broken():
		return false

	# Very close players can be noticed from any direction. At normal range,
	# the player must be inside the enemy's forward-facing view cone.
	if distance_to_player <= close_detection_distance:
		return true

	return -_eye.global_basis.z.normalized().dot(vec_to_player.normalized()) > cone


func _can_see_player_during_chase() -> bool:
	return is_player_in_view()


func is_line_of_sight_broken() -> bool:
	if not is_instance_valid(player):
		return true

	var player_body_center := player.global_position + Vector3.UP
	_eye_ray_cast.target_position = _eye_ray_cast.to_local(player_body_center)
	_eye_ray_cast.force_raycast_update()
	
	# The view is clear when the ray reaches the player. Any other collider
	# between the enemy and player blocks line of sight.
	if _eye_ray_cast.is_colliding():
		var collider := _eye_ray_cast.get_collider() as Node
		return collider != player and not player.is_ancestor_of(collider)
	
	# Reaching the target point without hitting anything is also clear.
	return false
