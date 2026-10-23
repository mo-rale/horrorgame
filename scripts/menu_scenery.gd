extends Node3D
# Main-menu backdrop: the front gate of Halverson Works on a stormy night. A
# dead neon sign, a failing lamp, a fence and, whenever lightning strikes, the
# night-shift foreman standing a little closer than before. The set lives in
# scenes/main_menu_scenery.tscn; the script rebuilds it only if the nodes are
# missing (tools/bake_scenes.gd uses that to create the scene).

const TEX := "res://assets/SBS - Horror Texture Pack 128x128/128x128/"
const GROUND_TEXTURE := preload(TEX + "Stone/Horror_Stone_01-128x128.png")
const BRICK_TEXTURE := preload(TEX + "Brick/Horror_Brick_11-128x128.png")
const PATH_TEXTURE := preload(TEX + "Stone/Horror_Stone_07-128x128.png")
const METAL_TEXTURE := preload(TEX + "Metal/Horror_Metal_02-128x128.png")
const RUST_TEXTURE := preload(TEX + "Metal/Horror_Metal_09-128x128.png")
const ENEMY_MODEL := preload("res://scripts/enemy_model.gd")
const FLICKER := preload("res://scripts/flicker_light.gd")
const RAIN_SFX := preload("res://assets/sfx/menu/rain_loop.ogg")
const THUNDER_SFX := preload("res://assets/sfx/menu/thunder.ogg")

@export var camera_path: NodePath = ^"../Camera3D"

# Stations the figure moves between each time lightning strikes (far to near).
const FIGURE_STATIONS: Array[Vector3] = [
	Vector3(10.5, 0.95, -29.0),
	Vector3(8.0, 0.95, -23.0),
	Vector3(6.2, 0.95, -17.5),
	Vector3(5.0, 0.95, -13.0),
	Vector3(4.3, 0.95, -9.5),
]

var _camera: Camera3D
var _figure: Node3D
var _station := 0
var _strikes_at_closest := 0
var _time := 0.0
var _windows: Array[StandardMaterial3D] = []
var _window_phase: Array[float] = []
var _sign: Label3D
var _sign_timer := 0.0
var _thunder: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_camera = get_node_or_null(camera_path) as Camera3D
	if has_node("Factory"):
		_bind_set()
	else:
		_build_environment()
		_build_ground()
		_build_factory()
		_build_fence()
		_build_lamps()
		_build_trees()
		_build_figure()
		_build_audio()
	_start_runtime()
	var weather := get_parent()
	if weather and weather.has_signal("lightning_struck"):
		weather.connect("lightning_struck", _on_lightning)


func _enter_tree() -> void:
	# The rain loops. This runs before the Rain node's autoplay starts.
	var rain := get_node_or_null("Rain") as AudioStreamPlayer
	if rain and rain.stream is AudioStreamOggVorbis:
		(rain.stream as AudioStreamOggVorbis).loop = true


func _bind_set() -> void:
	_sign = $Factory/Sign
	_figure = $Figure
	_thunder = $Thunder


func _start_runtime() -> void:
	# Window glow pulses and the rain loops; both use the scene's own nodes.
	for node in get_tree().get_nodes_in_group("menu_windows"):
		var window_mesh := node as MeshInstance3D
		if window_mesh and is_ancestor_of(window_mesh):
			var material := window_mesh.material_override as StandardMaterial3D
			if not _windows.has(material):
				_windows.append(material)
				_window_phase.append(_rng.randf() * TAU)
	_place_figure()
	var world := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		world.environment = world.environment.duplicate()
		Settings.apply_quality(world.environment)


func _process(delta: float) -> void:
	_time += delta
	if _camera:
		# A slow, unsteady drift, as if someone is creeping up to the gate.
		_camera.position = Vector3(
			-1.2 + sin(_time * 0.11) * 0.45,
			1.65 + sin(_time * 0.27) * 0.03,
			3.0 - fmod(_time, 90.0) * 0.012
		)
		_camera.look_at(Vector3(4.2 + sin(_time * 0.07) * 0.5, 2.4, -22.0))
	for index in _windows.size():
		var pulse := 0.6 + 0.4 * sin(_time * (1.1 + index * 0.13) + _window_phase[index])
		_windows[index].emission_energy_multiplier = 1.0 + pulse * 1.2
	# The sign is mostly dead; a stray flicker brings it back for an instant.
	_sign_timer -= delta
	if _sign_timer <= 0.0 and _sign:
		_sign_timer = _rng.randf_range(0.04, 2.8)
		_sign.modulate.a = _rng.randf_range(0.0, 0.95) if _rng.randf() < 0.55 else 0.12


# ── Helpers ──────────────────────────────────────────────────────────────────

func _material(texture: Texture2D, tint: Color, uv := 0.3, roughness := 0.8) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * uv
	material.roughness = roughness
	return material


func _flat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _cylinder(top: float, bottom: float, height: float, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


# ── Scene pieces ─────────────────────────────────────────────────────────────

func _build_environment() -> void:
	var existing := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if existing == null:
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.016, 0.024)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.1, 0.13, 0.19)
	environment.ambient_light_energy = 0.8
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.05, 0.065, 0.085)
	environment.fog_density = 0.011
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.035
	environment.volumetric_fog_albedo = Color(0.55, 0.6, 0.7)
	environment.volumetric_fog_length = 70.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_bloom = 0.15
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.75
	Settings.apply_quality(environment)
	existing.environment = environment


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 140)
	ground.mesh = plane
	ground.material_override = _material(GROUND_TEXTURE, Color(0.38, 0.4, 0.44), 0.35, 0.28)
	add_child(ground)
	# The cracked path up to the gate.
	_box(Vector3(5.0, 0.03, 40.0), Vector3(6.0, 0.015, -12.0), _material(PATH_TEXTURE, Color(0.42, 0.42, 0.46), 0.45, 0.35))


func _build_factory() -> void:
	var brick := _material(BRICK_TEXTURE, Color(0.42, 0.37, 0.37), 0.28, 0.9)
	var factory := Node3D.new()
	factory.name = "Factory"
	factory.position = Vector3(10.0, 0.0, -38.0)
	add_child(factory)
	_box(Vector3(36, 11, 12), Vector3(0, 5.5, 0), brick, factory)
	_box(Vector3(14, 3, 12.6), Vector3(-3, 12.4, 0), brick, factory)        # raised roof section
	_box(Vector3(38, 0.6, 13), Vector3(0, 11.2, 0), _flat(Color(0.05, 0.05, 0.06)), factory)

	# Chimneys with smoke.
	var smoke_texture := _soft_texture()
	for chimney in [Vector3(-12, 0, -1), Vector3(-5, 0, -2), Vector3(13, 0, -1)]:
		var height := 22.0 + absf(chimney.x) * 0.2
		_cylinder(1.0, 1.5, height, Vector3(chimney.x, height * 0.5, chimney.z), brick, factory)
		_add_smoke(Vector3(chimney.x, height + 0.5, chimney.z), smoke_texture, factory)

	# Windows on the front face (z = +6): mostly black, a few lit, one red.
	var dark_glass := _glow(Color(0.02, 0.03, 0.04), 0.03)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for row in 3:
		for col in 11:
			var x := -15.0 + col * 3.0
			if absf(x - -1.0) < 4.2 and row == 0:
				continue    # leave room for the gate
			var y := 3.3 + row * 3.0
			var lit := rng.randf() < 0.16
			var red := row == 2 and col == 8
			var material: StandardMaterial3D = dark_glass
			if red:
				material = _glow(Color(0.9, 0.05, 0.03), 2.0)
			elif lit:
				material = _glow(Color(1.0, 0.6, 0.22), 1.6)
			var window := _box(Vector3(1.5, 1.8, 0.1), Vector3(x, y, 6.02), material, factory)
			window.name = "Window"
			if lit:
				window.add_to_group("menu_windows", true)

	# The gate and its dead sign.
	_box(Vector3(6.5, 5.4, 0.35), Vector3(-1.0, 2.7, 6.0), _material(RUST_TEXTURE, Color(0.35, 0.32, 0.3), 0.5, 0.7), factory)
	_box(Vector3(0.14, 5.4, 0.4), Vector3(-1.0, 2.7, 6.05), _flat(Color(0.02, 0.02, 0.02)), factory)
	_box(Vector3(7.0, 0.25, 0.5), Vector3(-1.0, 5.6, 6.1), _flat(Color(0.05, 0.05, 0.05)), factory)
	_sign = Label3D.new()
	_sign.name = "Sign"
	_sign.text = "HALV  RSON  W RKS"
	_sign.font_size = 140
	_sign.pixel_size = 0.014
	_sign.shaded = false
	_sign.double_sided = false
	_sign.modulate = Color(0.95, 0.35, 0.28, 0.0)
	_sign.outline_size = 0
	_sign.position = Vector3(-1.0, 7.2, 6.3)
	factory.add_child(_sign)
	# A single red lamp over the gate.
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-1.0, 4.9, 7.5)
	lamp.light_color = Color(1.0, 0.1, 0.05)
	lamp.light_energy = 1.6
	lamp.omni_range = 9.0
	lamp.set_script(FLICKER)
	lamp.set("flicker_chance", 1.0)
	factory.add_child(lamp)
	_box(Vector3(0.3, 0.3, 0.3), Vector3(-1.0, 4.9, 6.3), _glow(Color(1.0, 0.1, 0.05), 3.0), factory)


func _add_smoke(at: Vector3, texture: Texture2D, parent: Node3D) -> void:
	var smoke := CPUParticles3D.new()
	smoke.position = at
	smoke.amount = 40
	smoke.lifetime = 9.0
	smoke.preprocess = 9.0
	smoke.direction = Vector3(0.35, 1.0, 0.0)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 1.8
	smoke.scale_amount_min = 4.0
	smoke.scale_amount_max = 8.0
	smoke.gravity = Vector3(1.0, 0.0, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = Color(0.1, 0.11, 0.14)
	quad.material = material
	smoke.mesh = quad
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	smoke.color_ramp = ramp
	parent.add_child(smoke)


func _soft_texture() -> GradientTexture2D:
	var soft := GradientTexture2D.new()
	soft.width = 64
	soft.height = 64
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	soft.gradient = gradient
	return soft


func _build_fence() -> void:
	var iron := _material(METAL_TEXTURE, Color(0.16, 0.16, 0.18), 0.6, 0.6)
	for index in 25:
		var x := -36.0 + index * 3.0
		if x > 3.0 and x < 9.5:
			continue        # the gap where the gate stands
		_box(Vector3(0.14, 2.6, 0.14), Vector3(x, 1.3, -5.0), iron)
		if index < 24:
			for y in [0.5, 1.4, 2.3]:
				_box(Vector3(3.0, 0.07, 0.05), Vector3(x + 1.5, y, -5.0), iron)
	# The gate itself: one leaf hangs open, the other has fallen off its hinge.
	var left := Node3D.new()
	left.position = Vector3(3.0, 0.0, -5.0)
	left.rotation.y = deg_to_rad(62.0)
	add_child(left)
	for y in [0.4, 1.0, 1.6, 2.2]:
		_box(Vector3(3.1, 0.07, 0.05), Vector3(1.55, y, 0), iron, left)
	for x in [0.0, 1.0, 2.0, 3.0]:
		_box(Vector3(0.05, 2.4, 0.05), Vector3(x + 0.05, 1.25, 0), iron, left)
	var right := Node3D.new()
	right.position = Vector3(9.5, 0.0, -5.0)
	right.rotation = Vector3(0.0, deg_to_rad(-20.0), deg_to_rad(-78.0))
	add_child(right)
	for y in [0.4, 1.0, 1.6, 2.2]:
		_box(Vector3(3.1, 0.07, 0.05), Vector3(-1.55, y, 0), iron, right)
	# Warning sign hanging on the fence.
	var board := _box(Vector3(1.4, 0.8, 0.04), Vector3(-6.0, 1.6, -4.92), _flat(Color(0.35, 0.05, 0.04)))
	var board_text := Label3D.new()
	board_text.text = "KEEP OUT\nSHIFT IN PROGRESS"
	board_text.font_size = 40
	board_text.pixel_size = 0.0035
	board_text.modulate = Color(0.9, 0.85, 0.75)
	board_text.outline_size = 0
	board_text.position = Vector3(0, 0, 0.03)
	board.add_child(board_text)


func _build_lamps() -> void:
	var iron := _material(METAL_TEXTURE, Color(0.2, 0.2, 0.22), 0.6, 0.6)
	# A working-ish street lamp near the camera, and a dying one further off.
	for spec in [[Vector3(1.8, 0, -3.0), 4.5, 1.0], [Vector3(14.0, 0, -9.0), 1.6, 0.35]]:
		var base: Vector3 = spec[0]
		var pole := Node3D.new()
		pole.position = base
		add_child(pole)
		_cylinder(0.06, 0.1, 5.2, Vector3(0, 2.6, 0), iron, pole)
		_box(Vector3(1.1, 0.07, 0.07), Vector3(-0.5, 5.15, 0), iron, pole)
		_box(Vector3(0.5, 0.12, 0.3), Vector3(-1.0, 5.05, 0), iron, pole)
		_box(Vector3(0.36, 0.06, 0.2), Vector3(-1.0, 4.97, 0), _glow(Color(1.0, 0.8, 0.5), 3.0), pole)
		var light := OmniLight3D.new()
		light.position = Vector3(-1.0, 4.8, 0)
		light.light_color = Color(1.0, 0.72, 0.38)
		light.light_energy = spec[1]
		light.omni_range = 17.0
		light.shadow_enabled = true
		light.set_script(FLICKER)
		light.set("flicker_chance", 1.0)
		light.set("dropout_chance", spec[2])
		pole.add_child(light)


func _build_trees() -> void:
	var bark := _flat(Color(0.03, 0.025, 0.025), 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for spot in [Vector2(-7, -2), Vector2(-15, -14), Vector2(24, -11), Vector2(-24, -26), Vector2(30, -22)]:
		var tree := Node3D.new()
		tree.position = Vector3(spot.x, 0, spot.y)
		add_child(tree)
		_cylinder(0.08, 0.32, 7.5, Vector3(0, 3.75, 0), bark, tree)
		for branch in 6:
			var length := rng.randf_range(1.8, 3.4)
			var arm := _cylinder(0.03, 0.09, length, Vector3.ZERO, bark, tree)
			var height := rng.randf_range(3.0, 7.0)
			arm.position = Vector3(0, height, 0)
			arm.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(0.7, 1.2))
			arm.position += arm.basis.y * length * 0.5


func _build_figure() -> void:
	if ResourceLoader.exists("res://scenes/enemy_model.tscn"):
		_figure = (load("res://scenes/enemy_model.tscn") as PackedScene).instantiate()
	else:
		_figure = Node3D.new()
		_figure.set_script(ENEMY_MODEL)
	_figure.name = "Figure"
	add_child(_figure)


func _place_figure() -> void:
	_figure.position = FIGURE_STATIONS[_station]
	if _camera:
		var look := _camera.global_position
		look.y = _figure.position.y
		_figure.look_at(look, Vector3.UP)


func _build_audio() -> void:
	var rain := AudioStreamPlayer.new()
	rain.name = "Rain"
	var rain_stream: AudioStreamOggVorbis = RAIN_SFX
	rain_stream.loop = true
	rain.stream = rain_stream
	rain.bus = &"SFX"
	rain.volume_db = -13.0
	rain.autoplay = true
	add_child(rain)
	_thunder = AudioStreamPlayer.new()
	_thunder.name = "Thunder"
	_thunder.stream = THUNDER_SFX
	_thunder.bus = &"SFX"
	_thunder.volume_db = -3.0
	add_child(_thunder)


func _on_lightning() -> void:
	# The flash hides the figure's move. It creeps closer with every strike and
	# starts over once it has stood at the front of the path for a while.
	if _station >= FIGURE_STATIONS.size() - 1:
		_strikes_at_closest += 1
		if _strikes_at_closest >= 2:
			_station = 0
			_strikes_at_closest = 0
	else:
		_station += 1
	_place_figure()
	get_tree().create_timer(_rng.randf_range(0.4, 2.2)).timeout.connect(
		func() -> void:
			_thunder.pitch_scale = _rng.randf_range(0.8, 1.1)
			_thunder.play()
	)
