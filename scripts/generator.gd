extends Node3D

signal generator_started
signal fuel_changed(current_fuel: int, required_fuel: int)

const REQUIRED_FUEL := 3

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
var can_interact := true  # Cooldown flag
var is_outline_visible := false  # Track outline state to prevent flickering

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


func _update_fuel_display() -> void:
	if fuel < REQUIRED_FUEL:
		fuelcount.text = "FUEL: " + str(fuel) + "/" + str(REQUIRED_FUEL)
		fuelcount.modulate = Color.RED if fuel == 0 else Color.YELLOW
	else:
		fuelcount.text = "GENERATOR READY!"
		fuelcount.modulate = Color.GREEN

func fueled():
	if fuel < REQUIRED_FUEL:
		fuel += 1
		correct.play()
		_update_fuel_display()
		fuel_changed.emit(fuel, REQUIRED_FUEL)


func get_current_fuel() -> int:
	return fuel


func get_required_fuel() -> int:
	return REQUIRED_FUEL

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
	
	if fuel < REQUIRED_FUEL:
		can_interact = false  # Start cooldown
		fuelcount.text = "NOT ENOUGH FUEL!"
		fuelcount.modulate = Color.RED
		error.play()
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
