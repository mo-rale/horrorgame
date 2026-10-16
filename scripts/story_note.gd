extends StaticBody3D
# A readable note. Look at it and press E to read; press E again, ESC, or walk
# away to put it down. The paper, collision and hint live in scenes/story_note.tscn.

@export var title := "NOTE"
@export_multiline var body := ""
@export var paper_size := Vector3(0.4, 0.03, 0.3)
@export var read_range := 4.0

static var notes_read := {}

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _hint: Label3D
var _layer: CanvasLayer
var _reading := false
var _opened_frame := -10


func _ready() -> void:
	if has_node("Paper"):
		_mesh = $Paper
		_hint = $Hint
	else:
		_build_model()
	# Each note has its own paper size and highlight, so give it private copies
	# of the scene's shared mesh, shape and material.
	_material = _mesh.material_override.duplicate() as StandardMaterial3D
	_mesh.material_override = _material
	var box := (_mesh.mesh as BoxMesh).duplicate() as BoxMesh
	box.size = paper_size
	_mesh.mesh = box
	var shape := ($CollisionShape3D.shape as BoxShape3D).duplicate() as BoxShape3D
	shape.size = paper_size + Vector3(0.12, 0.12, 0.12)
	$CollisionShape3D.shape = shape
	_hint.position = Vector3(0.0, maxf(paper_size.y, 0.3) * 0.5 + 0.2, 0.0)
	_hint.visible = false


func _build_model() -> void:
	# Only used by tools/bake_scenes.gd to create scenes/story_note.tscn.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.86, 0.8, 0.62)
	material.emission_enabled = true
	material.emission = Color(0.55, 0.48, 0.3)
	material.emission_energy_multiplier = 0.25
	_mesh = MeshInstance3D.new()
	_mesh.name = "Paper"
	var box := BoxMesh.new()
	box.size = paper_size
	_mesh.mesh = box
	_mesh.material_override = material
	add_child(_mesh)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = paper_size + Vector3(0.12, 0.12, 0.12)
	collision.shape = shape
	add_child(collision)

	_hint = Label3D.new()
	_hint.name = "Hint"
	_hint.text = "[E] READ"
	_hint.font_size = 36
	_hint.pixel_size = 0.004
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.no_depth_test = true
	_hint.modulate = Color(1.0, 0.9, 0.6)
	_hint.position = Vector3(0.0, 0.35, 0.0)
	_hint.visible = false
	add_child(_hint)


func show_outline() -> void:
	_material.emission_energy_multiplier = 1.6
	_hint.visible = not _reading


func hide_outline() -> void:
	_material.emission_energy_multiplier = 0.25
	_hint.visible = false


func interact() -> void:
	if _reading:
		_close()
	else:
		_open()


func _open() -> void:
	_reading = true
	_opened_frame = Engine.get_process_frames()
	_hint.visible = false
	notes_read[name] = true
	_layer = CanvasLayer.new()
	_layer.layer = 35
	add_child(_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -48.0
	panel.custom_minimum_size = Vector2(640.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.92)
	style.border_color = Color(0.55, 0.45, 0.25)
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	column.add_child(heading)
	var text := Label.new()
	text.text = body.replace("\\n", "\n")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 17)
	text.add_theme_color_override("font_color", Color(0.9, 0.87, 0.78))
	text.custom_minimum_size = Vector2(600.0, 0.0)
	column.add_child(text)
	var footer := Label.new()
	footer.text = "[E] close"
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	column.add_child(footer)


func _close() -> void:
	_reading = false
	if is_instance_valid(_layer):
		_layer.queue_free()
		_layer = null


func _process(_delta: float) -> void:
	if not _reading:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var too_far := (
		player != null
		and player.global_position.distance_to(global_position) > read_range
	)
	var pressed_close := (
		Engine.get_process_frames() - _opened_frame > 2
		and (Input.is_action_just_pressed("Interact") or Input.is_key_pressed(KEY_ESCAPE))
	)
	if too_far or pressed_close:
		_close()
