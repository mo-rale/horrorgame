extends Node
# Run: Godot --path . res://tests/menu_shot.tscn
# Screenshots the main menu at a few moments (including a lightning strike).

var menu: Node
var frame := 0


func _ready() -> void:
	menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)


func _process(_delta: float) -> void:
	frame += 1
	var weather := menu.get_node("Scenery")
	if frame == 120:
		get_viewport().get_texture().get_image().save_png("user://menu_calm.png")
		weather._start_lightning()
		weather._flash_timer = 0.6
	if frame == 124:
		get_viewport().get_texture().get_image().save_png("user://menu_flash.png")
	if frame == 400:
		weather._start_lightning()
		weather._flash_timer = 0.6
	if frame == 404:
		get_viewport().get_texture().get_image().save_png("user://menu_flash2.png")
		get_tree().quit()
