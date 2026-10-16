extends Node
# Run: Godot --path . res://tests/ray_probe.tscn
# Debug: what is directly in front of the camera 2.4 m from valve A?

var main: Node
var frame := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.play_intro = false
	add_child(main)


func _process(_delta: float) -> void:
	frame += 1
	if frame != 100:
		return
	var player := main.get_node("player") as Player
	player.controls_locked = true
	var valve: Node3D = get_tree().get_nodes_in_group("pressure_valve")[0]
	var front: Vector3 = valve.global_basis.z.normalized()
	player.global_position = valve.global_position + front * 2.4 + Vector3.UP * 0.05
	player.rotation.y = atan2(front.x, front.z)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cam := player.camera
	var space := cam.get_world_3d().direct_space_state
	for offset in [Vector3.ZERO, Vector3(0, 0, 0)]:
		var query := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 5.0)
		query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		print("[Ray] cam=%s hit=%s" % [cam.global_position, hit.get("collider")])
		if hit.has("collider"):
			print("[Ray] collider path=%s pos=%s" % [hit["collider"].get_path(), hit["position"]])
	print("[Ray] valve pos=%s basis_z=%s" % [valve.global_position, front])
	# What meshes are within 1.5m of the camera ray?
	for mesh in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		var d := m.global_position.distance_to(cam.global_position)
		if d < 3.5 and m.is_visible_in_tree():
			print("[Ray] near mesh %s d=%.2f size=%s" % [m.get_path(), d, m.get_aabb().size])
	get_tree().quit()
