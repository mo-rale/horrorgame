extends CharacterBody3D
class_name Player

signal calm_pressed(amount: float)
signal anxiety_calmed

const SPEED = 5.0
const SPRINT_SPEED = 9.0
const CROUCH_SPEED = 2.5
const JUMP_VELOCITY = 4.5

# FOV
const NORMAL_FOV = 75.0
const SPRINT_FOV = 95.0
const FOV_SPEED = 8.0

@onready var camera: Camera3D = $head/Camera3D
@onready var footsteps: AudioStreamPlayer3D = $footsteps
@onready var flashlight: AudioStreamPlayer3D = %flashlight
@onready var light: SpotLight3D = %light
@onready var raycast: RayCast3D = $head/Camera3D/RayCast3D
@onready var grab: AudioStreamPlayer3D = $grab
@onready var heartbeat: AudioStreamPlayer = $heartbeat
@onready var hand: Node3D = %hand
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var anxiety_hud: CanvasLayer = %AnxietyHUD
@onready var anxiety_bar: ProgressBar = %AnxietyBar
@onready var anxiety_value_label: Label = %AnxietyValueLabel
@onready var calm_button: Button = %CalmButton

var current_interactable: Node = null
var mouse_sensitivity := 0.001
var pitch = 0.0
var is_flashlight_on = false
var is_crouching = false

# Footsteps
var footstep_cooldown = 0.0

@export_group("Footstep Audio")
@export var walking_footstep_volume_db := -30.0
@export var sprinting_footstep_volume_db := -25.0
@export var crouching_footstep_volume_db := -40.0
@export var walking_noise_radius := 7.0
@export var sprinting_noise_radius := 14.0
@export var crouching_noise_radius := 2.0

# Headbob
var headbob_time = 0.0
var headbob_amount = 0.2
var headbob_speed = 10.0
var camera_default_pos: Vector3

# Crouch
const CROUCH_HEIGHT = -0.6
const CROUCH_COLLIDER_HEIGHT = 1.2
const CROUCH_TRANSITION_SPEED = 8.0
var crouch_offset := 0.0
var _standing_collider_height := 0.0
var _standing_collider_y := 0.0
var _crouching_collider_y := 0.0

# Grab
var grabbed_object: RigidBody3D = null

@export_group("Held Object")
@export var held_object_clearance_radius := 0.4

var _held_object_clearance_shape := SphereShape3D.new()

@export_group("Anxiety")
@export_range(2, 10, 1) var calm_presses_required := 5
@export_range(1.0, 50.0, 1.0) var calm_reduction_per_press := 18.0

var _anxiety_active := false
var _calm_phase_started := false
var _calm_press_count := 0
var _calm_key := KEY_NONE
var _calm_keys: Array[int] = [KEY_Q, KEY_C, KEY_Z, KEY_X]

@export_group("Stamina")
@export var stamina_drain_per_second := 22.0
@export var stamina_regen_per_second := 14.0
@export var stamina_regen_delay := 1.0
@export var stamina_resume_threshold := 25.0

@export_group("Flashlight Battery")
@export var battery_drain_per_second := 1.1
@export var battery_recharge_per_second := 2.0
@export var enemy_flicker_distance := 14.0

var controls_locked := false
var stamina := 100.0
var battery := 100.0
var _stamina_exhausted := false
var _is_sprinting := false
var _stamina_regen_timer := 0.0
var _flashlight_base_energy := 1.0
var _flicker_timer := 0.0
var _flicker_off_time := 0.0
var _stamina_bar: ProgressBar
var _battery_bar: ProgressBar


func _ready():
	_flashlight_base_energy = light.light_energy
	_build_survival_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_sensitivity *= Settings.mouse_sensitivity
	camera_default_pos = camera.position
	camera.fov = NORMAL_FOV
	light.visible = false
	if heartbeat.stream:
		heartbeat.stream = heartbeat.stream.duplicate()
		if heartbeat.stream is AudioStreamMP3:
			(heartbeat.stream as AudioStreamMP3).loop = true

	# Keep this player's collider independent if the scene is instantiated
	# more than once, then remember the standing dimensions.
	collision_shape.shape = collision_shape.shape.duplicate()
	var capsule := collision_shape.shape as CapsuleShape3D
	_standing_collider_height = capsule.height
	_standing_collider_y = collision_shape.position.y
	_crouching_collider_y = _standing_collider_y - (
		_standing_collider_height - CROUCH_COLLIDER_HEIGHT
	) * 0.5
	_held_object_clearance_shape.radius = held_object_clearance_radius
	calm_button.pressed.connect(_register_calm_press)
	anxiety_hud.visible = false

func _input(event):
	if controls_locked:
		return

	if (
		_anxiety_active
		and _calm_phase_started
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == _calm_key
	):
		_register_calm_press()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		# Rotate player left/right
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Rotate camera up/down
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = pitch
	
	# Left click - drop object or use it on something
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if grabbed_object:
			# Use the held object when aiming at a compatible target.
			if raycast.is_colliding():
				var use_target := _find_item_use_target(raycast.get_collider())
				if use_target and grabbed_object.has_method("use"):
					var item_to_use := grabbed_object
					grabbed_object = null

					if current_interactable and current_interactable.has_method("hide_outline"):
						current_interactable.hide_outline()
					current_interactable = null

					item_to_use.use(use_target)
					return
			
			# If we didn't use it on anything, drop it
			drop_object()

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Cutscenes freeze the player in place but keep gravity and the light.
	if controls_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Stay crouched when there is not enough room to safely stand up.
	if Input.is_action_pressed("Crouch"):
		is_crouching = true
	elif is_crouching and _can_stand_up():
		is_crouching = false

	_update_crouch_collision(delta)

	# Jump
	if Input.is_action_just_pressed("Jump") and is_on_floor() and !is_crouching:
		velocity.y = JUMP_VELOCITY

	# Movement
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Backward")

	# Speed (sprinting costs stamina; running dry forces a recovery period)
	var current_speed = SPEED
	var wants_sprint: bool = (
		Input.is_action_pressed("Sprint")
		and input_dir != Vector2.ZERO
		and not is_crouching
		and not _stamina_exhausted
	)
	_is_sprinting = wants_sprint
	_update_stamina(delta, wants_sprint)

	if is_crouching:
		current_speed = CROUCH_SPEED
	elif wants_sprint:
		current_speed = SPRINT_SPEED

	# Flashlight
	if Input.is_action_just_pressed("Flashlight") and (battery > 0.0 or is_flashlight_on):
		is_flashlight_on = !is_flashlight_on
		light.visible = is_flashlight_on
		flashlight.pitch_scale = randf_range(0.9, 1.1)
		flashlight.play()
	_update_flashlight(delta)

	var direction := (
		transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()

	# Smooth crouch transition
	var target_offset = 0.0

	if is_crouching:
		target_offset = CROUCH_HEIGHT

	crouch_offset = lerpf(
		crouch_offset,
		target_offset,
		delta * CROUCH_TRANSITION_SPEED
	)

	var target_camera_pos = camera_default_pos
	target_camera_pos.y += crouch_offset

	# Headbob
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var moving: bool = horizontal_speed > 0.1

	if moving and is_on_floor():
		var bob_speed = headbob_speed

		if is_crouching:
			bob_speed *= 0.5

		headbob_time += delta * bob_speed * max(horizontal_speed / SPEED, 0.5)

		camera.position.y = target_camera_pos.y + sin(headbob_time) * headbob_amount
		camera.position.x = target_camera_pos.x + cos(headbob_time * 0.5) * headbob_amount * 0.5
	else:
		camera.position = camera.position.lerp(target_camera_pos, delta * 10.0)

	# Sprint FOV Effect
	var target_fov = NORMAL_FOV

	if _is_sprinting and moving:
		target_fov = SPRINT_FOV

	camera.fov = lerpf(camera.fov, target_fov, delta * FOV_SPEED)

	# Footsteps
	footstep_cooldown -= delta

	if moving and is_on_floor():
		if footstep_cooldown <= 0.0:
			footsteps.pitch_scale = randf_range(0.9, 1.1)
			var noise_radius := walking_noise_radius
	
			if is_crouching:
				footsteps.volume_db = crouching_footstep_volume_db
				footstep_cooldown = 0.7
				noise_radius = crouching_noise_radius
			elif _is_sprinting:
				footsteps.volume_db = sprinting_footstep_volume_db
				footstep_cooldown = 0.28
				noise_radius = sprinting_noise_radius
			else:
				footsteps.volume_db = walking_footstep_volume_db
				footstep_cooldown = 0.45

			footsteps.play()
			_emit_noise(noise_radius)

	if grabbed_object:
		_update_held_object_position()
	
	# ===== INTERACTION & GRAB =====
	_update_interaction()


## Called by the enemy: 0..1 closeness of an active threat (drives camera shake).
var threat_proximity := 0.0
var _trauma := 0.0


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _process(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 0.9)
	var shake := maxf(_trauma * _trauma, threat_proximity * threat_proximity * 0.35)
	if shake > 0.001:
		camera.h_offset = randf_range(-1.0, 1.0) * 0.05 * shake
		camera.v_offset = randf_range(-1.0, 1.0) * 0.05 * shake
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _update_stamina(delta: float, sprinting: bool) -> void:
	if sprinting:
		stamina = maxf(0.0, stamina - stamina_drain_per_second * delta)
		_stamina_regen_timer = stamina_regen_delay
		if stamina <= 0.0:
			_stamina_exhausted = true
	else:
		_stamina_regen_timer -= delta
		if _stamina_regen_timer <= 0.0:
			stamina = minf(100.0, stamina + stamina_regen_per_second * delta)
		if _stamina_exhausted and stamina >= stamina_resume_threshold:
			_stamina_exhausted = false

	_stamina_bar.value = stamina
	_stamina_bar.modulate = (
		Color(1.0, 0.3, 0.25) if _stamina_exhausted else Color(0.85, 0.85, 0.85)
	)
	# Fade the bar out when full so it does not clutter the screen.
	var target_alpha := 0.0 if stamina >= 99.9 and not _stamina_exhausted else 0.9
	_stamina_bar.modulate.a = lerpf(_stamina_bar.modulate.a, target_alpha, 0.2)


func _update_flashlight(delta: float) -> void:
	if is_flashlight_on:
		battery = maxf(0.0, battery - battery_drain_per_second * delta)
		if battery <= 0.0:
			is_flashlight_on = false
			light.visible = false
			flashlight.play()
	else:
		battery = minf(100.0, battery + battery_recharge_per_second * delta)

	_battery_bar.value = battery
	_battery_bar.modulate = (
		Color(1.0, 0.3, 0.25) if battery < 20.0 else Color(0.95, 0.85, 0.45)
	)

	if not is_flashlight_on:
		return

	# Dying battery and a nearby enemy both make the beam stutter.
	var flicker_chance := 0.0
	if battery < 25.0:
		flicker_chance = (25.0 - battery) / 25.0 * 0.6
	var enemy_node := get_tree().get_first_node_in_group("enemy") as Node3D
	if enemy_node and is_instance_valid(enemy_node) and enemy_node.visible:
		var dist := global_position.distance_to(enemy_node.global_position)
		if dist < enemy_flicker_distance:
			flicker_chance = maxf(flicker_chance, (1.0 - dist / enemy_flicker_distance) * 0.7)

	_flicker_off_time -= delta
	_flicker_timer -= delta
	if _flicker_off_time > 0.0:
		light.light_energy = _flashlight_base_energy * randf_range(0.0, 0.25)
		return
	light.light_energy = _flashlight_base_energy * (
		1.0 if battery >= 25.0 else lerpf(0.35, 1.0, battery / 25.0)
	)
	if flicker_chance > 0.0 and _flicker_timer <= 0.0:
		_flicker_timer = randf_range(0.15, 0.5)
		if randf() < flicker_chance:
			_flicker_off_time = randf_range(0.05, 0.2)


func _build_survival_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var box := VBoxContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 28.0
	box.offset_top = -80.0
	box.offset_bottom = -24.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	layer.add_child(box)
	_stamina_bar = _make_hud_bar(box)
	_battery_bar = _make_hud_bar(box)
	_stamina_bar.modulate.a = 0.0


func _make_hud_bar(parent: Control) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(180.0, 8.0)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 1, 1, 0.9)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	parent.add_child(bar)
	return bar


func _update_crouch_collision(delta: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	var target_height := (
		CROUCH_COLLIDER_HEIGHT if is_crouching else _standing_collider_height
	)
	var target_y := _crouching_collider_y if is_crouching else _standing_collider_y
	var blend := clampf(delta * CROUCH_TRANSITION_SPEED, 0.0, 1.0)

	capsule.height = lerpf(capsule.height, target_height, blend)
	collision_shape.position.y = lerpf(collision_shape.position.y, target_y, blend)


func _can_stand_up() -> bool:
	var capsule := collision_shape.shape as CapsuleShape3D
	var current_top := collision_shape.position.y + capsule.height * 0.5
	var standing_top := _standing_collider_y + _standing_collider_height * 0.5
	var check_radius := capsule.radius * 0.75
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(check_radius, 0.0, 0.0),
		Vector3(-check_radius, 0.0, 0.0),
		Vector3(0.0, 0.0, check_radius),
		Vector3(0.0, 0.0, -check_radius),
	]
	var space_state := get_world_3d().direct_space_state

	for offset in offsets:
		var ray_start: Vector3 = global_transform * (offset + Vector3.UP * current_top)
		var ray_end: Vector3 = global_transform * (offset + Vector3.UP * (standing_top + 0.05))
		var query := PhysicsRayQueryParameters3D.create(
			ray_start,
			ray_end,
			collision_mask,
			[get_rid()]
		)
		if not space_state.intersect_ray(query).is_empty():
			return false

	return true

func _update_interaction() -> void:
	var new_interactable: Node = null
	
	if raycast.is_colliding():
		var collider = raycast.get_collider()

		if grabbed_object:
			new_interactable = _find_item_use_target(collider)
		else:
			# Check for grabable objects first.
			var grabable: Node = null
			var temp = collider
			while temp:
				if temp.is_in_group("grabable"):
					grabable = temp
					break
				temp = temp.get_parent()
			
			# Check for interactable objects (generator, etc.).
			var interactable: Node = null
			temp = collider
			while temp:
				if temp.has_method("interact"):
					interactable = temp
					break
				temp = temp.get_parent()
			
			if grabable:
				new_interactable = grabable
			elif interactable:
				new_interactable = interactable
	
	# Only update if the interactable changed
	if new_interactable != current_interactable:
		# Hide old outline
		if current_interactable and current_interactable.has_method("hide_outline"):
			current_interactable.hide_outline()
		
		# Show new outline
		current_interactable = new_interactable
		if current_interactable and current_interactable.has_method("show_outline"):
			current_interactable.show_outline()
	
	# ===== INTERACT BUTTON =====
	if Input.is_action_just_pressed("Interact"):
		# If we're holding something, drop it
		if grabbed_object:
			drop_object()
		# Otherwise, try to interact with what we're looking at
		elif current_interactable and current_interactable.has_method("interact"):
			current_interactable.interact()
		# Or try to grab something
		elif not grabbed_object:
			try_grab()


func _find_item_use_target(collider: Node) -> Node:
	var target := collider
	while target:
		if target.is_in_group("generator") and target.has_method("fueled"):
			return target
		target = target.get_parent()

	return null

func try_grab() -> void:
	if not raycast.is_colliding():
		return
	
	var collider = raycast.get_collider()
	
	# Check if the collider is in the "grabable" group
	if collider.is_in_group("grabable"):
		var rigid_body = collider as RigidBody3D
		if rigid_body:
			# Store the original parent BEFORE reparenting
			var original_parent = rigid_body.get_parent()
			
			# Call the grab method on the object
			if rigid_body.has_method("grab"):
				rigid_body.grab()
			
			# Store the grabbed object
			grabbed_object = rigid_body
			
			# Play grab sound
			grab.pitch_scale = randf_range(0.9, 1.1)
			grab.play()
			
			# Remove from current parent
			if rigid_body.get_parent():
				rigid_body.get_parent().remove_child(rigid_body)
			
			# Add to hand
			hand.add_child(rigid_body)
			
			# Reset position and rotation relative to hand
			rigid_body.position = Vector3.ZERO
			rigid_body.rotation = Vector3.ZERO
			
			# Store original parent for later
			rigid_body.set_meta("original_parent", original_parent)
			
			# Hide outline immediately after grabbing
			if current_interactable and current_interactable.has_method("hide_outline"):
				current_interactable.hide_outline()
			current_interactable = null

func drop_object() -> void:
	if not grabbed_object:
		return

	var desired_drop_position = global_position + -global_transform.basis.z * 2.0
	desired_drop_position.y += 0.5
	var safe_drop_position := _get_safe_held_object_position(desired_drop_position)
	
	# Get the original parent or use the current scene as fallback
	var original_parent = grabbed_object.get_meta("original_parent", null)
	
	# If no original parent was stored, or it's been removed, use the current scene
	if not original_parent or not is_instance_valid(original_parent):
		original_parent = get_tree().current_scene
	
	# Remove from hand first
	if grabbed_object.get_parent() == hand:
		hand.remove_child(grabbed_object)
	else:
		# If it's not in hand, remove from wherever it is
		if grabbed_object.get_parent():
			grabbed_object.get_parent().remove_child(grabbed_object)
	
	# Add to the original parent
	original_parent.add_child(grabbed_object)
	
	# Position the object before re-enabling physics so it cannot briefly
	# overlap a wall during the reparent operation.
	grabbed_object.global_position = safe_drop_position

	if grabbed_object.has_method("drop"):
		grabbed_object.drop()
	
	# Re-enable physics (in case the object's drop() method didn't do it)
	grabbed_object.freeze = false
	grabbed_object.gravity_scale = 1.0
	
	# Apply a small throw force
	var throw_force = -global_transform.basis.z * 5.0 + Vector3.UP * 2.0
	grabbed_object.apply_central_impulse(throw_force)
	
	# Clear the meta and reference
	if grabbed_object.has_meta("original_parent"):
		grabbed_object.remove_meta("original_parent")
	
	grabbed_object = null


func _update_held_object_position() -> void:
	grabbed_object.global_position = _get_safe_held_object_position(hand.global_position)


func _get_safe_held_object_position(desired_position: Vector3) -> Vector3:
	var origin: Vector3 = camera.global_position
	var motion: Vector3 = desired_position - origin
	if motion.length_squared() < 0.0001:
		return desired_position

	var exclusions: Array[RID] = [get_rid(), grabbed_object.get_rid()]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _held_object_clearance_shape
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.motion = motion
	query.collision_mask = collision_mask
	query.exclude = exclusions
	query.collide_with_areas = false

	var cast_result: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	var safe_fraction: float = clampf(cast_result[0], 0.0, 1.0)
	return origin + motion * safe_fraction


func _emit_noise(noise_radius: float) -> void:
	get_tree().call_group("enemy", "hear_noise", global_position, noise_radius)


func start_stalking_heartbeat() -> void:
	if not heartbeat.playing:
		heartbeat.play()


func stop_stalking_heartbeat() -> void:
	heartbeat.stop()


func start_stalking_anxiety() -> void:
	_anxiety_active = true
	_calm_phase_started = false
	_calm_press_count = 0
	_calm_key = KEY_NONE
	anxiety_bar.value = 0.0
	anxiety_value_label.text = "0%"
	calm_button.visible = false
	anxiety_hud.visible = true


func update_stalking_anxiety(value: float, heartbeat_threshold: float) -> void:
	if not _anxiety_active:
		return
	anxiety_bar.value = clampf(value, 0.0, 100.0)
	get_tree().call_group("post_fx", "set_anxiety", anxiety_bar.value / 100.0)
	anxiety_value_label.text = "%d%%" % roundi(anxiety_bar.value)
	if value >= heartbeat_threshold and not _calm_phase_started:
		_calm_phase_started = true
		calm_button.visible = true
		_choose_next_calm_key()


func end_stalking_anxiety() -> void:
	_anxiety_active = false
	_calm_phase_started = false
	_calm_press_count = 0
	calm_button.visible = false
	anxiety_hud.visible = false
	get_tree().call_group("post_fx", "set_anxiety", 0.0)
	stop_stalking_heartbeat()


func _register_calm_press() -> void:
	if not _anxiety_active or not _calm_phase_started:
		return
	_calm_press_count += 1
	calm_pressed.emit(calm_reduction_per_press)
	if _calm_press_count >= calm_presses_required:
		anxiety_calmed.emit()
		return
	_choose_next_calm_key()


func _choose_next_calm_key() -> void:
	var previous_key := _calm_key
	while _calm_key == previous_key:
		_calm_key = _calm_keys.pick_random()
	calm_button.text = "CALM  [%s]   %d/%d" % [
		OS.get_keycode_string(_calm_key),
		_calm_press_count,
		calm_presses_required,
	]
	var viewport_size := get_viewport().get_visible_rect().size
	var prompt_size := Vector2(230.0, 64.0)
	calm_button.position = Vector2(
		randf_range(60.0, maxf(60.0, viewport_size.x - prompt_size.x - 60.0)),
		randf_range(120.0, maxf(120.0, viewport_size.y - prompt_size.y - 70.0))
	)
