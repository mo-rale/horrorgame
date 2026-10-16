extends Node3D
# Run: Godot --path . res://tests/nav_probe.tscn -- <style 0|1|2>
# Forces a stalking encounter of one style in the real level and logs it.

var main: Node
var frame := 0
var last_state := -1
var style := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		style = int(args[0])
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)
	(main.get_node("Enemy") as Enemy).forced_stalk_style = style


func _process(_delta: float) -> void:
	frame += 1
	var enemy := main.get_node("Enemy") as Enemy
	if frame == 200 and style == 9:
		enemy.visible = true
		enemy.global_position = Vector3(-2.7, 1.45, 57.1)
		enemy._enter_state(Enemy.State.CHASING)
	if frame == 200 and style != 9:
		enemy._stalking_cooldown = 0.0
	if enemy._state != last_state:
		last_state = enemy._state
		print("[Nav] frame=%d enemy state=%d pos=%s" % [frame, enemy._state, enemy.global_position])
	if frame == 220:
		enemy._anxiety_level = 99.0
	if frame > 228 and frame % 60 == 0 and enemy._state == Enemy.State.CHASING:
		print("[Nav] chase pos=%s path_idx=%d/%d vel=%s" % [enemy.global_position, enemy._direct_path_index, enemy._direct_path.size(), enemy.velocity])
	if frame > 200 and frame % 120 == 0 and enemy._state == Enemy.State.STALKING:
		var p := main.get_node("player") as Player
		print("[Nav] style=%d dist=%.1f frozen=%s watch=%.1f" % [style, enemy.global_position.distance_to(p.global_position), enemy._statue_frozen, enemy._statue_watch_time])
	if frame == 1100 or (_shot_wait > 120):
		get_tree().quit()


var _shot_wait := -1


func _physics_process(_delta: float) -> void:
	# Capture the jumpscare a few frames after the catch for visual review.
	if main.get("_jumpscare_running") and _shot_wait < 0:
		_shot_wait = 0
	if _shot_wait >= 0:
		_shot_wait += 1
		if _shot_wait == 14:
			get_viewport().get_texture().get_image().save_png("user://jumpscare_shot.png")
			print("[Nav] jumpscare screenshot saved")
