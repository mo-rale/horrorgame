extends StaticBody3D
# The plant's fuse box. Fuses are inserted here (hold a fuse, aim, left click),
# not into the generator. Once all three are in, the generator can be started.
# The box is built from code; its front faces local +Z.

signal fuse_installed(fuse_type: String, installed: int, required: int)

const CORRECT_SFX := preload("res://assets/sfx/generator/chrisiex1-correct-156911.mp3")
const ERROR_SFX := preload("res://assets/sfx/generator/error (mp3cut.net).mp3")
const SLOT_COLORS := {
	"RED": Color(1.0, 0.06, 0.04),
	"BLUE": Color(0.08, 0.3, 1.0),
	"YELLOW": Color(1.0, 0.72, 0.05),
}
const SLOT_ORDER := ["RED", "BLUE", "YELLOW"]

var installed_fuses: Array[String] = []
var _slot_materials := {}
var _body_material: StandardMaterial3D
var _label: Label3D
var _audio: AudioStreamPlayer3D
var _outlined := false


func _ready() -> void:
	add_to_group("fuse_box")

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.1, 0.1, 0.11)
	_body_material.metallic = 0.5
	_body_material.roughness = 0.6
	_body_material.emission_enabled = true
	_body_material.emission = Color(0.9, 0.7, 0.3)
	_body_material.emission_energy_multiplier = 0.0

	_add_box(Vector3(1.3, 2.0, 0.5), Vector3(0.0, 1.0, -0.25), _body_material)
	# Dark door panel and a warning stripe so it reads as an electrical cabinet.
	var panel := StandardMaterial3D.new()
	panel.albedo_color = Color(0.04, 0.04, 0.045)
	_add_box(Vector3(1.1, 1.4, 0.04), Vector3(0.0, 1.15, 0.02), panel)
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.85, 0.7, 0.05)
	_add_box(Vector3(1.1, 0.12, 0.05), Vector3(0.0, 1.95, 0.02), stripe)

	for index in SLOT_ORDER.size():
		var fuse_type: String = SLOT_ORDER[index]
		var color: Color = SLOT_COLORS[fuse_type]
		var slot_material := StandardMaterial3D.new()
		slot_material.albedo_color = color * 0.25
		slot_material.emission_enabled = true
		slot_material.emission = color
		slot_material.emission_energy_multiplier = 0.15
		_slot_materials[fuse_type] = slot_material
		_add_box(
			Vector3(0.16, 0.4, 0.08),
			Vector3(-0.32 + 0.32 * index, 1.2, 0.07),
			slot_material
		)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 2.0, 0.6)
	collision.shape = shape
	collision.position = Vector3(0.0, 1.0, -0.2)
	add_child(collision)

	_label = Label3D.new()
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0.0, 2.35, 0.2)
	_label.visible = false
	add_child(_label)

	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"SFX"
	_audio.unit_size = 6.0
	_audio.position = Vector3(0.0, 1.2, 0.2)
	add_child(_audio)


func _add_box(size: Vector3, offset: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	add_child(instance)


func show_outline() -> void:
	_outlined = true
	_body_material.emission_energy_multiplier = 0.35
	_refresh_label()
	_label.visible = true


func hide_outline() -> void:
	_outlined = false
	_body_material.emission_energy_multiplier = 0.0
	_label.visible = false


func interact() -> void:
	# Empty-handed: just report what the box needs.
	_refresh_label()


func is_complete() -> bool:
	return installed_fuses.size() >= SLOT_ORDER.size()


func install_fuse(fuse_type: String) -> bool:
	var generator := get_tree().get_first_node_in_group("generator")
	if generator == null:
		return false
	if (
		generator.has_method("get_current_pressure_valves")
		and generator.get_current_pressure_valves() < generator.get_required_pressure_valves()
	):
		_reject("CLOSE THE PRESSURE VALVES FIRST")
		return false
	if installed_fuses.has(fuse_type) or not SLOT_COLORS.has(fuse_type):
		_reject("THIS SLOT IS ALREADY FILLED")
		return false
	if generator.has_method("install_fuse") and not bool(generator.install_fuse(fuse_type)):
		_reject("THE FUSE WON'T SEAT")
		return false

	installed_fuses.append(fuse_type)
	var material: StandardMaterial3D = _slot_materials[fuse_type]
	material.albedo_color = SLOT_COLORS[fuse_type]
	material.emission_energy_multiplier = 3.5
	_audio.stream = CORRECT_SFX
	_audio.pitch_scale = randf_range(0.95, 1.05)
	_audio.play()
	_refresh_label()
	fuse_installed.emit(fuse_type, installed_fuses.size(), SLOT_ORDER.size())
	return true


func _reject(message: String) -> void:
	_label.text = message
	_label.modulate = Color(1.0, 0.3, 0.25)
	_label.visible = true
	_audio.stream = ERROR_SFX
	_audio.pitch_scale = 1.0
	_audio.play()
	await get_tree().create_timer(1.4).timeout
	if _outlined:
		_refresh_label()
	else:
		_label.visible = false


func _refresh_label() -> void:
	var count := installed_fuses.size()
	if is_complete():
		_label.text = "FUSE BOX\nPOWERED"
		_label.modulate = Color(0.4, 1.0, 0.5)
	else:
		_label.text = "FUSE BOX  %d/%d\nHOLD A FUSE + CLICK" % [count, SLOT_ORDER.size()]
		_label.modulate = Color(1.0, 0.85, 0.4)
