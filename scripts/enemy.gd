extends CharacterBody3D
class_name Enemy

# ── Signals ──────────────────────────────────────────────────────────────
signal reached_player

# ── States ───────────────────────────────────────────────────────────────
enum State { ROAMING, INVESTIGATING, STALKING, CHASING, SEARCHING }

var _state: State = State.ROAMING

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
@export_range(0.0, 1.0) var stalking_chance := 0.65
@export var stalking_speed := 2.6
@export var stalking_start_distance := 8.0
@export var stalking_follow_distance := 12.0
@export var stalking_chase_distance := 5.5
@export var stalking_duration_min := 10.0
@export var stalking_duration_max := 18.0
@export var stalking_lost_sight_time := 3.0
@export var stalking_path_update_delay := 0.5
@export var stalking_cooldown_time := 25.0
@export var watched_before_chase := 1.75
@export_range(-1.0, 1.0) var player_look_dot_threshold := 0.82
@export var stalking_footstep_volume_db := -12.0

@export_group("Chasing")
@export var chasing_speed := 6.0
@export var chase_max_time := 8.0
@export var catching_distance := 1.4
@export var update_path_delay := 0.2

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
var _stalking_timer := 0.0
var _stalking_lost_sight_timer := 0.0
var _stalking_path_timer := 0.0
var _stalking_cooldown := 0.0
var _watched_timer := 0.0
var _seen_sound_played := false
var _footstep_base_volume_db := 0.0

# ── Chasing state ────────────────────────────────────────────────────────
var _chase_timer := 0.0
var _update_path_timer := 0.0

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
@onready var _roaming: AudioStreamPlayer3D = $roaming
@onready var _stalking: AudioStreamPlayer3D = $stalking
@onready var _seen: AudioStreamPlayer3D = $seen
@onready var ray_cast_3d: RayCast3D = %EyeRayCast
@onready var generator: Node3D = get_tree().get_first_node_in_group("generator")

func _ready() -> void:
	randomize()
	add_to_group("enemy")
	_footstep_base_volume_db = _footsteps.volume_db
	_nav_map = get_world_3d().get_navigation_map()
	_sync_map_then_start_roaming()


func _sync_map_then_start_roaming() -> void:
	# Wait until the NavigationServer has actually finished building this
	# map at least once. A fixed frame-count wait is not reliable here;
	# map_get_iteration_id() is the engine's own ground truth for "ready".
	while NavigationServer3D.map_get_iteration_id(_nav_map) == 0:
		await get_tree().process_frame
	
	_map_synchronized = true
	_enter_state(State.ROAMING)


func _physics_process(delta: float) -> void:
	if not _map_synchronized:
		return
	_stalking_cooldown = maxf(_stalking_cooldown - delta, 0.0)
	
	match _state:
		State.ROAMING:
			_update_roaming(delta)
		State.INVESTIGATING:
			_update_investigating(delta)
		State.STALKING:
			_update_stalking(delta)
		State.CHASING:
			_update_chasing(delta)
		State.SEARCHING:
			_update_searching(delta)
	
	_move_along_path(delta)


# ── State transition ─────────────────────────────────────────────────────

func _enter_state(new_state: State, data := {}) -> void:
	if _state == State.STALKING and new_state != State.STALKING:
		_stalking.stop()
	_state = new_state
	
	match _state:
		State.ROAMING:
			_travel_to_random_position()
			_play_roaming_sound()

		State.INVESTIGATING:
			if not data.has("sound_position"):
				printerr(name + ": entered Investigating without sound_position.")
				_enter_state(State.ROAMING)
				return
			_heard_position = NavigationServer3D.map_get_closest_point(
				_nav_map,
				data["sound_position"]
			)
			_investigation_timer = investigation_time
			travel_to_position(_heard_position, investigating_speed)

		State.STALKING:
			_stalking_timer = randf_range(stalking_duration_min, stalking_duration_max)
			_stalking_lost_sight_timer = stalking_lost_sight_time
			_stalking_path_timer = 0.0
			_stalking_cooldown = stalking_cooldown_time
			_watched_timer = 0.0
			_seen_sound_played = false
			_player_last_seen_position = player.global_position
			travel_to_position(_pick_stalking_target(), stalking_speed)
			_play_stalking_sound()
		
		State.CHASING:
			_chase_timer = chase_max_time
			_update_path_timer = 0.0
			_player_last_seen_position = player.global_position
			travel_to_position(_player_last_seen_position, chasing_speed)
			_play_scream_chase()
		
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
	
	if is_player_in_view():
		var distance_to_player := global_position.distance_to(player.global_position)
		var can_stalk := (
			distance_to_player >= stalking_start_distance
			and _stalking_cooldown <= 0.0
			and randf() <= stalking_chance
		)
		_enter_state(State.STALKING if can_stalk else State.CHASING)


func _update_investigating(delta: float) -> void:
	if is_player_in_view():
		_enter_state(State.CHASING)
		return

	_investigation_timer -= delta
	if _investigation_timer <= 0.0:
		_enter_state(State.ROAMING)
		return

	# Stay near the source and look for the player until the investigation
	# timer expires. A newer sound can redirect us through hear_noise().
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		rotate_y(investigation_turn_speed * delta)


func _update_stalking(delta: float) -> void:
	_stalking_timer -= delta
	_stalking_path_timer -= delta

	var distance_to_player := global_position.distance_to(player.global_position)
	var has_line_of_sight := (
		distance_to_player <= max_spotting_distance
		and not is_line_of_sight_broken()
	)

	if has_line_of_sight:
		_player_last_seen_position = player.global_position
		_stalking_lost_sight_timer = stalking_lost_sight_time
	else:
		_stalking_lost_sight_timer -= delta

	if _stalking_lost_sight_timer <= 0.0:
		_enter_state(State.SEARCHING, {
			"player_last_seen_position": _player_last_seen_position
		})
		return

	if _stalking_timer <= 0.0:
		if has_line_of_sight:
			_enter_state(State.CHASING)
		else:
			_enter_state(State.SEARCHING, {
				"player_last_seen_position": _player_last_seen_position
			})
		return

	var player_is_watching := has_line_of_sight and _is_player_looking_at_enemy()
	if player_is_watching:
		_stop_moving()
		_watched_timer += delta
		if not _seen_sound_played:
			_seen_sound_played = true
			_play_seen_sound()

		if (
			player.is_flashlight_on
			or _watched_timer >= watched_before_chase
			or distance_to_player <= stalking_chase_distance
		):
			_enter_state(State.CHASING)
		return

	_watched_timer = maxf(_watched_timer - delta * 0.5, 0.0)
	var player_horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	if has_line_of_sight and (
		distance_to_player <= stalking_chase_distance
		or player_horizontal_speed > 7.0
	):
		_enter_state(State.CHASING)
		return

	if has_line_of_sight and _stalking_path_timer <= 0.0:
		_stalking_path_timer = stalking_path_update_delay
		travel_to_position(_pick_stalking_target(), stalking_speed)


func _update_chasing(delta: float) -> void:
	_update_path_timer -= delta

	var can_see_player := _can_see_player_during_chase()
	if can_see_player:
		_chase_timer = chase_max_time
		_player_last_seen_position = player.global_position

		if _update_path_timer <= 0.0:
			_update_path_timer = update_path_delay
			travel_to_position(_player_last_seen_position, chasing_speed)
	else:
		_chase_timer -= delta

		# Keep pursuing the last visible location. Never replace it with the
		# player's hidden position while a wall blocks sight.
		if _update_path_timer <= 0.0:
			_update_path_timer = update_path_delay
			travel_to_position(_player_last_seen_position, chasing_speed)

		var reached_last_seen := global_position.distance_to(_player_last_seen_position) <= (
			navigation_agent.target_desired_distance + 0.25
		)
		if reached_last_seen or _chase_timer <= 0.0:
			_enter_state(State.SEARCHING, {
				"player_last_seen_position": _player_last_seen_position
			})
			return

	if can_see_player and global_position.distance_to(player.global_position) <= catching_distance:
		reached_player.emit()


func _update_searching(delta: float) -> void:
	_search_timer -= delta
	
	if _search_timer <= 0.0:
		_enter_state(State.ROAMING)
		return
	
	if navigation_agent.is_navigation_finished():
		_go_to_position_around_last_seen()
	
	if is_player_in_view():
		_enter_state(State.CHASING)


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


func _play_roaming_sound() -> void:
	if _roaming == null:
		return
	# _roaming's Stream is an AudioStreamRandomizer, so .play() automatically
	# picks one of its variations - no manual pitch/clip selection needed here.
	_roaming.play()


func _play_stalking_sound() -> void:
	if _stalking and not _stalking.playing:
		_stalking.pitch_scale = randf_range(0.95, 1.05)
		_stalking.play()


func _play_seen_sound() -> void:
	if _seen:
		_seen.pitch_scale = randf_range(0.97, 1.03)
		_seen.play()


func hear_noise(sound_position: Vector3, hearing_distance: float) -> void:
	if not _map_synchronized or _state in [State.STALKING, State.CHASING]:
		return
	var distance_to_sound := global_position.distance_to(sound_position)
	if distance_to_sound > hearing_distance:
		return

	# Hearing gives the enemy an approximate source rather than perfect
	# knowledge through walls. Distant sounds create more uncertainty.
	var distance_ratio := clampf(distance_to_sound / maxf(hearing_distance, 0.01), 0.0, 1.0)
	var uncertainty := hearing_position_uncertainty * distance_ratio
	var estimated_position := sound_position + _random_point_in_circle(uncertainty)
	_enter_state(State.INVESTIGATING, {"sound_position": estimated_position})


func _pick_stalking_target() -> Vector3:
	# Favor the space behind the player. The navigation mesh decides the
	# actual route, so the enemy still has to walk around walls and doors.
	var behind_player := player.global_position + (
		player.global_basis.z.normalized() * stalking_follow_distance
	)
	return NavigationServer3D.map_get_closest_point(_nav_map, behind_player)


func _is_player_looking_at_enemy() -> bool:
	if not is_instance_valid(player.camera):
		return false
	var camera_to_enemy: Vector3 = _eye.global_position - player.camera.global_position
	if camera_to_enemy.length_squared() < 0.001:
		return true
	var player_forward := -player.camera.global_basis.z.normalized()
	return player_forward.dot(camera_to_enemy.normalized()) >= player_look_dot_threshold


func _stop_moving() -> void:
	navigation_agent.target_position = global_position
	velocity = Vector3.ZERO


func travel_to_position(wanted_position: Vector3, speed: float, _play_run_anim := false) -> void:
	navigation_agent.target_position = wanted_position
	_current_speed = speed


func _travel_to_random_position() -> void:
	var rand_pos := _pick_roam_target()
	travel_to_position(rand_pos, roaming_speed)


func _pick_roam_target() -> Vector3:
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

	var vec_to_player := player.global_position - global_position
	var distance_to_player := vec_to_player.length()
	
	if distance_to_player > max_spotting_distance:
		return false
	if is_line_of_sight_broken():
		return false

	# Very close players can be noticed from any direction. At normal range,
	# the player must be inside the enemy's forward-facing view cone.
	if distance_to_player <= close_detection_distance:
		return true

	return -_eye.global_basis.z.normalized().dot(vec_to_player.normalized()) > 0.3


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
