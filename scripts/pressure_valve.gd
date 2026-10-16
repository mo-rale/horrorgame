extends StaticBody3D
# A steam-line pressure valve. It leaks (hissing, puffing steam, red lamp) until
# the player shuts it with the hand wheel. The model lives in the scene
# (scenes/pressure_valve.tscn) and faces local +Z; its back is a wall bracket at
# about z = -0.75. If the model nodes are missing the script rebuilds them, which
# is how tools/bake_scenes.gd creates the scene.

const METAL_TEXTURE := preload("res://assets/SBS - Horror Texture Pack 128x128/128x128/Metal/Horror_Metal_02-128x128.png")
const BODY_TEXTURE := preload("res://assets/SBS - Horror Texture Pack 128x128/128x128/Metal/Horror_Metal_10-128x128.png")
const TURN_SFX := preload("res://assets/sfx/valve/valve_turn.wav")
const CLANK_SFX := preload("res://assets/sfx/valve/metal_clank.ogg")
const SLAM_SFX := preload("res://assets/sfx/valve/metal_slam.ogg")
const RELEASE_SFX := preload("res://assets/sfx/valve/steam_release.wav")
const LEAK_SFX := preload("res://assets/sfx/valve/steam_leak_loop.wav")

const LAMP_OPEN := Color(1.0, 0.12, 0.05)
const LAMP_CLOSED := Color(0.1, 1.0, 0.25)

@export var valve_id := "VALVE_A"
@export var display_name := "PRESSURE VALVE A"

var activated := false
var turning := false

var _wheel: Node3D
var _needle: Node3D
var _outline: MeshInstance3D
var _lamp_mesh: MeshInstance3D
var _lamp_material: StandardMaterial3D
var _lamp_light: OmniLight3D
var _steam: CPUParticles3D
var _label: Label3D
var _turn_player: AudioStreamPlayer3D
var _impact_player: AudioStreamPlayer3D
var _release_player: AudioStreamPlayer3D
var _leak_player: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("pressure_valve")
	if has_node("ValveWheel"):
		_bind_model()
	else:
		_build_model()
		_build_audio()
	_prepare_runtime()
	_set_leaking(true)


func _bind_model() -> void:
	_wheel = $ValveWheel
	_outline = $ValveWheel/Outline
	_needle = $Needle
	_lamp_mesh = $LampMesh
	_lamp_light = $LampLight
	_steam = $Steam
	_label = $Label
	_turn_player = $TurnPlayer
	_impact_player = $ImpactPlayer
	_release_player = $ReleasePlayer
	_leak_player = $LeakPlayer


func _prepare_runtime() -> void:
	# Each valve gets its own lamp material (the scene's is shared by every
	# instance) and a looping copy of the leak sound.
	_lamp_material = _lamp_mesh.material_override.duplicate() as StandardMaterial3D
	_lamp_mesh.material_override = _lamp_material
	var leak_stream := LEAK_SFX.duplicate() as AudioStreamWAV
	leak_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	leak_stream.loop_begin = 0
	leak_stream.loop_end = leak_stream.data.size() / 2   # 16-bit mono
	_leak_player.stream = leak_stream
	_label.visible = false
	_outline.visible = false
	_set_lamp(LAMP_OPEN)


# ── Model ────────────────────────────────────────────────────────────────────

func _material(texture: Texture2D, tint: Color, metallic := 0.08, roughness := 0.75) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.8
	material.metallic = metallic
	material.roughness = roughness
	return material


func _add_cylinder(radius: float, length: float, position: Vector3, material: Material, along_z := false, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	if along_z:
		instance.rotation.x = PI * 0.5
	parent.add_child(instance)
	return instance


func _add_box(size: Vector3, position: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance


func _build_model() -> void:
	var steel := _material(METAL_TEXTURE, Color(0.85, 0.85, 0.9))
	var iron := _material(BODY_TEXTURE, Color(0.7, 0.6, 0.55), 0.05, 0.8)
	var red_paint := StandardMaterial3D.new()
	red_paint.albedo_color = Color(0.7, 0.06, 0.04)
	red_paint.metallic = 0.0
	red_paint.roughness = 0.6
	var gauge_face := StandardMaterial3D.new()
	gauge_face.albedo_color = Color(0.85, 0.82, 0.7)
	gauge_face.emission_enabled = true
	gauge_face.emission = Color(0.5, 0.45, 0.3)
	gauge_face.emission_energy_multiplier = 0.3

	# Main riser bolted to the wall, clamps, and the branch that feeds the valve.
	_add_cylinder(0.16, 5.0, Vector3(0, 2.5, -0.6), steel)
	for y in [0.5, 2.3, 3.8]:
		_add_cylinder(0.22, 0.12, Vector3(0, y, -0.6), iron)
	_add_cylinder(0.11, 0.8, Vector3(0, 1.2, -0.2), steel, true)
	# Valve body with flanges.
	_add_cylinder(0.2, 0.36, Vector3(0, 1.2, 0.28), iron, true)
	_add_cylinder(0.27, 0.07, Vector3(0, 1.2, 0.08), steel, true)
	_add_cylinder(0.27, 0.07, Vector3(0, 1.2, 0.48), steel, true)
	_add_cylinder(0.035, 0.4, Vector3(0, 1.2, 0.62), steel, true)

	# Hand wheel: rim, hub and spokes, all on one pivot so it can spin.
	_wheel = Node3D.new()
	_wheel.name = "ValveWheel"
	_wheel.position = Vector3(0, 1.2, 0.78)
	add_child(_wheel)
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.27
	rim_mesh.outer_radius = 0.34
	rim_mesh.rings = 20
	rim_mesh.ring_segments = 8
	var rim := MeshInstance3D.new()
	rim.mesh = rim_mesh
	rim.material_override = red_paint
	rim.rotation.x = PI * 0.5
	_wheel.add_child(rim)
	_add_cylinder(0.07, 0.12, Vector3.ZERO, red_paint, true, _wheel)
	for angle in [0.0, PI * 0.5]:
		var spoke := _add_box(Vector3(0.6, 0.035, 0.035), Vector3.ZERO, red_paint, _wheel)
		spoke.rotation.z = angle

	# Highlight ring shown while the player looks at the valve.
	var outline_mesh := TorusMesh.new()
	outline_mesh.inner_radius = 0.3
	outline_mesh.outer_radius = 0.42
	outline_mesh.rings = 20
	outline_mesh.ring_segments = 8
	var outline_material := StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = Color(1.0, 0.75, 0.3, 0.55)
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline = MeshInstance3D.new()
	_outline.name = "Outline"
	_outline.mesh = outline_mesh
	_outline.material_override = outline_material
	_outline.rotation.x = PI * 0.5
	_outline.visible = false
	_wheel.add_child(_outline)

	# Pressure gauge above the body; the needle swings down when the valve shuts.
	_add_cylinder(0.025, 0.3, Vector3(0, 1.5, 0.28), steel)
	_add_cylinder(0.15, 0.07, Vector3(0, 1.72, 0.28), steel, true)
	_add_cylinder(0.125, 0.02, Vector3(0, 1.72, 0.32), gauge_face, true)
	_needle = Node3D.new()
	_needle.name = "Needle"
	_needle.position = Vector3(0, 1.72, 0.335)
	_needle.rotation.z = deg_to_rad(-70.0)
	add_child(_needle)
	_add_box(Vector3(0.012, 0.11, 0.008), Vector3(0, 0.05, 0), red_paint, _needle)

	# Status lamp + a small light so the valve can be found in the dark.
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	_lamp_material.emission_energy_multiplier = 3.0
	_lamp_material.albedo_color = LAMP_OPEN
	_lamp_material.emission = LAMP_OPEN
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.045
	lamp_mesh.height = 0.09
	_lamp_mesh = MeshInstance3D.new()
	_lamp_mesh.name = "LampMesh"
	_lamp_mesh.mesh = lamp_mesh
	_lamp_mesh.material_override = _lamp_material
	_lamp_mesh.position = Vector3(0.22, 1.42, 0.3)
	add_child(_lamp_mesh)
	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "LampLight"
	_lamp_light.position = Vector3(0.1, 1.5, 0.6)
	_lamp_light.omni_range = 5.5
	_lamp_light.light_energy = 1.5
	_lamp_light.shadow_enabled = false
	add_child(_lamp_light)

	# Steam leaking from the flange.
	_steam = CPUParticles3D.new()
	_steam.name = "Steam"
	_steam.position = Vector3(0.05, 1.25, 0.5)
	_steam.amount = 28
	_steam.lifetime = 1.6
	_steam.direction = Vector3(0.2, 0.5, 0.8)
	_steam.spread = 24.0
	_steam.initial_velocity_min = 0.5
	_steam.initial_velocity_max = 1.0
	_steam.gravity = Vector3(0, 0.25, 0)
	_steam.scale_amount_min = 0.7
	_steam.scale_amount_max = 1.6
	var puff_mesh := QuadMesh.new()
	puff_mesh.size = Vector2(0.28, 0.28)
	var puff_material := StandardMaterial3D.new()
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_material.vertex_color_use_as_albedo = true
	puff_material.albedo_color = Color(0.85, 0.87, 0.9, 1.0)
	var soft := GradientTexture2D.new()
	soft.width = 64
	soft.height = 64
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var soft_gradient := Gradient.new()
	soft_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	soft_gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	soft.gradient = soft_gradient
	puff_material.albedo_texture = soft
	puff_mesh.material = puff_material
	_steam.mesh = puff_mesh
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.0)
	])
	_steam.color_ramp = ramp
	add_child(_steam)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 1.9, 1.7)
	collision.shape = shape
	collision.position = Vector3(0, 1.1, 0.05)
	add_child(collision)

	_label = Label3D.new()
	_label.name = "Label"
	_label.position = Vector3(0, 2.2, 0.5)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 36
	_label.pixel_size = 0.005
	_label.outline_size = 7
	_label.modulate = Color(1.0, 0.8, 0.35)
	_label.visible = false
	add_child(_label)


func _build_audio() -> void:
	_turn_player = _make_player("TurnPlayer", TURN_SFX, 0.0, 14.0)
	_impact_player = _make_player("ImpactPlayer", CLANK_SFX, 0.0, 22.0)
	_release_player = _make_player("ReleasePlayer", RELEASE_SFX, 2.0, 28.0)
	_leak_player = _make_player("LeakPlayer", LEAK_SFX, -14.0, 14.0)
	_leak_player.position = Vector3(0.05, 1.25, 0.5)


func _make_player(player_name: String, stream: AudioStream, volume_db: float, max_distance: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.unit_size = 4.0
	player.max_distance = max_distance
	player.position = Vector3(0, 1.2, 0.6)
	add_child(player)
	return player


# ── State ────────────────────────────────────────────────────────────────────

func _set_lamp(color: Color) -> void:
	_lamp_material.albedo_color = color
	_lamp_material.emission = color
	_lamp_light.light_color = color


func _set_leaking(leaking: bool) -> void:
	_steam.emitting = leaking
	if leaking:
		_leak_player.play()
	else:
		_leak_player.stop()


func show_outline() -> void:
	if activated or turning:
		return
	_outline.visible = true
	_label.text = "%s\n[E] CLOSE" % display_name
	_label.modulate = Color(1.0, 0.8, 0.35)
	_label.visible = true


func hide_outline() -> void:
	_outline.visible = false
	_label.visible = false


func interact() -> void:
	if activated or turning:
		return

	var generator := get_tree().get_first_node_in_group("generator")
	if generator == null or not generator.has_method("open_pressure_valve"):
		push_warning("%s could not find the generator" % display_name)
		return
	if not bool(generator.open_pressure_valve(valve_id)):
		return

	turning = true
	hide_outline()
	_impact_player.stream = CLANK_SFX
	_impact_player.pitch_scale = randf_range(0.9, 1.05)
	_impact_player.play()
	_turn_player.play()

	var turn_tween := create_tween().set_parallel(true)
	turn_tween.set_trans(Tween.TRANS_SINE)
	turn_tween.set_ease(Tween.EASE_IN_OUT)
	turn_tween.tween_property(_wheel, "rotation:z", _wheel.rotation.z - TAU * 1.75, 1.3)
	turn_tween.tween_property(_needle, "rotation:z", deg_to_rad(65.0), 1.3)
	turn_tween.tween_property(_leak_player, "volume_db", -40.0, 1.3)
	await turn_tween.finished

	activated = true
	turning = false
	_set_leaking(false)
	_leak_player.volume_db = -14.0
	_set_lamp(LAMP_CLOSED)
	# The line vents as it seals: one last burst of steam and a heavy clunk.
	_steam.amount = 40
	_steam.one_shot = true
	_steam.explosiveness = 0.8
	_steam.restart()
	_steam.emitting = true
	_release_player.play()
	_impact_player.stream = SLAM_SFX
	_impact_player.pitch_scale = 1.0
	_impact_player.play()

	_label.text = "%s\nCLOSED" % display_name
	_label.modulate = Color(0.3, 1.0, 0.45)
	_label.visible = true
	await get_tree().create_timer(1.4).timeout
	_label.visible = false
