extends Node3D

signal generator_started
signal fuel_changed(current_fuel: int, required_fuel: int)
signal fuse_changed(current_fuses: int, required_fuses: int)

const REQUIRED_FUEL := 3
const REQUIRED_FUSES := 3

@onready var start: AudioStreamPlayer3D = $start
@onready var running: AudioStreamPlayer3D = $running
@onready var smoke: CPUParticles3D = $smoke
@onready var outline: MeshInstance3D = %outline
@onready var fuelcount: Label3D = $fuelcount
@onready var error: AudioStreamPlayer3D = $error
@onready var gas_detect_area: Area3D = $gas_detect_area
@onready var light: OmniLight3D = $light
@onready var correct: AudioStreamPlayer3D = $correct

var started := false
var fuel := 0
var installed_fuses: Array[String] = []
var can_interact := true  # Cooldown flag
var is_outline_visible := false  # Track outline state to prevent flickering

@export_group("Enemy Hearing")
@export var fuel_insert_noise_radius := 8.0
@export var error_noise_radius := 18.0
@export var startup_noise_radius := 35.0

func _ready() -> void:
	light.visible = false
	outline.visible = false
	smoke.emitting = false
	# Add this node to the "generator" group so the enemy and fuel can find it
	add_to_group("generator")
	
	# Connect the area signals
	gas_detect_area.body_entered.connect(_on_gas_detect_area_body_entered)
	gas_detect_area.body_exited.connect(_on_gas_detect_area_body_exited)
	_update_fuel_display()
	fuse_changed.emit(installed_fuses.size(), REQUIRED_FUSES)


func _update_fuel_display() -> void:
	if installed_fuses.size() < REQUIRED_FUSES:
		fuelcount.text = "FUSES: %d/%d" % [installed_fuses.size(), REQUIRED_FUSES]
		fuelcount.modulate = Color.RED if installed_fuses.is_empty() else Color.YELLOW
	elif fuel < REQUIRED_FUEL:
		fuelcount.text = "FUEL: " + str(fuel) + "/" + str(REQUIRED_FUEL)
		fuelcount.modulate = Color.RED if fuel == 0 else Color.YELLOW
	else:
		fuelcount.text = "GENERATOR READY!"
		fuelcount.modulate = Color.GREEN

func fueled() -> bool:
	if installed_fuses.size() < REQUIRED_FUSES:
		_reject_action("INSTALL FUSES FIRST!")
		return false
	if fuel < REQUIRED_FUEL:
		fuel += 1
		correct.play()
		_emit_noise(fuel_insert_noise_radius)
		_update_fuel_display()
		fuel_changed.emit(fuel, REQUIRED_FUEL)
		return true
	return false


func install_fuse(fuse_type: String) -> bool:
	if started or installed_fuses.has(fuse_type) or installed_fuses.size() >= REQUIRED_FUSES:
		_reject_action("FUSE ALREADY INSTALLED!")
		return false
	installed_fuses.append(fuse_type)
	correct.play()
	_emit_noise(fuel_insert_noise_radius)
	_update_fuel_display()
	fuse_changed.emit(installed_fuses.size(), REQUIRED_FUSES)
	return true


func get_current_fuel() -> int:
	return fuel


func get_required_fuel() -> int:
	return REQUIRED_FUEL


func get_current_fuses() -> int:
	return installed_fuses.size()


func get_required_fuses() -> int:
	return REQUIRED_FUSES

func show_outline() -> void:
	# Only show outline if the generator hasn't started yet and not already visible
	if not started and not is_outline_visible:
		outline.visible = true
		is_outline_visible = true

func hide_outline() -> void:
	# Only hide if currently visible
	if is_outline_visible:
		outline.visible = false
		is_outline_visible = false

func interact() -> void:
	# Don't allow interaction if we're on cooldown or already started
	if not can_interact or started:
		return

	if installed_fuses.size() < REQUIRED_FUSES:
		can_interact = false
		fuelcount.text = "MISSING FUSES: %d/%d" % [installed_fuses.size(), REQUIRED_FUSES]
		fuelcount.modulate = Color.RED
		error.play()
		_emit_noise(error_noise_radius)
		await error.finished
		can_interact = true
		_update_fuel_display()
	elif fuel < REQUIRED_FUEL:
		can_interact = false  # Start cooldown
		fuelcount.text = "NOT ENOUGH FUEL!"
		fuelcount.modulate = Color.RED
		error.play()
		_emit_noise(error_noise_radius)
		# Wait for error sound to finish
		await error.finished
		can_interact = true  # End cooldown
		_update_fuel_display()
	else:
		fuelcount.visible = false
		started = true
		
		# Hide the outline immediately when interaction starts
		hide_outline()
		
		start.play()
		_emit_noise(startup_noise_radius)
		await get_tree().create_timer(2.0).timeout
		light.visible = true
		smoke.emitting = true
		running.play()
		generator_started.emit()

# Called when a body enters the gas detection area
func _on_gas_detect_area_body_entered(body: Node) -> void:
	# Check if the body is a fuel canister
	if body.is_in_group("grabable") and body.has_method("use"):
		# Use the fuel on the generator
		body.use(self)

# Called when a body exits the gas detection area
func _on_gas_detect_area_body_exited(body: Node) -> void:
	# Optional: Handle when fuel leaves the area
	pass


func _emit_noise(noise_radius: float) -> void:
	get_tree().call_group("enemy", "hear_noise", global_position, noise_radius)


func _reject_action(message: String) -> void:
	fuelcount.text = message
	fuelcount.modulate = Color.RED
	if not error.playing:
		error.play()
	_emit_noise(error_noise_radius)
	_restore_status_after_delay()


func _restore_status_after_delay() -> void:
	await get_tree().create_timer(1.2).timeout
	if not started:
		_update_fuel_display()
