extends Node
# Renders the cover art: the factory gate in a lightning flash with the foreman
# standing in the rain, plus the title. Writes assets/ui/cover.png (1920x1080),
# assets/ui/splash.png (boot splash) and icon.png.
# Run windowed from the project root:  godot --path . res://tools/make_cover.tscn

const FONT_BOLD := "res://assets/fonts/Cinzel,Irish_Grover/Cinzel/static/Cinzel-Bold.ttf"
const FONT_SEMI := "res://assets/fonts/Cinzel,Irish_Grover/Cinzel/static/Cinzel-SemiBold.ttf"

var _frames := 0
var _viewport: SubViewport
var _scenery: Node3D
var _camera: Camera3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	_scenery = (load("res://scenes/main_menu_scenery.tscn") as PackedScene).instantiate()
	_viewport.add_child(_scenery)
	_camera = _scenery.get_node("Camera3D") as Camera3D
	_camera.fov = 42.0
	(_scenery.get_node("Rain") as GPUParticles3D).amount = 4200
	_viewport.add_child(_overlay())


func _overlay() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(1920, 1080)

	# Vignette: darker toward the edges and a heavier left side for the title.
	for spec in [[0.0, 0.0, 1920.0, 1080.0, Color(0, 0, 0, 0.0)]]:
		pass
	var left := _gradient_rect(Vector2.ZERO, Vector2(1100, 1080), Color(0, 0, 0, 0.86), Color(0, 0, 0, 0.0), true)
	root.add_child(left)
	var bottom := _gradient_rect(Vector2(0, 700), Vector2(1920, 380), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.8), false)
	root.add_child(bottom)
	var top := _gradient_rect(Vector2(0, 0), Vector2(1920, 260), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), false)
	root.add_child(top)

	_label(root, "A NIGHT SHIFT HORROR", FONT_SEMI, 26, Color(0.62, 0.2, 0.16), Vector2(110, 312))
	_label(root, "HALVERSON", FONT_BOLD, 118, Color(0.8, 0.07, 0.06), Vector2(104, 350), 12)
	_label(root, "WORKS", FONT_BOLD, 118, Color(0.8, 0.07, 0.06), Vector2(104, 462), 12)
	var rule := ColorRect.new()
	rule.color = Color(0.45, 0.07, 0.05)
	rule.position = Vector2(116, 626)
	rule.size = Vector2(430, 3)
	root.add_child(rule)
	_label(root, "NIGHT SHIFT. NOBODY CLOCKED OUT.", FONT_SEMI, 30, Color(0.66, 0.6, 0.54), Vector2(112, 646))
	_label(root, "RESTORE THE POWER  -  CLOSE THE VALVES  -  GET OUT", FONT_SEMI, 18, Color(0.45, 0.42, 0.38), Vector2(114, 948))
	return root


func _gradient_rect(pos: Vector2, rect_size: Vector2, from: Color, to: Color, horizontal: bool) -> TextureRect:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([from, to])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.position = pos
	rect.size = rect_size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	return rect


func _label(parent: Control, text: String, font_path: String, size: int, color: Color, pos: Vector2, outline := 4) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", load(font_path))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0, 0))
	label.add_theme_constant_override("outline_size", outline)
	label.position = pos
	parent.add_child(label)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 3:
		# Freeze the set, stage the shot, and fire one bright strike.
		_scenery.set_process(false)
		(_scenery.get_node("Set") as Node3D).set_process(false)
		_camera.position = Vector3(6.4, 1.3, -3.4)
		_camera.look_at(Vector3(8.4, 1.9, -20.0))
		var figure := _scenery.get_node("Set/Figure") as Node3D
		figure.position = Vector3(7.2, 0.95, -10.5)
		figure.look_at(Vector3(_camera.global_position.x, figure.position.y, _camera.global_position.z), Vector3.UP)
		(_scenery.get_node("LightningLight") as DirectionalLight3D).light_energy = 1.7
		(_scenery.get_node("LightningLight") as DirectionalLight3D).rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	if _frames == 14:
		var image := _viewport.get_texture().get_image()
		image.save_png("res://assets/ui/cover.png")
		var splash := image.duplicate() as Image
		splash.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
		splash.save_png("res://assets/ui/splash.png")
		print("[Cover] wrote cover.png and splash.png")
		get_tree().quit()
