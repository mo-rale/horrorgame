extends Node
# Run: Godot --path . res://tests/menu_keys.tscn
# Opens settings -> controls, rebinds Flashlight to G through the real UI flow,
# checks InputMap + saved config, resets, and screenshots each tab.

var menu: Node
var frame := 0


func _ready() -> void:
	menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	event.keycode = code as Key
	event.pressed = true
	Input.parse_input_event(event)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://menukeys_%s.png" % name)


func _process(_delta: float) -> void:
	frame += 1
	if frame == 30:
		menu._show_settings()
	if frame == 36:
		_shot("audio")
		menu._select_tab(1)
	if frame == 42:
		_shot("display")
		menu._select_tab(2)
	if frame == 48:
		menu._key_buttons["Flashlight"].pressed.emit()
	if frame == 54:
		_shot("waiting")
		_key(KEY_G)
	if frame == 62:
		print("[Keys] flashlight=%s (want G)  F-is-free=%s" % [Settings.key_text("Flashlight"), Settings.action_for_key(KEY_F) == ""])
		menu._key_buttons["Forward"].pressed.emit()
	if frame == 66:
		_key(KEY_G)   # already used by Flashlight: should swap
	if frame == 72:
		print("[Keys] forward=%s flashlight=%s (want G and W)" % [Settings.key_text("Forward"), Settings.key_text("Flashlight")])
		_shot("rebound")
		var config := ConfigFile.new()
		config.load("user://settings.cfg")
		print("[Keys] saved forward=%s" % config.get_value("keys", "Forward"))
		Settings.reset_bindings()
	if frame == 80:
		print("[Keys] after reset: forward=%s flashlight=%s sprint=%s (want W F SHIFT)" % [Settings.key_text("Forward"), Settings.key_text("Flashlight"), Settings.key_text("Sprint")])
		get_tree().quit()
