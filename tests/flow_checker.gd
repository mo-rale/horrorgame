extends Node
# Outlives scene changes: after a delay, reports which scene is current, then quits.

var t := 0.0


func _process(delta: float) -> void:
	t += delta
	if t > 4.0:
		var scene := get_tree().current_scene
		print("[Flow] current scene: ", scene.name if scene else "none", " stats=", Engine.get_meta("run_stats", {}))
		get_tree().quit()
