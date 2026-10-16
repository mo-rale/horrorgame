extends Node3D
# Stalker figure with a little procedural animation. The enemy faces -Z, feet
# near y = -0.95. The body lives in the scene (scenes/enemy_model.tscn); the
# script only rebuilds it if the nodes are missing (tools/bake_scenes.gd uses
# that to create the scene).

const SKIN_TEXTURE := preload("res://assets/SBS - Horror Texture Pack 128x128/128x128/Stains/Horror_Stain_09-128x128.png")

var _skin: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _head: Node3D
var _torso: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _leg_left: Node3D
var _leg_right: Node3D
var _body: CharacterBody3D
var _time := 0.0
var _walk_phase := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if has_node("Torso"):
		_torso = $Torso
		_head = $Torso/Head
		_arm_left = $Torso/ArmLeft
		_arm_right = $Torso/ArmRight
		_leg_left = $LegLeft
		_leg_right = $LegRight
		_eye_material = $Torso/Head/EyeLeft.material_override as StandardMaterial3D
	else:
		_build_body()
	# Randomise so duplicated enemies would not move in lockstep.
	_time = randf() * 10.0


func _build_body() -> void:
	_skin = StandardMaterial3D.new()
	_skin.albedo_texture = SKIN_TEXTURE
	_skin.albedo_color = Color(0.42, 0.4, 0.38)
	_skin.roughness = 0.95
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = Color(1.0, 0.1, 0.05)
	_eye_material.emission_enabled = true
	_eye_material.emission = Color(1.0, 0.08, 0.04)
	_eye_material.emission_energy_multiplier = 4.0

	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0.0, 0.1, 0.0)
	_torso.rotation.x = deg_to_rad(-10.0)
	add_child(_torso)
	_add_part(_torso, "Spine", _capsule(0.17, 0.95), Vector3(0.0, 0.2, 0.0))
	_add_part(_torso, "Chest", _capsule(0.2, 0.5), Vector3(0.0, 0.5, 0.0), Vector3(1.3, 1.0, 0.8))

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.85, -0.08)
	_torso.add_child(_head)
	var skull := _sphere(0.15)
	_add_part(_head, "Skull", skull, Vector3.ZERO, Vector3(0.85, 1.35, 0.9))
	_add_part(_head, "EyeLeft", _eye_sphere(), Vector3(-0.055, 0.04, -0.125), Vector3(1.0, 0.55, 0.6) * 0.45)
	_add_part(_head, "EyeRight", _eye_sphere(), Vector3(0.055, 0.04, -0.125), Vector3(1.0, 0.55, 0.6) * 0.45)

	_arm_left = _make_limb("ArmLeft", _torso, Vector3(-0.3, 0.62, 0.0), 0.045, 1.15)
	_arm_right = _make_limb("ArmRight", _torso, Vector3(0.3, 0.62, 0.0), 0.045, 1.15)
	_leg_left = _make_limb("LegLeft", self, Vector3(-0.11, -0.12, 0.0), 0.07, 0.9)
	_leg_right = _make_limb("LegRight", self, Vector3(0.11, -0.12, 0.0), 0.07, 0.9)

	var eye_light := OmniLight3D.new()
	eye_light.name = "EyeLight"
	eye_light.light_color = Color(1.0, 0.1, 0.05)
	eye_light.light_energy = 0.35
	eye_light.omni_range = 3.0
	eye_light.shadow_enabled = false
	_head.add_child(eye_light)
	eye_light.position = Vector3(0.0, 0.0, -0.3)


func _process(delta: float) -> void:
	_time += delta
	var speed := 0.0
	if _body:
		speed = Vector2(_body.velocity.x, _body.velocity.z).length()
	var walking := clampf(speed / 3.0, 0.0, 1.0)
	_walk_phase += delta * (3.0 + speed * 1.4)

	var swing := sin(_walk_phase) * 0.7 * walking
	_leg_left.rotation.x = swing
	_leg_right.rotation.x = -swing
	# Arms hang loose and drag behind the stride with a slow idle sway.
	var idle := sin(_time * 1.3) * 0.06
	_arm_left.rotation.x = deg_to_rad(-12.0) - swing * 0.5 + idle
	_arm_right.rotation.x = deg_to_rad(-12.0) + swing * 0.5 - idle
	_arm_left.rotation.z = deg_to_rad(6.0) + sin(_time * 0.9) * 0.04
	_arm_right.rotation.z = deg_to_rad(-6.0) - sin(_time * 0.9) * 0.04
	_torso.rotation.z = sin(_walk_phase * 0.5) * 0.06 * walking

	# Slow, wrong-looking head tilt with an occasional twitch.
	var twitch := 0.0
	if fmod(_time, 4.7) < 0.12:
		twitch = sin(_time * 90.0) * 0.12
	_head.rotation.z = sin(_time * 0.6) * 0.22 + twitch
	_head.rotation.x = deg_to_rad(8.0) + sin(_time * 0.4) * 0.05
	# Eyes pulse faintly.
	_eye_material.emission_energy_multiplier = 3.5 + sin(_time * 5.0) * 0.8


func _make_limb(limb_name: String, parent: Node3D, pivot_position: Vector3, radius: float, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = limb_name
	pivot.position = pivot_position
	parent.add_child(pivot)
	_add_part(pivot, "Mesh", _capsule(radius, length), Vector3(0.0, -length * 0.5, 0.0))
	return pivot


func _add_part(parent: Node3D, part_name: String, mesh: Mesh, offset: Vector3, part_scale := Vector3.ONE) -> void:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = offset
	instance.scale = part_scale
	if mesh is SphereMesh and mesh.get_meta("eye", false):
		instance.material_override = _eye_material
	else:
		instance.material_override = _skin
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 4
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


func _eye_sphere() -> SphereMesh:
	var mesh := _sphere(0.1)
	mesh.set_meta("eye", true)
	return mesh
