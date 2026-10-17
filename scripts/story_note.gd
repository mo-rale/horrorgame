extends StaticBody3D
# A readable note. Look at it and press E to read; press E again, ESC, or walk
# away to put it down. The paper, collision and hint live in scenes/story_note.tscn.
# The note is a handwritten card in the Whispered Evidence font (title, date line,
# body, signature): shown large while reading, and drawn once as a texture onto
# the paper sheet in the level.

const HAND: Font = preload("res://assets/fonts/WhisperedEvidence/WhisperedEvidence-Regular.ttf")
const PAPER_SHADER: Shader = preload("res://scenes/note_paper.gdshader")
const PAPER_COLOR := Color(0.85, 0.8, 0.67)
const INK := Color(0.16, 0.14, 0.12)
const RED_INK := Color(0.42, 0.1, 0.08)
const FADED_INK := Color(0.36, 0.33, 0.29)
# Cards are laid out for this height and scaled to whatever size they are drawn at.
const CARD_HEIGHT := 900.0
# Height in pixels of the texture drawn onto the paper in the level.
const TEXTURE_HEIGHT := 640.0
# Thickness of the paper sheet in the level (paper_size only sets its outline).
const SHEET := 0.004

@export var title := "NOTE"
## Small line under the title: when it was written, or what it is.
@export var date_line := ""
@export_multiline var body := ""
## Signed at the bottom, e.g. "Mara".
@export var signature := ""
@export var paper_size := Vector3(0.4, 0.03, 0.3)
@export var read_range := 4.0

static var notes_read := {}

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _face: MeshInstance3D
var _face_material: StandardMaterial3D
var _hint: Label3D
var _layer: CanvasLayer
var _frame: Control
var _reading := false
var _opened_frame := -10
# The sheet rests against whatever is behind the thinnest side of paper_size (a
# desk, a crate, a wall). _front points away from that surface; the writing faces
# that way with _face_basis and covers _face_size.
var _front := Vector3.UP
var _face_basis := Basis.IDENTITY
var _face_size := Vector2.ONE


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
	var shape := ($CollisionShape3D.shape as BoxShape3D).duplicate() as BoxShape3D
	shape.size = paper_size + Vector3(0.12, 0.12, 0.12)
	$CollisionShape3D.shape = shape
	_hint.position = Vector3(0.0, maxf(paper_size.y, 0.3) * 0.5 + 0.2, 0.0)
	_hint.visible = false
	_build_sheet()
	_settle_on_surface()
	_draw_writing()


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
	_hint.text = "[%s] READ" % Settings.key_text("Interact")
	_hint.font_size = 36
	_hint.pixel_size = 0.004
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.no_depth_test = true
	_hint.modulate = Color(1.0, 0.9, 0.6)
	_hint.position = Vector3(0.0, 0.35, 0.0)
	_hint.visible = false
	add_child(_hint)


# ── The paper in the level ───────────────────────────────────────────────────

func _build_sheet() -> void:
	# A thin sheet at the back of the paper_size box, with the writing on a quad
	# just in front of it. Wall notes stand up; desk notes read from the -Z edge.
	var thin := 0
	for axis in 3:
		if paper_size[axis] < paper_size[thin]:
			thin = axis
	_front = Vector3.ZERO
	_front[thin] = 1.0
	var up := Vector3.FORWARD if thin == 1 else Vector3.UP
	var right := up.cross(_front)
	_face_basis = Basis(right, up, _front)
	_face_size = Vector2((paper_size * right).abs().length(), (paper_size * up).abs().length())

	var box := (_mesh.mesh as BoxMesh).duplicate() as BoxMesh
	var sheet_size := paper_size
	sheet_size[thin] = SHEET
	box.size = sheet_size
	_mesh.mesh = box

	_face_material = StandardMaterial3D.new()
	_face_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_face_material.emission_enabled = true
	_face_material.emission = _material.emission
	_face_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	_face_material.emission_energy_multiplier = _material.emission_energy_multiplier
	var quad := QuadMesh.new()
	quad.size = _face_size
	_face = MeshInstance3D.new()
	_face.mesh = quad
	_face.material_override = _face_material
	_face.basis = _face_basis
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_face.visible = false
	# Internal, so tools/bake_scenes.gd never saves it into the scene.
	add_child(_face, false, Node.INTERNAL_MODE_BACK)
	_place_sheet(paper_size[thin] * 0.5)


## Puts the sheet's back `depth` metres behind the note's centre.
func _place_sheet(depth: float) -> void:
	_mesh.position = _front * (SHEET * 0.5 + 0.001 - depth)
	_face.position = _mesh.position + _front * (SHEET * 0.5 + 0.0006)


func _settle_on_surface() -> void:
	# Lay the sheet flat on whatever it rests on, once the level's collision exists.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var front := (global_basis * _front).normalized()
	var query := PhysicsRayQueryParameters3D.create(
		global_position + front * 0.05, global_position - front * 0.4)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var depth := front.dot(global_position - hit.position)
	# Only a nearby surface: a note over a gap keeps its place instead of falling.
	if depth <= paper_size[_front.abs().max_axis_index()] * 0.5 + 0.15:
		_place_sheet(depth)


func _draw_writing() -> void:
	# Draw the card once into a texture for the paper, then drop the viewport.
	if DisplayServer.get_name() == "headless":
		return
	var pixels := Vector2(TEXTURE_HEIGHT * _face_size.x / _face_size.y, TEXTURE_HEIGHT).round()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(pixels)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(_build_card(pixels))
	add_child(viewport, false, Node.INTERNAL_MODE_BACK)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_face_material.albedo_texture = texture
	_face_material.emission_texture = texture
	_face.visible = true


# ── The card ─────────────────────────────────────────────────────────────────

## Builds the handwritten card at `size` pixels: aged paper, red title with a
## rule under it, the date line, the body (shrunk to fit) and the signature.
func _build_card(size: Vector2) -> Control:
	var k := size.y / CARD_HEIGHT
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var card := Control.new()
	card.size = size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var paper := ColorRect.new()
	var paper_material := ShaderMaterial.new()
	paper_material.shader = PAPER_SHADER
	paper_material.set_shader_parameter("paper", PAPER_COLOR)
	paper_material.set_shader_parameter("size", size)
	paper_material.set_shader_parameter("seed", rng.randf() * 100.0)
	paper.material = paper_material
	paper.size = size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)

	var margin := Vector2(78.0, 58.0) * k
	var width := size.x - margin.x * 2.0
	var title_size := _fit_line(title, 64.0 * k, width)
	var date_size := _fit_line(date_line, 30.0 * k, width)
	var signature_size := _fit_line("—" + signature, 48.0 * k, width)
	var heading := _hand_label(title, title_size, RED_INK)
	var rule := ColorRect.new()
	rule.color = Color(RED_INK, 0.75)
	rule.custom_minimum_size = Vector2(0.0, maxf(1.0, 2.5 * k))
	var dated := _hand_label(date_line, date_size, FADED_INK)
	dated.visible = not date_line.is_empty()
	# The bottom row holds the signature (if any) and the red scratch, so it is
	# always kept free of body text.
	var signed := _hand_label("" if signature.is_empty() else "—" + signature, signature_size, INK)
	signed.custom_minimum_size = Vector2(0.0, HAND.get_height(signature_size))
	var text := body.replace("\\n", "\n").strip_edges()

	# Shrink the body until everything fits on the card.
	var fixed := margin.y * 2.0 + HAND.get_height(title_size) + rule.custom_minimum_size.y + 30.0 * k
	fixed += HAND.get_height(signature_size) + 18.0 * k
	if dated.visible:
		fixed += HAND.get_height(date_size) + 6.0 * k
	var spacing := 6.0 * k
	var body_size := int(40.0 * k)
	while body_size > int(18.0 * k):
		var lines := HAND.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, body_size).y \
			/ HAND.get_height(body_size)
		if fixed + lines * (HAND.get_height(body_size) + spacing) <= size.y * 0.97:
			break
		body_size -= 1
	var writing := _hand_label(text, body_size, INK)
	writing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	writing.add_theme_constant_override("line_spacing", int(spacing))
	writing.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.position = margin
	column.size = Vector2(width, size.y - margin.y * 2.0)
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	column.add_child(heading)
	column.add_child(rule)
	column.add_child(_gap(12.0 * k))
	column.add_child(dated)
	column.add_child(_gap(18.0 * k))
	column.add_child(writing)
	column.add_child(signed)

	# A double scratch of red ink at the end of the signature row, a little
	# different on every note. It rises to the right from its lower-left end.
	var mark := Control.new()
	mark.position = Vector2(size.x - margin.x - rng.randf_range(100.0, 140.0) * k,
		size.y - margin.y - rng.randf_range(6.0, 16.0) * k)
	mark.rotation = deg_to_rad(rng.randf_range(-48.0, -36.0))
	card.add_child(mark)
	for i in 2:
		var stroke := ColorRect.new()
		stroke.color = Color(0.55, 0.14, 0.1, 0.85)
		stroke.size = Vector2(rng.randf_range(110.0, 135.0) * k, maxf(1.0, 2.2 * k))
		stroke.position = Vector2(0.0, i * 7.0 * k)
		mark.add_child(stroke)
	return card


## The largest font size up to `font_size` at which one line of `text` fits in `width`.
func _fit_line(text: String, font_size: float, width: float) -> int:
	var fitted := int(font_size)
	while fitted > 8 and HAND.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > width:
		fitted -= 1
	return fitted


func _hand_label(text: String, font_size: float, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", HAND)
	label.add_theme_font_size_override("font_size", maxi(1, int(font_size)))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, height)
	return gap


# ── Reading ──────────────────────────────────────────────────────────────────

func show_outline() -> void:
	_material.emission_energy_multiplier = 1.6
	_face_material.emission_energy_multiplier = 1.6
	_hint.visible = not _reading


func hide_outline() -> void:
	_material.emission_energy_multiplier = 0.25
	_face_material.emission_energy_multiplier = 0.25
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
	add_child(_layer, false, Node.INTERNAL_MODE_BACK)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(dim)

	# Laid out on a 1920x1080 frame, scaled to the window.
	_frame = Control.new()
	_frame.size = Vector2(1920.0, 1080.0)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_frame)
	get_viewport().size_changed.connect(_fit_frame)
	_fit_frame()

	# Wide enough to read comfortably, even for the tall wall notices.
	var card_size := Vector2(clampf(860.0 * _face_size.x / _face_size.y, 960.0, 1240.0), 860.0)
	var shadow := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER_COLOR
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size = 28
	style.shadow_offset = Vector2(8.0, 12.0)
	shadow.add_theme_stylebox_override("panel", style)
	shadow.size = card_size
	shadow.position = (_frame.size - card_size) * 0.5 - Vector2(0.0, 20.0)
	shadow.pivot_offset = card_size * 0.5
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.add_child(_build_card(card_size))
	_frame.add_child(shadow)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) + 1
	var tilt := deg_to_rad(rng.randf_range(-1.4, 1.4))

	var footer := Label.new()
	footer.text = "[%s] close" % Settings.key_text("Interact")
	footer.add_theme_font_size_override("font_size", 22)
	footer.add_theme_color_override("font_color", Color(0.75, 0.7, 0.62))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.size = Vector2(1920.0, 40.0)
	footer.position = Vector2(0.0, 1020.0)
	_frame.add_child(footer)

	# Lift the paper into view.
	shadow.modulate.a = 0.0
	shadow.rotation = tilt + deg_to_rad(2.0)
	shadow.position.y += 40.0
	var tween := _layer.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(dim, "color:a", 0.62, 0.2)
	tween.tween_property(shadow, "modulate:a", 1.0, 0.18)
	tween.tween_property(shadow, "rotation", tilt, 0.3)
	tween.tween_property(shadow, "position:y", shadow.position.y - 40.0, 0.3)


func _fit_frame() -> void:
	if not is_instance_valid(_frame):
		return
	var view := get_viewport().get_visible_rect().size
	var s := minf(view.x / 1920.0, view.y / 1080.0)
	_frame.scale = Vector2(s, s)
	_frame.position = (view - Vector2(1920.0, 1080.0) * s) * 0.5


func _close() -> void:
	_reading = false
	if get_viewport().size_changed.is_connected(_fit_frame):
		get_viewport().size_changed.disconnect(_fit_frame)
	if is_instance_valid(_layer):
		_layer.queue_free()
		_layer = null
		_frame = null


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
