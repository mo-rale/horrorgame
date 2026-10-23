extends Node
# Gives every button, check box and slider under a root node a sound: a low
# metallic tick on hover/focus, a heavy clunk on press, a deeper one for
# back/resume, a heartbeat sting for PLAY and a faint tick when a slider moves.
# Use UiSounds.attach(some_control_or_canvas_layer) once; it also covers
# controls added later and keeps working while the game is paused.

const HOVER := preload("res://assets/sfx/ui/hover.wav")
const CLICK := preload("res://assets/sfx/ui/click.wav")
const BACK := preload("res://assets/sfx/ui/back.wav")
const START := preload("res://assets/sfx/ui/start.wav")
const SLIDER := preload("res://assets/sfx/ui/slider.wav")
const PAUSE_OPEN := preload("res://assets/sfx/ui/pause_open.wav")
const PAUSE_CLOSE := preload("res://assets/sfx/ui/pause_close.wav")

const BACK_WORDS := ["back", "resume", "mainmenu", "quit"]

var _players: Dictionary = {}
var _quiet_until := 0.0
var _slider_cooldown := 0.0


static func attach(root: Node) -> Node:
	var existing := root.get_node_or_null("UiSounds")
	if existing:
		return existing
	var instance: Node = load("res://scripts/ui_sounds.gd").new()
	instance.name = "UiSounds"
	root.add_child(instance)
	return instance


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound_name in ["hover", "click", "back", "start", "slider", "pause_open", "pause_close"]:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		player.volume_db = -6.0
		add_child(player)
		_players[sound_name] = player
	_players["hover"].stream = HOVER
	_players["hover"].volume_db = -14.0
	_players["click"].stream = CLICK
	_players["back"].stream = BACK
	_players["start"].stream = START
	_players["slider"].stream = SLIDER
	_players["slider"].volume_db = -16.0
	_players["pause_open"].stream = PAUSE_OPEN
	_players["pause_close"].stream = PAUSE_CLOSE

	# Ignore the focus sound of the very first button grabbing focus on load.
	_quiet_until = Time.get_ticks_msec() / 1000.0 + 0.4
	var scope := get_parent()
	_hook_tree(scope)
	get_tree().node_added.connect(
		func(node: Node) -> void:
			if scope.is_ancestor_of(node):
				_hook(node)
	)


func play(sound_name: String) -> void:
	var player := _players.get(sound_name) as AudioStreamPlayer
	if player and player.is_inside_tree():
		player.pitch_scale = randf_range(0.96, 1.04) if sound_name in ["hover", "click"] else 1.0
		player.play()


func _hook_tree(node: Node) -> void:
	_hook(node)
	for child in node.get_children():
		_hook_tree(child)


func _hook(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.mouse_entered.connect(_on_hover.bind(button))
		button.focus_entered.connect(_on_focus.bind(button))
		button.pressed.connect(_on_pressed.bind(button))
	elif node is Slider:
		var slider := node as Slider
		slider.mouse_entered.connect(_on_hover.bind(slider))
		slider.value_changed.connect(_on_slider_changed)


func _on_hover(control: Control) -> void:
	if control is BaseButton and (control as BaseButton).disabled:
		return
	play("hover")


func _on_focus(_button: BaseButton) -> void:
	if Time.get_ticks_msec() / 1000.0 < _quiet_until:
		return
	play("hover")


func _on_pressed(button: BaseButton) -> void:
	var lowered := button.name.to_lower()
	if lowered.contains("play") and not lowered.contains("playagain"):
		play("start")
	elif BACK_WORDS.any(func(word: String) -> bool: return lowered.contains(word)):
		play("back")
	else:
		play("click")


func _on_slider_changed(_value: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _slider_cooldown:
		return
	_slider_cooldown = now + 0.06
	play("slider")
