extends Node
# Run: godot --headless --path . res://tools/lint_scripts.tscn
# Loads every project script and scene so the engine reports warnings/errors.

func _ready() -> void:
	for dir in ["res://scripts", "res://tests", "res://tools"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd"):
				load("%s/%s" % [dir, file])
	for dir in ["res://scenes", "res://tests", "res://tools"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tscn"):
				var scene := load("%s/%s" % [dir, file]) as PackedScene
				if scene:
					scene.instantiate().free()
	print("[Lint] done")
	get_tree().quit()
