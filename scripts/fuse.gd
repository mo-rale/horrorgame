extends RigidBody3D

@export_enum("RED", "BLUE", "YELLOW") var fuse_type: String = "RED"
@export var fuse_color := Color(0.85, 0.08, 0.06, 1.0)

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var outline: MeshInstance3D = $Outline
@onready var label: Label3D = $Label
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var is_grabbed := false
var is_used := false


func _ready() -> void:
	add_to_group("grabable")
	add_to_group("fuse")
	outline.visible = false
	label.visible = false
	var material := mesh.material_override as StandardMaterial3D
	if material:
		material = material.duplicate()
		material.albedo_color = fuse_color
		material.emission_enabled = true
		material.emission = fuse_color * 0.28
		mesh.material_override = material


func _process(_delta: float) -> void:
	if label.visible:
		var camera := get_viewport().get_camera_3d()
		if camera:
			label.look_at(camera.global_position)


func show_outline() -> void:
	if is_grabbed or is_used:
		return
	outline.visible = true
	label.text = "%s FUSE" % fuse_type
	label.modulate = fuse_color.lightened(0.25)
	label.visible = true


func hide_outline() -> void:
	outline.visible = false
	label.visible = false


func grab() -> void:
	is_grabbed = true
	collision_shape.disabled = true
	hide_outline()
	freeze = true
	gravity_scale = 0.0


func drop() -> void:
	is_grabbed = false
	collision_shape.disabled = false
	freeze = false
	gravity_scale = 1.0


func use(target: Node) -> void:
	if is_used:
		return
	# Fuses go into the plant's fuse box, never straight into the generator.
	if target.is_in_group("fuse_box") and target.has_method("install_fuse"):
		if bool(target.install_fuse(fuse_type)):
			is_used = true
			queue_free()
