extends Node3D
# Stalker figure. The enemy faces -Z, feet near y = -0.95. The body and its
# animation live in the scene (scenes/enemy_model.tscn): an AnimationPlayer holds
# the clips (scenes/enemy_animations.tres) and an AnimationTree blends them. This
# script only feeds the tree, and rebuilds the body if its nodes are missing
# (tools/bake_scenes.gd uses that); tools/build_enemy_animations.gd adds the
# animation nodes to the baked scene.
#
# The tree has one state machine with four moods, each a blend space over speed
# (idle > walk > run):  Calm, Stalk, Chase, Search.

const SKIN_TEXTURE := preload("res://assets/SBS - Horror Texture Pack 128x128/128x128/Stains/Horror_Stain_09-128x128.png")

var _skin: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _head: Node3D
var _torso: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _leg_left: Node3D
var _leg_right: Node3D
var _strips: Array[Node3D] = []
var _body: CharacterBody3D
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _mood := &"calm"

## Enemy state name -> mood. Anything not listed (dormant, roaming, investigating,
## vanishing) is the calm walk.
const MOOD_OF_STATE := {&"stalking": &"stalk", &"chasing": &"chase", &"searching": &"search"}
## The tree's state for each mood, and the speed at which its walk or run clip
## plays at normal rate. Faster or slower than that and the clip is sped up or slowed.
const STATE_OF_MOOD := {&"calm": "Calm", &"stalk": "Stalk", &"chase": "Chase", &"search": "Search"}
const NATURAL_SPEED := {&"calm": 2.0, &"stalk": 2.5, &"chase": 8.2, &"search": 5.0}


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
		for index in 4:
			# Older baked copies (e.g. the menu backdrop's figure) have no coat strips.
			var strip := get_node_or_null("Torso/CoatStrip%d" % index) as Node3D
			if strip:
				_strips.append(strip)
	else:
		_build_body()
	_tree = get_node_or_null("AnimationTree") as AnimationTree
	if _tree:
		_tree.active = true
		_playback = _tree.get("parameters/States/playback") as AnimationNodeStateMachinePlayback
		var enemy := get_parent()
		if enemy and enemy.has_signal("state_changed"):
			enemy.connect("state_changed", _on_enemy_state_changed)


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

	_build_clothes()

	var eye_light := OmniLight3D.new()
	eye_light.name = "EyeLight"
	eye_light.light_color = Color(1.0, 0.1, 0.05)
	eye_light.light_energy = 0.35
	eye_light.omni_range = 3.0
	eye_light.shadow_enabled = false
	_head.add_child(eye_light)
	eye_light.position = Vector3(0.0, 0.0, -0.3)


func _build_clothes() -> void:
	# A torn foreman's coat, a dented hard hat and a hollow mouth.
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.2, 0.17, 0.14)
	cloth.roughness = 1.0
	var hat_material := StandardMaterial3D.new()
	hat_material.albedo_color = Color(0.3, 0.23, 0.06)
	hat_material.roughness = 0.7
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.0, 0.0, 0.0)
	dark.roughness = 1.0

	var coat_mesh := CylinderMesh.new()
	coat_mesh.top_radius = 0.2
	coat_mesh.bottom_radius = 0.33
	coat_mesh.height = 0.78
	coat_mesh.radial_segments = 14
	var coat := MeshInstance3D.new()
	coat.name = "Coat"
	coat.mesh = coat_mesh
	coat.material_override = cloth
	coat.position = Vector3(0.0, -0.08, 0.0)
	_torso.add_child(coat)
	# Tattered strips hanging from the hem; they sway in _process.
	for index in 4:
		var angle := index * PI * 0.5 + PI * 0.25
		var pivot := Node3D.new()
		pivot.name = "CoatStrip%d" % index
		pivot.position = Vector3(sin(angle) * 0.31, -0.46, cos(angle) * 0.31)
		pivot.rotation.y = angle
		_torso.add_child(pivot)
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(0.1, 0.4, 0.012)
		var strip := MeshInstance3D.new()
		strip.name = "Strip"
		strip.mesh = strip_mesh
		strip.material_override = cloth
		strip.position = Vector3(0.0, -0.2, 0.0)
		pivot.add_child(strip)
		_strips.append(pivot)

	var hat_mesh := SphereMesh.new()
	hat_mesh.radius = 0.175
	hat_mesh.height = 0.35
	hat_mesh.is_hemisphere = true
	hat_mesh.radial_segments = 14
	hat_mesh.rings = 6
	var hat := MeshInstance3D.new()
	hat.name = "HardHat"
	hat.mesh = hat_mesh
	hat.material_override = hat_material
	hat.position = Vector3(0.0, 0.14, 0.03)
	hat.rotation = Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(7.0))
	hat.scale = Vector3(1.0, 0.85, 1.1)
	_head.add_child(hat)
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.215
	brim_mesh.bottom_radius = 0.215
	brim_mesh.height = 0.02
	brim_mesh.radial_segments = 14
	var brim := MeshInstance3D.new()
	brim.name = "HatBrim"
	brim.mesh = brim_mesh
	brim.material_override = hat_material
	brim.position = Vector3(0.0, 0.14, 0.0)
	brim.rotation.x = deg_to_rad(-30.0)
	_head.add_child(brim)

	var mouth := MeshInstance3D.new()
	mouth.name = "Mouth"
	mouth.mesh = _sphere(0.05)
	mouth.material_override = dark
	mouth.position = Vector3(0.0, -0.085, -0.115)
	mouth.scale = Vector3(1.2, 1.2, 0.5)
	_head.add_child(mouth)


func _on_enemy_state_changed(state_name: StringName) -> void:
	set_mood(MOOD_OF_STATE.get(state_name, &"calm"))


## Switches the animation mood: &"calm", &"stalk", &"chase" or &"search".
func set_mood(mood: StringName) -> void:
	if mood == _mood or _playback == null or not STATE_OF_MOOD.has(mood):
		return
	_mood = mood
	_playback.travel(STATE_OF_MOOD[mood])


func _process(_delta: float) -> void:
	if _tree == null:
		return
	var speed := 0.0
	if _body:
		speed = Vector2(_body.velocity.x, _body.velocity.z).length()
	# Every mood's blend space reads the same speed, so a switch mid-stride is smooth.
	for state_name: String in STATE_OF_MOOD.values():
		_tree.set("parameters/States/%s/blend_position" % state_name, speed)
	# Match the stride to the ground speed so the feet do not skate.
	var pace := 1.0
	if speed > 0.3:
		pace = clampf(speed / NATURAL_SPEED[_mood], 0.6, 2.4)
	_tree.set("parameters/Pace/scale", pace)


func _make_limb(limb_name: String, parent: Node3D, pivot_position: Vector3, radius: float, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = limb_name
	pivot.position = pivot_position
	parent.add_child(pivot)
	_add_part(pivot, "Mesh", _capsule(radius, length), Vector3(0.0, -length * 0.5, 0.0))
	if limb_name.begins_with("Arm"):
		# A thin hand with three long fingers.
		_add_part(pivot, "Hand", _sphere(0.055), Vector3(0.0, -length - 0.02, 0.0), Vector3(1.0, 1.3, 0.6))
		for finger in 3:
			_add_part(pivot, "Finger%d" % finger, _capsule(0.012, 0.13), Vector3((finger - 1) * 0.028, -length - 0.14, 0.0))
	else:
		_add_part(pivot, "Boot", _box_mesh(Vector3(0.13, 0.1, 0.26)), Vector3(0.0, -length - 0.02, -0.06))
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


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
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
