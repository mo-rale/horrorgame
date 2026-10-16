extends Node3D
# Run (windowed): Godot --path . res://tests/render_enemy.tscn
# Saves a screenshot of the enemy model plus post-processing to user://enemy_shot.png

var frames := 0
var enemy: Node3D


func _ready() -> void:
	enemy = load("res://scenes/enemy.tscn").instantiate()
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.visible = true
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.9, 0.5, -2.4)
	cam.look_at(Vector3(0.0, 0.1, 0.0))
	cam.current = true
	var light := OmniLight3D.new()
	light.position = Vector3(1.5, 1.5, -2.5)
	light.light_energy = 2.0
	light.omni_range = 8.0
	add_child(light)
	var fx := CanvasLayer.new()
	fx.set_script(load("res://scripts/post_fx.gd"))
	add_child(fx)


func _process(_delta: float) -> void:
	frames += 1
	if frames == 5:
		enemy.visible = true
	if frames == 30:
		get_viewport().get_texture().get_image().save_png("user://enemy_shot.png")
		print("[Shot] saved ", ProjectSettings.globalize_path("user://enemy_shot.png"))
		get_tree().quit()
