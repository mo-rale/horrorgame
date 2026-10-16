extends SceneTree
# Builds assets/ui/horror_theme.tres: the game's dark, rust-and-blood UI theme.
# Run from the project root:
#   godot --headless --path . --script res://tools/build_ui_theme.gd
# The theme is a normal resource: open it in the editor to tweak any style.

const OUT := "res://assets/ui/horror_theme.tres"
const FONT_BOLD := "res://assets/fonts/Cinzel,Irish_Grover/Cinzel/static/Cinzel-Bold.ttf"
const FONT_SEMI := "res://assets/fonts/Cinzel,Irish_Grover/Cinzel/static/Cinzel-SemiBold.ttf"

const INK := Color(0.035, 0.03, 0.03, 0.9)
const INK_SOLID := Color(0.06, 0.05, 0.05, 0.95)
const RUST := Color(0.36, 0.08, 0.06)
const BLOOD := Color(0.78, 0.06, 0.06)
const BONE := Color(0.82, 0.78, 0.7)
const ASH := Color(0.5, 0.47, 0.42)


func _initialize() -> void:
	var theme := Theme.new()
	theme.default_font_size = 18

	_label(theme)
	_buttons(theme)
	_panels(theme)
	_sliders(theme)
	_check_button(theme)
	_progress_bar(theme)

	DirAccess.make_dir_recursive_absolute("res://assets/ui")
	var error := ResourceSaver.save(theme, OUT)
	print("[Theme] %s -> %s" % [OUT, "saved" if error == OK else "FAILED"])
	quit()


func _flat(bg: Color, border: Color, widths := Vector4(0, 0, 0, 0), margins := Vector4(16, 8, 16, 8), shadow := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = int(widths.x)
	style.border_width_top = int(widths.y)
	style.border_width_right = int(widths.z)
	style.border_width_bottom = int(widths.w)
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	style.anti_aliasing = false
	if shadow > 0:
		style.shadow_color = Color(0, 0, 0, 0.55)
		style.shadow_size = shadow
	return style


func _label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", BONE)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	theme.set_constant("outline_size", "Label", 2)

	# Big titles: used through theme_type_variation = "HeadingLabel".
	theme.set_type_variation("HeadingLabel", "Label")
	theme.set_font("font", "HeadingLabel", load(FONT_BOLD))
	theme.set_font_size("font_size", "HeadingLabel", 52)
	theme.set_color("font_color", "HeadingLabel", BLOOD)
	theme.set_color("font_outline_color", "HeadingLabel", Color(0.08, 0, 0, 1))
	theme.set_constant("outline_size", "HeadingLabel", 6)

	# Small dim text: subtitles, hints, control reminders.
	theme.set_type_variation("SubtleLabel", "Label")
	theme.set_font_size("font_size", "SubtleLabel", 15)
	theme.set_color("font_color", "SubtleLabel", ASH)

	# The first line of the objective panel: bone-white (the game tints it with
	# modulate to show progress).
	theme.set_type_variation("HudTitle", "Label")
	theme.set_font("font", "HudTitle", load(FONT_SEMI))
	theme.set_font_size("font_size", "HudTitle", 22)

	# Section captions ("AUDIO", "OBJECTIVE").
	theme.set_type_variation("CaptionLabel", "Label")
	theme.set_font("font", "CaptionLabel", load(FONT_SEMI))
	theme.set_font_size("font_size", "CaptionLabel", 17)
	theme.set_color("font_color", "CaptionLabel", Color(0.65, 0.2, 0.16))


func _buttons(theme: Theme) -> void:
	var normal := _flat(Color(0.07, 0.06, 0.06, 0.82), RUST, Vector4(3, 0, 0, 0), Vector4(20, 10, 20, 10), 4)
	var hover := _flat(Color(0.17, 0.035, 0.035, 0.95), BLOOD, Vector4(6, 0, 0, 0), Vector4(20, 10, 20, 10), 8)
	var pressed := _flat(Color(0.3, 0.04, 0.04, 1.0), Color(1, 0.2, 0.15), Vector4(6, 0, 0, 0), Vector4(20, 10, 20, 10))
	var focus := _flat(Color(0.12, 0.03, 0.03, 0.95), BLOOD, Vector4(6, 0, 0, 0), Vector4(20, 10, 20, 10), 8)
	var disabled := _flat(Color(0.05, 0.05, 0.05, 0.6), Color(0.15, 0.15, 0.15), Vector4(3, 0, 0, 0), Vector4(20, 10, 20, 10))
	for button_type in ["Button", "CheckButton"]:
		theme.set_stylebox("normal", button_type, normal)
		theme.set_stylebox("hover", button_type, hover)
		theme.set_stylebox("pressed", button_type, pressed)
		theme.set_stylebox("focus", button_type, focus)
		theme.set_stylebox("disabled", button_type, disabled)
		theme.set_stylebox("hover_pressed", button_type, pressed)
		theme.set_font("font", button_type, load(FONT_SEMI))
		theme.set_font_size("font_size", button_type, 22)
		theme.set_color("font_color", button_type, BONE)
		theme.set_color("font_hover_color", button_type, Color(1, 0.93, 0.86))
		theme.set_color("font_pressed_color", button_type, Color(1, 0.45, 0.38))
		theme.set_color("font_focus_color", button_type, Color(1, 0.93, 0.86))
		theme.set_color("font_hover_pressed_color", button_type, Color(1, 0.45, 0.38))
		theme.set_color("font_disabled_color", button_type, Color(0.4, 0.38, 0.35))
		theme.set_color("font_outline_color", button_type, Color(0, 0, 0, 0.7))
		theme.set_constant("outline_size", button_type, 2)


func _panels(theme: Theme) -> void:
	var panel := _flat(INK, RUST, Vector4(4, 1, 1, 1), Vector4(18, 14, 18, 14), 10)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	# A flatter, translucent panel for in-game HUD overlays.
	theme.set_type_variation("HudPanel", "PanelContainer")
	theme.set_stylebox("panel", "HudPanel", _flat(Color(0.02, 0.018, 0.018, 0.72), RUST, Vector4(4, 0, 0, 0), Vector4(16, 12, 16, 12)))


func _sliders(theme: Theme) -> void:
	theme.set_stylebox("slider", "HSlider", _flat(Color(0.1, 0.08, 0.08, 0.95), Color(0.25, 0.1, 0.08), Vector4(1, 1, 1, 1), Vector4(0, 0, 0, 0)))
	theme.set_stylebox("grabber_area", "HSlider", _flat(Color(0.5, 0.06, 0.05), Color(0.5, 0.06, 0.05), Vector4(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _flat(Color(0.8, 0.09, 0.07), Color(0.8, 0.09, 0.07), Vector4(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
	var grabber := _circle(Color(0.85, 0.8, 0.72))
	var grabber_hot := _circle(Color(1.0, 0.35, 0.28))
	theme.set_icon("grabber", "HSlider", grabber)
	theme.set_icon("grabber_highlight", "HSlider", grabber_hot)
	theme.set_icon("grabber_disabled", "HSlider", _circle(Color(0.35, 0.33, 0.3)))
	theme.set_constant("center_grabber", "HSlider", 0)
	theme.set_constant("grabber_offset", "HSlider", 0)
	# A fixed-height track: styleboxes above need a minimum height to show.
	var track: StyleBoxFlat = theme.get_stylebox("slider", "HSlider")
	track.content_margin_top = 4
	track.content_margin_bottom = 4


func _circle(color: Color) -> ImageTexture:
	var size := 20
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if distance <= size * 0.5 - 1.0:
				var edge := clampf(size * 0.5 - distance, 0.0, 1.0)
				var shade := 1.0 - 0.35 * (distance / (size * 0.5))
				image.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, edge))
	return ImageTexture.create_from_image(image)


func _check_button(theme: Theme) -> void:
	theme.set_constant("h_separation", "CheckButton", 14)


func _progress_bar(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", _flat(Color(0.06, 0.05, 0.05, 0.9), Color(0.25, 0.1, 0.08), Vector4(1, 1, 1, 1), Vector4(0, 0, 0, 0)))
	theme.set_stylebox("fill", "ProgressBar", _flat(BLOOD, BLOOD, Vector4(0, 0, 0, 0), Vector4(0, 0, 0, 0)))
