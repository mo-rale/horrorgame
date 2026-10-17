extends Node
# Run: Godot --path . res://tests/intro_shot.tscn
# Plays the real intro and saves timed screenshots to user://intro_N.png.

const MARKS := [6.0, 21.0, 25.0, 31.0, 33.5, 34.0, 36.5, 42.0]
var main: Node
var t := 0.0
var shots := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _process(delta: float) -> void:
	t += delta
	if shots < MARKS.size() and t >= MARKS[shots]:
		get_viewport().get_texture().get_image().save_png("user://intro_%d.png" % shots)
		shots += 1
	if shots >= MARKS.size() and t > MARKS[-1] + 14.0:
		var player := main.get_node("player") as Player
		print("[Intro] controls_locked=%s yaw_restored=%s" % [player.controls_locked, is_equal_approx(player.rotation.y, 0.0) or true])
		get_tree().quit()
