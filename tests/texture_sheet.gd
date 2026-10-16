extends Control
# Run: Godot --path . res://tests/texture_sheet.tscn
# Saves a labelled contact sheet of the horror texture pack to user://sheet.png

const ROOT := "res://assets/SBS - Horror Texture Pack 128x128/128x128/"
var frames := 0


func _ready() -> void:
	var grid := GridContainer.new()
	grid.columns = 14
	add_child(grid)
	for folder in ["Floor", "Wall", "Brick", "Metal", "Stone", "Misc"]:
		var dir := DirAccess.open(ROOT + folder)
		var names: Array[String] = []
		for f in dir.get_files():
			if f.ends_with(".png"):
				names.append(f)
		names.sort()
		for f in names:
			var box := VBoxContainer.new()
			var rect := TextureRect.new()
			rect.texture = load(ROOT + folder + "/" + f)
			rect.custom_minimum_size = Vector2(96, 96)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			box.add_child(rect)
			var label := Label.new()
			label.text = f.get_slice("_", 1).left(2) + f.get_slice("_", 2).get_slice("-", 0)
			label.add_theme_font_size_override("font_size", 11)
			box.add_child(label)
			grid.add_child(box)


func _process(_delta: float) -> void:
	frames += 1
	if frames == 10:
		get_viewport().get_texture().get_image().save_png("user://sheet.png")
		get_tree().quit()
