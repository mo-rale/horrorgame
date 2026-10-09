extends Node3D

var player_spawn: Vector3:
	get:
		return %PlayerSpawn.global_position

var enemy_spawn: Vector3:
	get:
		return %EnemySpawn.global_position

var generator_spawn: Vector3:
	get:
		return %GeneratorSpawn.global_position


func rebuild(navigation_region: NavigationRegion3D) -> Array[Marker3D]:
	# Geometry and spawn markers are authored in level_map.tscn so they remain
	# visible and editable in Godot's 3D viewport. The main controller bakes
	# navigation one physics frame later, after all CSG geometry is ready.
	if navigation_region.navigation_mesh == null:
		push_error("LevelMap requires a NavigationMesh resource")

	var markers: Array[Marker3D] = []
	for child in %GasSpawnPoints.get_children():
		if child is Marker3D:
			markers.append(child)
	return markers
