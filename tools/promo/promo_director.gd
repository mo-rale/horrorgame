@tool
class_name PromoDirector
extends Node
## Plays the Halverson Works promo trailer. Everything in it is a node in
## tools/promo/promo_trailer.tscn, so it can be edited by hand:
##
## - Shots: one PromoShot per shot, played top to bottom (drag to reorder).
##   Selecting a shot loads its game scene into the 3D view and shows its titles
##   in the 2D view. Its PromoKey cameras are the camera keyframes: select one
##   and tick "Preview" at the top of the 3D view to look through it. Move it
##   like any node, or fly the editor camera to a view and use Perspective menu >
##   Align Transform with View (Ctrl+Alt+M). Duplicate a key (Ctrl+D) to add one.
##   PromoForemanKey markers place the foreman.
## - Cues: one PromoCue (an AudioStreamPlayer) per sound, placed by "At".
## - Titles: the title layouts; change fonts, sizes and positions there.
##
## Press F6 to watch it. To record a video, turn on Movie Maker (the film-strip
## button at the top right of the editor) and press F6. The file goes to the path
## in this scene root's "movie_file" metadata (build/HalversonWorks_Promo.avi by default).

const LEVEL_SCENE := "res://scenes/main.tscn"
const GATE_SCENE := "res://scenes/main_menu_scenery.tscn"
const PLAYER_PARK := Vector3(0.0, 0.05, 60.0)

## Start the preview from this shot (empty = the beginning). Sounds start at the
## matching point on the timeline.
@export var start_from: PromoShot
## Close the game when the trailer ends (needed for Movie Maker recordings).
@export var quit_when_done := true
## Hide the gas cans and fuses the game scatters at random, so a stray pickup
## never wanders into a shot and every take looks the same.
@export var hide_pickups := true
## Length of the whole trailer.
@export_custom(PROPERTY_HINT_NONE, "suffix:s", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var total_length := 0.0:
	get:
		var t := 0.0
		for shot in get_shots():
			t += shot.duration
		return t

var _stage: Node
var _black: ColorRect
var _card: RichTextLabel
var _lower: Control
var _headline: Label
var _subline: Label
var _low_center: Label
var _title: Control
var _end: Control

var _shots: Array[PromoShot] = []
var _cues: Array[PromoCue] = []
var _keys: Array[PromoKey] = []
var _foreman_keys: Array[PromoForemanKey] = []
var _t := 0.0
var _shot_index := -1
var _shot_start := 0.0
var _total := 0.0
var _world: Node
var _world_kind := -1
var _cam: Camera3D
var _player: Node3D
var _enemy: Node3D
var _figure: Node3D
var _cue_volume: Dictionary = {}
var _cue_started: Dictionary = {}
var _prev_local := -1.0
var _mute_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _limiter: AudioEffectHardLimiter
var _preview_shot: PromoShot
var _preview_state: Array = []


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		var selection := _editor_selection()
		if not selection.is_connected("selection_changed", _on_editor_selection_changed):
			selection.connect("selection_changed", _on_editor_selection_changed)


func _ready() -> void:
	_find_nodes()
	if Engine.is_editor_hint():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	ResourceLoader.load_threaded_request(LEVEL_SCENE)
	ResourceLoader.load_threaded_request(GATE_SCENE)
	_shots = get_shots()
	for shot in _shots:
		_total += shot.duration
	if start_from:
		_t = start_from.starts_at
	for child in $Cues.get_children():
		if child is PromoCue:
			child.stop()
			_cues.append(child)
			_cue_volume[child] = child.volume_db
	_hide_text()
	_black.color.a = 1.0
	# Keep the trailer mix from clipping while it plays.
	_limiter = AudioEffectHardLimiter.new()
	_limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, _limiter)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		var selection := _editor_selection()
		if selection.is_connected("selection_changed", _on_editor_selection_changed):
			selection.disconnect("selection_changed", _on_editor_selection_changed)
		return
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _limiter:
			AudioServer.remove_bus_effect(0, i)
			break


func _find_nodes() -> void:
	_stage = $Stage
	_black = %Black
	_card = %Card
	_lower = %LowerThird
	_headline = %Headline
	_subline = %Subline
	_low_center = %LowCenter
	_title = %TitleBlock
	_end = %EndCard


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_follow_selection()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _shots.is_empty():
		return
	_t += delta
	if _t >= _total:
		if quit_when_done:
			get_tree().quit()
		return
	var index := _shot_at(_t)
	if index != _shot_index:
		_begin_shot(index)
	var shot := _shots[_shot_index]
	var local := _t - _shot_start
	_update_text(shot, local)
	_update_black(shot, local)
	if shot.kind != PromoShot.Kind.CARD and _cam:
		_update_camera(shot, local)
		_update_foreman(shot, local, delta)
		_update_flashlight(shot, local)
		_update_lightning(shot, local)
	_keep_game_quiet(delta)
	_update_cues()


## The shots in playing order.
func get_shots() -> Array[PromoShot]:
	var shots: Array[PromoShot] = []
	var parent := get_node_or_null("Shots")
	if parent:
		for child in parent.get_children():
			if child is PromoShot:
				shots.append(child)
	return shots


## Names the shot playing at `time` on the trailer timeline, and how far into it.
func describe_time(time: float) -> String:
	var start := 0.0
	for shot in get_shots():
		if time < start + shot.duration:
			return "%s  +%.2f s" % [shot.name, time - start]
		start += shot.duration
	return "after the end"


# ── Shots ────────────────────────────────────────────────────────────────────

func _shot_at(time: float) -> int:
	var acc := 0.0
	for i in _shots.size():
		acc += _shots[i].duration
		if time < acc:
			return i
	return _shots.size() - 1


func _begin_shot(index: int) -> void:
	_shot_index = index
	var shot := _shots[index]
	_shot_start = shot.starts_at
	_prev_local = -1.0
	_keys = shot.get_keys()
	_foreman_keys = shot.get_foreman_keys()
	_hide_text()
	if shot.kind == PromoShot.Kind.CARD:
		# Load the next scene behind the black card so the cut is clean.
		for i in range(index + 1, _shots.size()):
			if _shots[i].kind != PromoShot.Kind.CARD:
				_ensure_world(_shots[i].kind)
				break
		return
	_ensure_world(shot.kind)
	_setup_shot(shot)


func _ensure_world(kind: int) -> void:
	if kind == _world_kind and is_instance_valid(_world):
		return
	# Also clears an editor preview left behind when the script was reloaded.
	for child in _stage.get_children():
		child.queue_free()
	_cam = null
	_player = null
	_enemy = null
	_figure = null
	_world_kind = kind
	var path := LEVEL_SCENE if kind == PromoShot.Kind.LEVEL else GATE_SCENE
	var packed: PackedScene
	if not Engine.is_editor_hint():
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		packed = load(path) as PackedScene
	_world = packed.instantiate()
	if kind == PromoShot.Kind.LEVEL:
		_world.set("play_intro", false)
		_stage.add_child(_world)
		_player = _world.get_node("player")
		_enemy = _world.get_node("Enemy")
		_cam = _player.get_node("head/Camera3D")
		_enemy.get_node("Model").process_mode = Node.PROCESS_MODE_ALWAYS
		if hide_pickups:
			for node in _world.find_children("*", "Node3D", true, false):
				var file := node.scene_file_path
				if file.ends_with("gas_can.tscn") or file.ends_with("fuse.tscn"):
					(node as Node3D).visible = false
		if Engine.is_editor_hint():
			# The preview brightens the level; keep that off main.tscn's own environment.
			var world_env := _world.get_node("WorldEnvironment") as WorldEnvironment
			world_env.environment = world_env.environment.duplicate()
	else:
		_stage.add_child(_world)
		if not Engine.is_editor_hint():
			# Take the camera away from the menu's own slow drift.
			_world.get_node("Set").set("_camera", null)
		_cam = _world.get_node("Camera3D")
		_figure = _world.find_child("Figure", true, false) as Node3D
		if not Engine.is_editor_hint():
			# The gate's own lightning is random; shots fire it on cue instead.
			_world.set("_lightning_timer", 1.0e9)
			(_world.get("_rng") as RandomNumberGenerator).seed = 3
	_cam.current = true
	_mute_timer = 0.0


func _setup_shot(shot: PromoShot) -> void:
	_cam.current = true
	if _world_kind == PromoShot.Kind.LEVEL:
		_player.global_position = PLAYER_PARK
		_player.get_node("MeshInstance3D").visible = false
		var light := _player.get_node("head/Camera3D/light") as Light3D
		light.visible = shot.flashlight
		light.light_energy = shot.flashlight_energy
		_player.get_node("head/Camera3D/low_poly_flashlight").visible = shot.show_hand
		_enemy.visible = shot.show_foreman
		var env := (_world.get_node("WorldEnvironment") as WorldEnvironment).environment
		env.adjustment_enabled = true
		var settings := get_node_or_null("/root/Settings")
		var base_brightness: float = settings.brightness if settings else 1.0
		env.adjustment_brightness = base_brightness * shot.brightness
		_hide_game_hud.call_deferred()
	elif _figure:
		_figure.visible = shot.show_foreman


func _hide_game_hud() -> void:
	if not is_instance_valid(_world):
		return
	for node in _world.find_children("*", "CanvasLayer", true, false):
		var script: Script = node.get_script()
		var is_film_look := script != null and script.resource_path.ends_with("post_fx.gd")
		# In the editor the film look would cover the titles in the 2D view.
		if Engine.is_editor_hint() or not is_film_look:
			node.visible = false


# ── Camera, foreman, flashlight ──────────────────────────────────────────────

func _update_camera(shot: PromoShot, local: float) -> void:
	if _player:
		# The game must not move the player or the foreman during the trailer.
		_player.set_physics_process(false)
		_player.set_process(false)
		_player.set_process_input(false)
		_enemy.set_physics_process(false)
		_enemy.set_process(false)
	if _keys.is_empty():
		return
	var pose := _camera_pose(local)
	var xf: Transform3D = pose[0]
	if shot.handheld > 0.0:
		var s := shot.handheld
		xf.origin += Vector3(sin(local * 1.7) * 0.6 + sin(local * 3.1) * 0.3,
			sin(local * 2.3) * 0.5 + sin(local * 4.7) * 0.2, 0.0) * s * 0.04
		var yaw := sin(local * 0.9) * 0.6 * s * 0.01
		var pitch := sin(local * 1.3) * 0.4 * s * 0.01
		xf.basis = Basis(Vector3.UP, yaw) * xf.basis * Basis(Vector3.RIGHT, pitch)
	_cam.global_transform = xf
	_cam.fov = pose[1]


## Returns [transform, fov] at `time`, gliding from key to key.
func _camera_pose(time: float) -> Array:
	var prev := _keys[0]
	if time > prev.time:
		for i in range(1, _keys.size()):
			var key := _keys[i]
			if time <= key.time:
				var u := _ease((time - prev.time) / maxf(0.001, key.time - prev.time), key.easing)
				var pos := prev.global_position.lerp(key.global_position, u)
				var fov := lerpf(prev.fov, key.fov, u)
				if prev.look_distance > 0.0 and key.look_distance > 0.0:
					var aim := prev.get_look_point().lerp(key.get_look_point(), u)
					if pos.distance_to(aim) > 0.01:
						return [Transform3D(Basis.looking_at(aim - pos, Vector3.UP), pos), fov]
				var from_rot := prev.global_basis.get_rotation_quaternion()
				var rot := from_rot.slerp(key.global_basis.get_rotation_quaternion(), u)
				return [Transform3D(Basis(rot), pos), fov]
			prev = key
	return [Transform3D(prev.global_basis.orthonormalized(), prev.global_position), prev.fov]


static func _ease(u: float, easing: PromoKey.Easing) -> float:
	match easing:
		PromoKey.Easing.SMOOTH:
			return u * u * (3.0 - 2.0 * u)
		PromoKey.Easing.EASE_IN:
			return u * u
		PromoKey.Easing.EASE_OUT:
			return 1.0 - (1.0 - u) * (1.0 - u)
	return u


func _update_foreman(shot: PromoShot, local: float, delta: float) -> void:
	var body: Node3D = _enemy if _enemy else _figure
	if body == null or not shot.show_foreman or _foreman_keys.is_empty():
		return
	var pose := _foreman_pose(local)
	var prev := body.global_position
	body.global_position = pose[0]
	var face: Vector3 = _cam.global_position if shot.foreman_faces_camera else pose[1]
	face.y = body.global_position.y
	if body.global_position.distance_to(face) > 0.05:
		body.look_at(face, Vector3.UP)
	if _enemy and delta > 0.0:
		# The model animates its walk from the body's velocity.
		(_enemy as CharacterBody3D).velocity = (body.global_position - prev) / delta


## Fires the gate's lightning at the times listed in the shot.
func _update_lightning(shot: PromoShot, local: float) -> void:
	if _world_kind != PromoShot.Kind.GATE or not is_instance_valid(_world):
		return
	for strike in shot.lightning:
		if _prev_local < strike and local >= strike:
			_world.call("_start_lightning")
	# A strike books the next random one; push that off again.
	_world.set("_lightning_timer", 1.0e9)
	_prev_local = local


## Returns [position, the point he walks towards] at `time`. He walks in a
## straight line from marker to marker.
func _foreman_pose(time: float) -> Array:
	var first := _foreman_keys[0]
	if time <= first.time or _foreman_keys.size() == 1:
		return [first.global_position, _foreman_keys[mini(1, _foreman_keys.size() - 1)].global_position]
	for i in range(1, _foreman_keys.size()):
		var a := _foreman_keys[i - 1]
		var b := _foreman_keys[i]
		if time <= b.time:
			var u := (time - a.time) / maxf(0.001, b.time - a.time)
			return [a.global_position.lerp(b.global_position, u), b.global_position]
	var last := _foreman_keys[-1].global_position
	return [last, last]


func _update_flashlight(shot: PromoShot, local: float) -> void:
	if _player == null or shot.flicker.is_empty():
		return
	var light := _player.get_node("head/Camera3D/light") as Light3D
	light.light_energy = shot.flashlight_energy
	for window in shot.flicker:
		if local >= window.x and local <= window.y:
			light.light_energy = shot.flashlight_energy * _rng.randf_range(0.0, 0.3)


# ── Text and fades ───────────────────────────────────────────────────────────

func _hide_text() -> void:
	for node: CanvasItem in [_card, _lower, _low_center, _title, _end]:
		node.visible = false


## Fills in the shot's title layout and returns it (null when it has no text).
func _apply_text(shot: PromoShot) -> CanvasItem:
	match shot.text_style:
		PromoShot.TextStyle.CENTER:
			_card.text = "[center]%s[/center]" % shot.text
			return _card
		PromoShot.TextStyle.LOWER_THIRD:
			_headline.text = shot.text
			_subline.text = shot.subtext
			_subline.visible = not shot.subtext.is_empty()
			return _lower
		PromoShot.TextStyle.LOW_CENTER:
			_low_center.text = shot.text
			return _low_center
		PromoShot.TextStyle.TITLE:
			return _title
		PromoShot.TextStyle.END:
			return _end
	return null


func _update_text(shot: PromoShot, local: float) -> void:
	var node := _apply_text(shot)
	if node == null:
		return
	var out := shot.text_out if shot.text_out >= 0.0 else shot.duration - 0.7
	var alpha := clampf((local - shot.text_in) / 0.6, 0.0, 1.0) * clampf(1.0 - (local - out) / 0.5, 0.0, 1.0)
	node.visible = alpha > 0.0
	node.modulate.a = alpha


func _update_black(shot: PromoShot, local: float) -> void:
	var a := 0.0
	if shot.kind == PromoShot.Kind.CARD:
		a = 1.0
	else:
		if shot.fade_in > 0.0:
			a = maxf(a, 1.0 - local / shot.fade_in)
		if shot.fade_out > 0.0:
			a = maxf(a, (local - (shot.duration - shot.fade_out)) / shot.fade_out)
	_black.color.a = clampf(a, 0.0, 1.0)


# ── Sound ────────────────────────────────────────────────────────────────────

func _update_cues() -> void:
	for cue in _cues:
		if cue.stream == null:
			continue
		var local := _t - cue.at
		if local < 0.0 or local >= cue.length:
			if _cue_started.has(cue):
				cue.stop()
				_cue_started.erase(cue)
			continue
		var gain := 1.0
		if cue.fade_in > 0.0:
			gain = minf(gain, local / cue.fade_in)
		if cue.fade_out > 0.0:
			gain = minf(gain, (cue.length - local) / cue.fade_out)
		cue.volume_db = _cue_volume[cue] + linear_to_db(clampf(gain, 0.0001, 1.0))
		if not _cue_started.has(cue):
			_cue_started[cue] = true
			cue.play(cue.from + local)


## The trailer has its own sound mix, so the game scenes stay silent.
func _keep_game_quiet(delta: float) -> void:
	_mute_timer -= delta
	if _mute_timer > 0.0 or not is_instance_valid(_world):
		return
	_mute_timer = 0.5
	for node in _world.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			node.volume_db = -80.0


# ── Editor preview ───────────────────────────────────────────────────────────
# Selecting a shot, or anything under it, in the Scene dock previews it: its game
# scene loads into Stage, its titles show, and only its cameras stay visible. The
# game camera (with the flashlight) and the foreman follow the selected key, so
# "Preview" through a key shows that frame of the trailer. Nothing of the preview
# is saved, because the nodes under Stage have no owner.

func _editor_selection() -> Object:
	return Engine.get_singleton(&"EditorInterface").get_selection()


func _on_editor_selection_changed() -> void:
	if not is_inside_tree() or get_tree().edited_scene_root != self:
		return
	for node: Node in _editor_selection().get_selected_nodes():
		var shot := _shot_of(node)
		if shot:
			_preview(shot)
			return


func _shot_of(node: Node) -> PromoShot:
	while node and node != self:
		if node is PromoShot:
			return node
		node = node.get_parent()
	return null


func _preview(shot: PromoShot) -> void:
	_find_nodes()
	_preview_shot = shot
	_preview_state = []
	for other in get_shots():
		other.visible = other == shot
	if shot.kind != PromoShot.Kind.CARD:
		_ensure_world(shot.kind)
		_setup_shot(shot)


func _follow_selection() -> void:
	if not is_instance_valid(_preview_shot) or not _preview_shot.is_inside_tree():
		return
	var shot := _preview_shot
	var text := _apply_text(shot)
	for node: CanvasItem in [_card, _lower, _low_center, _title, _end]:
		node.visible = node == text
	if text:
		text.modulate.a = 1.0
	if shot.kind == PromoShot.Kind.CARD or not is_instance_valid(_cam):
		return
	_keys = shot.get_keys()
	_foreman_keys = shot.get_foreman_keys()
	var time := 0.0
	for node: Node in _editor_selection().get_selected_nodes():
		if (node is PromoKey or node is PromoForemanKey) and node.get_parent() == shot:
			time = node.time
	var cam_pose := _camera_pose(time) if not _keys.is_empty() else []
	var foreman_pose := _foreman_pose(time) if not _foreman_keys.is_empty() else []
	# Only touch the scene when something moved, so the editor can stay idle.
	var state := [shot, cam_pose, foreman_pose]
	if state == _preview_state:
		return
	_preview_state = state
	if not cam_pose.is_empty():
		_cam.global_transform = cam_pose[0]
		_cam.fov = cam_pose[1]
	_update_foreman(shot, time, 0.0)
