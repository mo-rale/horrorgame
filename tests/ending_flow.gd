extends Node
# Run: Godot --path . res://tests/ending_flow.tscn
# Checks that reaching the exit hands over to the ending scene with run stats.

var main: Node
var t := 0.0
var started := false


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _process(delta: float) -> void:
	t += delta
	if t > 3.0 and not started:
		started = true
		main.generator_powered = true
		var checker := Node.new()
		checker.set_script(load("res://tests/flow_checker.gd"))
		get_tree().root.add_child(checker)
		main._on_victory_area_body_entered(main.get_node("player"))
