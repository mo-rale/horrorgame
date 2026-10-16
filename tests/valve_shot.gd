extends Node
# Run: Godot --path . res://tests/valve_shot.tscn
# Screenshots each pressure valve (leaking, with the focus outline) to
# user://valve_N.png, then closes valve A and screenshots/prints the result.

var main: Node
var frame := 0
var index := 0
var wait := 0
var valves: Array = []
var closing_frame := -1


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _place_in_front(player: Player, valve: Node3D) -> void:
	var front: Vector3 = valve.global_basis.z.normalized()
	player.global_position = valve.global_position + front * 2.4 + Vector3.UP * 0.05
	player.rotation.y = atan2(front.x, front.z)
	player.camera.rotation = Vector3(deg_to_rad(-4.0), 0, 0)


func _process(_delta: float) -> void:
	frame += 1
	if frame < 90:
		return
	var player := main.get_node("player") as Player
	if valves.is_empty():
		valves = get_tree().get_nodes_in_group("pressure_valve")
		valves.sort_custom(func(a, b): return a.valve_id < b.valve_id)
		player.controls_locked = true
		player.light.visible = true
		print("[Valve] found %d valves" % valves.size())

	if index < valves.size():
		var valve: Node3D = valves[index]
		if wait == 0:
			_place_in_front(player, valve)
			valve.show_outline()
		wait += 1
		if wait == 12:
			get_viewport().get_texture().get_image().save_png("user://valve_%d.png" % index)
			valve.hide_outline()
			index += 1
			wait = 0
		return

	var valve_a: Node3D = valves[0]
	if closing_frame < 0:
		_place_in_front(player, valve_a)
		valve_a.interact()
		closing_frame = frame
		print("[Valve] interact: turning=%s activated=%s" % [valve_a.turning, valve_a.activated])
	elif frame == closing_frame + 20:
		get_viewport().get_texture().get_image().save_png("user://valve_turning.png")
	elif frame == closing_frame + 150:
		print("[Valve] after: turning=%s activated=%s generator valves=%d" % [
			valve_a.turning, valve_a.activated,
			main.get_node("Generator").get_current_pressure_valves()])
		get_viewport().get_texture().get_image().save_png("user://valve_closed.png")
		get_tree().quit()
