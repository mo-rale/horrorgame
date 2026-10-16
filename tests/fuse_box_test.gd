extends Node
# Run: Godot --path . res://tests/fuse_box_test.tscn
# Checks fuses only work in the fuse box (after the valves), then screenshots it.

var main: Node
var frame := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	var generator := main.get_node("Generator")
	var box := get_tree().get_first_node_in_group("fuse_box")
	if frame == 120:
		var fuse := get_tree().get_nodes_in_group("fuse")[0]
		fuse.use(generator)
		print("[Fuse] into generator: fuses=%d used=%s (want 0, false)" % [generator.get_current_fuses(), fuse.is_used])
		fuse.use(box)
		print("[Fuse] into box before valves: box=%d used=%s (want 0, false)" % [box.installed_fuses.size(), fuse.is_used])
		for id in ["VALVE_A", "VALVE_B", "VALVE_C"]:
			generator.open_pressure_valve(id)
		var types := []
		for f in get_tree().get_nodes_in_group("fuse"):
			types.append(f.fuse_type)
			f.use(box)
		print("[Fuse] after valves: box=%d generator=%d complete=%s (want 3, 3, true)" % [
			box.installed_fuses.size(), generator.get_current_fuses(), box.is_complete()])
		var player := main.get_node("player") as Player
		player.controls_locked = true
		player.global_position = Vector3(25.5, 0.1, 42.2)
		player.rotation.y = deg_to_rad(-90.0)
		player.camera.rotation = Vector3.ZERO
		box.show_outline()
	if frame == 135:
		get_viewport().get_texture().get_image().save_png("user://fusebox.png")
		print("[Fuse] screenshot saved")
		get_tree().quit()
