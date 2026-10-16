extends StaticBody3D
# The plant's fuse box: a steel cabinet with its door hanging open, three fuse
# sockets (red, blue, yellow) and a main breaker. Fuses are inserted here (hold
# a fuse, aim, left click), not into the generator. When all three are in, the
# breaker flips on and the generator can be started. The model lives in the scene
# (scenes/fuse_box.tscn); the script rebuilds it only if the nodes are missing
# (tools/bake_scenes.gd uses that). The front faces local +Z and the back sits
# against a wall.

signal fuse_installed(fuse_type: String, installed: int, required: int)

const FuseModel := preload("res://scripts/fuse_model.gd")
const CABINET_TEXTURE := preload("res://assets/SBS - Horror Texture Pack 128x128/128x128/Metal/Horror_Metal_11-128x128.png")
const INSERT_SFX := preload("res://assets/sfx/fuse/insert_click.wav")
const SPARK_SFX := preload("res://assets/sfx/fuse/spark.wav")
const POWER_SFX := preload("res://assets/sfx/fuse/power_up.wav")
const HUM_SFX := preload("res://assets/sfx/fuse/transformer_hum.wav")
const ERROR_SFX := preload("res://assets/sfx/generator/error (mp3cut.net).mp3")

const SLOT_COLORS := {
	"RED": Color(1.0, 0.06, 0.04),
	"BLUE": Color(0.1, 0.32, 1.0),
	"YELLOW": Color(1.0, 0.72, 0.05),
}
const SLOT_ORDER := ["RED", "BLUE", "YELLOW"]
const SLOT_RATING := {"RED": "15A", "BLUE": "20A", "YELLOW": "30A"}
const SLOT_Y := 1.0
const FUSE_SCALE := 0.8

var installed_fuses: Array[String] = []

var _body_material: StandardMaterial3D
var _lamps := {}                      # fuse_type -> StandardMaterial3D
var _installed_models := {}           # fuse_type -> Node3D
var _lever: Node3D
var _power_lamp: StandardMaterial3D
var _inner_light: OmniLight3D
var _sparks: CPUParticles3D
var _label: Label3D
var _sfx: AudioStreamPlayer3D
var _hum: AudioStreamPlayer3D
var _outlined := false
var _spark_flash := 0.0


func _ready() -> void:
	add_to_group("fuse_box")
	if has_node("CabinetBack"):
		_bind_model()
	else:
		_build_cabinet()
		_build_sockets()
		_build_breaker_and_cables()
		_build_effects()
	_prepare_runtime()


func _bind_model() -> void:
	_body_material = $CabinetBack.material_override as StandardMaterial3D
	for fuse_type in SLOT_ORDER:
		_lamps[fuse_type] = get_node("Lamp_" + fuse_type).material_override
	_lever = $Lever
	_power_lamp = $PowerLamp.material_override as StandardMaterial3D
	_inner_light = $InnerLight
	_sparks = $Sparks
	_label = $Label
	_sfx = $Sfx
	_hum = $Hum


func _prepare_runtime() -> void:
	var hum_stream := HUM_SFX.duplicate() as AudioStreamWAV
	hum_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum_stream.loop_begin = 0
	hum_stream.loop_end = hum_stream.data.size() >> 1   # 16-bit mono: 2 bytes per sample
	_hum.stream = hum_stream
	_label.visible = false


# ── Model ────────────────────────────────────────────────────────────────────

func _box(size: Vector3, position: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance


func _cylinder(radius: float, height: float, position: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance


func _flat(color: Color, roughness := 0.7, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _build_cabinet() -> void:
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_texture = CABINET_TEXTURE
	_body_material.albedo_color = Color(0.62, 0.66, 0.62)
	_body_material.uv1_triplanar = true
	_body_material.uv1_scale = Vector3.ONE * 0.9
	_body_material.roughness = 0.75
	_body_material.emission_enabled = true
	_body_material.emission = Color(1.0, 0.8, 0.4)
	_body_material.emission_energy_multiplier = 0.0

	var dark := _flat(Color(0.05, 0.055, 0.05))
	# Shell: back, two sides, top and bottom make an open-fronted cabinet.
	_box(Vector3(1.4, 2.0, 0.06), Vector3(0, 1.0, -0.47), _body_material).name = "CabinetBack"
	_box(Vector3(0.06, 2.0, 0.5), Vector3(-0.67, 1.0, -0.22), _body_material)
	_box(Vector3(0.06, 2.0, 0.5), Vector3(0.67, 1.0, -0.22), _body_material)
	_box(Vector3(1.4, 0.06, 0.5), Vector3(0, 2.0, -0.22), _body_material)
	_box(Vector3(1.4, 0.06, 0.5), Vector3(0, 0.03, -0.22), _body_material)
	# Dark mounting plate inside.
	_box(Vector3(1.26, 1.86, 0.03), Vector3(0, 1.0, -0.43), dark)

	# The door, hinged on the left and swung open toward the player.
	var hinge := Node3D.new()
	hinge.position = Vector3(-0.7, 1.0, 0.03)
	hinge.rotation.y = deg_to_rad(-112.0)
	add_child(hinge)
	_box(Vector3(1.3, 1.94, 0.04), Vector3(0.65, 0, 0), _body_material, hinge)
	_box(Vector3(1.1, 0.7, 0.01), Vector3(0.65, 0.35, -0.025), _flat(Color(0.8, 0.77, 0.62)), hinge)
	var chart := Label3D.new()
	chart.text = "FUSE SCHEDULE\nRED     15A  LINE 1\nBLUE    20A  LINE 2\nYELLOW  30A  MAIN\n\nREPLACE WITH\nSAME RATING ONLY"
	chart.font_size = 22
	chart.pixel_size = 0.0035
	chart.modulate = Color(0.1, 0.08, 0.05)
	chart.outline_size = 0
	chart.double_sided = false
	chart.position = Vector3(0.65, 0.35, -0.034)
	chart.rotation.y = PI
	hinge.add_child(chart)
	_box(Vector3(1.3, 0.1, 0.045), Vector3(0.65, 0.88, 0), _flat(Color(0.85, 0.7, 0.05)), hinge)

	# Danger sign above the cabinet.
	var sign_plate := _flat(Color(0.8, 0.62, 0.04))
	sign_plate.emission_enabled = true
	sign_plate.emission = Color(0.7, 0.5, 0.02)
	sign_plate.emission_energy_multiplier = 0.35
	_box(Vector3(0.9, 0.34, 0.03), Vector3(0, 2.3, -0.2), sign_plate)
	var danger := Label3D.new()
	danger.text = "DANGER  480V"
	danger.font_size = 40
	danger.pixel_size = 0.004
	danger.modulate = Color(0.1, 0.06, 0.02)
	danger.outline_size = 0
	danger.double_sided = false
	danger.position = Vector3(0, 2.3, -0.18)
	add_child(danger)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 2.0, 0.6)
	collision.shape = shape
	collision.position = Vector3(0, 1.0, -0.2)
	add_child(collision)

	_label = Label3D.new()
	_label.name = "Label"
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0.0, 2.75, 0.3)
	_label.visible = false
	add_child(_label)


func _build_sockets() -> void:
	var bakelite := _flat(Color(0.07, 0.065, 0.06), 0.5)
	var brass := _flat(Color(0.85, 0.65, 0.3), 0.4, 0.2)
	brass.emission_enabled = true
	brass.emission = Color(0.45, 0.32, 0.1)
	brass.emission_energy_multiplier = 0.25
	var rail := _flat(Color(0.5, 0.52, 0.55), 0.5, 0.2)
	_box(Vector3(1.2, 0.04, 0.03), Vector3(0, SLOT_Y + 0.38, -0.39), rail)
	_box(Vector3(1.2, 0.04, 0.03), Vector3(0, SLOT_Y - 0.38, -0.39), rail)

	for index in SLOT_ORDER.size():
		var fuse_type: String = SLOT_ORDER[index]
		var color: Color = SLOT_COLORS[fuse_type]
		var x := -0.38 + 0.38 * index
		# Holder block with a brass clip at each end.
		_box(Vector3(0.24, 0.84, 0.08), Vector3(x, SLOT_Y, -0.38), bakelite)
		for sign_y in [-1.0, 1.0]:
			_box(Vector3(0.14, 0.07, 0.09), Vector3(x, SLOT_Y + sign_y * 0.33, -0.3), brass)
			_box(Vector3(0.015, 0.1, 0.1), Vector3(x - 0.06, SLOT_Y + sign_y * 0.33, -0.28), brass)
			_box(Vector3(0.015, 0.1, 0.1), Vector3(x + 0.06, SLOT_Y + sign_y * 0.33, -0.28), brass)
		# Colour plate and rating under the socket, plus a status lamp above.
		var plate := _flat(color * 0.55)
		_box(Vector3(0.2, 0.05, 0.02), Vector3(x, SLOT_Y - 0.5, -0.33), plate)
		var rating := Label3D.new()
		rating.text = "%s  %s" % [fuse_type.left(1), SLOT_RATING[fuse_type]]
		rating.font_size = 26
		rating.pixel_size = 0.0032
		rating.modulate = Color(0.9, 0.88, 0.8)
		rating.outline_size = 0
		rating.double_sided = false
		rating.position = Vector3(x, SLOT_Y - 0.6, -0.32)
		add_child(rating)
		var lamp_material := StandardMaterial3D.new()
		lamp_material.albedo_color = color * 0.2
		lamp_material.emission_enabled = true
		lamp_material.emission = color
		lamp_material.emission_energy_multiplier = 0.1
		_lamps[fuse_type] = lamp_material
		var lamp_mesh := SphereMesh.new()
		lamp_mesh.radius = 0.035
		lamp_mesh.height = 0.07
		var lamp := MeshInstance3D.new()
		lamp.name = "Lamp_" + fuse_type
		lamp.mesh = lamp_mesh
		lamp.material_override = lamp_material
		lamp.position = Vector3(x, SLOT_Y + 0.55, -0.32)
		add_child(lamp)


func _build_breaker_and_cables() -> void:
	var dark := _flat(Color(0.06, 0.06, 0.06))
	# Main breaker: a lever on a plate, down = off, up = on.
	_box(Vector3(0.34, 0.3, 0.04), Vector3(0.0, 1.88, -0.4), _flat(Color(0.12, 0.12, 0.13)))
	_lever = Node3D.new()
	_lever.name = "Lever"
	_lever.position = Vector3(0.0, 1.88, -0.37)
	_lever.rotation.z = deg_to_rad(-35.0)
	add_child(_lever)
	_box(Vector3(0.04, 0.2, 0.04), Vector3(0, 0.08, 0.02), _flat(Color(0.75, 0.05, 0.03)), _lever)
	_cylinder(0.035, 0.05, Vector3(0, 0.19, 0.02), _flat(Color(0.75, 0.05, 0.03)), _lever)

	_power_lamp = StandardMaterial3D.new()
	_power_lamp.emission_enabled = true
	_power_lamp.emission_energy_multiplier = 2.5
	_set_power_lamp(Color(1.0, 0.08, 0.04))
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.04
	lamp_mesh.height = 0.08
	var power := MeshInstance3D.new()
	power.name = "PowerLamp"
	power.mesh = lamp_mesh
	power.material_override = _power_lamp
	power.position = Vector3(0.22, 1.88, -0.36)
	add_child(power)

	# Cables from the sockets up into the ceiling and a conduit alongside.
	for x in [-0.4, -0.38, 0.0, 0.38]:
		_cylinder(0.018, 1.2, Vector3(x, 2.6, -0.4), dark)
	_cylinder(0.06, 1.6, Vector3(0.52, 2.8, -0.42), _flat(Color(0.5, 0.5, 0.52), 0.5, 0.2))
	# Cable bundle looping out of the bottom.
	for x in [-0.3, 0.0, 0.3]:
		_cylinder(0.02, 0.5, Vector3(x, 0.05, -0.38), dark)


func _build_effects() -> void:
	_inner_light = OmniLight3D.new()
	_inner_light.name = "InnerLight"
	_inner_light.position = Vector3(0, 1.4, 0.5)
	_inner_light.light_color = Color(1.0, 0.72, 0.35)
	_inner_light.light_energy = 0.7
	_inner_light.omni_range = 4.0
	_inner_light.shadow_enabled = false
	add_child(_inner_light)

	_sparks = CPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.position = Vector3(0, SLOT_Y, -0.2)
	_sparks.amount = 24
	_sparks.lifetime = 0.45
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.explosiveness = 1.0
	_sparks.direction = Vector3(0, 0.3, 1.0)
	_sparks.spread = 60.0
	_sparks.initial_velocity_min = 1.2
	_sparks.initial_velocity_max = 2.6
	_sparks.gravity = Vector3(0, -6.0, 0)
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.012
	spark_mesh.height = 0.024
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color(1.0, 0.85, 0.4)
	spark_mesh.material = spark_material
	_sparks.mesh = spark_mesh
	add_child(_sparks)

	_sfx = AudioStreamPlayer3D.new()
	_sfx.name = "Sfx"
	_sfx.bus = &"SFX"
	_sfx.unit_size = 5.0
	_sfx.position = Vector3(0, SLOT_Y, 0.2)
	add_child(_sfx)

	_hum = AudioStreamPlayer3D.new()
	_hum.name = "Hum"
	_hum.stream = HUM_SFX
	_hum.bus = &"SFX"
	_hum.volume_db = -22.0
	_hum.unit_size = 3.0
	_hum.max_distance = 12.0
	_hum.position = Vector3(0, 1.2, 0.0)
	add_child(_hum)


func _set_power_lamp(color: Color) -> void:
	_power_lamp.albedo_color = color
	_power_lamp.emission = color


# ── Behaviour ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _spark_flash > 0.0:
		_spark_flash = maxf(0.0, _spark_flash - delta * 5.0)
		_inner_light.light_energy = 0.7 + _spark_flash * 4.0
	elif is_complete():
		# A powered box buzzes and its light flickers a little.
		_inner_light.light_energy = 0.8 + sin(Time.get_ticks_msec() * 0.03) * 0.08


func show_outline() -> void:
	_outlined = true
	_body_material.emission_energy_multiplier = 0.3
	_refresh_label()
	_label.visible = true


func hide_outline() -> void:
	_outlined = false
	_body_material.emission_energy_multiplier = 0.0
	_label.visible = false


func interact() -> void:
	# Empty-handed: just report what the box needs.
	_refresh_label()


func is_complete() -> bool:
	return installed_fuses.size() >= SLOT_ORDER.size()


func install_fuse(fuse_type: String) -> bool:
	var generator := get_tree().get_first_node_in_group("generator")
	if generator == null:
		return false
	if (
		generator.has_method("get_current_pressure_valves")
		and generator.get_current_pressure_valves() < generator.get_required_pressure_valves()
	):
		_reject("CLOSE THE PRESSURE VALVES FIRST")
		return false
	if installed_fuses.has(fuse_type) or not SLOT_COLORS.has(fuse_type):
		_reject("THIS SLOT IS ALREADY FILLED")
		return false
	if generator.has_method("install_fuse") and not bool(generator.install_fuse(fuse_type)):
		_reject("THE FUSE WON'T SEAT")
		return false

	installed_fuses.append(fuse_type)
	_seat_fuse(fuse_type)
	_play(INSERT_SFX, randf_range(0.95, 1.05))
	_spark_flash = 1.0
	_sparks.restart()
	_sparks.emitting = true
	# The spark crackles a moment after the click.
	get_tree().create_timer(0.12).timeout.connect(
		func() -> void: _play(SPARK_SFX, randf_range(0.95, 1.1))
	)
	_refresh_label()
	fuse_installed.emit(fuse_type, installed_fuses.size(), SLOT_ORDER.size())
	if is_complete():
		_power_on()
	return true


func _seat_fuse(fuse_type: String) -> void:
	var index: int = SLOT_ORDER.find(fuse_type)
	var color: Color = SLOT_COLORS[fuse_type]
	var model := FuseModel.build(color, FUSE_SCALE)
	model.position = Vector3(-0.38 + 0.38 * index, SLOT_Y, -0.28)
	add_child(model)
	_installed_models[fuse_type] = model
	var lamp: StandardMaterial3D = _lamps[fuse_type]
	lamp.albedo_color = color
	lamp.emission_energy_multiplier = 3.0


func _power_on() -> void:
	_set_power_lamp(Color(0.1, 1.0, 0.25))
	_inner_light.light_color = Color(0.6, 1.0, 0.7)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_lever, "rotation:z", deg_to_rad(35.0), 0.35)
	get_tree().create_timer(0.3).timeout.connect(
		func() -> void:
			_play(POWER_SFX, 1.0)
			_hum.play()
	)


func _play(stream: AudioStream, pitch: float) -> void:
	_sfx.stream = stream
	_sfx.pitch_scale = pitch
	_sfx.play()


func _reject(message: String) -> void:
	_label.text = message
	_label.modulate = Color(1.0, 0.3, 0.25)
	_label.visible = true
	_play(ERROR_SFX, 1.0)
	get_tree().create_timer(1.4).timeout.connect(
		func() -> void:
			if _outlined:
				_refresh_label()
			else:
				_label.visible = false
	)


func _refresh_label() -> void:
	var count := installed_fuses.size()
	if is_complete():
		_label.text = "FUSE BOX\nPOWERED"
		_label.modulate = Color(0.4, 1.0, 0.5)
	else:
		_label.text = "FUSE BOX  %d/%d\nHOLD A FUSE + CLICK" % [count, SLOT_ORDER.size()]
		_label.modulate = Color(1.0, 0.85, 0.4)
