extends SceneTree
# Bakes the code-built models into real scenes so they can be seen and edited in
# the Godot editor. Each script (valve, fuse, fuse box, enemy, note, menu set)
# builds its nodes when none exist; this tool lets it do that once, names the
# nodes, and saves the result.
#
# Run from the project root:
#   godot --headless --path . --script res://tools/bake_scenes.gd
# Add "-- name" to bake only scenes whose path contains that name.
# NOTE: baking overwrites the scenes, including any edits made in the editor.

# [output path, kind, source]  (kind: "script" builds a root from a script,
# "scene" instantiates an existing scene that already has the script attached)
const BAKES := [
	["res://scenes/enemy_model.tscn", "script", ["Node3D", "EnemyModel", "res://scripts/enemy_model.gd"]],
	["res://scenes/pressure_valve.tscn", "script", ["StaticBody3D", "PressureValve", "res://scripts/pressure_valve.gd"]],
	["res://scenes/fuse.tscn", "scene", "res://scenes/fuse.tscn"],
	["res://scenes/fuse_box.tscn", "script", ["StaticBody3D", "FuseBox", "res://scripts/fuse_box.gd"]],
	["res://scenes/story_note.tscn", "script", ["StaticBody3D", "StoryNote", "res://scripts/story_note.gd"]],
	["res://scenes/main_menu_scenery.tscn", "scene", "res://scenes/main_menu_scenery.tscn"],
]


var _index := 0
var _pending: Node = null


func _process(_delta: float) -> bool:
	# One scene per two frames: the first frame adds the root so the scripts'
	# _ready functions build their nodes, the second frame saves the scene.
	if _pending != null:
		_finish(BAKES[_index][0], _pending)
		_pending = null
		_index += 1
		return false
	if _index >= BAKES.size():
		quit()
		return false
	if not _wanted(BAKES[_index][0]):
		_index += 1
		return false
	_pending = _start(BAKES[_index][1], BAKES[_index][2])
	get_root().add_child(_pending)
	return false


func _wanted(path: String) -> bool:
	# Pass scene names after "--" to bake only those, e.g. "-- enemy_model".
	var filters := OS.get_cmdline_user_args()
	if filters.is_empty():
		return true
	for filter in filters:
		if path.contains(filter):
			return true
	return false


func _start(kind: String, source) -> Node:
	var root: Node
	if kind == "script":
		root = ClassDB.instantiate(source[0]) as Node
		root.name = source[1]
		root.set_script(load(source[2]))
	else:
		root = (load(source) as PackedScene).instantiate()
	return root


func _finish(path: String, root: Node) -> void:
	_fix_runtime_state(path, root)
	_name_and_own(root, root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error != OK:
		push_error("Could not pack %s (error %d)" % [path, error])
	else:
		error = ResourceSaver.save(packed, path)
		print("[Bake] %s -> %s (%d nodes)" % [path, "saved" if error == OK else "FAILED", _count(root)])
	get_root().remove_child(root)
	root.queue_free()


func _fix_runtime_state(path: String, root: Node) -> void:
	# Streams that the scripts duplicate and loop at runtime must be saved as
	# the original imported files, not as embedded copies.
	if path.ends_with("pressure_valve.tscn"):
		(root.get_node("LeakPlayer") as AudioStreamPlayer3D).stream = load("res://assets/sfx/valve/steam_leak_loop.wav")
	elif path.ends_with("fuse_box.tscn"):
		(root.get_node("Hum") as AudioStreamPlayer3D).stream = load("res://assets/sfx/fuse/transformer_hum.wav")


func _name_and_own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if child.name.begins_with("@"):
			child.name = _readable_name(child)
		if child.owner == null:
			child.owner = scene_root
		# Instanced sub-scenes keep their own internals.
		if child.scene_file_path.is_empty():
			_name_and_own(child, scene_root)


func _readable_name(node: Node) -> String:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance and mesh_instance.mesh:
		return mesh_instance.mesh.get_class().trim_suffix("Mesh")
	return node.get_class()


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
