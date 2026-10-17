extends Node
# Run: Godot --path . res://tests/fuse_box_test.tscn
# Checks fuses only work in the fuse box (after the valves), then screenshots
# the empty box, a held-style fuse, and the finished box.

var main: Node
var frame := 0
var phase := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _stand_in_front(box: Node3D, distance := 2.3, height_tilt := 0.0) -> void:
	var player := main.get_node("player") as Player
	player.controls_locked = true
	player.light.visible = true
	var front: Vector3 = box.global_basis.z.normalized()
	player.global_position = box.global_position + front * distance + Vector3.UP * 0.05
	player.rotation.y = atan2(front.x, front.z)
	player.camera.rotation = Vector3(deg_to_rad(height_tilt), 0, 0)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % name)


func _process(_delta: float) -> void:
	frame += 1
	var generator := main.get_node("Generator")
	var box := get_tree().get_first_node_in_group("fuse_box")
	if frame == 80:
		# A fuse lying on the floor, seen from about a metre away.
		var lying := get_tree().get_nodes_in_group("fuse")[0] as Node3D
		var player := main.get_node("player") as Player
		player.controls_locked = true
		player.light.visible = true
		player.global_position = lying.global_position + Vector3(1.2, -0.7, 0.4)
		player.camera.look_at(lying.global_position)
	if frame == 90:
		_shot("fuse_pickup")
	if frame == 100:
		var fuse := get_tree().get_nodes_in_group("fuse")[0]
		fuse.use(generator)
		print("[Fuse] into generator: fuses=%d used=%s (want 0, false)" % [generator.get_current_fuses(), fuse.is_used])
		fuse.use(box)
		print("[Fuse] into box with valves open: box=%d used=%s (want 1, true)" % [box.installed_fuses.size(), fuse.is_used])
		print("[Fuse] first fuse woke the enemy: %s (want true)" % main.enemy.awakened)
		_stand_in_front(box, 2.6, 4.0)
		box.show_outline()
	if frame == 112:
		_shot("fusebox_empty")
		for id in ["VALVE_A", "VALVE_B", "VALVE_C"]:
			generator.open_pressure_valve(id)
		var fuses := get_tree().get_nodes_in_group("fuse")
		fuses[0].use(box)
	if frame == 130:
		_shot("fusebox_one")
		for f in get_tree().get_nodes_in_group("fuse"):
			f.use(box)
	if frame == 190:
		print("[Fuse] after: box=%d generator=%d complete=%s (want 3, 3, true)" % [
			box.installed_fuses.size(), generator.get_current_fuses(), box.is_complete()])
		_shot("fusebox_done")
		get_tree().quit()
