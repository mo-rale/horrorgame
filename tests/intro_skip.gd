extends Node
# Run: Godot --path . res://tests/intro_skip.tscn
# Presses SPACE during the intro and checks control returns at once.

var main: Node
var t := 0.0
var pressed := false


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)


func _process(delta: float) -> void:
	t += delta
	var player := main.get_node("player") as Player
	if t > 4.0 and not pressed:
		pressed = true
		print("[Skip] before: locked=%s" % player.controls_locked)
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.physical_keycode = KEY_SPACE
		event.pressed = true
		Input.parse_input_event(event)
	if pressed and t > 4.6:
		print("[Skip] after: locked=%s hud=%s intro_layer=%s (want false true null)" % [player.controls_locked, main.get_node("ObjectiveHUD").visible, main._intro_layer])
		get_tree().quit()
