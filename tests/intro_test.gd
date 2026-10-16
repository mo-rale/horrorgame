extends Node
# Run: Godot --headless --path . res://tests/intro_test.tscn
# Checks the intro locks the player, then releases control and the enemy.

var main: Node
var t := 0.0
var logged := {}


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _process(delta: float) -> void:
	t += delta
	var player: Player = main.get_node_or_null("player")
	var enemy: Node = main.get_node_or_null("Enemy")
	if player == null or enemy == null:
		return
	for mark in [2, 6, 14, 18]:
		if t >= mark and not logged.has(mark):
			logged[mark] = true
			print("[Intro] t=%d locked=%s enemy_physics=%s cam_rot=%s" % [mark, player.controls_locked, enemy.is_physics_processing(), player.camera.rotation])
	if t > 19.0:
		get_tree().quit()
