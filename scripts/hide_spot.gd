extends StaticBody3D
# A locker the player can hide in. Look at it and press Interact to climb in; press
# Interact again to climb out. While hidden the player cannot be seen, but the
# enemy remembers where it last saw them: hide in sight and it opens the locker.
# The model is built in code; the door faces local +Z.

const LOCKER_TEXTURE := preload("res://assets/SBS - Horror Texture Pack 128x128/128x128/Metal/Horror_Metal_11-128x128.png")

var occupied := false

var _hint: Label3D
var _material: StandardMaterial3D
var _collision: CollisionShape3D


func _ready() -> void:
	add_to_group("hide_spot")
	_material = StandardMaterial3D.new()
	_material.albedo_texture = LOCKER_TEXTURE
	_material.albedo_color = Color(0.55, 0.6, 0.55)
	_material.uv1_triplanar = true
	_material.uv1_scale = Vector3.ONE * 0.9
	_material.roughness = 0.8
	_material.emission_enabled = true
	_material.emission = Color(1.0, 0.75, 0.35)
	_material.emission_energy_multiplier = 0.0

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)

	_add_box("Body", Vector3(0.95, 2.3, 0.7), Vector3(0, 1.15, 0), _material)
	_add_box("Door", Vector3(0.84, 2.1, 0.03), Vector3(0, 1.15, 0.36), _material)
	for index in 5:
		_add_box("Slit%d" % index, Vector3(0.5, 0.025, 0.035), Vector3(0, 1.75 + index * 0.07, 0.37), dark)
	_add_box("Handle", Vector3(0.04, 0.16, 0.05), Vector3(0.3, 1.1, 0.39), dark)

	_collision = CollisionShape3D.new()
	_collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 2.3, 0.7)
	_collision.shape = shape
	_collision.position = Vector3(0, 1.15, 0)
	add_child(_collision)

	_hint = Label3D.new()
	_hint.name = "Hint"
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.no_depth_test = true
	_hint.font_size = 36
	_hint.pixel_size = 0.004
	_hint.modulate = Color(1.0, 0.9, 0.6)
	_hint.position = Vector3(0, 2.6, 0.4)
	_hint.visible = false
	add_child(_hint)


func _add_box(part_name: String, size: Vector3, offset: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	add_child(instance)


## Where the player's feet go while hiding.
func hide_position() -> Vector3:
	return global_position + Vector3(0.0, 0.05, 0.0)


## Where the player's feet go when climbing out (in front of the door).
func exit_position() -> Vector3:
	return global_position + global_basis.z.normalized() * 1.1


func set_occupied(value: bool) -> void:
	occupied = value
	_collision.set_deferred("disabled", value)
	# From inside you look out through the door slats: hide the shell so the
	# room is visible through the slit in the screen overlay.
	for part in ["Body", "Door", "Handle"]:
		(get_node(part) as MeshInstance3D).visible = not value
	_hint.visible = false


func show_outline() -> void:
	if occupied:
		return
	_material.emission_energy_multiplier = 0.35
	_hint.text = "[%s] HIDE" % Settings.key_text("Interact")
	_hint.visible = true


func hide_outline() -> void:
	_material.emission_energy_multiplier = 0.0
	_hint.visible = false


func interact() -> void:
	if occupied:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("hide_in"):
		player.hide_in(self)
