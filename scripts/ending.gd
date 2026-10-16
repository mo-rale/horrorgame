extends Node3D
# The ending: dawn at the factory gate. The player has walked out; the camera
# turns back to the plant, the windows go dark one by one, the foreman appears in
# the gateway and the sign comes back on. Then a title card with the run's stats.
# Reuses the main-menu backdrop (scenes/main_menu_scenery.tscn) graded for dawn.
# Press SPACE or ENTER to skip to the final card.

const UiSounds := preload("res://scripts/ui_sounds.gd")
const GATE_POSITION := Vector3(9.0, 0.95, -31.2)

@onready var scenery: Node3D = $Scenery
@onready var camera: Camera3D = $Camera3D
@onready var narration: Label = %Narration
@onready var fade: ColorRect = %Fade
@onready var final_card: Control = %FinalCard
@onready var stats_label: Label = %Stats
@onready var play_again_button: Button = %PlayAgainButton
@onready var menu_button: Button = %MenuButton

var _skipped := false
var _finished := false
var _fade_tween: Tween


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_grade_for_dawn()
	var birds_stream := $Birds.stream as AudioStreamOggVorbis
	birds_stream.loop = true

	var stats: Dictionary = Engine.get_meta("run_stats", {})
	var seconds := int(stats.get("time", 0))
	var new_best := Settings.record_run(seconds, int(stats.get("notes", 0))) if seconds > 0 else false
	stats_label.text = "TIME %02d:%02d     NOTES %d/%d" % [
		seconds / 60, seconds % 60, int(stats.get("notes", 0)), int(stats.get("notes_total", 8))
	]
	if new_best:
		stats_label.text += "     NEW BEST"
	play_again_button.pressed.connect(
		func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	menu_button.pressed.connect(
		func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	UiSounds.attach(self)
	_run()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		not _finished
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE)
	):
		_skipped = true


func _grade_for_dawn() -> void:
	# The menu set is built for a stormy night; take the storm away and light it
	# from behind with a cold dawn.
	var weather := scenery
	weather.set_process(false)
	(weather.get_node("LightningLight") as DirectionalLight3D).light_energy = 0.0
	(weather.get_node("Rain") as GPUParticles3D).emitting = false
	var set_node := weather.get_node("Set")
	set_node.set_process(false)
	var rain_audio := set_node.get_node_or_null("Rain") as AudioStreamPlayer
	if rain_audio:
		rain_audio.stop()
		rain_audio.autoplay = false
	(weather.get_node("Camera3D") as Camera3D).current = false
	camera.current = true

	var environment := (weather.get_node("WorldEnvironment") as WorldEnvironment).environment.duplicate() as Environment
	environment.background_color = Color(0.5, 0.36, 0.34)
	environment.ambient_light_color = Color(0.5, 0.42, 0.42)
	environment.ambient_light_energy = 1.3
	environment.fog_light_color = Color(0.6, 0.47, 0.42)
	environment.fog_density = 0.017
	environment.volumetric_fog_albedo = Color(0.95, 0.78, 0.66)
	environment.volumetric_fog_density = 0.03
	Settings.apply_quality(environment)
	(weather.get_node("WorldEnvironment") as WorldEnvironment).environment = environment

	var sun := weather.get_node("NightLight") as DirectionalLight3D
	sun.light_color = Color(1.0, 0.62, 0.42)
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-10.0, 180.0, 0.0)

	# The street lamps are off in daylight; keep the red lamp over the gate.
	for light in set_node.find_children("*", "OmniLight3D", true, false):
		if not (light.get_parent().name == "Factory"):
			(light as OmniLight3D).visible = false
	# The foreman waits out of sight until the very end.
	var figure := set_node.get_node("Figure") as Node3D
	figure.visible = false
	figure.position = GATE_POSITION


func _say(text: String, hold: float) -> void:
	if _skipped:
		return
	narration.text = text
	var tween := create_tween()
	tween.tween_property(narration, "modulate:a", 1.0, 0.9)
	await tween.finished
	await _wait(hold)
	tween = create_tween()
	tween.tween_property(narration, "modulate:a", 0.0, 0.8)
	await tween.finished


func _wait(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0 and not _skipped:
		await get_tree().process_frame
		remaining -= get_process_delta_time()


func _run() -> void:
	$Birds.play()
	await _wait(0.6)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "color:a", 0.0, 3.0)
	await _say("06:02. The gate seal released at dawn.", 2.4)
	await _say("You walked out. Fourteen others did not.", 2.6)

	# Turn around to look back at the plant.
	if not _skipped:
		var turn := create_tween()
		turn.set_trans(Tween.TRANS_SINE)
		turn.set_ease(Tween.EASE_IN_OUT)
		turn.tween_property(camera, "rotation:y", 0.0, 5.5)
		turn.parallel().tween_property(camera, "rotation:x", deg_to_rad(9.0), 5.5)
		await _wait(2.0)
		await _say("The generator is still running.", 2.0)
		if turn.is_running():
			await turn.finished

	# One by one the lights go out.
	var windows := get_tree().get_nodes_in_group("menu_windows")
	for node in windows:
		if _skipped:
			break
		var material := (node as MeshInstance3D).material_override as StandardMaterial3D
		var dim := create_tween()
		dim.tween_property(material, "emission_energy_multiplier", 0.0, 0.35)
		await _wait(0.3)
	await _wait(0.8)

	if not _skipped:
		$GateSound.play()
		await _wait(0.9)
		_reveal_foreman()
		var zoom := create_tween()
		zoom.tween_property(camera, "fov", 52.0, 6.0)
		await _wait(1.6)
	await _say("The gate always opens... for the next shift.", 3.2)
	await _wait(0.6)
	_show_final_card()


func _reveal_foreman() -> void:
	var set_node := scenery.get_node("Set")
	var figure := set_node.get_node("Figure") as Node3D
	figure.visible = true
	var look := camera.global_position
	look.y = figure.global_position.y
	figure.look_at(look, Vector3.UP)
	$Sting.play()
	# The dead neon sign comes back on, whole.
	var sign_label := set_node.get_node("Factory/Sign") as Label3D
	sign_label.text = "HALVERSON WORKS\nNEXT SHIFT  22:00"
	sign_label.modulate = Color(1.0, 0.28, 0.2, 1.0)


func _show_final_card() -> void:
	if _finished:
		return
	_finished = true
	if _fade_tween:
		_fade_tween.kill()
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 1.4)
	await tween.finished
	final_card.visible = true
	$UI/TopBar.visible = false
	$UI/BottomBar.visible = false
	narration.visible = false
	$UI/SkipHint.visible = false
	fade.color.a = 0.0
	$Birds.stop()
	play_again_button.grab_focus()
