extends Node
# Run: Godot --path . res://tests/ui_shot.tscn
# Screenshots the in-game HUD, pause screen, game over, victory and the menu's
# settings panel to user://ui_*.png.

var main: Node
var menu: Node
var frame := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://ui_%s.png" % name)


func _process(_delta: float) -> void:
	frame += 1
	var player: Player = null
	if is_instance_valid(main) and not main.is_queued_for_deletion():
		player = main.get_node("player") as Player
	if frame == 100 and player:
		player.stamina = 45.0
		player.battery = 35.0
		player.is_flashlight_on = true
	if frame == 112:
		_shot("hud")
		main._set_player_paused(true)
	if frame == 120:
		_shot("pause")
		main._set_player_paused(false)
		main.pause_screen.visible = false
		main._finish_game(main.game_over_screen, main.restart_button)
	if frame == 126:
		_shot("gameover")
		main.game_over_screen.visible = false
		main.victory_screen.visible = true
	if frame == 130:
		_shot("victory")
		get_tree().paused = false
		main.queue_free()
		menu = load("res://scenes/main_menu.tscn").instantiate()
		add_child(menu)
	if frame == 160:
		menu._show_settings()
	if frame == 170:
		_shot("settings")
		get_tree().quit()
