extends Node
# Renders the game's logo assets from icon.svg: a 256 px icon.png (used for the
# Windows export icon) and the 1280x720 boot splash.
# Run windowed from the project root:
#   godot --path . res://tools/make_logo_assets.tscn
# Outputs: res://icon.png and res://assets/ui/splash.png

const FONT_BOLD := "res://assets/fonts/Cinzel,Irish_Grover/Cinzel/static/Cinzel-Bold.ttf"
const FONT_SEMI := "res://assets/fonts/Cinzel,Irish_Grover/Cinzel/static/Cinzel-SemiBold.ttf"

var _frames := 0
var _viewport: SubViewport


func _ready() -> void:
	# icon.png from the SVG at 2x.
	var image := Image.new()
	image.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"), 2.0)
	image.save_png("res://icon.png")

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var background := ColorRect.new()
	background.color = Color(0.02, 0.014, 0.014)
	background.size = Vector2(1280, 720)
	_viewport.add_child(background)

	# A dim red glow behind the logo.
	var glow := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.28, 0.04, 0.03, 0.9), Color(0, 0, 0, 0)])
	var radial := GradientTexture2D.new()
	radial.gradient = gradient
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(0.5, 0.5)
	radial.fill_to = Vector2(1.0, 0.5)
	radial.width = 512
	radial.height = 512
	glow.texture = radial
	glow.position = Vector2(280, -20)
	glow.size = Vector2(720, 760)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_viewport.add_child(glow)

	var logo := TextureRect.new()
	var logo_image := Image.new()
	logo_image.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"), 2.4)
	logo.texture = ImageTexture.create_from_image(logo_image)
	logo.position = Vector2(640 - logo_image.get_width() * 0.5, 96)
	_viewport.add_child(logo)

	_add_label("HALVERSON WORKS", FONT_BOLD, 84, Color(0.78, 0.07, 0.06), 440)
	_add_label("NIGHT SHIFT. NOBODY CLOCKED OUT.", FONT_SEMI, 24, Color(0.55, 0.5, 0.46), 560)


func _add_label(text: String, font_path: String, size: int, color: Color, y: float) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", load(font_path))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0, 0))
	label.add_theme_constant_override("outline_size", 8 if size > 40 else 2)
	label.position = Vector2(0, y)
	label.size = Vector2(1280, size * 1.4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_viewport.add_child(label)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 6:
		_viewport.get_texture().get_image().save_png("res://assets/ui/splash.png")
		print("[Logo] wrote icon.png and assets/ui/splash.png")
		get_tree().quit()
