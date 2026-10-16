extends RigidBody3D

const FuseModel := preload("res://scripts/fuse_model.gd")

@export_enum("RED", "BLUE", "YELLOW") var fuse_type: String = "RED"
@export var fuse_color := Color(0.85, 0.08, 0.06, 1.0)

@onready var label: Label3D = $Label
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var is_grabbed := false
var is_used := false

var _outline: MeshInstance3D
var _glow_light: OmniLight3D


func _ready() -> void:
	add_to_group("grabable")
	add_to_group("fuse")
	label.visible = false

	# The cartridge lies along local Z so it sits in the hand like before.
	var model := FuseModel.build(fuse_color)
	model.rotation.x = PI * 0.5
	add_child(model)

	var outline_mesh := CylinderMesh.new()
	outline_mesh.top_radius = 0.11
	outline_mesh.bottom_radius = 0.11
	outline_mesh.height = 0.68
	var outline_material := StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_material.albedo_color = Color(1.0, 0.82, 0.18, 0.34)
	_outline = MeshInstance3D.new()
	_outline.mesh = outline_mesh
	_outline.material_override = outline_material
	_outline.rotation.x = PI * 0.5
	_outline.visible = false
	add_child(_outline)

	# A faint coloured glow makes a dropped fuse findable in the dark.
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = fuse_color
	_glow_light.light_energy = 0.45
	_glow_light.omni_range = 2.6
	_glow_light.shadow_enabled = false
	add_child(_glow_light)


func _process(_delta: float) -> void:
	if label.visible:
		var camera := get_viewport().get_camera_3d()
		if camera:
			label.look_at(camera.global_position)


func show_outline() -> void:
	if is_grabbed or is_used:
		return
	_outline.visible = true
	label.text = "%s FUSE" % fuse_type
	label.modulate = fuse_color.lightened(0.25)
	label.visible = true


func hide_outline() -> void:
	_outline.visible = false
	label.visible = false


func grab() -> void:
	is_grabbed = true
	collision_shape.disabled = true
	hide_outline()
	freeze = true
	gravity_scale = 0.0
	_glow_light.visible = false


func drop() -> void:
	is_grabbed = false
	collision_shape.disabled = false
	freeze = false
	gravity_scale = 1.0
	_glow_light.visible = true


func use(target: Node) -> void:
	if is_used:
		return
	# Fuses go into the plant's fuse box, never straight into the generator.
	if target.is_in_group("fuse_box") and target.has_method("install_fuse"):
		if bool(target.install_fuse(fuse_type)):
			is_used = true
			queue_free()
