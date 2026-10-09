extends RigidBody3D

@onready var label: Label3D = $Label
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var outline: MeshInstance3D = %outline
@onready var collide: AudioStreamPlayer3D = $collide

var is_grabbed := false
var is_used := false
var is_outline_visible := false
var collision_cooldown := false

@export_group("Collision Audio")
@export var minimum_impact_speed := 0.8
@export var full_volume_impact_speed := 7.0
@export var collision_cooldown_time := 0.35
@export var quiet_impact_noise_radius := 6.0
@export var loud_impact_noise_radius := 18.0

var _collision_base_volume_db := 0.0

func _ready() -> void:
	add_to_group("grabable")
	outline.visible = false
	label.visible = false
	collision_shape_3d.disabled = false
	_collision_base_volume_db = collide.volume_db

func _process(_delta: float) -> void:
	# Update label to face the camera
	if label and is_grabbed:
		var camera = get_viewport().get_camera_3d()
		if camera:
			label.look_at(camera.global_position)


# Called when the player highlights this object
func show_outline() -> void:
	if not is_grabbed and not is_outline_visible:
		if label:
			label.visible = true
			label.text = "gas"
		outline.visible = true
		is_outline_visible = true

# Called when the player stops highlighting this object
func hide_outline() -> void:
	if is_outline_visible:
		if label:
			label.visible = false
			label.text = "gas"
		outline.visible = false
		is_outline_visible = false

# Called when the object is grabbed
func grab() -> void:
	is_grabbed = true
	
	if collision_shape_3d:
		collision_shape_3d.disabled = true
	
	hide_outline()
	
	freeze = true
	gravity_scale = 0

# Called when the object is dropped
func drop() -> void:
	is_grabbed = false
	
	if collision_shape_3d:
		collision_shape_3d.disabled = false
	
	freeze = false
	gravity_scale = 1.0

# Called when the player uses this object on something (via left click)
func use(target: Node) -> void:
	if is_used:
		return
	
	if target.is_in_group("generator") and target.has_method("fueled"):
		target.fueled()
		is_used = true
		queue_free()

# Collision handler
func _on_body_entered(_body: Node) -> void:
	if is_grabbed or is_used or collision_cooldown or collide.playing:
		return

	var impact_speed := linear_velocity.length()
	if impact_speed < minimum_impact_speed:
		return

	var impact_strength := clampf(inverse_lerp(
		minimum_impact_speed,
		full_volume_impact_speed,
		impact_speed
	), 0.0, 1.0)
	collide.pitch_scale = randf_range(0.85, 1.15)
	collide.volume_db = _collision_base_volume_db + lerpf(-6.0, 0.0, impact_strength)
	collide.play()
	get_tree().call_group(
		"enemy",
		"hear_noise",
		global_position,
		lerpf(quiet_impact_noise_radius, loud_impact_noise_radius, impact_strength)
	)

	collision_cooldown = true
	await get_tree().create_timer(collision_cooldown_time).timeout
	collision_cooldown = false
