extends Node
# Bakes the level's navigation mesh once and saves it as
# res://assets/level_navmesh.tres, which scenes/level_map.tscn loads (see
# tools/gen_level.py). The game then does not bake at runtime, which logs a
# performance warning. Re-run after every level change:
#   python tools/gen_level.py
#   godot --headless --path . res://tools/bake_navmesh.tscn
# The first run needs the .tres to exist or gen_level to point at an inline mesh.

const LEVEL_PATH := "res://scenes/level_map.tscn"
const OUT_PATH := "res://assets/level_navmesh.tres"

var _level: Node3D
var _region: NavigationRegion3D
var _frames := 0


func _ready() -> void:
	_level = (load(LEVEL_PATH) as PackedScene).instantiate()
	add_child(_level)
	_region = _level.get_node("NavigationRegion3D")
	# Start from an empty mesh so a stale bake cannot be mistaken for a new one.
	_region.navigation_mesh.clear()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 5:
		_region.bake_navigation_mesh(false)
	if _frames == 60:
		var polygons := _region.navigation_mesh.get_polygon_count()
		if polygons == 0:
			push_error("Bake produced no polygons; scene not saved")
			get_tree().quit(1)
			return
		var mesh := _region.navigation_mesh.duplicate() as NavigationMesh
		var error := ResourceSaver.save(mesh, OUT_PATH)
		print("[NavBake] %d polygons -> %s" % [polygons, "saved" if error == OK else "FAILED"])
		get_tree().quit()
