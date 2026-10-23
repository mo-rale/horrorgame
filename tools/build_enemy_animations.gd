extends SceneTree
# Gives the enemy model real Godot animation nodes. Run from the project root:
#   godot --headless --path . --script res://tools/build_enemy_animations.gd
#
# It opens scenes/enemy_model.tscn, adds (or replaces)
#   AnimationPlayer  the walk, stalk, chase and search clips
#   AmbientPlayer    looping eye pulse and coat sway (its own library: an
#                    AnimationTree adopts every clip of its player, and would
#                    fight this one over the eye tracks)
#   AnimationTree    a state machine of four moods, each a blend space over speed
# and saves the scene again. The clips go to scenes/enemy_animations.tres, which
# can be opened and edited in Godot's Animation panel. The meshes and their
# placement in the scene are left exactly as they are.

const SCENE_PATH := "res://scenes/enemy_model.tscn"
const LIBRARY_PATH := "res://scenes/enemy_animations.tres"
const AMBIENT_PATH := "res://scenes/enemy_ambient.tres"
const STEP := 1.0 / 30.0

var _root: Node3D
var _torso_rest := Vector3.ZERO
var _torso_pos := Vector3.ZERO


func _initialize() -> void:
	# Godot drops the scene's uid lines when it is saved from a script; keep them.
	var original_text := FileAccess.get_file_as_string(SCENE_PATH)
	var packed := load(SCENE_PATH) as PackedScene
	_root = packed.instantiate() as Node3D
	for node_name in ["AnimationPlayer", "AmbientPlayer", "AnimationTree"]:
		var old := _root.get_node_or_null(node_name)
		if old:
			_root.remove_child(old)
			old.free()
	var torso := _root.get_node("Torso") as Node3D
	_torso_rest = torso.rotation
	_torso_pos = torso.position

	var library := AnimationLibrary.new()
	for clip: Array in _clips():
		library.add_animation(clip[0], _bake(clip[1], clip[2], clip[3]))
	var saved := ResourceSaver.save(library, LIBRARY_PATH)
	print("[Anim] library saved: ", saved == OK)
	# Make the scene point at the files instead of embedding a copy of every clip.
	library.take_over_path(LIBRARY_PATH)
	var ambient_library := AnimationLibrary.new()
	ambient_library.add_animation("ambient", _ambient())
	ResourceSaver.save(ambient_library, AMBIENT_PATH)
	ambient_library.take_over_path(AMBIENT_PATH)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	_root.add_child(player)
	player.owner = _root
	player.add_animation_library("", library)

	var ambient := AnimationPlayer.new()
	ambient.name = "AmbientPlayer"
	_root.add_child(ambient)
	ambient.owner = _root
	ambient.add_animation_library("", ambient_library)
	ambient.autoplay = "ambient"

	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	_root.add_child(tree)
	tree.owner = _root
	tree.tree_root = _build_tree()
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.active = true

	var result := PackedScene.new()
	var error := result.pack(_root)
	if error == OK:
		error = ResourceSaver.save(result, SCENE_PATH)
	if error == OK:
		_restore_uids(original_text)
	print("[Anim] scene saved: ", error == OK)
	quit()


func _restore_uids(original_text: String) -> void:
	var text := FileAccess.get_file_as_string(SCENE_PATH)
	for prefix in ["[gd_scene", "[ext_resource type=\"Script\"", "[ext_resource type=\"Texture2D\""]:
		var before := ""
		for line in original_text.split("
"):
			if line.begins_with(prefix):
				before = line
				break
		var after := ""
		for line in text.split("
"):
			if line.begins_with(prefix):
				after = line
				break
		if before != "" and after != "":
			text = text.replace(after, before)
	var file := FileAccess.open(SCENE_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# ── The tree ─────────────────────────────────────────────────────────────────

func _build_tree() -> AnimationNodeBlendTree:
	var machine := AnimationNodeStateMachine.new()
	# State name, idle clip, moving clip, speed at which the moving clip is at full strength.
	var moods := [
		["Calm", "calm_idle", "calm_walk", 2.0, 0.4],
		["Stalk", "stalk_idle", "stalk_creep", 2.5, 0.5],
		["Chase", "chase_idle", "chase_run", 8.2, 0.12],
		["Search", "search_idle", "search_jog", 5.0, 0.4],
	]
	for index in moods.size():
		var mood: Array = moods[index]
		var space := AnimationNodeBlendSpace1D.new()
		space.min_space = 0.0
		space.max_space = 10.0
		var idle := AnimationNodeAnimation.new()
		idle.animation = mood[1]
		space.add_blend_point(idle, 0.0)
		var moving := AnimationNodeAnimation.new()
		moving.animation = mood[2]
		space.add_blend_point(moving, mood[3])
		machine.add_node(mood[0], space, Vector2(220.0, index * 110.0))
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition("Start", "Calm", start)
	# Any mood can switch to any other; the new mood decides how long the blend takes.
	for from_mood: Array in moods:
		for to_mood: Array in moods:
			if from_mood[0] == to_mood[0]:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			transition.xfade_time = to_mood[4]
			machine.add_transition(from_mood[0], to_mood[0], transition)

	var tree := AnimationNodeBlendTree.new()
	tree.add_node("States", machine, Vector2(0.0, 0.0))
	# Speeds the stride up or down to match the ground speed (set from enemy_model.gd).
	tree.add_node("Pace", AnimationNodeTimeScale.new(), Vector2(300.0, 0.0))
	tree.connect_node("Pace", 0, "States")
	tree.connect_node("output", 0, "Pace")
	return tree


# ── The clips ────────────────────────────────────────────────────────────────
# Each entry: name, length in seconds, whether to loop, a function (phase, time)
# returning the pose. The phase runs 0 to TAU over the clip, so anything built from
# whole multiples of it loops without a seam.

func _clips() -> Array:
	return [
		["calm_idle", 6.0, true, _calm_idle],
		["calm_walk", 1.2, true, _calm_walk],
		["stalk_idle", 4.0, true, _stalk_idle],
		["stalk_creep", 1.8, true, _stalk_creep],
		["chase_idle", 0.9, true, _chase_idle],
		["chase_run", 0.62, true, _chase_run],
		["search_idle", 3.6, true, _search_idle],
		["search_jog", 1.6, true, _search_jog],
	]


## A pose: torso rotation and position, head, both arms, both legs (all rotations in radians).
func _pose(torso_turn: Vector3, torso_lift: float, head: Vector3, arm_left: Vector3, arm_right: Vector3,
		leg_left: float, leg_right: float) -> Dictionary:
	return {
		"Torso:rotation": _torso_rest + torso_turn,
		"Torso:position": _torso_pos + Vector3(0.0, torso_lift, 0.0),
		"Torso/Head:rotation": head,
		"Torso/ArmLeft:rotation": arm_left,
		"Torso/ArmRight:rotation": arm_right,
		"LegLeft:rotation": Vector3(leg_left, 0.0, 0.0),
		"LegRight:rotation": Vector3(leg_right, 0.0, 0.0),
	}


func _d(degrees: float) -> Vector3:
	return Vector3(deg_to_rad(degrees), 0.0, 0.0)


func _calm_idle(p: float, t: float) -> Dictionary:
	# Standing still: slow breathing, a wrong head tilt, and a twitch every so often.
	var twitch := 0.0
	if t > 4.7 and t < 4.82:
		twitch = sin(t * 90.0) * 0.12
	return _pose(
		Vector3(deg_to_rad(1.2) * sin(2.0 * p), 0.0, deg_to_rad(1.5) * sin(p)), 0.008 * sin(2.0 * p),
		Vector3(deg_to_rad(8.0) + sin(2.0 * p) * 0.05, 0.0, sin(p) * 0.22 + twitch),
		Vector3(deg_to_rad(-12.0) + sin(p) * 0.06, 0.0, deg_to_rad(6.0) + sin(p) * 0.04),
		Vector3(deg_to_rad(-12.0) - sin(p) * 0.06, 0.0, deg_to_rad(-6.0) - sin(p) * 0.04),
		0.0, 0.0)


func _calm_walk(p: float, _t: float) -> Dictionary:
	# A heavy, lurching walk: arms swing against the legs, the torso rolls with each step.
	var swing := sin(p) * 0.62
	return _pose(
		Vector3(deg_to_rad(2.0), 0.0, sin(p) * 0.06), 0.025 * cos(2.0 * p),
		Vector3(deg_to_rad(8.0) + cos(2.0 * p) * 0.04, 0.0, -sin(p) * 0.09),
		Vector3(deg_to_rad(-12.0) - swing * 0.5, 0.0, deg_to_rad(6.0)),
		Vector3(deg_to_rad(-12.0) + swing * 0.5, 0.0, deg_to_rad(-6.0)),
		swing, -swing)


func _stalk_idle(p: float, _t: float) -> Dictionary:
	# Hunched and perfectly still, head cocked, fingers trembling: watching you.
	var tremor := sin(10.0 * p) * 0.012
	return _pose(
		Vector3(deg_to_rad(-14.0), 0.0, deg_to_rad(2.0) * sin(p)), -0.05,
		Vector3(deg_to_rad(-6.0) + sin(2.0 * p) * 0.03, 0.0, deg_to_rad(16.0) + sin(p) * 0.04 + tremor),
		Vector3(deg_to_rad(30.0) + sin(2.0 * p) * 0.04 + tremor, 0.0, deg_to_rad(10.0)),
		Vector3(deg_to_rad(30.0) + sin(2.0 * p) * 0.04 - tremor, 0.0, deg_to_rad(-10.0)),
		deg_to_rad(5.0), deg_to_rad(-5.0))


func _stalk_creep(p: float, _t: float) -> Dictionary:
	# Low, slow and deliberate, arms hanging forward like claws.
	var swing := sin(p) * 0.45
	return _pose(
		Vector3(deg_to_rad(-16.0), 0.0, sin(p) * 0.04), -0.05 + 0.015 * cos(2.0 * p),
		Vector3(deg_to_rad(-8.0), sin(p) * 0.05, deg_to_rad(16.0) - sin(p) * 0.03),
		Vector3(deg_to_rad(28.0) - swing * 0.35, 0.0, deg_to_rad(9.0)),
		Vector3(deg_to_rad(28.0) + swing * 0.35, 0.0, deg_to_rad(-9.0)),
		swing + 0.1, -swing + 0.1)


func _chase_idle(p: float, _t: float) -> Dictionary:
	# Held in place and shaking, arms up, head thrust forward.
	return _pose(
		Vector3(deg_to_rad(-20.0) + sin(8.0 * p) * 0.02, 0.0, sin(6.0 * p) * 0.03), -0.03,
		Vector3(deg_to_rad(-14.0) + sin(5.0 * p) * 0.05, 0.0, deg_to_rad(10.0) + sin(7.0 * p) * 0.06),
		Vector3(deg_to_rad(60.0) + sin(8.0 * p) * 0.05, 0.0, deg_to_rad(18.0)),
		Vector3(deg_to_rad(60.0) - sin(8.0 * p) * 0.05, 0.0, deg_to_rad(-18.0)),
		deg_to_rad(8.0), deg_to_rad(-8.0))


func _chase_run(p: float, _t: float) -> Dictionary:
	# A full, lunging sprint: leaning far forward, arms pumping, head thrown ahead.
	var swing := sin(p) * 1.05
	return _pose(
		Vector3(deg_to_rad(-24.0) + cos(2.0 * p) * 0.04, sin(p) * 0.08, sin(p) * 0.09), -0.03 + 0.05 * cos(2.0 * p),
		Vector3(deg_to_rad(-18.0), -sin(p) * 0.1, deg_to_rad(8.0) - sin(p) * 0.12),
		Vector3(deg_to_rad(55.0) - swing * 0.6, 0.0, deg_to_rad(14.0)),
		Vector3(deg_to_rad(55.0) + swing * 0.6, 0.0, deg_to_rad(-14.0)),
		swing, -swing)


func _search_idle(p: float, _t: float) -> Dictionary:
	# Standing and looking for you: the head sweeps slowly left and right.
	return _pose(
		Vector3(deg_to_rad(-2.0), sin(p - 0.5) * 0.3, 0.0), 0.0,
		Vector3(deg_to_rad(6.0), sin(p) * 0.85, sin(2.0 * p) * 0.05),
		Vector3(deg_to_rad(-14.0), 0.0, deg_to_rad(6.0)),
		Vector3(deg_to_rad(-14.0), 0.0, deg_to_rad(-6.0)),
		0.0, 0.0)


func _search_jog(p: float, _t: float) -> Dictionary:
	# A jog with the head still sweeping side to side. Two strides per clip.
	var swing := sin(2.0 * p) * 0.8
	return _pose(
		Vector3(deg_to_rad(-10.0), sin(p - 0.5) * 0.12, sin(2.0 * p) * 0.06), 0.03 * cos(4.0 * p),
		Vector3(deg_to_rad(2.0), sin(p) * 0.8, sin(2.0 * p) * 0.05),
		Vector3(deg_to_rad(-25.0) - swing * 0.6, 0.0, deg_to_rad(8.0)),
		Vector3(deg_to_rad(-25.0) + swing * 0.6, 0.0, deg_to_rad(-8.0)),
		swing, -swing)


func _ambient() -> Animation:
	# Plays all the time, alongside the moods: eyes pulse, the eye light shimmers,
	# coat strips (if the scene has them) sway.
	var length := TAU / 5.0
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR
	var eye_left := _root.get_node("Torso/Head/EyeLeft") as MeshInstance3D
	var eye_right := _root.get_node("Torso/Head/EyeRight") as MeshInstance3D
	var eyes := ["Torso/Head/EyeLeft"]
	if eye_right.material_override != eye_left.material_override:
		eyes.append("Torso/Head/EyeRight")
	for eye: String in eyes:
		var track := _new_track(animation, eye + ":material_override:emission_energy_multiplier")
		_sample(animation, track, length, func(p: float, _t: float) -> Variant: return 3.5 + sin(p) * 0.8)
	if _root.has_node("Torso/Head/EyeLight"):
		var track := _new_track(animation, "Torso/Head/EyeLight:light_energy")
		_sample(animation, track, length, func(p: float, _t: float) -> Variant: return 0.35 + sin(p) * 0.04)
	for index in 4:
		var path := "Torso/CoatStrip%d" % index
		if _root.has_node(path):
			var track := _new_track(animation, path + ":rotation:x")
			_sample(animation, track, length, func(p: float, _t: float) -> Variant: return sin(p + index) * 0.1)
	return animation


# ── Keyframe helpers ─────────────────────────────────────────────────────────

func _bake(length: float, loop: bool, pose_function: Callable) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	for path: String in pose_function.call(0.0, 0.0):
		tracks[path] = _new_track(animation, path)
	var count := int(ceil(length / STEP))
	for step in count + 1:
		var t := minf(step * STEP, length)
		var pose: Dictionary = pose_function.call(TAU * t / length, t)
		for path: String in pose:
			animation.track_insert_key(tracks[path], t, pose[path])
	return animation


func _new_track(animation: Animation, path: String) -> int:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	return track


func _sample(animation: Animation, track: int, length: float, value: Callable) -> void:
	var count := int(ceil(length / STEP))
	for step in count + 1:
		var t := minf(step * STEP, length)
		animation.track_insert_key(track, t, value.call(TAU * t / length, t))
