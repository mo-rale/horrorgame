extends Node
# Run: Godot --path . res://tests/ending_shot.tscn
# Plays the ending in real time and saves screenshots to user://ending_N.png.

const MARKS := [2.0, 7.0, 12.5, 17.0, 20.5, 24.0, 28.0, 33.0]
var t := 0.0
var shots := 0


func _ready() -> void:
	Engine.set_meta("run_stats", {"time": 754, "notes": 5, "notes_total": 8})
	add_child(load("res://scenes/ending.tscn").instantiate())


func _process(delta: float) -> void:
	t += delta
	if shots < MARKS.size() and t >= MARKS[shots]:
		get_viewport().get_texture().get_image().save_png("user://ending_%d.png" % shots)
		shots += 1
	if shots >= MARKS.size() and t > MARKS[-1] + 1.0:
		get_tree().quit()
