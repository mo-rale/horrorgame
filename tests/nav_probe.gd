extends Node3D
# Run: Godot --path . res://tests/nav_probe.tscn
# Loads the real game, forces a stalking event in the real level and logs it.

var main: Node
var frame := 0
var last_state := -1


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	var enemy := main.get_node("Enemy") as Enemy
	if frame == 200:
		enemy._stalking_cooldown = 0.0
	if enemy._state != last_state:
		last_state = enemy._state
		print("[Nav] frame=%d enemy state=%d pos=%s" % [frame, enemy._state, enemy.global_position])
	if frame == 220:
		enemy._anxiety_level = 99.0
	if frame == 900:
		get_tree().quit()
