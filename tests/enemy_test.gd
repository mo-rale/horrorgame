extends Node
# Run (windowed or headless): Godot --path . res://tests/enemy_test.tscn
# Forces stalking, a chase and the lose-player search, logging state changes.

var main: Node
var enemy: Enemy
var player: Player
var t := 0.0
var step := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _process(delta: float) -> void:
	t += delta
	enemy = main.get_node_or_null("Enemy") as Enemy
	player = main.get_node_or_null("player") as Player
	if enemy == null or player == null or t < 4.0:
		return
	if step == 0:
		step = 1
		# The navmesh query is unreliable here, so skip placement and force the state.
		enemy._enter_state(Enemy.State.STALKING, {"teleport_position": Vector3(0, 1, 6)})
		print("[EnemyTest] forcing stalking")
	elif step == 1 and enemy._state == Enemy.State.STALKING:
		step = 2
		print("[EnemyTest] stalking ok, pause timer=%.2f" % enemy._next_stalk_pause)
		enemy._anxiety_level = 99.0
	elif step == 2 and enemy._state == Enemy.State.CHASING:
		step = 3
		print("[EnemyTest] chasing ok, trauma=%.2f" % player._trauma)
		enemy._chase_timer = 0.01
		# Hide from sight so the chase times out.
		enemy.global_position += Vector3(60, 0, 0)
	elif step == 3 and enemy._state == Enemy.State.SEARCHING:
		step = 4
		print("[EnemyTest] searching ok")
	if t > 40.0:
		print("[EnemyTest] done step=%d state=%d" % [step, enemy._state])
		get_tree().quit()
