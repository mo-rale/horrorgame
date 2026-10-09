extends Node3D

const MAP_MIN := Vector2(-30.0, -10.0)
const MAP_MAX := Vector2(30.0, 58.0)
const WALL_HEIGHT := 5.0
const WALL_THICKNESS := 0.8

var player_spawn := Vector3(0.0, 0.05, 52.0)
var enemy_spawn := Vector3(-23.0, 0.95, 35.0)
var generator_spawn := Vector3(0.0, 1.0, -4.0)


func rebuild(navigation_region: NavigationRegion3D) -> Array[Marker3D]:
	var wall_material := _find_wall_material(navigation_region)
	var floor_material := _find_floor_material(navigation_region)

	# Remove the old hand-placed geometry. It is replaced at runtime so the
	# saved UI and gameplay node changes in main.tscn remain untouched.
	for child in navigation_region.get_children():
		navigation_region.remove_child(child)
		child.queue_free()

	var geometry := Node3D.new()
	geometry.name = "RebuiltLevelGeometry"
	navigation_region.add_child(geometry)

	_add_box(
		geometry,
		"Floor",
		Vector3(0.0, -0.1, 24.0),
		Vector3(60.0, 0.2, 68.0),
		floor_material
	)

	# Perimeter.
	_add_wall(geometry, "WestBoundary", Vector2(-30.0, 24.0), Vector2(0.8, 68.0), wall_material)
	_add_wall(geometry, "EastBoundary", Vector2(30.0, 24.0), Vector2(0.8, 68.0), wall_material)
	_add_wall(geometry, "SouthBoundary", Vector2(0.0, -10.0), Vector2(60.0, 0.8), wall_material)
	_add_wall(geometry, "NorthBoundary", Vector2(0.0, 58.0), Vector2(60.0, 0.8), wall_material)

	# Generator wing. The center opening leads into two side rooms.
	_add_wall(geometry, "GeneratorDividerWest", Vector2(-17.0, 8.0), Vector2(26.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "GeneratorDividerEast", Vector2(17.0, 8.0), Vector2(26.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "SouthWestRoomLower", Vector2(-12.0, -6.5), Vector2(WALL_THICKNESS, 7.0), wall_material)
	_add_wall(geometry, "SouthWestRoomUpper", Vector2(-12.0, 4.5), Vector2(WALL_THICKNESS, 7.0), wall_material)
	_add_wall(geometry, "SouthEastRoomLower", Vector2(12.0, -6.5), Vector2(WALL_THICKNESS, 7.0), wall_material)
	_add_wall(geometry, "SouthEastRoomUpper", Vector2(12.0, 4.5), Vector2(WALL_THICKNESS, 7.0), wall_material)

	# Central storage rooms. Offset doorways prevent long, safe sightlines while
	# leaving multiple paths around every wall for the enemy.
	_add_wall(geometry, "MidDividerWest", Vector2(-20.0, 28.0), Vector2(20.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "MidDividerCenter", Vector2(3.0, 28.0), Vector2(14.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "MidDividerEast", Vector2(23.0, 28.0), Vector2(14.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "WestInnerLowerA", Vector2(-12.0, 11.0), Vector2(WALL_THICKNESS, 6.0), wall_material)
	_add_wall(geometry, "WestInnerLowerB", Vector2(-12.0, 20.0), Vector2(WALL_THICKNESS, 4.0), wall_material)
	_add_wall(geometry, "WestInnerUpperA", Vector2(-12.0, 38.5), Vector2(WALL_THICKNESS, 9.0), wall_material)
	_add_wall(geometry, "WestInnerUpperB", Vector2(-12.0, 53.5), Vector2(WALL_THICKNESS, 9.0), wall_material)
	_add_wall(geometry, "EastInnerLowerA", Vector2(12.0, 12.5), Vector2(WALL_THICKNESS, 9.0), wall_material)
	_add_wall(geometry, "EastInnerLowerB", Vector2(12.0, 25.5), Vector2(WALL_THICKNESS, 9.0), wall_material)
	_add_wall(geometry, "EastInnerUpperA", Vector2(12.0, 43.5), Vector2(WALL_THICKNESS, 7.0), wall_material)
	_add_wall(geometry, "EastInnerUpperB", Vector2(12.0, 54.5), Vector2(WALL_THICKNESS, 7.0), wall_material)

	# Northern loading area with two entrances and a central hiding block.
	_add_wall(geometry, "NorthDividerWestOuter", Vector2(-26.0, 45.0), Vector2(8.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "NorthDividerWestInner", Vector2(-12.0, 45.0), Vector2(12.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "NorthDividerEastInner", Vector2(12.0, 45.0), Vector2(12.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "NorthDividerEastOuter", Vector2(26.0, 45.0), Vector2(8.0, WALL_THICKNESS), wall_material)
	_add_wall(geometry, "CentralScreenLower", Vector2(0.0, 17.0), Vector2(WALL_THICKNESS, 10.0), wall_material)
	_add_wall(geometry, "CentralScreenUpper", Vector2(0.0, 36.5), Vector2(WALL_THICKNESS, 9.0), wall_material)

	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_height = 1.8
	navigation_mesh.agent_radius = 0.45
	navigation_mesh.agent_max_climb = 0.4
	navigation_mesh.agent_max_slope = 45.0
	navigation_mesh.cell_size = 0.25
	navigation_mesh.cell_height = 0.25
	navigation_mesh.filter_baking_aabb = AABB(
		Vector3(MAP_MIN.x, -0.5, MAP_MIN.y),
		Vector3(MAP_MAX.x - MAP_MIN.x, 3.0, MAP_MAX.y - MAP_MIN.y)
	)
	navigation_region.navigation_mesh = navigation_mesh
	navigation_region.bake_navigation_mesh(false)

	return _create_gas_spawn_points()


func _add_wall(
	parent: Node3D,
	wall_name: String,
	center: Vector2,
	size: Vector2,
	material: Material
) -> void:
	_add_box(
		parent,
		wall_name,
		Vector3(center.x, WALL_HEIGHT * 0.5, center.y),
		Vector3(size.x, WALL_HEIGHT, size.y),
		material
	)


func _add_box(
	parent: Node3D,
	box_name: String,
	box_position: Vector3,
	box_size: Vector3,
	material: Material
) -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = box_position
	parent.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box_size
	collision.shape = box_shape
	body.add_child(collision)


func _create_gas_spawn_points() -> Array[Marker3D]:
	var positions: Array[Vector3] = [
		Vector3(-23.0, 0.75, -4.0),
		Vector3(-18.0, 0.75, 4.0),
		Vector3(20.0, 0.75, -4.0),
		Vector3(22.0, 0.75, 14.0),
		Vector3(-23.0, 0.75, 18.0),
		Vector3(-20.0, 0.75, 35.0),
		Vector3(-22.0, 0.75, 51.0),
		Vector3(-5.0, 0.75, 23.0),
		Vector3(5.0, 0.75, 35.0),
		Vector3(21.0, 0.75, 35.0),
		Vector3(21.0, 0.75, 51.0),
		Vector3(-5.0, 0.75, 13.0),
	]
	var markers: Array[Marker3D] = []
	var spawn_root := Node3D.new()
	spawn_root.name = "GasSpawnPoints"
	add_child(spawn_root)

	for index in positions.size():
		var marker := Marker3D.new()
		marker.name = "GasSpawn%02d" % (index + 1)
		marker.position = positions[index]
		spawn_root.add_child(marker)
		marker.add_to_group("gas_spawn")
		markers.append(marker)

	return markers


func _find_wall_material(navigation_region: NavigationRegion3D) -> Material:
	for child in navigation_region.get_children():
		if child is CSGShape3D and child.material_override:
			return child.material_override
	return null


func _find_floor_material(navigation_region: NavigationRegion3D) -> Material:
	for child in navigation_region.get_children():
		if child is MeshInstance3D and child.material_override:
			return child.material_override
	return _find_wall_material(navigation_region)
