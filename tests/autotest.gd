extends Node
# Run: Godot --headless --path . res://tests/autotest.tscn
# Drives the real game scene with fake input and prints stamina/battery values.

var main: Node
var player: Player
var frame := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	if player == null:
		player = main.get_node_or_null("player") as Player
		return
	# Let navigation setup finish before testing.
	if frame < 200:
		return

	var step := frame - 200
	if step == 0:
		print("[Test] start stamina=%.1f battery=%.1f" % [player.stamina, player.battery])
		Input.action_press("Forward")
		Input.action_press("Sprint")
	if step == 120:
		print("[Test] after ~2s sprint stamina=%.1f sprinting=%s" % [player.stamina, player._is_sprinting])
	if step == 400:
		print("[Test] after long sprint stamina=%.1f exhausted=%s sprinting=%s" % [player.stamina, player._stamina_exhausted, player._is_sprinting])
		Input.action_release("Sprint")
		Input.action_release("Forward")
		Input.action_press("Flashlight")
	if step == 402:
		Input.action_release("Flashlight")
	if step == 900:
		print("[Test] flashlight on=%s battery=%.1f stamina=%.1f" % [player.is_flashlight_on, player.battery, player.stamina])
	if step == 905:
		get_tree().quit()
	return
