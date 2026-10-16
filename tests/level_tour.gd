extends Node
# Run: Godot --path . res://tests/level_tour.tscn
# Checks navmesh connectivity to every spawn/valve/generator and saves a
# screenshot from a vantage point in each room to user://tour_N.png.

const SHOTS := [
	["lobby", Vector3(0, 0, 53), 180.0, 4.0],
	["locker", Vector3(-14, 0, 50), 70.0, 0.0],
	["break", Vector3(14, 0, 54), -70.0, 0.0],
	["steam", Vector3(-14, 0, 42), 75.0, 0.0],
	["assembly", Vector3(0, 0, 43), 180.0, 0.0],
	["elect", Vector3(14, 0, 40), -75.0, 0.0],
	["boiler", Vector3(-14, 0, 22), 80.0, 0.0],
	["press", Vector3(0, 0, 26), 180.0, 0.0],
	["pump", Vector3(14, 0, 20), -85.0, 0.0],
	["fuel", Vector3(-14, 0, 5), 80.0, 0.0],
	["gen", Vector3(0, 0, 6), 160.0, 0.0],
	["gate", Vector3(0, 0, 3), 180.0, 0.0],
]

var main: Node
var player: Player
var frame := 0
var shot := 0
var wait := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	if frame < 60:
		return
	if player == null:
		player = main.get_node("player") as Player
		player.controls_locked = true
		_check_connectivity()
		return
	if shot >= SHOTS.size():
		get_tree().quit()
		return
	if wait == 0:
		var s: Array = SHOTS[shot]
		player.global_position = s[1] + Vector3.UP * 0.1
		player.rotation.y = deg_to_rad(s[2])
		player.camera.rotation = Vector3(deg_to_rad(s[3]), 0, 0)
		wait = 1
	else:
		wait += 1
		if wait == 8:
			get_viewport().get_texture().get_image().save_png("user://tour_%02d_%s.png" % [shot, SHOTS[shot][0]])
			shot += 1
			wait = 0


func _check_connectivity() -> void:
	var map: RID = main.navigation_region.get_navigation_map()
	var start: Vector3 = main._level_map.player_spawn
	var bad := 0
	var targets := {}
	for m in main._level_map.get_node("GasSpawnPoints").get_children():
		targets[m.name] = m.global_position
	for m in main._level_map.get_node("ValveSpawns").get_children():
		targets[m.name] = m.global_position
	targets["Generator"] = main._level_map.generator_spawn
	targets["Enemy"] = main._level_map.enemy_spawn
	targets["Gate"] = Vector3(-0.5, 0, -8.0)
	for key in targets:
		var path := NavigationServer3D.map_get_path(map, start, targets[key], true)
		var end := path[path.size() - 1] if path.size() > 0 else Vector3.ZERO
		var ok := path.size() > 0 and end.distance_to(NavigationServer3D.map_get_closest_point(map, targets[key])) < 0.6 \
			and NavigationServer3D.map_get_closest_point(map, targets[key]).distance_to(targets[key] - Vector3.UP * targets[key].y) < 1.5
		if not ok:
			bad += 1
		print("[Tour] %s reachable=%s" % [key, ok])
	print("[Tour] unreachable targets: %d" % bad)
